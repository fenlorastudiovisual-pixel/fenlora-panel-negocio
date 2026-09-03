-- ════════════════════════════════════════════════════════════════════
-- Pedidos ONLINE desde el menú (sin mesa) → entran al POS en "Fuera"
--   • recoger  → clave online_<id>   (canal Online del POS)
--   • domicilio→ clave delivery_<id> (canal Delivery del POS)
-- Los precios se RECALCULAN aquí (nunca se confía en lo que manda el navegador).
-- Las líneas entran 'sent'=true → van directo a COCINA.
-- Se corre en el SQL Editor de Supabase del POS. Reutiliza _menu_neg_por_key.
-- ════════════════════════════════════════════════════════════════════

create or replace function public.menu_crear_pedido_online(
  p_api_key text,
  p_tipo    text,               -- 'recoger' | 'domicilio'
  p_items   jsonb,
  p_cliente text default null,
  p_telefono text default null,
  p_direccion text default null,
  p_nota    text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_neg uuid; v_prefix text; v_ico text; v_tipo_pos text;
  v_clave text; v_num text; v_titulo text;
  v_lineas jsonb := '[]'::jsonb;
  v_total numeric := 0; it jsonb; v_prod record; v_qty int; v_lid int := 0;
  v_ahora bigint := (extract(epoch from clock_timestamp())*1000)::bigint;
begin
  v_neg := public._menu_neg_por_key(p_api_key);
  if v_neg is null then raise exception 'api_key_invalida'; end if;
  if p_tipo not in ('recoger','domicilio') then raise exception 'tipo_invalido'; end if;
  if p_tipo = 'domicilio' and (p_direccion is null or length(trim(p_direccion)) = 0)
    then raise exception 'direccion_requerida'; end if;

  if p_tipo = 'recoger' then
    v_prefix := 'online'; v_ico := '🌐'; v_tipo_pos := 'online';
  else
    v_prefix := 'delivery'; v_ico := '🛵'; v_tipo_pos := 'delivery';
  end if;

  v_num   := lpad(((v_ahora % 9000) + 1000)::text, 4, '0');   -- número corto legible
  v_clave := v_prefix || '_' || v_ahora::text;                -- clave única
  v_titulo := (case when p_tipo='recoger' then 'Recoger' else 'Domicilio' end) || ' #' || v_num;

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
      'cort', false, 'llevar', (p_tipo='recoger'), 'desc', 0, 'area', coalesce(v_prod.area,'COCINA'), 'canal', 'menu_online'
    );
  end loop;
  if jsonb_array_length(v_lineas) = 0 then raise exception 'pedido_vacio'; end if;

  insert into public.comandas (negocio_id, clave, titulo, tipo, estado, meta, lineas)
  values (v_neg, v_clave, v_titulo, v_tipo_pos, 'activa',
    jsonb_build_object(
      'title', v_titulo, 'ico', v_ico, 'canal','menu_online', 'tipoPedido', p_tipo,
      'cliente', coalesce(p_cliente,''), 'phone', coalesce(p_telefono,''),
      'address', coalesce(p_direccion,''), 'nota', coalesce(p_nota,''),
      'openedAt', v_ahora, '_dev','menu'),
    v_lineas);

  return jsonb_build_object('pedido_id', v_clave, 'numero', v_num, 'estado','recibido', 'total', v_total);
end; $$;
grant execute on function public.menu_crear_pedido_online(text, text, jsonb, text, text, text, text) to anon, authenticated;
