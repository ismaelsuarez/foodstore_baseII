-- POC U5 — P6: casos T01–T06, T08–T11 y T13 (design.md §13.5).
-- T07 está en 08_t07_ablacion.sql; T12 en 05_t12_atomicidad.sql; T14 compara huellas.
-- Las llamadas a la API corren con SET ROLE app_web; las verificaciones con RESET ROLE.
-- Cada grupo corre en BEGIN … ROLLBACK y luego se comprueba que no quedaron residuos.
\ir 00_guardas.sql
\ir 00_helpers.sql
\ir 00_ids.sql

SELECT pg_temp.verificar('F.estado_inicial', 'SELECT pg_temp.estado()', :'estado_fixture');

-- ===== T01 y T02 =====
BEGIN;
SET ROLE app_web;
SELECT pg_temp.esperar_ok('T01.api',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 3)$q$);
RESET ROLE;
SELECT pg_temp.verificar('T01.estado', 'SELECT pg_temp.estado()',
    'lineas=[O1/P1:3:1250.50:3751.50] stock_p1=7 stock_p2=2 total_o1=3751.50');
SET ROLE app_web;
SELECT pg_temp.esperar_ok('T02.api',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p2'), 2)$q$);
RESET ROLE;
SELECT pg_temp.verificar('T02.estado', 'SELECT pg_temp.estado()',
    'lineas=[O1/P1:3:1250.50:3751.50,O1/P2:2:300.00:600.00] stock_p1=7 stock_p2=0 total_o1=4351.50');
ROLLBACK;
SELECT pg_temp.verificar('T02.rollback', 'SELECT pg_temp.estado()', :'estado_fixture');

-- ===== T03: acceso directo denegado (diez sentencias enumeradas en §13.5) =====
BEGIN;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T03.01_insert_detalle',
    $q$INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
       VALUES (pg_temp.id('o1'), pg_temp.id('p1'), 1, 1250.50)$q$, '42501');
SELECT pg_temp.esperar_error('T03.02_update_detalle',
    $q$UPDATE detalle_pedido SET cantidad = 1$q$, '42501');
SELECT pg_temp.esperar_error('T03.03_delete_detalle',
    $q$DELETE FROM detalle_pedido$q$, '42501');
SELECT pg_temp.esperar_error('T03.04_select_detalle',
    $q$SELECT * FROM detalle_pedido$q$, '42501');
SELECT pg_temp.esperar_error('T03.05_call_procedimiento',
    $q$CALL public.registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
SELECT pg_temp.esperar_error('T03.06_calcular_total',
    $q$SELECT public.calcular_total_pedido(pg_temp.id('o1'))$q$, '42501');
SELECT pg_temp.esperar_error('T03.07_update_stock',
    $q$UPDATE producto SET stock = 0$q$, '42501');
SELECT pg_temp.esperar_error('T03.08_update_total',
    $q$UPDATE pedido SET total = 0$q$, '42501');
SELECT pg_temp.esperar_error('T03.09_select_total',
    $q$SELECT total FROM pedido$q$, '42501');
SELECT pg_temp.esperar_error('T03.10_select_usuario',
    $q$SELECT * FROM usuario$q$, '42501');
RESET ROLE;
ROLLBACK;
SELECT pg_temp.verificar('T03.residuo', 'SELECT pg_temp.estado()', :'estado_fixture');

-- ===== T04: INSERT por columna en pedido =====
BEGIN;
SET ROLE app_web;
SELECT pg_temp.esperar_ok('T04.1_insert_columnas_permitidas',
    $q$INSERT INTO pedido (usuario_id, forma_pago) VALUES (pg_temp.id('u1'), 'TARJETA') RETURNING id$q$);
SELECT pg_temp.esperar_error('T04.2_insert_con_fecha',
    $q$INSERT INTO pedido (usuario_id, forma_pago, fecha)
       VALUES (pg_temp.id('u1'), 'TARJETA', DATE '2000-01-01') RETURNING id$q$, '42501');
SELECT pg_temp.esperar_error('T04.3_insert_con_total',
    $q$INSERT INTO pedido (usuario_id, forma_pago, total)
       VALUES (pg_temp.id('u1'), 'TARJETA', 0) RETURNING id$q$, '42501');
RESET ROLE;
SELECT pg_temp.verificar('T04.1_fila',
    $q$SELECT string_agg(format('usuario=%s fecha_hoy=%s estado=%s total=%s eliminado=%s',
                               CASE usuario_id WHEN pg_temp.id('u1') THEN 'U1' ELSE usuario_id::text END,
                               (fecha = CURRENT_DATE)::text, estado, total, eliminado::text), ',')
       FROM pedido WHERE forma_pago = 'TARJETA'$q$,
    'usuario=U1 fecha_hoy=true estado=PENDIENTE total=0.00 eliminado=false');
ROLLBACK;
SELECT pg_temp.verificar('T04.residuo',
    $q$SELECT count(*)::text FROM pedido WHERE forma_pago = 'TARJETA'$q$, '0');

-- ===== T05: errores de negocio a través de la API =====
BEGIN;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T05.1_cantidad_0',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 0)$q$, '22023');
SELECT pg_temp.esperar_error('T05.2_cantidad_null',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), NULL)$q$, '22023');
SELECT pg_temp.esperar_error('T05.3_pedido_inexistente',
    $q$SELECT public.api_registrar_detalle_pedido(-1, pg_temp.id('p1'), 1)$q$, '23503');
