# Spec: indice_usuario_mail_lower

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`usuario`: `id`, `nombre`, `apellido`, `mail`, `rol`, `eliminado`. No se asume ninguna restricción de unicidad ni el inventario actual de índices.

## OBJETIVO

Evaluar una búsqueda de usuarios no eliminados por correo sin distinguir mayúsculas, sin cambiar las reglas de unicidad.

## CONSULTA

```sql
SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE
  AND lower(mail) = lower('ANA.GOMEZ@FOODSTORE.TEST');
```

## OBJETO_CANDIDATO

**CANDIDATO_PENDIENTE_DE_MEDICION**. Definición en [indices.sql](../sql/indices.sql).

```sql
CREATE INDEX idx_usuario_mail_lower
    ON usuario (lower(mail))
    WHERE eliminado = FALSE;
```

B-tree de expresión parcial, **no UNIQUE**. Aunque exista `UNIQUE(mail)`, `lower(mail)` es otra expresión: no se infiere unicidad case-insensitive ni redundancia.

## CRITERIO_DE_ACEPTACION

- Conservar todos los usuarios no eliminados que coincidan, sin asumir un único resultado.
- No introducir unicidad ni sustituir restricciones existentes.
- Aceptar el índice solo si la medición justifica lectura frente a espacio y mantenimiento.

## RIESGOS

Puede haber varias coincidencias con distinta capitalización. La transformación depende del tipo y configuración del correo; verificar su comportamiento real. Cambios de `mail` o `eliminado` afectan el índice. No es un contrato de autenticación ni garantiza una búsqueda cubierta.

## VALIDACION_PENDIENTE

Pendiente: inventariar índices y restricciones reales, obtener una nueva línea base y medir antes/después con `EXPLAIN (ANALYZE, BUFFERS)`. Realizar tres corridas por variante, descartar la primera como calentamiento y comparar el promedio de las otras dos sobre el mismo dataset. Registrar planes, filas, buffers y tiempos reales; medir también almacenamiento y mantenimiento en escrituras. No reutilizar cifras históricas como evidencia de este contrato. Verificar distintas capitalizaciones, ausencia de coincidencias y usuarios eliminados; usar datos válidos según las restricciones reales.