-- POC U5 — captura de IDs de los fixtures (§13.4) con \gset y publicación como
-- parámetros de sesión poc.* para las pruebas (legibles con pg_temp.id).
SELECT
    (SELECT id FROM categoria WHERE nombre = 'POC categoría') AS c1,
    (SELECT id FROM usuario WHERE mail = 'poc.u1@ejemplo.test') AS u1,
    (SELECT id FROM usuario WHERE mail = 'poc.u2@ejemplo.test') AS u2,
    (SELECT id FROM producto WHERE nombre = 'POC P1') AS p1,
    (SELECT id FROM producto WHERE nombre = 'POC P2') AS p2,
    (SELECT id FROM producto WHERE nombre = 'POC P3') AS p3,
    (SELECT id FROM producto WHERE nombre = 'POC P4') AS p4,
    (SELECT p.id FROM pedido p JOIN usuario u ON u.id = p.usuario_id
     WHERE u.mail = 'poc.u1@ejemplo.test' AND NOT p.eliminado) AS o1,
    (SELECT p.id FROM pedido p JOIN usuario u ON u.id = p.usuario_id
     WHERE u.mail = 'poc.u2@ejemplo.test') AS o2,
    (SELECT p.id FROM pedido p JOIN usuario u ON u.id = p.usuario_id
     WHERE u.mail = 'poc.u1@ejemplo.test' AND p.eliminado) AS o3
\gset

SELECT set_config('poc.c1', :'c1', false) AS c1,
       set_config('poc.u1', :'u1', false) AS u1,
       set_config('poc.u2', :'u2', false) AS u2,
       set_config('poc.p1', :'p1', false) AS p1,
       set_config('poc.p2', :'p2', false) AS p2,
       set_config('poc.p3', :'p3', false) AS p3,
       set_config('poc.p4', :'p4', false) AS p4,
       set_config('poc.o1', :'o1', false) AS o1,
       set_config('poc.o2', :'o2', false) AS o2,
       set_config('poc.o3', :'o3', false) AS o3;

-- Estado esperado de los fixtures, usado para comprobar ausencia de residuos.
\set estado_fixture 'lineas=[] stock_p1=10 stock_p2=2 total_o1=0.00'