SELECT pg_temp.esperar_error('T05.4_pedido_eliminado_O3',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o3'), pg_temp.id('p1'), 1)$q$, '23514');
SELECT pg_temp.esperar_error('T05.5_usuario_eliminado_O2',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o2'), pg_temp.id('p1'), 1)$q$, '23514');
SELECT pg_temp.esperar_error('T05.6_producto_no_disponible_P3',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p3'), 1)$q$, '23514');
SELECT pg_temp.esperar_error('T05.7_producto_eliminado_P4',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p4'), 1)$q$, '23514');
SELECT pg_temp.esperar_error('T05.8_stock_insuficiente',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p2'), 3)$q$, '23514');
RESET ROLE;
SELECT pg_temp.verificar('T05.1-8_sin_efectos', 'SELECT pg_temp.estado()', :'estado_fixture');
SET ROLE app_web;
SELECT pg_temp.esperar_ok('T05.9a_primera_llamada',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$);
SELECT pg_temp.esperar_error('T05.9b_duplicado',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '23505');
RESET ROLE;
SELECT pg_temp.verificar('T05.9_estado', 'SELECT pg_temp.estado()',
    'lineas=[O1/P1:1:1250.50:1250.50] stock_p1=9 stock_p2=2 total_o1=1250.50');
ROLLBACK;
SELECT pg_temp.verificar('T05.residuo', 'SELECT pg_temp.estado()', :'estado_fixture');

-- ===== T06: sin efectos parciales =====
-- (a) error de negocio después de una venta válida
BEGIN;
SET ROLE app_web;
SELECT pg_temp.esperar_ok('T06a.venta_valida',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 3)$q$);
SAVEPOINT s;
SELECT pg_temp.esperar_error('T06a.stock_insuficiente',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p2'), 5)$q$, '23514');
ROLLBACK TO SAVEPOINT s;
RESET ROLE;
SELECT pg_temp.verificar('T06a.estado', 'SELECT pg_temp.estado()',
    'lineas=[O1/P1:3:1250.50:3751.50] stock_p1=7 stock_p2=2 total_o1=3751.50');
ROLLBACK;
SELECT pg_temp.verificar('T06a.residuo', 'SELECT pg_temp.estado()', :'estado_fixture');

-- (b) fallo de permisos en el trigger AFTER, después del INSERT de la línea
BEGIN;
REVOKE EXECUTE ON FUNCTION public.calcular_total_pedido(BIGINT) FROM rol_propietario_ventas;
SAVEPOINT s;
SET ROLE app_web;
SELECT pg_temp.esperar_error('T06b.trigger_after_sin_execute',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$, '42501');
ROLLBACK TO SAVEPOINT s;
RESET ROLE;
SELECT pg_temp.verificar('T06b.estado', 'SELECT pg_temp.estado()', :'estado_fixture');
ROLLBACK;
SELECT pg_temp.verificar('T06b.residuo_acl',
    $q$SELECT has_function_privilege('rol_propietario_ventas',
             'public.calcular_total_pedido(bigint)', 'EXECUTE')::text$q$, 'true');

-- ===== T08: funciones trigger sin EXECUTE para rol_propietario_ventas ni PUBLIC =====
SELECT pg_temp.verificar('T08.catalogo',
    $q$SELECT count(*)::text
       FROM pg_proc p
       CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.oid IN ('public.fn_set_subtotal()'::regprocedure,
                       'public.fn_validar_detalle_vigente()'::regprocedure,
                       'public.fn_recalcular_total_insert()'::regprocedure,
                       'public.fn_recalcular_total_update()'::regprocedure,
                       'public.fn_recalcular_total_delete()'::regprocedure)
         AND a.privilege_type = 'EXECUTE'
         AND a.grantee IN (0, 'rol_propietario_ventas'::regrole)$q$, '0');
SELECT pg_temp.verificar('T08.has_function_privilege',
    $q$SELECT string_agg(has_function_privilege('rol_propietario_ventas', f, 'EXECUTE')::text, ',' ORDER BY f)
       FROM unnest(ARRAY['public.fn_recalcular_total_delete()', 'public.fn_recalcular_total_insert()',
                         'public.fn_recalcular_total_update()', 'public.fn_set_subtotal()',
                         'public.fn_validar_detalle_vigente()']) AS f$q$,
    'false,false,false,false,false');

-- ===== T09: secuencia de identidad de detalle_pedido sin GRANT =====
SELECT pg_temp.verificar('T09.catalogo',
    $q$SELECT coalesce(relacl::text, 'NULL') FROM pg_class
       WHERE oid = pg_get_serial_sequence('public.detalle_pedido', 'id')::regclass$q$, 'NULL');

-- ===== T10: FOR SHARE / FOR UPDATE exigen UPDATE sobre alguna columna (D11) =====
BEGIN;
SET ROLE rol_propietario_ventas;
SELECT pg_temp.esperar_ok('T10.1_for_share_usuario_matriz_completa',
    $q$SELECT eliminado FROM usuario WHERE id = pg_temp.id('u1') FOR SHARE$q$);
RESET ROLE;
REVOKE UPDATE (celular) ON usuario FROM rol_propietario_ventas;
SET ROLE rol_propietario_ventas;
SELECT pg_temp.esperar_error('T10.2_for_share_usuario_sin_update',
    $q$SELECT eliminado FROM usuario WHERE id = pg_temp.id('u1') FOR SHARE$q$, '42501');
RESET ROLE;
REVOKE UPDATE (total) ON pedido FROM rol_propietario_ventas;
SET ROLE rol_propietario_ventas;
SELECT pg_temp.esperar_error('T10.3_for_update_pedido_sin_update',
    $q$SELECT usuario_id FROM pedido WHERE id = pg_temp.id('o1') FOR UPDATE$q$, '42501');
RESET ROLE;
ROLLBACK;

-- ===== T11: search_path fijo frente a una tabla temporal homónima =====
BEGIN;
SET ROLE app_web;
-- Sentencia literal de §13.5; se registra sin veredicto (LIKE exige SELECT sobre el origen).
SELECT pg_temp.observar('T11.literal_create_temp_like',
    $q$CREATE TEMP TABLE producto (LIKE public.producto)$q$);
-- Variante con columnas explícitas, para probar la hipótesis H8.
SELECT pg_temp.esperar_ok('T11.create_temp_explicita',
    $q$CREATE TEMP TABLE producto (id BIGINT, nombre VARCHAR(120), precio NUMERIC(12,2),
                                   stock INTEGER, disponible BOOLEAN, categoria_id BIGINT,
                                   eliminado BOOLEAN)$q$);
SELECT pg_temp.esperar_ok('T11.insert_temp',
    $q$INSERT INTO pg_temp.producto VALUES (pg_temp.id('p1'), 'POC P1 temporal', 1250.50, 999,
                                             TRUE, pg_temp.id('c1'), FALSE)$q$);
SELECT pg_temp.esperar_ok('T11.api',
    $q$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'), pg_temp.id('p1'), 1)$q$);
RESET ROLE;
SELECT pg_temp.verificar('T11.public_producto',
    $q$SELECT stock::text FROM public.producto WHERE id = pg_temp.id('p1')$q$, '9');
SELECT pg_temp.verificar('T11.temp_producto',
    $q$SELECT stock::text FROM pg_temp.producto WHERE id = pg_temp.id('p1')$q$, '999');
ROLLBACK;
SELECT pg_temp.verificar('T11.residuo', 'SELECT pg_temp.estado()', :'estado_fixture');
SELECT pg_temp.verificar('T11.residuo_temp',
    $q$SELECT coalesce(to_regclass('pg_temp.producto')::text, 'NULL')$q$, 'NULL');

-- ===== T13: catálogo de la API y del rol propietario =====
SELECT pg_temp.verificar('T13.propietario',
    $q$SELECT pg_get_userbyid(proowner)::text FROM pg_proc
       WHERE oid = 'public.api_registrar_detalle_pedido(bigint,bigint,integer)'::regprocedure$q$,
    'rol_propietario_ventas');
SELECT pg_temp.verificar('T13.prosecdef',
    $q$SELECT prosecdef::text FROM pg_proc
       WHERE oid = 'public.api_registrar_detalle_pedido(bigint,bigint,integer)'::regprocedure$q$,
    'true');
SELECT pg_temp.verificar('T13.proconfig',
    $q$SELECT array_to_string(proconfig, ';') FROM pg_proc
       WHERE oid = 'public.api_registrar_detalle_pedido(bigint,bigint,integer)'::regprocedure$q$,
    'search_path=public, pg_temp');
SELECT pg_temp.verificar('T13.acl',
    $q$SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END
                         || ':' || a.privilege_type, ',' ORDER BY pg_get_userbyid(a.grantee))
       FROM pg_proc p
       CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.oid = 'public.api_registrar_detalle_pedido(bigint,bigint,integer)'::regprocedure$q$,
    'rol_app_escritura:EXECUTE,rol_propietario_ventas:EXECUTE');
SELECT pg_temp.verificar('T13.rol_propietario_atributos',
    $q$SELECT format('login=%s inherit=%s super=%s createrole=%s createdb=%s replication=%s bypassrls=%s',
                     rolcanlogin::text, rolinherit::text, rolsuper::text, rolcreaterole::text,
                     rolcreatedb::text, rolreplication::text, rolbypassrls::text)
       FROM pg_roles WHERE rolname = 'rol_propietario_ventas'$q$,
    'login=false inherit=false super=false createrole=false createdb=false replication=false bypassrls=false');
SELECT pg_temp.verificar('T13.rol_propietario_miembros',
    $q$SELECT count(*)::text FROM pg_auth_members WHERE roleid = 'rol_propietario_ventas'::regrole$q$,
    '0');
SELECT pg_temp.verificar('T13.create_public_roles_poc',
    $q$SELECT string_agg(r || '=' || has_schema_privilege(r, 'public', 'CREATE'), ',' ORDER BY r)
       FROM unnest(ARRAY['app_web', 'rol_app_escritura', 'rol_propietario_ventas',
                         'tst_u5_sin_privilegios']) AS r$q$,
    'app_web=false,rol_app_escritura=false,rol_propietario_ventas=false,tst_u5_sin_privilegios=false');
SELECT pg_temp.verificar('T13.create_public_PUBLIC',
    $q$SELECT count(*)::text FROM pg_namespace n
       CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
       WHERE n.nspname = 'public' AND a.grantee = 0 AND a.privilege_type = 'CREATE'$q$, '0');
-- Complementos: membresía sin ADMIN OPTION y rol sin privilegios sin acceso a la API.
SELECT pg_temp.verificar('T13.membresia_app_web',
    $q$SELECT string_agg(format('%s<-%s admin=%s', pg_get_userbyid(roleid), pg_get_userbyid(member),
                                admin_option::text), ',' ORDER BY 1)
       FROM pg_auth_members
       WHERE pg_get_userbyid(member) IN ('app_web', 'rol_app_escritura', 'rol_propietario_ventas',
                                         'tst_u5_sin_privilegios')$q$,
    'rol_app_escritura<-app_web admin=false');
SELECT pg_temp.verificar('T13.sin_privilegios_api',
    $q$SELECT has_function_privilege('tst_u5_sin_privilegios',
             'public.api_registrar_detalle_pedido(bigint,bigint,integer)', 'EXECUTE')::text$q$,
    'false');

SELECT pg_temp.verificar('F.estado_final', 'SELECT pg_temp.estado()', :'estado_fixture');
