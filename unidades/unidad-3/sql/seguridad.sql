-- Base de Datos II - Unidad 3 / Semana 5 - TP5
-- Requiere el modelo oficial indicado en las specs de este bloque.
-- No migra tablas ni acredita compatibilidad con schema.sql de la raíz.
-- Definiciones no ejecutadas en este bloque; validación real pendiente.
-- PRECONDICIÓN:
-- el rol PostgreSQL rol_soporte debe existir antes de ejecutar este script.
-- También debe existir v_usuarios_publico, definida en views.sql.
-- No crea roles, LOGIN, contraseñas, membresías ni acceso a la tabla usuario.
-- No revoca permisos previos: revisar privilegios directos, heredados y PUBLIC.
-- Prueba real de permisos pendiente del bloque de ejecución.
-- Spec: ../specs/vista_usuarios_publico.md

GRANT SELECT ON v_usuarios_publico TO rol_soporte;