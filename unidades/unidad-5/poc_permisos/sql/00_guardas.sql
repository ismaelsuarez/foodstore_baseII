-- POC U5 — guardas comunes (design.md §13.2). Cualquier fallo detiene el script
-- con ON_ERROR_STOP=1.
DO $guarda$
DECLARE
    v_bases text[];
BEGIN
    IF current_database() <> 'foodstore_u5_poc' THEN
        RAISE EXCEPTION 'GUARDA: base inesperada %', current_database();
    END IF;
    IF current_setting('server_version_num')::int NOT BETWEEN 170000 AND 179999 THEN
        RAISE EXCEPTION 'GUARDA: versión inesperada %', current_setting('server_version');
    END IF;
    SELECT array_agg(datname::text ORDER BY datname) INTO v_bases FROM pg_database;
    IF v_bases <> ARRAY['foodstore_u5_poc', 'postgres', 'template0', 'template1'] THEN
        RAISE EXCEPTION 'GUARDA: bases inesperadas %', v_bases;
    END IF;
END
$guarda$;

SELECT current_database() AS base,
       current_setting('server_version') AS server_version,
       current_user AS ejecutor;
