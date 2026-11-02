-- POC U5 — ACL de tablas y privilegios por columna (evidencia, no forma parte de la huella).
\ir 00_guardas.sql

SELECT c.relname AS tabla, coalesce(c.relacl::text, 'NULL') AS acl_tabla
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
ORDER BY 1;

SELECT c.relname AS tabla, a.attname AS columna, a.attacl::text AS acl_columna
FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  AND a.attnum > 0 AND a.attacl IS NOT NULL
ORDER BY 1, 2;
