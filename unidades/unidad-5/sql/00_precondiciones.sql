-- Unidad 5, Parte A — inventario previo y guardas de solo lectura.
-- REQ-A05/A06/A07/A12; SEC-11/12/15/17/20; design.md §14, VP-00..VP-12.
-- Uso futuro autorizado: psql -X -v ON_ERROR_STOP=1 -v u5_base_objetivo=... -d ... -f ...
-- No usar -1: este archivo administra su transacción READ ONLY.
-- No instala extensiones, vistas ni materializadas; no corrige ACL ni colisiones.
\set ON_ERROR_STOP on
\echo ADVERTENCIA: los roles son globales del clúster; una base nueva NO aísla roles en un clúster compartido.

\if :{?u5_base_objetivo}
\else
DO $$ BEGIN
    RAISE EXCEPTION 'Debe indicar la variable psql u5_base_objetivo (-v u5_base_objetivo=nombre_autorizado)';
END $$;
\endif
SELECT current_database() = :'u5_base_objetivo' AND :'u5_base_objetivo' <> '' AS u5_base_correcta \gset
\if :u5_base_correcta
\else
DO $$ BEGIN
    RAISE EXCEPTION 'La base actual no coincide con u5_base_objetivo; instalación detenida';
END $$;
\endif

BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;

-- Validar antes de consultar catálogos dependientes de la versión/tablas.
DO $$
DECLARE
    v_nombre text;
BEGIN
    IF current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999 THEN
        RAISE EXCEPTION 'VP-00: se requiere PostgreSQL 17.x; versión observada: %',
            current_setting('server_version');
    END IF;
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'La instalación requiere usuario efectivo superusuario';
    END IF;
    FOREACH v_nombre IN ARRAY ARRAY['categoria', 'usuario', 'producto', 'pedido', 'detalle_pedido'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                       WHERE n.nspname = 'public' AND c.relname = v_nombre AND c.relkind = 'r') THEN
            RAISE EXCEPTION 'VP-02: falta tabla canónica public.%', v_nombre;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_attribute
                       WHERE attrelid = to_regclass(format('public.%I', v_nombre))
                         AND attname = 'id' AND attidentity = 'a' AND NOT attisdropped) THEN
            RAISE EXCEPTION 'VP-12: public.%.id no tiene identidad GENERATED ALWAYS canónica', v_nombre;
        END IF;
    END LOOP;
END $$;

-- VP-00/01: identidad, versión e inventario sin consultar credenciales.
SELECT current_database() AS base_actual, session_user AS usuario_sesion,
       current_user AS usuario_efectivo, current_setting('server_version') AS server_version,
       current_setting('server_version_num') AS server_version_num;
SELECT datname, pg_get_userbyid(datdba) AS propietario FROM pg_database ORDER BY datname;
SELECT rolname, rolcanlogin, rolinherit, rolsuper, rolcreatedb, rolcreaterole,
       rolreplication, rolbypassrls FROM pg_roles ORDER BY rolname;

-- VP-02/12: propietarios REALES y secuencias de identidad; no se reasignan.
SELECT n.nspname AS esquema, c.relname AS objeto, c.relkind::text AS tipo,
       pg_get_userbyid(c.relowner) AS propietario, c.relacl
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN
    ('categoria', 'usuario', 'producto', 'pedido', 'detalle_pedido')
ORDER BY 1, 2;
SELECT t.tabla, s.oid::regclass AS secuencia, pg_get_userbyid(s.relowner) AS propietario,
       s.relacl
FROM (VALUES ('categoria'), ('usuario'), ('producto'), ('pedido'), ('detalle_pedido')) t(tabla)
LEFT JOIN pg_class s ON s.oid = to_regclass(pg_get_serial_sequence(format('public.%I', t.tabla), 'id'))
ORDER BY 1;
SELECT n.nspname, t.typname, pg_get_userbyid(t.typowner) AS propietario,
       e.enumlabel, e.enumsortorder
FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
JOIN pg_enum e ON e.enumtypid = t.oid
WHERE n.nspname = 'public' AND t.typname IN ('forma_pago', 'rol', 'estado_pedido')
ORDER BY 1, 2, e.enumsortorder;

-- VP-03: definición/propietario/configuración y ACL efectiva (NULL incluye PUBLIC).
SELECT p.oid::regprocedure AS rutina, pg_get_userbyid(p.proowner) AS propietario,
       p.prokind::text AS tipo, p.prosecdef, p.proconfig,
       md5(pg_get_functiondef(p.oid)) AS huella_definicion,
       CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type, a.is_grantable
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
WHERE n.nspname = 'public' AND p.proname IN
    ('registrar_detalle_pedido', 'calcular_total_pedido', 'fn_set_subtotal',
     'fn_validar_detalle_vigente', 'fn_recalcular_total_insert',
     'fn_recalcular_total_update', 'fn_recalcular_total_delete')
