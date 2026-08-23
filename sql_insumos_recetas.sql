-- ════════════════════════════════════════════════════════════════════
-- FENLORA POS · INVENTARIO DE INSUMOS + RECETAS  (modelo correcto)
-- Correr en: Supabase → SQL Editor → pega TODO → Run.  Seguro de re-correr.
--
-- Idea:
--   • El INVENTARIO son los INSUMOS / materia prima (panela, agua, queso,
--     bizcocho, café…), NO los platos. Cada insumo tiene su COSTO DE COMPRA
--     (promedio ponderado) y su existencia POR SEDE.
--   • Las RECETAS dicen qué insumos y cuánto lleva cada plato del menú.
--   • Al VENDER un plato, se descuentan sus insumos del inventario (por receta),
--     de forma idempotente por factura (nunca descuenta doble).
--
-- Reemplaza el enfoque anterior "stock por producto" (se eliminan sus objetos
-- porque no llegaron a tener datos reales).
-- ════════════════════════════════════════════════════════════════════

-- ── Limpieza del enfoque anterior (product-level), sin datos ─────────
drop function if exists public.kardex_mover(uuid,uuid,uuid,text,numeric,numeric,text,text,text);
drop function if exists public.stock_config(uuid,uuid,uuid,boolean,numeric,text);
drop table if exists public.kardex;
drop table if exists public.stock;

-- ── Insumos (materia prima) — a nivel de negocio ────────────────────
create table if not exists public.insumos (
  id          uuid primary key default gen_random_uuid(),
  negocio_id  uuid not null,
  nombre      text not null,
  unidad      text not null default 'un',   -- g, kg, ml, lt, un…
  categoria   text default '',
  costo_prom  numeric not null default 0,   -- costo de compra promedio ponderado (por unidad)
  activo      boolean not null default true,
  creado_at   timestamptz not null default now()
);
create index if not exists insumos_neg on public.insumos(negocio_id);

-- ── Existencia de cada insumo POR SEDE ──────────────────────────────
create table if not exists public.insumos_stock (
  id          uuid primary key default gen_random_uuid(),
  negocio_id  uuid not null,
  sede_id     uuid,
  insumo_id   uuid not null,
  cantidad    numeric not null default 0,
  minimo      numeric not null default 0,
  bajo_min_avisado boolean not null default false,
  actualizado_at timestamptz not null default now()
);
create unique index if not exists insumos_stock_uni
  on public.insumos_stock (negocio_id, coalesce(sede_id,'00000000-0000-0000-0000-000000000000'::uuid), insumo_id);

-- ── Kardex de insumos (movimientos) ─────────────────────────────────
create table if not exists public.insumos_kardex (
  id          uuid primary key default gen_random_uuid(),
  negocio_id  uuid not null,
  sede_id     uuid,
  insumo_id   uuid not null,
  tipo        text not null,               -- entrada|salida|ajuste|merma|consumo|venta
  cantidad    numeric not null,            -- magnitud (siempre positivo)
  saldo       numeric not null default 0,  -- existencia resultante
  costo_unit  numeric not null default 0,  -- costo unitario del movimiento (compra o COGS)
  motivo      text default '',
  usuario     text default '',
  ref         text,                        -- clave idempotente
  creado_at   timestamptz not null default now()
);
create index if not exists insumos_kardex_ni on public.insumos_kardex (negocio_id, insumo_id, creado_at);
create unique index if not exists insumos_kardex_ref on public.insumos_kardex (negocio_id, ref) where ref is not null;

-- ── Recetas: qué insumos lleva cada producto del menú ───────────────
create table if not exists public.recetas (
  id          uuid primary key default gen_random_uuid(),
  negocio_id  uuid not null,
  producto_id uuid not null,               -- id del producto en la tabla productos
  insumo_id   uuid not null,
  cantidad    numeric not null default 0,  -- cuánto de ese insumo lleva 1 unidad del plato
  creado_at   timestamptz not null default now()
);
create unique index if not exists recetas_uni on public.recetas (negocio_id, producto_id, insumo_id);
create index if not exists recetas_prod on public.recetas (negocio_id, producto_id);

-- ── Seguridad (RLS) — mismo patrón que el resto ─────────────────────
alter table public.insumos        enable row level security;
alter table public.insumos_stock  enable row level security;
alter table public.insumos_kardex enable row level security;
alter table public.recetas        enable row level security;

drop policy if exists insumos_rw on public.insumos;
create policy insumos_rw on public.insumos for all
  using (negocio_id in (select mis_negocios())) with check (negocio_id in (select mis_negocios()));
drop policy if exists insumos_stock_rw on public.insumos_stock;
create policy insumos_stock_rw on public.insumos_stock for all
  using (negocio_id in (select mis_negocios())) with check (negocio_id in (select mis_negocios()));
