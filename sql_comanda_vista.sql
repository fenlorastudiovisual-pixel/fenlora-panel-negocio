-- ═══════════════════════════════════════════════════════════════════
-- Vista de Comandas por negocio  (la ELIGE el admin, la HEREDA el equipo)
-- 'seg' = interruptor Salón/Fuera · 'split' = pantalla partida · 'cards' = tarjetas
-- Se corre en el SQL Editor de Supabase del POS.
-- ═══════════════════════════════════════════════════════════════════

alter table public.negocios add column if not exists comanda_vista text;

-- Lectura pública (la vista no es dato sensible): la usa cada dispositivo al abrir.
create or replace function public.negocio_comanda_vista(p_sub text)
returns text
language sql
security definer
stable
as $$
  select comanda_vista
  from public.negocios
  where subdominio = p_sub or id::text = p_sub
  limit 1;
$$;
grant execute on function public.negocio_comanda_vista(text) to anon, authenticated;

-- Guardar: solo el dueño/admin del negocio (scoped por mis_negocios()).
create or replace function public.set_comanda_vista(p_vista text)
returns void
language plpgsql
security definer
as $$
begin
  if p_vista is null or p_vista not in ('seg','split','cards') then
    raise exception 'vista invalida';
  end if;
  update public.negocios
     set comanda_vista = p_vista
   where id in (select mis_negocios());
end;
$$;
grant execute on function public.set_comanda_vista(text) to authenticated;
