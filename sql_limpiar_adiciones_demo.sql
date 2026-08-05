-- ════════════════════════════════════════════════════════════════════
-- FENLORA POS · Limpieza de la adición de DEMO "Agrégale algo más"
-- (Leche vegetal / Crema batida / Sabor extra)  ← nunca se pidieron
-- ─ Quita SOLO ese grupo de opciones de los productos que lo tengan.
-- ─ NO borra productos. NO toca otras opciones (Sabor, Tazas, etc.).
-- Correr en: Supabase → SQL Editor
-- ════════════════════════════════════════════════════════════════════
update productos
set opciones = coalesce((
  select jsonb_agg(g)
  from jsonb_array_elements(opciones) as g
  where g->>'t' is distinct from 'Agrégale algo más'
), '[]'::jsonb)
where opciones @> '[{"t":"Agrégale algo más"}]';
