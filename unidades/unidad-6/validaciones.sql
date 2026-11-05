-- Unidad 6 — validaciones de Food Store para la línea base y la restauración.
--
-- Solo consulta: no modifica datos, no crea objetos y no ejecuta mantenimiento.
-- Las consultas corren en una transacción READ ONLY y REPEATABLE READ que termina
-- en ROLLBACK: todos los valores provienen de la misma instantánea. READ ONLY es
-- una protección complementaria a la revisión de este archivo, no una garantía
-- absoluta.
--
-- Usa los nombres reales del esquema canónico (schema.sql). La tabla de usuarios
-- es usuario; la diferencia con la tabla cliente del PDF sigue documentada como
-- CD-2 y no se resuelve aquí.
--
-- Salida determinista, una línea por clave, ordenada por nombre de clave:
--   clave|valor
-- Claves:
--   conteo.<tabla>      conteo exacto con count(*), incluidas las bajas lógicas.
--   eliminados.<tabla>  filas con eliminado = TRUE, ya incluidas en conteo.<tabla>.
--   control.producto_invalido        productos con precio < 0 OR stock < 0.
--   control.detalle_pedido_invalido  detalles con cantidad <= 0 OR precio_unitario < 0.
-- Los controles esperan 0. Este archivo no decide aprobación: compara y decide el
-- script que lo invoca (backup_foodstore.sh, restore_test.sh).
--
-- Invocación prevista, sin conexión fija ni contraseñas en el archivo:
--   docker exec -i CONTENEDOR psql -X -w -U USUARIO -d BASE \
--     -f - < unidades/unidad-6/validaciones.sql

\set ON_ERROR_STOP on
\set QUIET on
\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
\pset footer off
\pset null '(null)'

START TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT v.clave, v.valor
FROM (
            SELECT 'conteo.categoria' AS clave, count(*) AS valor FROM public.categoria
  UNION ALL SELECT 'conteo.usuario', count(*) FROM public.usuario
  UNION ALL SELECT 'conteo.producto', count(*) FROM public.producto
  UNION ALL SELECT 'conteo.pedido', count(*) FROM public.pedido
  UNION ALL SELECT 'conteo.detalle_pedido', count(*) FROM public.detalle_pedido
  UNION ALL SELECT 'eliminados.categoria', count(*) FILTER (WHERE eliminado) FROM public.categoria
  UNION ALL SELECT 'eliminados.usuario', count(*) FILTER (WHERE eliminado) FROM public.usuario
  UNION ALL SELECT 'eliminados.producto', count(*) FILTER (WHERE eliminado) FROM public.producto
  UNION ALL SELECT 'eliminados.pedido', count(*) FILTER (WHERE eliminado) FROM public.pedido
  UNION ALL SELECT 'eliminados.detalle_pedido', count(*) FILTER (WHERE eliminado) FROM public.detalle_pedido
  UNION ALL SELECT 'control.producto_invalido', count(*)
              FROM public.producto
             WHERE precio < 0 OR stock < 0
  UNION ALL SELECT 'control.detalle_pedido_invalido', count(*)
              FROM public.detalle_pedido
             WHERE cantidad <= 0 OR precio_unitario < 0
) AS v
ORDER BY v.clave COLLATE "C";

ROLLBACK;
