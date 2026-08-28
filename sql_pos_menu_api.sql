-- ════════════════════════════════════════════════════════════════════
-- FENLORA POS · ENLACE con el MENÚ DIGITAL (contrato v1)  ·  LADO POS
-- Correr en: Supabase → SQL Editor → pega TODO → Run.  Seguro de re-correr.
--
-- Crea:
--   • menu_api_keys        : una clave secreta por negocio enlazado.
--   • menu_catalogo(key)   : el menú lee la carta del POS (productos visibles en QR).
--   • menu_crear_comanda(key, mesa, items, nota) : el pedido del menú entra como
--                            comanda en la mesa; los precios se RECALCULAN aquí
--                            (nunca se confía en lo que manda el menú).
--   • menu_llamar_mesero(key, mesa, motivo) : marca un aviso en la comanda de la mesa.
--
-- Seguridad: la api_key mapea al negocio. Las funciones son SECURITY DEFINER y
-- validan la key adentro; el navegador del cliente nunca ve la key (vive en el
-- Worker del menú, lado servidor).
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.menu_api_keys (
  id          uuid primary key default gen_random_uuid(),
  negocio_id  uuid not null,
  api_key     text not null unique,
  activo      boolean not null default true,
  creado_at   timestamptz not null default now()
);
create index if not exists menu_api_keys_neg on public.menu_api_keys(negocio_id);

alter table public.menu_api_keys enable row level security;
drop policy if exists menu_api_keys_rw on public.menu_api_keys;
create policy menu_api_keys_rw on public.menu_api_keys for all
  using (negocio_id in (select mis_negocios())) with check (negocio_id in (select mis_negocios()));

-- Resuelve api_key → negocio_id (interno). SECURITY DEFINER para saltar RLS al validar.
create or replace function public._menu_neg_por_key(p_api_key text)
returns uuid language sql security definer set search_path = public as $$
  select negocio_id from public.menu_api_keys where api_key = p_api_key and activo limit 1;
$$;

-- ── Catálogo: el menú pide la carta del negocio ──
create or replace function public.menu_catalogo(p_api_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_neg uuid; v_nombre text; v_res jsonb;
begin
  v_neg := public._menu_neg_por_key(p_api_key);
  if v_neg is null then raise exception 'api_key_invalida'; end if;
  select nombre into v_nombre from public.negocios where id = v_neg;
  select jsonb_build_object(
    'negocio', jsonb_build_object('nombre', coalesce(v_nombre,''), 'moneda','COP'),
    'categorias', coalesce((
      select jsonb_agg(distinct categoria) from public.productos
      where negocio_id = v_neg and activo and en_qr), '[]'::jsonb),
    'productos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'categoria', categoria, 'nombre', nombre,
        'descripcion', coalesce(descripcion,''), 'precio', precio,
        'imagen_url', img_url, 'disponible', true, 'destacado', coalesce(recomendado,false)
      ) order by categoria, nombre)
      from public.productos where negocio_id = v_neg and activo and en_qr), '[]'::jsonb)
  ) into v_res;
  return v_res;
end; $$;

