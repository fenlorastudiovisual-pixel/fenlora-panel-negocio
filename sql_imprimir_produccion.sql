-- ════════════════════════════════════════════════════════════════════
-- FENLORA · Interruptor "Imprimir comandas a cocina/barra" por negocio
-- Lo controla SOLO Fenlora (superadmin) desde el apartado Negocios.
-- Por defecto viene ENCENDIDO (comportamiento actual: sí imprime).
-- Si se apaga, la comanda IGUAL se muestra en pantallas/KDS, solo NO se imprime.
--
-- Cómo aplicarlo:  Supabase → tu proyecto → SQL Editor → pega TODO esto → Run.
-- Es seguro correrlo varias veces (usa IF NOT EXISTS / OR REPLACE).
-- ════════════════════════════════════════════════════════════════════

-- 1) Columna en la tabla de negocios (por defecto true = sí imprime)
alter table public.negocios
  add column if not exists imprimir_produccion boolean not null default true;

-- 2) Función pública para que el POS del negocio consulte si debe imprimir.
--    SECURITY DEFINER para que el rol anónimo pueda leer solo este dato,
--    sin exponer el resto de la tabla negocios.
create or replace function public.negocio_imprime_produccion(p_sub text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce(imprimir_produccion, true)
  from public.negocios
  where lower(subdominio) = lower(p_sub)
  limit 1;
$$;

-- 3) Permisos de ejecución (el POS usa la clave anónima)
grant execute on function public.negocio_imprime_produccion(text) to anon, authenticated;
