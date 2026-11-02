-- SEC-03.P/R, SEC-05.P, SEC-13.P, REG-02/03: dos transacciones independientes.
-- Mismos IDs, argumentos y estado inicial, sin cambiar la lógica canónica.
-- Se excluyen SOLO id/created_at del detalle: son identidad/tiempo de dos ejecuciones.
-- No se equiparan por redondeo ni por una segunda definición del subtotal/total.
\ir 00_guardas.sql
\ir 00_helpers.sql
CREATE TEMP VIEW u5_estado_venta AS
SELECT 'linea'::text AS tipo, d.pedido_id AS pedido, d.producto_id AS producto,
       d.cantidad, d.precio_unitario AS precio, d.subtotal,
       NULL::integer AS stock, NULL::numeric AS total, d.eliminado
FROM public.detalle_pedido d WHERE d.pedido_id IN (pg_temp.id('o1'),pg_temp.id('o2'),pg_temp.id('o3'))
UNION ALL
SELECT 'producto',NULL,p.id,NULL,p.precio,NULL,p.stock,NULL,p.eliminado
FROM public.producto p WHERE p.id IN (pg_temp.id('p1'),pg_temp.id('p2'),pg_temp.id('p3'),pg_temp.id('p4'))
UNION ALL
SELECT 'pedido',p.id,NULL,NULL,NULL,NULL,NULL,p.total,p.eliminado
FROM public.pedido p WHERE p.id IN (pg_temp.id('o1'),pg_temp.id('o2'),pg_temp.id('o3'));
BEGIN;
\ir 13_fixtures.sql
CALL public.registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p1'),3);
CALL public.registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p2'),2);
SELECT pg_temp.verificar('SEC03.P.canonica.dos_lineas',
 $$SELECT count(*)::text FROM pg_temp.u5_estado_venta WHERE tipo='linea'$$,'2');
SELECT jsonb_agg(to_jsonb(e) ORDER BY tipo,pedido,producto) AS u5_canonica FROM pg_temp.u5_estado_venta e
\gset
ROLLBACK;
SELECT pg_temp.sin_fixtures('SEC03.P.canonica.rollback');
BEGIN;
\ir 13_fixtures.sql
SET ROLE app_web;
SELECT pg_temp.esperar_ok('REG02.api.primera',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p1'),3)$$);
SELECT pg_temp.esperar_ok('REG02.api.segunda',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p2'),2)$$);
RESET ROLE;
SELECT pg_temp.verificar('SEC03.P.api.dos_lineas',
 $$SELECT count(*)::text FROM pg_temp.u5_estado_venta WHERE tipo='linea'$$,'2');
SELECT pg_temp.verificar('REG03.derivados_stock', $q$
 SELECT ((SELECT total FROM public.pedido WHERE id=pg_temp.id('o1'))=4351.50
 AND (SELECT stock FROM public.producto WHERE id=pg_temp.id('p1'))=7
 AND (SELECT stock FROM public.producto WHERE id=pg_temp.id('p2'))=0
 AND EXISTS (SELECT FROM public.detalle_pedido WHERE pedido_id=pg_temp.id('o1')
  AND producto_id=pg_temp.id('p1') AND cantidad=3 AND precio_unitario=1250.50 AND subtotal=3751.50)
 AND EXISTS (SELECT FROM public.detalle_pedido WHERE pedido_id=pg_temp.id('o1')
  AND producto_id=pg_temp.id('p2') AND cantidad=2 AND precio_unitario=300 AND subtotal=600))::text$q$,'true');
SELECT jsonb_agg(to_jsonb(e) ORDER BY tipo,pedido,producto) AS u5_api FROM pg_temp.u5_estado_venta e
\gset
ROLLBACK;
SELECT pg_temp.sin_fixtures('SEC03.P.api.rollback');
-- Los resultados se transportan como JSON sintético en variables de psql porque
-- INSERT en una tabla TEMP dentro de la transacción también se revertiría.
WITH canonica AS (SELECT value FROM jsonb_array_elements(:'u5_canonica'::jsonb)),
 api AS (SELECT value FROM jsonb_array_elements(:'u5_api'::jsonb))
SELECT 'canonica-api' AS sentido,value FROM (SELECT * FROM canonica EXCEPT SELECT * FROM api) d
UNION ALL
SELECT 'api-canonica',value FROM (SELECT * FROM api EXCEPT SELECT * FROM canonica) d;
SELECT pg_temp.verificar('SEC03.P.EXCEPT.bidireccional',format($q$
 WITH canonica AS (SELECT value FROM jsonb_array_elements(%L::jsonb)),
 api AS (SELECT value FROM jsonb_array_elements(%L::jsonb))
 SELECT count(*)::text FROM (
 (SELECT * FROM canonica EXCEPT SELECT * FROM api) UNION ALL
 (SELECT * FROM api EXCEPT SELECT * FROM canonica)) d$q$, :'u5_canonica', :'u5_api'),'0');
\unset u5_canonica
\unset u5_api