ORDER BY 1, 7;

-- VP-04: funciones asociadas, estado y definición de los triggers canónicos.
SELECT c.oid::regclass AS tabla, t.tgname, t.tgfoid::regprocedure AS funcion,
       t.tgenabled::text AS habilitado, pg_get_triggerdef(t.oid) AS definicion
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.oid = to_regclass('public.detalle_pedido') AND NOT t.tgisinternal
ORDER BY t.tgname;

-- VP-05/06: inventario; D9 pendiente, NO se revocan CONNECT ni TEMP.
SELECT n.nspname, pg_get_userbyid(n.nspowner) AS propietario, n.nspacl,
       CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type, a.is_grantable
FROM pg_namespace n
CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
WHERE n.nspname IN ('public', 'reportes') ORDER BY 1, 4, 5;
SELECT d.datname, pg_get_userbyid(d.datdba) AS propietario, d.datacl,
       CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type, a.is_grantable
FROM pg_database d
CROSS JOIN LATERAL aclexplode(coalesce(d.datacl, acldefault('d', d.datdba))) a
WHERE d.datname = current_database() ORDER BY 4, 5;

-- VP-07: disponibilidad, instalación, ubicación y ACL; no CREATE EXTENSION.
SELECT name, default_version, installed_version FROM pg_available_extensions
WHERE name = 'pgcrypto';
SELECT e.extname, e.extversion, n.nspname AS esquema,
       pg_get_userbyid(e.extowner) AS propietario
FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname = 'pgcrypto';
SELECT p.oid::regprocedure AS rutina, p.proacl,
       CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type
FROM pg_proc p
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
WHERE p.oid IN (to_regprocedure('public.crypt(text,text)'), to_regprocedure('public.gen_salt(text)'))
ORDER BY 1, 3;
-- REVISAR: §14 VP-07 y §5.2 requieren comprobar formato/costo bcrypt en ejecución
-- autorizada. Aquí solo se inspeccionan catálogos; no se generan sales ni hashes.

-- VP-08/09: valores observados, sin modificar configuración ni datos.
SELECT pg_get_userbyid(d.defaclrole) AS rol_creador,
       coalesce(n.nspname, '(global)') AS esquema, d.defaclobjtype::text AS tipo,
       d.defaclacl FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace ORDER BY 1, 2, 3;
SELECT name, setting, unit, source FROM pg_settings WHERE name IN
    ('log_statement', 'log_parameter_max_length', 'log_parameter_max_length_on_error',
     'log_min_error_statement', 'log_min_duration_statement', 'log_file_mode',
     'logging_collector', 'password_encryption', 'createrole_self_grant') ORDER BY name;
-- REVISAR: §7/SEC-16: la configuración preventiva y la inspección de logs son
-- previas a pruebas con credenciales, no se instalan ni acreditan en esta etapa.

-- VP-10: inventario global y filtro U5 separado (no confundir pg_monitor con U5).
SELECT r.rolname AS rol, m.rolname AS miembro, g.rolname AS otorgante,
       a.admin_option, a.inherit_option, a.set_option
FROM pg_auth_members a JOIN pg_roles r ON r.oid = a.roleid
JOIN pg_roles m ON m.oid = a.member JOIN pg_roles g ON g.oid = a.grantor
ORDER BY 1, 2;
SELECT r.rolname AS rol_u5, m.rolname AS miembro, a.admin_option,
       a.inherit_option, a.set_option
FROM pg_auth_members a JOIN pg_roles r ON r.oid = a.roleid
JOIN pg_roles m ON m.oid = a.member
WHERE r.rolname IN ('rol_app_lectura', 'rol_app_escritura', 'rol_app_autenticacion',
                    'rol_soporte', 'rol_reportes', 'rol_propietario_ventas',
                    'rol_propietario_credenciales', 'app_web', 'admin_datos')
   OR m.rolname IN ('rol_app_lectura', 'rol_app_escritura', 'rol_app_autenticacion',
                    'rol_soporte', 'rol_reportes', 'rol_propietario_ventas',
                    'rol_propietario_credenciales', 'app_web', 'admin_datos')
ORDER BY 1, 2;

-- VP-11: no instala U3, no mueve ni duplica la materializada.
SELECT n.nspname AS esquema, c.relname, c.relkind::text AS tipo,
       pg_get_userbyid(c.relowner) AS propietario, c.reloptions, c.relacl
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('v_productos_vigentes', 'v_usuarios_publico', 'v_pedidos_resumen',
                   'v_pedido_detalle', 'mv_facturacion_categoria_mes')
ORDER BY 2, 1;

