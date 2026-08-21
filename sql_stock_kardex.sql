-- ════════════════════════════════════════════════════════════════════
-- FENLORA POS · STOCK y KARDEX  (Fase 1: por producto, por sede)
-- Correr en: Supabase → SQL Editor → pega TODO → Run.
-- Es seguro correrlo varias veces (usa IF NOT EXISTS / OR REPLACE).
--
-- Qué crea:
--   • stock   : existencia actual por negocio + sede + producto.
--   • kardex  : libro de movimientos (entradas/salidas) con saldo por movimiento.
--   • kardex_mover(...)  : función ATÓMICA que mueve el kardex y actualiza la
--                          existencia en un solo paso. Es IDEMPOTENTE (por 'ref'),
--                          así una venta nunca descuenta doble aunque se reintente
--                          o venga de dos dispositivos.
--   • stock_config(...)  : prende/apaga el control por producto y fija el mínimo.
--
-- Mismo aislamiento por negocio que facturas/comandas: negocio_id in (select mis_negocios()).
-- ════════════════════════════════════════════════════════════════════

-- ── Tabla de existencias ────────────────────────────────────────────
create table if not exists public.stock (
  id             uuid primary key default gen_random_uuid(),
  negocio_id     uuid not null,
  sede_id        uuid,
  producto_id    uuid not null,
  controlar      boolean not null default false,  -- ¿este producto lleva inventario?
  cantidad       numeric not null default 0,      -- existencia actual
  minimo         numeric not null default 0,      -- umbral de alerta
  unidad         text    not null default 'un',   -- un, botella, kg, lt… (para Fase 2)
  costo_prom     numeric not null default 0,      -- costo promedio ponderado
  bajo_min_avisado boolean not null default false,-- para avisar una sola vez por cruce
  actualizado_at timestamptz not null default now()
);
-- Una sola fila por producto por sede (trata sede nula como un valor fijo)
create unique index if not exists stock_uni
  on public.stock (negocio_id, coalesce(sede_id,'00000000-0000-0000-0000-000000000000'::uuid), producto_id);

-- ── Tabla de movimientos (kardex) ───────────────────────────────────
create table if not exists public.kardex (
  id          uuid primary key default gen_random_uuid(),
  negocio_id  uuid not null,
  sede_id     uuid,
  producto_id uuid not null,
  tipo        text not null,               -- entrada|salida|ajuste|merma|cortesia|consumo|venta
  cantidad    numeric not null,            -- magnitud del movimiento (siempre positivo)
  saldo       numeric not null default 0,  -- existencia resultante después del movimiento
  costo_unit  numeric not null default 0,
  motivo      text default '',
  usuario     text default '',
  ref         text,                        -- clave idempotente (ej: 'factura:<id>:<pid>')
  creado_at   timestamptz not null default now()
);
create index if not exists kardex_np on public.kardex (negocio_id, producto_id, creado_at);
-- Idempotencia: un movimiento con la misma 'ref' no se puede repetir
create unique index if not exists kardex_ref_uni on public.kardex (negocio_id, ref) where ref is not null;

-- ── Seguridad (RLS) — mismo patrón que facturas/comandas/anulaciones ─
alter table public.stock  enable row level security;
alter table public.kardex enable row level security;

drop policy if exists stock_rw on public.stock;
create policy stock_rw on public.stock
  for all
  using      (negocio_id in (select mis_negocios()))
  with check (negocio_id in (select mis_negocios()));

drop policy if exists kardex_rw on public.kardex;
create policy kardex_rw on public.kardex
  for all
  using      (negocio_id in (select mis_negocios()))
  with check (negocio_id in (select mis_negocios()));

