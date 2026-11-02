-- SEC-15.N/R, REG-05: después de ambos instaladores; misma sesión que 01_f0.sql.
\ir 00_guardas.sql
\ir 00_helpers.sql
DO $g$
BEGIN
    IF to_regclass('pg_temp.u5_f0') IS NULL OR to_regclass('pg_temp.u5_vp02') IS NULL THEN
        RAISE EXCEPTION 'Falta F0/VP-02 previo a instalación; no reconstruirlo a posteriori';
    END IF;
END $g$;
-- El ACL se excluye SOLO aquí: su valor exacto se contrasta en 11_matriz.sql.
-- Las nuevas funciones y USAGE de public no son objetos canónicos de esta huella (D-4).
CREATE TEMP VIEW u5_diferencias_f0_f1 AS
SELECT 'F0-F1'::text AS sentido, d.* FROM (
    SELECT * FROM pg_temp.u5_f0 WHERE clase <> 'rutina_acl'
    EXCEPT SELECT * FROM pg_temp.u5_huella WHERE clase <> 'rutina_acl') d
UNION ALL
SELECT 'F1-F0', d.* FROM (
    SELECT * FROM pg_temp.u5_huella h WHERE clase <> 'rutina_acl'
      -- §4.2 permite crear la materializada NUEVA en reportes si no existía.
      -- Una U3 ya presente nunca se mueve ni se excluye de la comparación.
      AND NOT (h.clase='vista_u3' AND h.clave='reportes.mv_facturacion_categoria_mes'
       AND NOT EXISTS (SELECT FROM pg_temp.u5_f0 f WHERE f.clase='vista_u3'
        AND f.clave IN ('public.mv_facturacion_categoria_mes','reportes.mv_facturacion_categoria_mes')))
    EXCEPT SELECT * FROM pg_temp.u5_f0 WHERE clase <> 'rutina_acl') d;
SELECT * FROM pg_temp.u5_diferencias_f0_f1 ORDER BY sentido, clase, clave;
SELECT pg_temp.verificar('SEC15.N.huella',
    'SELECT count(*)::text FROM pg_temp.u5_diferencias_f0_f1', '0');
SELECT pg_temp.verificar('REG05.VP02', $q$
    SELECT count(*)::text FROM pg_temp.u5_vp02 v
    LEFT JOIN pg_proc p ON p.oid = to_regprocedure(v.firma)
    WHERE p.oid IS NULL OR p.proowner IS DISTINCT FROM v.proowner
       OR pg_get_userbyid(p.proowner) IS DISTINCT FROM v.propietario
$q$, '0');
SELECT f.clave, f.valor AS acl_f0, h.valor AS acl_f1
FROM pg_temp.u5_f0 f JOIN pg_temp.u5_huella h USING (clase,clave)
WHERE f.clase='rutina_acl' ORDER BY f.clave;
