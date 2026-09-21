# Unidad 4 — FNBC y desnormalización controlada

| Parte | Estado final |
|---|---|
| 1 — FNBC | **PASS** sobre el modelo oficial |
| 2 — Desnormalización | **EXPERIMENTO VÁLIDO / CANDIDATO DESCARTADO** |

La implementación experimental mantuvo consistencia y equivalencia, pero
su relación costo/beneficio no justifica adoptarla como diseño permanente.
**REJECTED_AFTER_MEASUREMENT: no incorporar detalle_pedido.categoria_id a schema.sql.**

## Documentación vigente

1. [Informe vigente y decisión final](informes/informe_u4_fnbc_desnormalizacion.md).
2. [Evidencia técnica completa](informes/evidencia_modelo_oficial.md): planes,
   pruebas, conteos y límites del ensayo.
3. [Spec FNBC](specs/u4_fnbc_control_lote.md) y [SQL FNBC](sql/tp_fnbc_control_lote.sql).
4. [Spec del candidato](specs/u4_desnormalizacion_top_categorias.md) y
   [SQL experimental](sql/tp_desnormalizacion_top_categorias.sql).

## Parte 1 — FNBC: PASS

Se conservaron las dependencias de negocio, las claves candidatas y la
descomposición en responsable_control_deposito y control_lote_responsable.
La vista v_control_lote_almacen reconstruyó las **3 filas originales**;
el EXCEPT bidireccional produjo **0 / 0**. La descomposición es sin pérdida;
R1 (F1) requiere el JOIN para verificarse y no queda preservada localmente por las PK.

**usuario pertenece al modelo oficial**: se reutilizaron los usuarios 801 y
802 no eliminados. Unidad 4 no creó ni eliminó esa tabla ni modificó sus
filas. lote y deposito son tablas maestras auxiliares de la extensión
académica; las FK de responsables apuntan a usuario(id).

## Parte 2 — Experimento válido, candidato descartado

detalle_pedido.categoria_id se probó exclusivamente en la copia descartable
foodstore_u4_oficial; **no forma parte del esquema canónico**. El diseño
experimental conserva backfill, NOT NULL, FK, dos triggers, auditoría y DOWN.
La fuente única de verdad sigue siendo **producto.categoria_id**.

| Medida | Normalizada / sin trigger | Candidato / con trigger | Variación |
|---|---:|---:|---:|
| Mediana de lectura, 5 corridas (ms) | 200.392 | 196.507 | -1.94 % |
| Buffers compartidos hit + read | 8382 | 13386 | +59.70 % |
| INSERT de 1000 detalles, promedio válido (ms) | 21.3385 | 28.8015 | +34.97 % |

La reducción de mediana es marginal, no una mejora robusta. Aumentaron
los buffers y la dispersión; el candidato agrega costo de escritura y
complejidad. El INSERT mide el costo incremental del trigger, no todo el
costo de la desnormalización. Propagación puntual: **57.540 ms para 18
detalles del producto 17**, no una mediana.

Equivalencia **0 / 0**, triggers A/B/C **PASS** y auditoría final **0**.
Dos sesiones actualizaron el mismo producto: la segunda esperó un bloqueo
y el resultado fue consistente. **No se ensayó INSERT concurrente de detalle
contra UPDATE de categoría del producto**. El DOWN se revisó estáticamente,
sin ejecutarlo. El rechazo es una decisión humana basada en evidencia,
no un fracaso del experimento.

## Semántica oficial y reproducción del laboratorio

El ensayo usó **PostgreSQL 17.11**, el 2026-09-20, en foodstore_u4_oficial,
copia de foodstore_tp5_oficial. Hubo **20.275 pedidos y 50.272 detalles
vigentes de CURRENT_DATE**; el backfill alcanzó **550.000 filas**.

El modelo incluye usuario, pedido.usuario_id, subtotal físico y
eliminado; pedido.fecha es **DATE**. Ambas consultas usan SUM(dp.subtotal),
ped.eliminado = FALSE, dp.eliminado = FALSE y ped.fecha = CURRENT_DATE.
No excluyen ventas por baja actual de producto/categoría ni por disponibilidad.
La categoría sigue siendo la actual del producto, no una captura al vender.

Para reproducir, utilizar una nueva copia descartable oficial, verificar los
usuarios 801/802 y el volumen del día, y seguir el protocolo y los scripts de
carga/pruebas de la evidencia. No aplicar automáticamente los scripts a una
base importante: el candidato modifica únicamente el laboratorio y sus DDL
no son idempotentes. No se realizaron nuevas ejecuciones en este cierre.
Los tiempos son específicos del dataset, máquina, cachés y estado físico del
ensayo; no son garantías universales. Los empates en el corte del Top 5
requieren atención porque el orden solicitado no incluye desempate.

[schema.sql raíz](../../schema.sql) y
[datos_iniciales.sql raíz](../../datos_iniciales.sql) permanecen históricos:
**no reconstruyen por sí solos la copia oficial medida**. No se modifican
ni se propone integrar la columna redundante.

## Evidencia histórica

El [informe histórico](informes/informe_u4_fnbc_desnormalizacion_historico.md)
corresponde a una iteración anterior basada en un modelo no alineado. Se
conserva íntegro exclusivamente por trazabilidad; **sus métricas no justifican
la decisión vigente**.

La evidencia técnica del Bloque 2 también se conserva intacta. Su enlace
congelado denominado «informe histórico» utiliza el nombre anterior, ahora
ocupado por el informe vigente; el archivo histórico correcto es el que
tiene el sufijo _historico.md, enlazado arriba.
