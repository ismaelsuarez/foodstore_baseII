# Spec: vista_usuarios_publico

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`usuario`: `id`, `nombre`, `apellido`, `mail`, `rol`, `contrasena`, `celular`, `eliminado`. `rol` es una columna del dominio; no define por sí misma el rol PostgreSQL `rol_soporte`.

## OBJETIVO

Minimizar la información accesible para soporte. La vista no expone `contrasena` ni `celular`; tampoco expone usuarios eliminados.

## CONSULTA

```sql
SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE;
```

## OBJETO_CANDIDATO

Definición de la vista en [views.sql](../sql/views.sql) y concesión en [seguridad.sql](../sql/seguridad.sql).

```sql
CREATE OR REPLACE VIEW v_usuarios_publico AS
SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE;
```

Precondición de la concesión: `rol_soporte` debe existir. No se define ni crea en este bloque; tampoco se inventan LOGIN, contraseña, membresías o atributos.

```sql
GRANT SELECT ON v_usuarios_publico TO rol_soporte;
```

## CRITERIO_DE_ACEPTACION

- Exponer exactamente `id`, `nombre`, `apellido`, `mail`, `rol`; omitir `contrasena` y `celular`.
- Excluir usuarios eliminados y cumplir equivalencia bidireccional con la consulta manual.
- Verificar posteriormente que `rol_soporte` puede consultar la vista y no puede acceder a `usuario.contrasena` ni `usuario.celular` directamente o mediante permisos heredados.
- No conceder SELECT sobre `usuario` para hacer funcionar esta vista.

## RIESGOS

Instalación prevista en una copia limpia. Si existe una versión anterior, `CREATE OR REPLACE VIEW` puede no aceptar cambios de columnas; evaluar dependencias y migración por separado. Este bloque no elimina objetos instalados. El nombre «publico» no concede permisos a `PUBLIC`. Un `GRANT` sobre la vista no revoca permisos existentes sobre la tabla ni otras rutas de acceso. Revisar permisos directos, por columna, membresías, `PUBLIC` y privilegios elevados antes de afirmar seguridad efectiva.

## VALIDACION_PENDIENTE

Pendiente: instalar en una copia con el modelo oficial y comprobar las columnas expuestas. Comparar con la consulta manual mediante `EXCEPT` en ambos sentidos: el criterio esperado es que ambas diferencias estén vacías, no un resultado ya obtenido. Usar un mismo estado de datos para ambas consultas. Una vista convencional no demuestra por sí sola mejora de rendimiento. La prueba real de permisos queda pendiente del bloque de ejecución: verificar existencia del rol, acceso al esquema y privilegios del propietario de la vista; inventariar permisos efectivos; realizar prueba positiva sobre la vista y negativa sobre las dos columnas sensibles de la tabla bajo el rol previsto. Usar únicamente una sesión autorizada, sin diseñar credenciales. Si existen accesos indebidos, documentarlos y proponer corrección separada; este bloque no los revoca.