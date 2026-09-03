-- ════════════════════════════════════════════════════════════════════
-- Storage de fotos de producto (Supabase Storage) · bucket 'productos'
-- Las fotos se guardan como <negocio_id>/<archivo>.webp y la base guarda solo la URL.
-- Lectura pública (el menú y el POS cargan por URL). Subir/editar/borrar: solo
-- usuarios del negocio dueño de esa carpeta (validado con mis_negocios()).
-- Se corre en el SQL Editor de Supabase del POS.
-- ════════════════════════════════════════════════════════════════════

-- 1) Bucket público
insert into storage.buckets (id, name, public)
values ('productos', 'productos', true)
on conflict (id) do update set public = true;

-- 2) Políticas sobre storage.objects (limpia por si ya existían)
drop policy if exists productos_fotos_read   on storage.objects;
drop policy if exists productos_fotos_insert on storage.objects;
drop policy if exists productos_fotos_update on storage.objects;
drop policy if exists productos_fotos_delete on storage.objects;

-- Lectura pública de este bucket
create policy productos_fotos_read on storage.objects
  for select using ( bucket_id = 'productos' );

-- Subir: solo a la carpeta de un negocio del usuario (primer segmento = negocio_id)
create policy productos_fotos_insert on storage.objects
  for insert to authenticated
  with check ( bucket_id = 'productos'
    and (storage.foldername(name))[1]::uuid in (select mis_negocios()) );

-- Reemplazar (upsert) sus propias fotos
create policy productos_fotos_update on storage.objects
  for update to authenticated
  using ( bucket_id = 'productos'
    and (storage.foldername(name))[1]::uuid in (select mis_negocios()) );

-- Borrar sus propias fotos
create policy productos_fotos_delete on storage.objects
  for delete to authenticated
  using ( bucket_id = 'productos'
    and (storage.foldername(name))[1]::uuid in (select mis_negocios()) );