drop policy if exists insumos_kardex_rw on public.insumos_kardex;
create policy insumos_kardex_rw on public.insumos_kardex for all
  using (negocio_id in (select mis_negocios())) with check (negocio_id in (select mis_negocios()));
drop policy if exists recetas_rw on public.recetas;
create policy recetas_rw on public.recetas for all
  using (negocio_id in (select mis_negocios())) with check (negocio_id in (select mis_negocios()));

-- ── Función: mover kardex + existencia de un insumo (ATÓMICA e IDEMPOTENTE) ──
create or replace function public.insumo_mover(
  p_negocio uuid, p_sede uuid, p_insumo uuid,
  p_tipo text, p_cantidad numeric,
  p_costo numeric default 0, p_motivo text default '', p_usuario text default '',
  p_ref text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  strow public.insumos_stock%rowtype;
  z uuid := '00000000-0000-0000-0000-000000000000';
  delta numeric := 0;
  mov_cant numeric := 0;
  nuevo numeric := 0;
  alerta boolean := false;
  existing numeric;
  tot_prev numeric := 0;
  costo_actual numeric := 0;
begin
  if p_negocio is null or p_negocio not in (select mis_negocios()) then
    raise exception 'No autorizado para este negocio';
  end if;

  -- Idempotencia
  if p_ref is not null then
    select saldo into existing from public.insumos_kardex
      where negocio_id = p_negocio and ref = p_ref limit 1;
    if found then
      return jsonb_build_object('saldo', existing, 'dup', true, 'alerta', false);
    end if;
  end if;

  -- Existencia (crear si no existe) y bloquear
  select * into strow from public.insumos_stock
    where negocio_id = p_negocio and coalesce(sede_id, z) = coalesce(p_sede, z) and insumo_id = p_insumo
    for update;
  if not found then
    insert into public.insumos_stock (negocio_id, sede_id, insumo_id)
      values (p_negocio, p_sede, p_insumo) returning * into strow;
  end if;

  -- Delta según tipo
  if p_tipo = 'entrada' then
    delta := abs(p_cantidad); mov_cant := abs(p_cantidad);
  elsif p_tipo = 'ajuste' then
    delta := p_cantidad - strow.cantidad; mov_cant := abs(delta);
  else
    delta := -abs(p_cantidad); mov_cant := abs(p_cantidad);
  end if;
  nuevo := strow.cantidad + delta;

  -- Costo de compra promedio ponderado (a nivel de negocio, sobre TODAS las sedes)
  select coalesce(costo_prom,0) into costo_actual from public.insumos where id = p_insumo;
  if p_tipo = 'entrada' and coalesce(p_costo,0) > 0 then
    select coalesce(sum(cantidad),0) into tot_prev from public.insumos_stock
      where negocio_id = p_negocio and insumo_id = p_insumo;   -- incluye esta sede antes de sumar
    -- tot_prev ya trae la existencia previa (aún no aplicamos el update)
    if (greatest(tot_prev,0) + abs(p_cantidad)) > 0 then
      costo_actual := ((greatest(tot_prev,0) * costo_actual) + (abs(p_cantidad) * p_costo))
                      / (greatest(tot_prev,0) + abs(p_cantidad));
    else
      costo_actual := p_costo;
    end if;
    update public.insumos set costo_prom = costo_actual where id = p_insumo;
  end if;

  if strow.minimo > 0 and nuevo <= strow.minimo and not strow.bajo_min_avisado then
    alerta := true;
  end if;

  update public.insumos_stock set
    cantidad = nuevo,
    bajo_min_avisado = case when strow.minimo > 0 and nuevo <= strow.minimo then true else false end,
    actualizado_at = now()
    where id = strow.id;

  insert into public.insumos_kardex (negocio_id, sede_id, insumo_id, tipo, cantidad, saldo, costo_unit, motivo, usuario, ref)
    values (p_negocio, p_sede, p_insumo, p_tipo, mov_cant, nuevo,
            case when p_tipo='entrada' then coalesce(p_costo,0) else costo_actual end,
            coalesce(p_motivo,''), coalesce(p_usuario,''), p_ref);

  return jsonb_build_object('saldo', nuevo, 'dup', false, 'alerta', alerta);

exception
  when unique_violation then
    select saldo into existing from public.insumos_kardex
      where negocio_id = p_negocio and ref = p_ref limit 1;
    return jsonb_build_object('saldo', coalesce(existing, 0), 'dup', true, 'alerta', false);
end;
$$;

grant execute on function public.insumo_mover(uuid,uuid,uuid,text,numeric,numeric,text,text,text) to anon, authenticated;
