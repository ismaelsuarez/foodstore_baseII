-- POC U5 — P2: fixtures sintéticos (design.md §13.4). Sin seed canónico.
-- 'POC_SIN_CREDENCIAL' es un marcador, no un hash ni una credencial.
\ir 00_guardas.sql
\ir 00_guarda_sin_roles.sql

BEGIN;

INSERT INTO categoria (nombre) VALUES ('POC categoría');

INSERT INTO usuario (nombre, apellido, mail, contrasena, rol, eliminado) VALUES
    ('POC', 'Uno', 'poc.u1@ejemplo.test', 'POC_SIN_CREDENCIAL', 'USUARIO', FALSE),
    ('POC', 'Dos', 'poc.u2@ejemplo.test', 'POC_SIN_CREDENCIAL', 'USUARIO', TRUE);

INSERT INTO producto (nombre, precio, stock, disponible, eliminado, categoria_id)
SELECT v.nombre, v.precio, v.stock, v.disponible, v.eliminado, c.id
FROM (VALUES
        ('POC P1', 1250.50, 10, TRUE,  FALSE),
        ('POC P2',  300.00,  2, TRUE,  FALSE),
        ('POC P3',  100.00,  5, FALSE, FALSE),
        ('POC P4',  100.00,  5, TRUE,  TRUE)
     ) AS v(nombre, precio, stock, disponible, eliminado)
CROSS JOIN categoria c
WHERE c.nombre = 'POC categoría';

INSERT INTO pedido (usuario_id, forma_pago, eliminado)
SELECT u.id, 'EFECTIVO', v.eliminado
FROM (VALUES (1, 'poc.u1@ejemplo.test', FALSE),
             (2, 'poc.u2@ejemplo.test', FALSE),
             (3, 'poc.u1@ejemplo.test', TRUE)) AS v(orden, mail, eliminado)
JOIN usuario u ON u.mail = v.mail
ORDER BY v.orden;

COMMIT;

\ir 00_ids.sql

SELECT 'categoria' AS tabla, count(*) FROM categoria
UNION ALL SELECT 'usuario', count(*) FROM usuario
UNION ALL SELECT 'producto', count(*) FROM producto
UNION ALL SELECT 'pedido', count(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', count(*) FROM detalle_pedido;