-- Guardas: fallar con diagnóstico, sin reparar automáticamente.
DO $$
DECLARE
    v_nombre text;
    v_oid oid;
    v_esquema text;
    v_funcion oid;
    v_esperado record;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN
        ('rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
         'rol_app_autenticacion', 'rol_propietario_ventas', 'rol_propietario_credenciales',
         'app_web', 'admin_datos') OR starts_with(rolname, 'tst_u5_')) THEN
        RAISE EXCEPTION 'VP-01: colisión con roles U5 o identidades tst_u5_; los roles son globales del clúster';
    END IF;

    FOREACH v_nombre IN ARRAY ARRAY['categoria', 'usuario', 'producto', 'pedido', 'detalle_pedido'] LOOP
        v_oid := to_regclass(format('public.%I', v_nombre));
        IF v_oid IS NULL OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = v_oid AND relkind = 'r') THEN
            RAISE EXCEPTION 'VP-02: falta tabla canónica public.%', v_nombre;
        END IF;
        IF pg_get_serial_sequence(format('public.%I', v_nombre), 'id') IS NULL
           OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = v_oid
                          AND attname = 'id' AND attidentity = 'a' AND NOT attisdropped) THEN
            RAISE EXCEPTION 'VP-12: public.%.id no tiene identidad GENERATED ALWAYS canónica', v_nombre;
        END IF;
    END LOOP;
    FOREACH v_nombre IN ARRAY ARRAY['forma_pago', 'rol', 'estado_pedido'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                       WHERE n.nspname = 'public' AND t.typname = v_nombre AND t.typtype = 'e') THEN
            RAISE EXCEPTION 'VP-02: falta ENUM canónico public.%', v_nombre;
        END IF;
    END LOOP;

    FOR v_esperado IN SELECT * FROM (VALUES
        ('public.registrar_detalle_pedido(bigint,bigint,integer)', 'p'),
        ('public.calcular_total_pedido(bigint)', 'f'),
        ('public.fn_set_subtotal()', 'f'), ('public.fn_validar_detalle_vigente()', 'f'),
        ('public.fn_recalcular_total_insert()', 'f'), ('public.fn_recalcular_total_update()', 'f'),
        ('public.fn_recalcular_total_delete()', 'f')) AS e(firma, tipo)
    LOOP
        v_oid := to_regprocedure(v_esperado.firma);
        IF v_oid IS NULL OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = v_oid
            AND prokind::text = v_esperado.tipo AND NOT prosecdef AND proconfig IS NULL) THEN
            RAISE EXCEPTION 'VP-03: rutina canónica ausente o configuración no canónica: %', v_esperado.firma;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_proc p,
                   LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                   WHERE p.oid = v_oid AND a.grantee NOT IN (0, p.proowner)) THEN
            RAISE EXCEPTION 'VP-03: ACL adicional en %; requiere revisión, no se revoca silenciosamente', v_esperado.firma;
        END IF;
    END LOOP;
    FOR v_esperado IN SELECT * FROM (VALUES
        ('trg_subtotal', 'public.fn_set_subtotal()'),
        ('trg_detalle_vigente', 'public.fn_validar_detalle_vigente()'),
        ('trg_total_detalle_insert', 'public.fn_recalcular_total_insert()'),
        ('trg_total_detalle_update', 'public.fn_recalcular_total_update()'),
        ('trg_total_detalle_delete', 'public.fn_recalcular_total_delete()')) AS e(nombre, firma)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.detalle_pedido'::regclass
                       AND tgname = v_esperado.nombre AND tgfoid = to_regprocedure(v_esperado.firma)
                       AND tgenabled = 'O' AND NOT tgisinternal) THEN
            RAISE EXCEPTION 'VP-04: trigger ausente, deshabilitado o con función distinta: %', v_esperado.nombre;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.detalle_pedido'::regclass
        AND NOT tgisinternal) <> 5 THEN
        RAISE EXCEPTION 'VP-04: se esperan exactamente cinco triggers no internos en detalle_pedido';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname IN
                   ('api_registrar_detalle_pedido', 'fn_autenticar', 'fn_resetear_password')) THEN
        RAISE EXCEPTION 'Colisión con nombres de rutinas nuevas U5 en public';
    END IF;

    -- No se presume confiable a cualquier rol que ya pueda crear en public.
    IF EXISTS (SELECT 1 FROM pg_namespace n,
               LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
               WHERE a.grantee = 0 AND a.privilege_type = 'CREATE') THEN
        RAISE EXCEPTION 'VP-05/SEC-17: PUBLIC tiene CREATE en algún esquema; los propietarios U5 no deben heredar CREATE, revisar sin corregir';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles r CROSS JOIN pg_namespace n
               WHERE n.nspname = 'public' AND NOT r.rolsuper
                 AND r.oid <> n.nspowner
                 AND r.oid <> (SELECT datdba FROM pg_database WHERE datname = current_database())
                 AND r.rolname <> 'pg_database_owner'
                 AND has_schema_privilege(r.oid, n.oid, 'CREATE')) THEN
        RAISE EXCEPTION 'VP-05/SEC-17: otros roles pueden crear en public; revisar confianza antes de instalar';
    END IF;
    -- ACL PUBLIC en tablas/columnas/secuencias/vistas daría acceso extra a roles recién creados.
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
               LATERAL aclexplode(coalesce(c.relacl, acldefault(
                   CASE WHEN c.relkind = 'S' THEN 's'::"char" ELSE 'r'::"char" END, c.relowner))) a
               WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
                 AND a.grantee = 0) OR EXISTS (
        SELECT 1 FROM pg_attribute att JOIN pg_class c ON c.oid = att.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace,
        LATERAL aclexplode(att.attacl) a WHERE n.nspname = 'public' AND a.grantee = 0) THEN
        RAISE EXCEPTION 'ACL de PUBLIC sobre relaciones/columnas de public incompatible con mínimo privilegio; revisar';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_default_acl) THEN
        RAISE EXCEPTION 'VP-08: existen privilegios por defecto previos; §6 exige exactamente las dos entradas U5, revisar sin borrar';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pgcrypto') THEN
        RAISE EXCEPTION 'VP-07: pgcrypto no está disponible en este servidor';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
                   WHERE e.extname = 'pgcrypto' AND n.nspname = 'public') THEN
        RAISE EXCEPTION 'VP-07: se requiere pgcrypto instalada en public; su instalación requiere autorización separada (§5.2)';
    END IF;
    FOREACH v_nombre IN ARRAY ARRAY['public.crypt(text,text)', 'public.gen_salt(text)'] LOOP
        v_funcion := to_regprocedure(v_nombre);
        IF v_funcion IS NULL OR NOT EXISTS (
            SELECT 1 FROM pg_depend d JOIN pg_extension e ON e.oid = d.refobjid
            WHERE d.classid = 'pg_proc'::regclass AND d.objid = v_funcion
              AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e' AND e.extname = 'pgcrypto') THEN
            RAISE EXCEPTION 'VP-07: falta función auténtica de pgcrypto: %', v_nombre;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_proc p,
                       LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                       WHERE p.oid = v_funcion AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
            RAISE EXCEPTION 'VP-07: % no concede EXECUTE a PUBLIC como presupone §2.1; revisar sin ampliar permisos', v_nombre;
        END IF;
    END LOOP;

    FOREACH v_nombre IN ARRAY ARRAY['v_productos_vigentes', 'v_usuarios_publico',
                                    'v_pedidos_resumen', 'v_pedido_detalle'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                       WHERE n.nspname = 'public' AND c.relname = v_nombre AND c.relkind = 'v'
                         AND NOT coalesce(c.reloptions, ARRAY[]::text[]) @> ARRAY['security_invoker=true']) THEN
            RAISE EXCEPTION 'VP-11: falta vista U3 public.% o usa security_invoker; no se instala/corrige automáticamente', v_nombre;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM pg_class WHERE relname = 'mv_facturacion_categoria_mes' AND relkind = 'm') <> 1 THEN
        RAISE EXCEPTION 'VP-11: se requiere una única mv_facturacion_categoria_mes existente; no se crea ni duplica';
    END IF;
    SELECT n.nspname INTO v_esquema FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'mv_facturacion_categoria_mes' AND c.relkind = 'm';
    -- REVISAR: §4.2 permite ubicación real arbitraria, pero §3.3 solo autoriza
    -- USAGE en public/reportes. Otra ubicación exige decisión humana, no GRANT nuevo.
    IF v_esquema NOT IN ('public', 'reportes') THEN
        RAISE EXCEPTION 'VP-11: materializada en esquema % fuera de public/reportes; revisar matriz de esquemas', v_esquema;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
               LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
               WHERE c.relname = 'mv_facturacion_categoria_mes' AND c.relkind = 'm' AND a.grantee = 0) THEN
        RAISE EXCEPTION 'VP-11: PUBLIC tiene privilegios sobre la materializada; revisar sin revocar silenciosamente';
    END IF;
    -- §4.1 usa IF NOT EXISTS; solo se reutiliza un esquema controlado por el instalador.
    IF EXISTS (SELECT 1 FROM pg_namespace n WHERE n.nspname = 'reportes' AND (
        n.nspowner <> (SELECT oid FROM pg_roles WHERE rolname = current_user)
        OR EXISTS (SELECT 1 FROM aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
                   WHERE a.grantee <> n.nspowner))) THEN
        RAISE EXCEPTION 'VP-05: reportes preexistente no pertenece exclusivamente al instalador o tiene ACL adicionales';
    END IF;
    RAISE NOTICE 'Inventario finalizado sin cambios; conservar salida y revisar pendientes antes de autorizar instalación';
END $$;

COMMIT;
