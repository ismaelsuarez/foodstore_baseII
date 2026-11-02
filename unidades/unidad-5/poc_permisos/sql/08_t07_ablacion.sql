-- POC U5 — T07: ablación de los 23 privilegios individuales de rol_propietario_ventas
-- (design.md §13.5). USAGE sobre public se excluye porque PUBLIC lo conserva.
-- Cada ablación corre en su propia transacción: REVOKE, venta como app_web, ROLLBACK.
-- Resultado esperado de cada una: 42501.
\ir 00_guardas.sql
\ir 00_helpers.sql
\ir 00_ids.sql

SELECT pg_temp.verificar('T07.estado_inicial', 'SELECT pg_temp.estado()', :'estado_fixture');

-- T07.01
BEGIN;
REVOKE EXECUTE ON PROCEDURE public.registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.01 REVOKE EXECUTE ON PROCEDURE public.registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.02
BEGIN;
REVOKE EXECUTE ON FUNCTION public.calcular_total_pedido(BIGINT) FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.02 REVOKE EXECUTE ON FUNCTION public.calcular_total_pedido(BIGINT)',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.03
BEGIN;
REVOKE SELECT (id) ON pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.03 REVOKE SELECT (id) ON pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.04
BEGIN;
REVOKE SELECT (usuario_id) ON pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.04 REVOKE SELECT (usuario_id) ON pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.05
BEGIN;
REVOKE SELECT (eliminado) ON pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.05 REVOKE SELECT (eliminado) ON pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.06
BEGIN;
REVOKE UPDATE (total) ON pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.06 REVOKE UPDATE (total) ON pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.07
BEGIN;
REVOKE SELECT (id) ON usuario FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.07 REVOKE SELECT (id) ON usuario',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.08
BEGIN;
REVOKE SELECT (eliminado) ON usuario FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.08 REVOKE SELECT (eliminado) ON usuario',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.09
BEGIN;
REVOKE UPDATE (celular) ON usuario FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.09 REVOKE UPDATE (celular) ON usuario',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.10
BEGIN;
REVOKE SELECT (id) ON producto FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.10 REVOKE SELECT (id) ON producto',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.11
BEGIN;
REVOKE SELECT (precio) ON producto FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.11 REVOKE SELECT (precio) ON producto',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.12
BEGIN;
REVOKE SELECT (stock) ON producto FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.12 REVOKE SELECT (stock) ON producto',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.13
BEGIN;
REVOKE SELECT (disponible) ON producto FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.13 REVOKE SELECT (disponible) ON producto',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.14
BEGIN;
REVOKE SELECT (eliminado) ON producto FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.14 REVOKE SELECT (eliminado) ON producto',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.15
BEGIN;
REVOKE UPDATE (stock) ON producto FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.15 REVOKE UPDATE (stock) ON producto',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.16
BEGIN;
REVOKE SELECT (pedido_id) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.16 REVOKE SELECT (pedido_id) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.17
BEGIN;
REVOKE SELECT (producto_id) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.17 REVOKE SELECT (producto_id) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.18
BEGIN;
REVOKE SELECT (subtotal) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.18 REVOKE SELECT (subtotal) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.19
BEGIN;
REVOKE SELECT (eliminado) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.19 REVOKE SELECT (eliminado) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.20
BEGIN;
REVOKE INSERT (pedido_id) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.20 REVOKE INSERT (pedido_id) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.21
BEGIN;
REVOKE INSERT (producto_id) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.21 REVOKE INSERT (producto_id) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.22
BEGIN;
REVOKE INSERT (cantidad) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.22 REVOKE INSERT (cantidad) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

-- T07.23
BEGIN;
REVOKE INSERT (precio_unitario) ON detalle_pedido FROM rol_propietario_ventas;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T07.23 REVOKE INSERT (precio_unitario) ON detalle_pedido',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK;

SELECT pg_temp.verificar('T07.residuo', 'SELECT pg_temp.estado()', :'estado_fixture');
