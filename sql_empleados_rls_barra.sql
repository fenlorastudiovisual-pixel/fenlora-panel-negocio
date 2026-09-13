-- ════════════════════════════════════════════════════════════════════
-- FENLORA · Habilitar el rol 'barra' en la POLÍTICA RLS de empleados.
--
-- PROBLEMA QUE ARREGLA:
--   Al crear un empleado "Barra", Supabase lo rechaza con:
--     "new row violates row-level security policy for table empleados"
--   Existe una política RLS (seguridad por fila) cuya condición WITH CHECK
--   solo permite insertar roles mesero/cajero/cocina. 'barra' no está en
--   la lista, así que se bloquea. (Por eso Juan y Pedro sí subieron.)
--
--   Este script busca esa(s) política(s) y les agrega 'barra' a la lista,
--   SIN tocar el resto de la condición (sigue igual de seguro).
--
-- Correr en: Supabase → SQL Editor del POS. Seguro re-correr (idempotente):
--   si ya tienen 'barra', no hace nada.
-- ════════════════════════════════════════════════════════════════════

do $$
declare
  p record;
  wc text; ql text; roles_txt text; cmd_txt text; stmt text;
begin
  for p in
    select * from pg_policies
     where schemaname='public' and tablename='empleados'
  loop
    -- Solo tocamos políticas que listan roles (contienen 'cocina') y que
    -- todavía NO incluyen 'barra'.
    if position('cocina' in coalesce(p.with_check,'')||coalesce(p.qual,'')) > 0
       and position('barra' in coalesce(p.with_check,'')||coalesce(p.qual,'')) = 0
    then
      -- Insertar 'barra' justo al lado de 'cocina' en la lista de roles.
      wc := regexp_replace(coalesce(p.with_check,''), '''cocina''(::text)?', '''cocina''\1, ''barra''\1', 'g');
      ql := regexp_replace(coalesce(p.qual,''),       '''cocina''(::text)?', '''cocina''\1, ''barra''\1', 'g');
      roles_txt := array_to_string(p.roles, ', ');
      cmd_txt := case p.cmd
        when 'ALL' then 'all' when 'SELECT' then 'select'
        when 'INSERT' then 'insert' when 'UPDATE' then 'update'
        when 'DELETE' then 'delete' else 'all' end;

      execute format('drop policy %I on public.empleados', p.policyname);

      stmt := format('create policy %I on public.empleados as %s for %s to %s',
                     p.policyname, lower(p.permissive), cmd_txt, roles_txt);
      if p.qual is not null and p.cmd in ('ALL','SELECT','UPDATE','DELETE') then
        stmt := stmt || ' using (' || ql || ')';
      end if;
      if p.with_check is not null and p.cmd in ('ALL','INSERT','UPDATE') then
        stmt := stmt || ' with check (' || wc || ')';
      end if;
      execute stmt;
      raise notice 'Política RLS actualizada (barra habilitado): %', p.policyname;
    end if;
  end loop;
end $$;

-- Para confirmar: aquí deberías ver 'barra' dentro de with_check.
select policyname, cmd, with_check
  from pg_policies
 where schemaname='public' and tablename='empleados'
 order by cmd;
