# Unidad 4 — FNBC y desnormalización controlada

Trabajo sobre normalización avanzada, Forma Normal de Boyce-Codd,
descomposición lossless y desnormalización controlada aplicada a Food
Store.

## Contenido

- `sql/` — scripts SQL de esta unidad.
- `specs/` — especificaciones utilizadas como contrato antes de generar SQL.
- `informes/` — informe consolidado de ambas partes.

## Artefactos

- [specs/u4_fnbc_control_lote.md](specs/u4_fnbc_control_lote.md)
- [specs/u4_desnormalizacion_top_categorias.md](specs/u4_desnormalizacion_top_categorias.md)
- [sql/tp_fnbc_control_lote.sql](sql/tp_fnbc_control_lote.sql)
- [sql/tp_desnormalizacion_top_categorias.sql](sql/tp_desnormalizacion_top_categorias.sql)
- [informes/informe_u4_fnbc_desnormalizacion.md](informes/informe_u4_fnbc_desnormalizacion.md)

## Parte 1 — FNBC

Trabaja sobre la relación académica `control_lote_almacen`: identifica
sus dependencias funcionales, sus claves candidatas, demuestra que
viola la Forma Normal de Boyce-Codd, la descompone en
`responsable_control_deposito` y `control_lote_responsable`, y
verifica que la descomposición es sin pérdida (lossless) mediante una
vista de compatibilidad y `EXCEPT` bidireccional.

El script `sql/tp_fnbc_control_lote.sql` crea tablas mínimas de apoyo
(`lote`, `deposito`, `usuario`) porque esas entidades no forman parte
del `schema.sql` base del proyecto — existen únicamente para hacer
reproducible este ejercicio académico.

## Parte 2 — Desnormalización controlada

Agrega `detalle_pedido.categoria_id` como dato redundante para
acelerar el reporte "Top categorías por monto vendido".
`producto.categoria_id` sigue siendo la única fuente de verdad; dos triggers mantienen la consistencia con `producto.categoria_id` como fuente de verdad: al insertar o cambiar el producto de un detalle, su categoría se deriva desde `producto`; y cuando cambia la categoría de un producto, el cambio se propaga a sus detalles. Además, existe
una consulta de auditoría para detectar desincronización.

Esto se realizó sobre una copia de laboratorio (`foodstore_u4`) y **no**
está integrado al `schema.sql` base actual.

## Base canónica

El esquema base del proyecto continúa en:

- [../../schema.sql](../../schema.sql)
- [../../datos_iniciales.sql](../../datos_iniciales.sql)

Desde `unidades/unidad-4/` la raíz del repositorio está dos niveles
arriba.

## Dataset de laboratorio

Unidad 4 reutilizó el dataset masivo de TP3. La copia canónica está en:

[../unidad-2/tp3/sql/carga_masiva_tp3.sql](../unidad-2/tp3/sql/carga_masiva_tp3.sql)

No se duplica ese archivo acá.

## Evidencia medida

- Baseline normalizado: mediana = 239.969 ms.
- Desnormalizado: mediana = 220.722 ms.
- Reducción aproximada de Execution Time: 8.02 %.
- Speedup aproximado: 1.09x.
- Buffers: aproximadamente 36.400 → 5.690 (reducción aproximada de
  84.4 %).

La mejora principal observada fue una reducción de trabajo lógico y de
buffers, no una mejora extrema de tiempo — no se presentan estos
valores como universales; corresponden al entorno y dataset de esta
medición puntual.

## Reversibilidad

Ambos scripts documentan: la migración, la auditoría de consistencia,
la validación de equivalencia y un plan de reversión / DOWN explícito.
Fueron ejecutados sobre una base de laboratorio, no sobre la base
productiva del proyecto.

## Para un revisor / IA

1. Leer primero este README.
2. No asumir que los SQL de Unidad 4 forman parte del `schema.sql` base.
3. No ejecutar ambos scripts automáticamente sobre una base importante.
4. Leer las specs antes de evaluar la implementación.
5. Consultar el informe para la evidencia real.
6. No inventar columnas como `subtotal`, `eliminado`, `estado` u otras
   que no existan en `schema.sql`.
7. Preservar las mediciones históricas.
8. Distinguir dato histórico de dato redundante.
9. Verificar equivalencia con `EXCEPT` cuando corresponda.
10. Verificar consistencia con la consulta de auditoría.

