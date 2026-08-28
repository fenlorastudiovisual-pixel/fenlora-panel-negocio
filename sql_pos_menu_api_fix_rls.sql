-- ════════════════════════════════════════════════════════════════════
-- PARCHE · Permiso (RLS) de menu_api_keys para el SUPERADMIN de Fenlora
-- Correr en: Supabase del POS → SQL Editor → Run.
--
-- Problema: al generar la API key salía "new row violates row-level security
-- policy for table menu_api_keys". Es porque el superadmin no es "miembro" de
-- cada negocio (mis_negocios() no los incluye). Solución: permitir también al
-- superadmin, igual que en la tabla de negocios.
-- ════════════════════════════════════════════════════════════════════

drop policy if exists menu_api_keys_rw on public.menu_api_keys;
create policy menu_api_keys_rw on public.menu_api_keys
  for all
  using      (public.es_super_admin() OR negocio_id in (select mis_negocios()))
  with check (public.es_super_admin() OR negocio_id in (select mis_negocios()));