-- ── Comanda: el pedido del menú entra a la mesa (precios recalculados) ──
create or replace function public.menu_crear_comanda(
  p_api_key text, p_mesa text, p_items jsonb, p_nota text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_neg uuid; v_clave text; v_titulo text;
  v_lineas jsonb := '[]'::jsonb; v_existing jsonb;
  v_total numeric := 0; it jsonb; v_prod record; v_qty int; v_lid int := 0;
  v_ahora bigint := (extract(epoch from clock_timestamp())*1000)::bigint;
begin
  v_neg := public._menu_neg_por_key(p_api_key);
  if v_neg is null then raise exception 'api_key_invalida'; end if;
  if p_mesa is null or length(trim(p_mesa)) = 0 then raise exception 'mesa_requerida'; end if;

  v_clave  := 'mesa_' || regexp_replace(p_mesa, '[^0-9A-Za-z]', '', 'g');
  v_titulo := 'Mesa ' || p_mesa;

  for it in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_qty := coalesce((it->>'cantidad')::int, 0);
    if v_qty <= 0 or v_qty > 99 then continue; end if;
    select id, nombre, precio, area into v_prod from public.productos
      where negocio_id = v_neg and activo and en_qr and id = (it->>'producto_id')::uuid;
    if not found then raise exception 'producto_no_disponible'; end if;
    v_lid := v_lid + 1;
    v_total := v_total + (v_prod.precio * v_qty);
    v_lineas := v_lineas || jsonb_build_object(
      'lid', v_lid, 'id', v_prod.id, 'n', v_prod.nombre, 'qty', v_qty, 'unit', v_prod.precio,
      'opts', '[]'::jsonb, 'notes', jsonb_build_array(jsonb_build_array()),
      'sent', true, 'sentAt', v_ahora, 'held', false, 'served', false, 'ready', false,
      'cort', false, 'llevar', false, 'desc', 0, 'area', coalesce(v_prod.area,'COCINA'), 'canal', 'menu_qr'
    );
  end loop;
  if jsonb_array_length(v_lineas) = 0 then raise exception 'pedido_vacio'; end if;

  -- Si la mesa ya tiene comanda activa, AGREGAR las líneas (no reemplazar)
  select lineas into v_existing from public.comandas
    where negocio_id = v_neg and clave = v_clave and estado = 'activa';
  if v_existing is not null then v_lineas := v_existing || v_lineas; end if;

  insert into public.comandas (negocio_id, clave, titulo, tipo, estado, meta, lineas)
  values (v_neg, v_clave, v_titulo, 'mesa', 'activa',
    jsonb_build_object('title', v_titulo, 'canal','menu_qr', 'cliente', coalesce(p_nota,''), '_dev','menu'),
    v_lineas)
  on conflict (negocio_id, clave) do update
    set lineas = excluded.lineas, estado = 'activa',
        meta = public.comandas.meta || jsonb_build_object('canal','menu_qr','_dev','menu');

  return jsonb_build_object('comanda_id', v_clave, 'estado', 'recibida', 'total', v_total);
end; $$;

-- ── Llamar al mesero: marca un aviso en la comanda de la mesa ──
create or replace function public.menu_llamar_mesero(
  p_api_key text, p_mesa text, p_motivo text default 'llamado'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_neg uuid; v_clave text; v_titulo text;
  v_aviso jsonb; v_ahora bigint := (extract(epoch from clock_timestamp())*1000)::bigint;
begin
  v_neg := public._menu_neg_por_key(p_api_key);
  if v_neg is null then raise exception 'api_key_invalida'; end if;
  if p_mesa is null or length(trim(p_mesa)) = 0 then raise exception 'mesa_requerida'; end if;
  v_clave  := 'mesa_' || regexp_replace(p_mesa, '[^0-9A-Za-z]', '', 'g');
  v_titulo := 'Mesa ' || p_mesa;
  v_aviso  := jsonb_build_object('motivo', coalesce(p_motivo,'llamado'), 'ts', v_ahora);

  insert into public.comandas (negocio_id, clave, titulo, tipo, estado, meta, lineas)
  values (v_neg, v_clave, v_titulo, 'mesa', 'activa',
    jsonb_build_object('title', v_titulo, '_dev','menu', 'llamado', v_aviso), '[]'::jsonb)
  on conflict (negocio_id, clave) do update
    set meta = public.comandas.meta || jsonb_build_object('llamado', v_aviso, '_dev','menu'),
        estado = 'activa';
  return jsonb_build_object('ok', true);
end; $$;

-- Permisos: el Worker del menú llama con la clave anónima (la seguridad real es la api_key)
grant execute on function public.menu_catalogo(text) to anon, authenticated;
grant execute on function public.menu_crear_comanda(text, text, jsonb, text) to anon, authenticated;
grant execute on function public.menu_llamar_mesero(text, text, text) to anon, authenticated;
