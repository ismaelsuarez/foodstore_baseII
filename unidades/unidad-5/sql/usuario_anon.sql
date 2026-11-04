-- Food Store — Unidad 5, Parte D: anonimización de usuario.
-- Crea usuario_anon a partir de usuario con datos sintéticos deterministas y compara la
-- cantidad de usuarios por rol y mes de alta en ambas tablas.
-- Ejecutar con psql -v ON_ERROR_STOP=1 sobre una base descartable con schema.sql y
-- datos_iniciales.sql. No modifica usuario ni el esquema canónico.

-- El mes de alta depende de la zona horaria de la sesión: se fija para ambas consultas.
SET TimeZone = 'America/Argentina/Buenos_Aires';

-- 1. Construcción de usuario_anon
-- Misma estructura que usuario (columnas, tipos y NOT NULL), sin identidad ni UNIQUE.
-- Identificadores personales: tokens derivados del id, siempre iguales para el mismo usuario.
-- Se conservan rol, eliminado y created_at, que sostienen la equivalencia estadística.
BEGIN;

CREATE TABLE usuario_anon (LIKE usuario);
ALTER TABLE usuario_anon ADD PRIMARY KEY (id);

INSERT INTO usuario_anon (id, nombre, apellido, mail, celular, contrasena, rol, eliminado, created_at)
SELECT id,
       'Usuario ' || id,
       'Anonimo',
       'usuario' || id || '@anon.test',
       CASE WHEN celular IS NULL THEN NULL ELSE lpad(id::text, 10, '0') END,
       'ANON_NO_AUTH',
       rol,
       eliminado,
       created_at
FROM usuario;

COMMIT;

\echo '== usuario_anon'
SELECT * FROM usuario_anon ORDER BY id;

-- 2. Usuarios por rol y mes de alta, sobre usuario_anon
\echo '== Consulta sobre usuario_anon'
SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
FROM usuario_anon
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;

-- 3. La misma consulta sobre usuario
\echo '== Consulta sobre usuario'
SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
FROM usuario
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;

-- 4. Equivalencia: diferencia en ambos sentidos. Se esperan 0 filas distintas.
\echo '== Equivalencia (EXCEPT ALL en ambos sentidos)'
SELECT count(*) AS filas_distintas
FROM (
    (SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
     FROM usuario_anon GROUP BY rol, mes_alta
     EXCEPT ALL
     SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
     FROM usuario GROUP BY rol, mes_alta)
    UNION ALL
    (SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
     FROM usuario GROUP BY rol, mes_alta
     EXCEPT ALL
     SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
     FROM usuario_anon GROUP BY rol, mes_alta)
) AS diferencias;

-- 5. Ningún identificador personal de usuario aparece en usuario_anon. Se espera 0.
\echo '== Identificadores copiados'
SELECT count(*) AS filas_con_identificador_original
FROM usuario_anon a
WHERE EXISTS (
    SELECT 1
    FROM usuario u
    WHERE u.nombre = a.nombre
       OR u.apellido = a.apellido
       OR u.mail = a.mail
       OR u.celular = a.celular
       OR u.contrasena = a.contrasena
);
