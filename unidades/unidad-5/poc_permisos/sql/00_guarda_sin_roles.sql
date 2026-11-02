-- POC U5 — guarda previa a P3: ningún rol de U5 ni tst_u5_* existe todavía.
DO $guarda$
DECLARE
    v_roles text[];
BEGIN
    SELECT array_agg(rolname::text ORDER BY rolname) INTO v_roles
    FROM pg_roles
    WHERE rolname IN ('rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
                      'rol_app_autenticacion', 'rol_propietario_ventas',
                      'rol_propietario_credenciales', 'app_web', 'admin_datos', 'usuario_anon')
       OR rolname LIKE 'tst\_u5\_%';
    IF v_roles IS NOT NULL THEN
        RAISE EXCEPTION 'GUARDA: roles de U5 ya existentes %', v_roles;
    END IF;
END
$guarda$;
