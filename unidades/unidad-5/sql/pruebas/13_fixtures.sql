-- SOLO dentro de BEGIN ... ROLLBACK, como superusuario; nunca ejecutar aisladamente.
-- IDs reservados en 12_reservar_ids.sql, reutilizados en ambas rutas de equivalencia.
-- Datos sintéticos, sin contraseñas ni hashes literales. SEED_NO_AUTH es un marcador.
SELECT pg_temp.sin_fixtures('FIXTURE.sin_colisiones');
INSERT INTO public.categoria(id,nombre) OVERRIDING SYSTEM VALUE
VALUES (pg_temp.id('c1'),'__U5_VERIFICACION__');
INSERT INTO public.usuario(id,nombre,apellido,mail,contrasena,rol,eliminado) OVERRIDING SYSTEM VALUE VALUES
 (pg_temp.id('u1'),'U5','Prueba','u5.verificacion.uno@ejemplo.test','SEED_NO_AUTH','USUARIO',false),
 (pg_temp.id('u2'),'U5','Baja','u5.verificacion.baja@ejemplo.test','SEED_NO_AUTH','USUARIO',true),
 (pg_temp.id('ua'),'U5','Admin','u5.verificacion.admin@ejemplo.test','SEED_NO_AUTH','ADMIN',false);
INSERT INTO public.producto(id,nombre,precio,stock,disponible,eliminado,categoria_id)
OVERRIDING SYSTEM VALUE VALUES
 (pg_temp.id('p1'),'__U5_VERIFICACION_P1',1250.50,10,true,false,pg_temp.id('c1')),
 (pg_temp.id('p2'),'__U5_VERIFICACION_P2',300,2,true,false,pg_temp.id('c1')),
 (pg_temp.id('p3'),'__U5_VERIFICACION_P3',100,5,false,false,pg_temp.id('c1')),
 (pg_temp.id('p4'),'__U5_VERIFICACION_P4',100,5,true,true,pg_temp.id('c1'));
INSERT INTO public.pedido(id,usuario_id,forma_pago,eliminado) OVERRIDING SYSTEM VALUE VALUES
 (pg_temp.id('o1'),pg_temp.id('u1'),'EFECTIVO',false),
 (pg_temp.id('o2'),pg_temp.id('u2'),'EFECTIVO',false),
 (pg_temp.id('o3'),pg_temp.id('u1'),'EFECTIVO',true);
-- -1 se usa como ausente en casos negativos: no asumirlo sin comprobar.
DO $g$
BEGIN
 IF EXISTS (SELECT FROM public.pedido WHERE id=-1)
 OR EXISTS (SELECT FROM public.producto WHERE id=-1)
 OR EXISTS (SELECT FROM public.usuario WHERE id=-1) THEN
  RAISE EXCEPTION 'La referencia negativa de prueba ya existe; no ejecutar casos';
 END IF;
END $g$;
