-- Unidad 5, Parte B — operaciones de prueba para la auditoría nativa.
-- Ejecutar sobre una base de laboratorio de Food Store, por TCP, para que el log registre el
-- origen de la conexión:
--   psql -X -v ON_ERROR_STOP=1 "host=127.0.0.1 dbname=<base> user=<rol>" -f auditoria_test.sql
-- La lectura no queda registrada con log_statement = mod. La inserción y la actualización sí
-- quedan registradas, y luego se revierten con ROLLBACK: no alteran los datos del proyecto.
-- El intento de inicio de sesión fallido se hace aparte, con credenciales sintéticas
-- (ver docs/informe_auditoria.md).
\set ON_ERROR_STOP on

-- Contexto de la sesión: quién, desde dónde y cuándo.
SELECT current_user AS usuario, inet_client_addr() AS origen, now() AS momento;

-- 1. Lectura
SELECT id, nombre, precio, stock
FROM public.producto
WHERE eliminado = FALSE
ORDER BY id
LIMIT 3;

BEGIN;

-- 2. Inserción
INSERT INTO public.categoria (nombre, descripcion)
VALUES ('Auditoría Parte B', 'Fila de prueba; se revierte al final')
RETURNING id, nombre;

-- 3. Actualización
UPDATE public.producto
SET stock = stock + 1
WHERE id = (SELECT min(id) FROM public.producto)
RETURNING id, stock;

ROLLBACK;

-- Comprobación: la fila de prueba no quedó guardada.
SELECT count(*) AS categorias_de_prueba
FROM public.categoria
WHERE nombre = 'Auditoría Parte B';