-- ── Función: fijar control/mínimo/unidad de un producto ─────────────
create or replace function public.stock_config(
  p_negocio uuid, p_sede uuid, p_producto uuid,
  p_controlar boolean, p_minimo numeric, p_unidad text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_negocio is null or p_negocio not in (select mis_negocios()) then
    raise exception 'No autorizado para este negocio';
  end if;
  insert into public.stock (negocio_id, sede_id, producto_id, controlar, minimo, unidad)
  values (p_negocio, p_sede, p_producto, coalesce(p_controlar,false), coalesce(p_minimo,0), coalesce(nullif(p_unidad,''),'un'))
  on conflict (negocio_id, coalesce(sede_id,'00000000-0000-0000-0000-000000000000'::uuid), producto_id)
  do update set controlar = excluded.controlar,
                minimo    = excluded.minimo,
                unidad    = excluded.unidad,
                bajo_min_avisado = case when excluded.minimo <= 0 then false else public.stock.bajo_min_avisado end,
                actualizado_at = now();
end;
$$;

-- ── Función: mover kardex + actualizar existencia (ATÓMICA e IDEMPOTENTE) ──
create or replace function public.kardex_mover(
  p_negocio uuid, p_sede uuid, p_producto uuid,
  p_tipo text, p_cantidad numeric,
  p_costo numeric default 0, p_motivo text default '', p_usuario text default '',
  p_ref text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  strow public.stock%rowtype;
  z uuid := '00000000-0000-0000-0000-000000000000';
  delta numeric := 0;
  mov_cant numeric := 0;
  nuevo numeric := 0;
  nuevocosto numeric := 0;
  alerta boolean := false;
  existing numeric;
begin
  if p_negocio is null or p_negocio not in (select mis_negocios()) then
    raise exception 'No autorizado para este negocio';
  end if;

  -- Idempotencia: si ya existe un movimiento con esta 'ref', no repetir
  if p_ref is not null then
    select saldo into existing from public.kardex
      where negocio_id = p_negocio and ref = p_ref limit 1;
    if found then
      return jsonb_build_object('saldo', existing, 'dup', true, 'alerta', false);
    end if;
  end if;

  -- Obtener (o crear) la fila de existencia y bloquearla
  select * into strow from public.stock
    where negocio_id = p_negocio
      and coalesce(sede_id, z) = coalesce(p_sede, z)
      and producto_id = p_producto
    for update;
  if not found then
    insert into public.stock (negocio_id, sede_id, producto_id)
      values (p_negocio, p_sede, p_producto)
      returning * into strow;
  end if;

  -- Calcular el delta según el tipo de movimiento
  if p_tipo = 'entrada' then
    delta := abs(p_cantidad);  mov_cant := abs(p_cantidad);
  elsif p_tipo = 'ajuste' then
    -- p_cantidad = existencia CONTADA (valor absoluto al que queda)
    delta := p_cantidad - strow.cantidad;  mov_cant := abs(delta);
  else
    -- salida | venta | merma | cortesia | consumo
    delta := -abs(p_cantidad);  mov_cant := abs(p_cantidad);
  end if;
  nuevo := strow.cantidad + delta;

  -- Costo promedio ponderado (solo en entradas con costo)
  if p_tipo = 'entrada' and coalesce(p_costo,0) > 0 and (greatest(strow.cantidad,0) + abs(p_cantidad)) > 0 then
    nuevocosto := ((greatest(strow.cantidad,0) * strow.costo_prom) + (abs(p_cantidad) * p_costo))
                  / (greatest(strow.cantidad,0) + abs(p_cantidad));
  else
    nuevocosto := strow.costo_prom;
  end if;

  -- ¿Cruzó el mínimo por primera vez? (avisar una sola vez)
  if strow.minimo > 0 and nuevo <= strow.minimo and not strow.bajo_min_avisado then
    alerta := true;
  end if;

  update public.stock set
    cantidad = nuevo,
    costo_prom = nuevocosto,
    bajo_min_avisado = case when strow.minimo > 0 and nuevo <= strow.minimo then true else false end,
    actualizado_at = now()
    where id = strow.id;

  insert into public.kardex (negocio_id, sede_id, producto_id, tipo, cantidad, saldo, costo_unit, motivo, usuario, ref)
    values (p_negocio, p_sede, p_producto, p_tipo, mov_cant, nuevo, coalesce(p_costo,0),
            coalesce(p_motivo,''), coalesce(p_usuario,''), p_ref);

  return jsonb_build_object('saldo', nuevo, 'dup', false, 'alerta', alerta);

exception
  -- Carrera: dos dispositivos mandaron la misma venta a la vez → tratar como duplicado
  when unique_violation then
    select saldo into existing from public.kardex
      where negocio_id = p_negocio and ref = p_ref limit 1;
    return jsonb_build_object('saldo', coalesce(existing, strow.cantidad), 'dup', true, 'alerta', false);
end;
$$;

-- ── Permisos de ejecución (el POS usa usuarios autenticados) ─────────
grant execute on function public.stock_config(uuid,uuid,uuid,boolean,numeric,text) to anon, authenticated;
grant execute on function public.kardex_mover(uuid,uuid,uuid,text,numeric,numeric,text,text,text) to anon, authenticated;
