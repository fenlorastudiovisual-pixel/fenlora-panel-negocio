-- ════════════════════════════════════════════════════════════════════
-- FENLORA · El menú consulta el ESTADO de un pedido online (para avisar
-- al cliente cuando esté listo: el "beeper de KFC").
-- Correr en: Supabase → SQL Editor del POS. Seguro re-correr. Aditivo.
-- No toca ninguna función existente; solo agrega menu_estado_pedido().
--
-- Lee la comanda por (negocio, clave) y calcula el estado a partir de sus
-- líneas (ready/served). El POS ya sincroniza esas líneas cuando Barra/
-- Cocina marca "listo", así que aquí solo se leen.
--   recibido    → llegó, nada listo aún
--   preparando  → algo listo, falta el resto
--   listo       → todo lo pendiente está listo para recoger
--   entregado   → ya se entregó / se cerró
-- ════════════════════════════════════════════════════════════════════

create or replace function public.menu_estado_pedido(
  p_api_key text,
  p_clave   text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_neg uuid;
  v_lineas jsonb;
  v_meta jsonb;
  v_titulo text;
  v_pend int := 0;      -- líneas enviadas y NO servidas
  v_pend_listas int := 0;
  v_servidas int := 0;
  it jsonb;
  v_estado text;
begin
  v_neg := public._menu_neg_por_key(p_api_key);
  if v_neg is null then raise exception 'api_key_invalida'; end if;

  select lineas, meta, titulo into v_lineas, v_meta, v_titulo
    from public.comandas
   where negocio_id = v_neg and clave = p_clave
   limit 1;

  if not found then
    -- Ya no existe la comanda → asumimos entregada/cerrada.
    return jsonb_build_object('estado','entregado','listo',true,'existe',false);
  end if;

  for it in select value from jsonb_array_elements(coalesce(v_lineas,'[]'::jsonb)) loop
    if coalesce((it->>'served')::boolean,false) then
      v_servidas := v_servidas + 1;
    elsif coalesce((it->>'sent')::boolean,false) then
      v_pend := v_pend + 1;
      if coalesce((it->>'ready')::boolean,false) then
        v_pend_listas := v_pend_listas + 1;
      end if;
    end if;
  end loop;

  if v_pend = 0 and v_servidas > 0 then
    v_estado := 'entregado';
  elsif v_pend = 0 then
    v_estado := 'recibido';
  elsif v_pend_listas >= v_pend then
    v_estado := 'listo';
  elsif v_pend_listas > 0 then
    v_estado := 'preparando';
  else
    v_estado := 'recibido';
  end if;

  return jsonb_build_object(
    'estado', v_estado,
    'listo', (v_estado = 'listo'),
    'entregado', (v_estado = 'entregado'),
    'existe', true,
    'titulo', coalesce(v_meta->>'title', v_titulo, ''),
    'pend', v_pend, 'listas', v_pend_listas, 'servidas', v_servidas
  );
end; $$;

grant execute on function public.menu_estado_pedido(text, text) to anon, authenticated;
