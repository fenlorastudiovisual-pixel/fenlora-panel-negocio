-- ════════════════════════════════════════════════════════════════════
-- FENLORA POS · Tabla de ANULACIONES (producto puntual o comanda completa)
-- Alimenta las métricas de "Anulaciones" en Reportes.
-- Correr en: Supabase → SQL Editor
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.anulaciones (
  id         text primary key,
  negocio_id uuid not null,
  ts         timestamptz not null default now(),
  tipo       text not null default 'producto',   -- 'producto' | 'comanda'
  mesa       text,
  origen     text,
  mesero     text,
  producto   text,
  qty        int  default 1,
  unit       int  default 0,
  monto      int  default 0,
  motivo     text
);

create index if not exists anulaciones_neg_ts on public.anulaciones(negocio_id, ts);

alter table public.anulaciones enable row level security;

-- Lectura/escritura solo del propio negocio (mismo patrón que facturas/comandas)
drop policy if exists anulaciones_rw on public.anulaciones;
create policy anulaciones_rw on public.anulaciones
  for all
  using      (negocio_id in (select mis_negocios()))
  with check (negocio_id in (select mis_negocios()));
