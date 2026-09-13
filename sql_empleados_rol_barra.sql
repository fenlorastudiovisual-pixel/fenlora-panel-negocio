-- ════════════════════════════════════════════════════════════════════
-- FENLORA · Permitir el rol 'barra' (y dejar la lista de roles al día) en
-- la tabla de empleados del POS.
--
-- PROBLEMA QUE ARREGLA:
--   Al crear un empleado con rol "Barra", el POS lo guardaba en el equipo
--   local (por eso se ve en el panel del admin), pero al subirlo a la nube
--   Supabase lo rechazaba por una restricción CHECK vieja en la columna
--   'rol' que solo permitía mesero/cajero/cocina. Como el kiosco
--   (/negocio/barra) lee SIEMPRE desde la nube, no encontraba ningún
--   empleado de barra → "Aún no hay barras registrados".
--
-- Correr en: Supabase → SQL Editor del POS. Seguro re-correr (idempotente).
-- No borra empleados ni toca datos; solo ajusta la restricción de la
-- columna 'rol'.
-- ════════════════════════════════════════════════════════════════════

do $$
declare
  r record;
begin
  -- 1) Quitar CUALQUIER restricción CHECK existente en public.empleados
  --    que mencione la columna 'rol' (nombre desconocido → la buscamos).
  for r in
    select con.conname
      from pg_constraint con
      join pg_class     cls on cls.oid = con.conrelid
      join pg_namespace ns  on ns.oid  = cls.relnamespace
     where ns.nspname = 'public'
       and cls.relname = 'empleados'
       and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%rol%'
  loop
    execute format('alter table public.empleados drop constraint %I', r.conname);
    raise notice 'Restricción CHECK vieja eliminada: %', r.conname;
  end loop;

  -- 2) Volver a crear la restricción con TODOS los roles válidos,
  --    incluida 'barra'. Si ya existe con este nombre, no falla.
  if not exists (
    select 1 from pg_constraint con
      join pg_class cls on cls.oid = con.conrelid
      join pg_namespace ns on ns.oid = cls.relnamespace
     where ns.nspname='public' and cls.relname='empleados'
       and con.conname='empleados_rol_chk'
  ) then
    alter table public.empleados
      add constraint empleados_rol_chk
      check (rol in ('admin','mesero','cajero','cocina','barra'));
    raise notice 'Restricción nueva creada: empleados_rol_chk (incluye barra)';
  end if;
end $$;
