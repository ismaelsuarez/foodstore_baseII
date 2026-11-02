-- Vista TEMP de catálogo vivo; F0/F1 toman instantáneas en la misma conexión.
-- Basada en poc_permisos/sql/huella.sql. A-1: todo "char" se convierte a text.
-- ACL de tablas/esquemas cambia deliberadamente: se verifica en 11_matriz.sql.
CREATE OR REPLACE TEMP VIEW u5_huella AS
WITH tablas AS (
    SELECT c.* FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace
      AND c.relname IN ('categoria','usuario','producto','pedido','detalle_pedido')
), rutinas AS (
    SELECT p.* FROM pg_proc p WHERE p.oid IN (
        to_regprocedure('public.registrar_detalle_pedido(bigint,bigint,integer)'),
        to_regprocedure('public.calcular_total_pedido(bigint)'),
        to_regprocedure('public.fn_set_subtotal()'),
        to_regprocedure('public.fn_validar_detalle_vigente()'),
        to_regprocedure('public.fn_recalcular_total_insert()'),
        to_regprocedure('public.fn_recalcular_total_update()'),
        to_regprocedure('public.fn_recalcular_total_delete()'))
)
SELECT 'rutina'::text AS clase, p.oid::regprocedure::text AS clave,
       concat_ws('|', pg_get_userbyid(p.proowner), p.prosecdef::text,
           coalesce(array_to_string(p.proconfig, ';'), 'NULL'),
           md5(pg_get_functiondef(p.oid))) AS valor FROM rutinas p
UNION ALL
SELECT 'rutina_acl', p.oid::regprocedure::text, coalesce(p.proacl::text, 'NULL') FROM rutinas p
UNION ALL
SELECT 'base',datname::text,pg_get_userbyid(datdba)::text
FROM pg_database WHERE datname=current_database()
UNION ALL
SELECT 'esquema','public',pg_get_userbyid(nspowner)::text FROM pg_namespace WHERE nspname='public'
UNION ALL
SELECT 'tabla', c.relname::text, concat_ws('|', c.relkind::text, pg_get_userbyid(c.relowner))
FROM tablas c
UNION ALL
SELECT 'columna', c.relname || '.' || a.attname,
       concat_ws('|', a.attnum::text, format_type(a.atttypid,a.atttypmod), a.attnotnull::text,
           a.attidentity::text, a.attgenerated::text, coalesce(pg_get_expr(d.adbin,d.adrelid),''))
FROM tablas c JOIN pg_attribute a ON a.attrelid = c.oid
LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
WHERE a.attnum > 0 AND NOT a.attisdropped
UNION ALL
SELECT 'restriccion', k.conrelid::regclass || '.' || k.conname,
       pg_get_constraintdef(k.oid) || '|' || k.convalidated::text
FROM pg_constraint k WHERE k.conrelid IN (SELECT oid FROM tablas)
UNION ALL
SELECT 'indice', i.indexrelid::regclass::text, pg_get_indexdef(i.indexrelid)
FROM pg_index i WHERE i.indrelid IN (SELECT oid FROM tablas)
UNION ALL
SELECT 'trigger', t.tgrelid::regclass || '.' || t.tgname,
       concat_ws('|', t.tgfoid::regprocedure::text, t.tgenabled::text, pg_get_triggerdef(t.oid))
FROM pg_trigger t WHERE NOT t.tgisinternal AND t.tgrelid IN (SELECT oid FROM tablas)
UNION ALL
SELECT 'secuencia', s.oid::regclass::text,
       concat_ws('|', pg_get_userbyid(s.relowner), coalesce(s.relacl::text,'NULL'))
FROM pg_class s WHERE s.oid IN (
    SELECT pg_get_serial_sequence('public.' || relname, 'id')::regclass FROM tablas)
UNION ALL
SELECT 'tipo', t.typname::text, pg_get_userbyid(t.typowner) || '|' ||
       (SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
        FROM pg_enum e WHERE e.enumtypid = t.oid)
FROM pg_type t WHERE t.typnamespace = 'public'::regnamespace
AND t.typname IN ('rol','forma_pago','estado_pedido')
UNION ALL
SELECT 'vista_u3', n.nspname || '.' || c.relname,
       concat_ws('|', c.relkind::text, pg_get_userbyid(c.relowner), pg_get_viewdef(c.oid),
                     coalesce(c.reloptions::text,'NULL'))
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public','reportes') AND c.relkind IN ('v','m')
AND c.relname IN ('v_productos_vigentes','v_usuarios_publico','v_pedidos_resumen',
                 'v_pedido_detalle','mv_facturacion_categoria_mes');
