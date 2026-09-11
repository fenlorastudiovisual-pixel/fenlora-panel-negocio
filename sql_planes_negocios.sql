-- FENLORA POS · columnas del plan + directorio por negocio (Supabase)
-- Correr en: Supabase → SQL Editor (proyecto del POS). Seguro reejecutar.
alter table negocios add column if not exists cerebro         text    default 'economico';
alter table negocios add column if not exists canal           text    default 'menu';
alter table negocios add column if not exists plan_bot        text    default 'ninguno';
alter table negocios add column if not exists plan_remark     text    default 'ninguno';
alter table negocios add column if not exists plan_fidelidad  text    default 'no';
alter table negocios add column if not exists precio_total    integer default 0;
alter table negocios add column if not exists categoria       text;
alter table negocios add column if not exists municipio       text;
alter table negocios add column if not exists en_prueba       integer default 0;
alter table negocios add column if not exists descuento_pct   integer default 0;
alter table negocios add column if not exists descuento_hasta text;
