-- POC U5 — huella de catálogo del esquema public (F0 en P2, F1 en P7).
-- Cubre VP-02, VP-03, VP-04 y VP-12: propietarios, definiciones, ACL de rutinas,
-- triggers, estructura de tablas y ACL de secuencias. El ACL de las tablas se
-- registra aparte (acl_tablas.sql) porque los GRANT de la POC lo cambian a propósito.
-- Ejecutar con psql -At; cada fila es una línea comparable con diff.
\ir 00_guardas.sql

SELECT linea FROM (
    SELECT 'base|' || datname || '|owner=' || pg_get_userbyid(datdba)
    FROM pg_database WHERE datname = current_database()
    UNION ALL
    SELECT 'esquema|public|owner=' || pg_get_userbyid(nspowner)
           || '|acl=' || coalesce(nspacl::text, 'NULL')
    FROM pg_namespace WHERE nspname = 'public'
    UNION ALL
    SELECT 'tipo|' || t.typname || '|owner=' || pg_get_userbyid(t.typowner) || '|labels='
           || (SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
               FROM pg_enum e WHERE e.enumtypid = t.oid)
    FROM pg_type t WHERE t.typnamespace = 'public'::regnamespace AND t.typtype = 'e'
    UNION ALL
    SELECT 'tabla|' || relname || '|owner=' || pg_get_userbyid(relowner)
    FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
    UNION ALL
    SELECT 'columna|' || c.relname || '.' || a.attname || '|' || format_type(a.atttypid, a.atttypmod)
           || '|notnull=' || a.attnotnull || '|identity=' || a.attidentity::text
           || '|default=' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
      AND a.attnum > 0 AND NOT a.attisdropped
    UNION ALL
    SELECT 'restriccion|' || conrelid::regclass || '.' || conname || '|' || pg_get_constraintdef(oid)
    FROM pg_constraint WHERE connamespace = 'public'::regnamespace
    UNION ALL
    SELECT 'indice|' || i.indexrelid::regclass || '|' || pg_get_indexdef(i.indexrelid)
    FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
    WHERE c.relnamespace = 'public'::regnamespace
    UNION ALL
    SELECT 'secuencia|' || relname || '|owner=' || pg_get_userbyid(relowner)
           || '|acl=' || coalesce(relacl::text, 'NULL')
    FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'S'
    UNION ALL
    SELECT 'rutina|' || p.oid::regprocedure || '|owner=' || pg_get_userbyid(p.proowner)
           || '|prosecdef=' || p.prosecdef
           || '|proconfig=' || coalesce(array_to_string(p.proconfig, ';'), 'NULL')
           || '|def_md5=' || md5(pg_get_functiondef(p.oid))
    FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
    UNION ALL
    SELECT 'rutina_acl|' || p.oid::regprocedure || '|' || coalesce(p.proacl::text, 'NULL')
    FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
    UNION ALL
    SELECT 'trigger|' || tgrelid::regclass || '.' || tgname || '|' || tgfoid::regprocedure
           || '|enabled=' || tgenabled::text || '|' || pg_get_triggerdef(oid)
    FROM pg_trigger WHERE NOT tgisinternal
) h(linea)
ORDER BY linea;
