# Unidad 4 — FNBC y desnormalización controlada

**Entrega canónica cerrada: FNBC PASS; candidato de desnormalización REJECT / DO_NOT_ADOPT.**
El laboratorio quedó sin objetos experimentales tras el DOWN definitivo de Fase 8.
No incorporar `detalle_pedido.categoria_id` a `schema.sql` ni reinstalar el candidato automáticamente.

## Lectura de la entrega

1. [Informe breve de entrega](informes/informe_entrega_u4_modelo_canonico.md): teoría, SQL, planes y decisión.
2. [Informe técnico y cierre del laboratorio](informes/informe_u4_fnbc_desnormalizacion.md).
3. Artefactos SQL: [Parte 1 FNBC](sql/tp_fnbc_control_lote.sql) y
   [Parte 2 experimental, descartada](sql/tp_desnormalizacion_top_categorias.sql).

## Resultado vigente

| Parte | Resultado acreditado |
|---|---|
| FNBC | Dos claves candidatas; descomposición sin pérdida, F1 no preservada; 3/3 filas y EXCEPT 0/0; DOWN real |
| Lectura Top 5 | Mediana 212.668 → 87.657 ms; buffers raíz 6794 → 12091 (+77.97 %) |
| Decisión Parte 2 | REJECT: falla la puerta de buffers predeclarada, aunque mejora el tiempo |
| Estado final DB | CLEAN_CANONICAL_NO_U4_CANDIDATE; datos canónicos e índices conservados |

La fuente estructural es [schema.sql](../../schema.sql); el seed es
[datos_iniciales.sql](../../datos_iniciales.sql). No son archivos históricos obsoletos.
El laboratorio `foodstore_u4_revalidacion` se construyó desde esas fuentes y los
[tres índices aceptados de TP5](../unidad-3/sql/indices.sql), sin restaurar dumps antiguos.
El seed mínimo no equivale al dataset sintético ampliado de las mediciones.

FNBC reutilizó los usuarios canónicos **1 y 2**, mapeados desde los identificadores
lógicos 801/802 del ejemplo; no creó ni modificó usuarios. La Parte 2 utilizó
8 categorías, 20000 usuarios, 50000 productos, 200000 pedidos y 500000 detalles.
La fecha del benchmark fue **2026-09-23**, con PostgreSQL **17.11**.

La categoría del producto siguió siendo fuente de verdad. Se preserva el deadlock
**40P01** del candidato inicial; la remediación por permisos/API y gate pasó los
escenarios autorizados, no DML arbitrario de administradores. La decisión final
sigue siendo rechazo por los criterios medidos, no adopción por corrección funcional.

## Evidencia verificable

- [FNBC canónico](informes/evidencia_revalidacion_fnbc_modelo_canonico.md).
- [Dataset reproducible](informes/evidencia_dataset_parte2_modelo_canonico.md).
- [Baseline BEFORE](informes/evidencia_baseline_parte2_modelo_canonico.md).
- [Selección y criterios previos](informes/decision_patron_parte2_modelo_canonico.md).
- [Fallo concurrente original](informes/evidencia_implementacion_candidato_a_modelo_canonico.md).
- [Remediación con ruta cerrada](informes/evidencia_remediacion_serializada_modelo_canonico.md).
- [READ AFTER y decisión](informes/evidencia_read_after_decision_modelo_canonico.md).
- Contratos: [spec FNBC](specs/u4_fnbc_control_lote.md) y [spec Parte 2](specs/u4_desnormalizacion_top_categorias.md).

Las evidencias conservan el estado de su fecha: `REJECTED_PENDING_FINAL_CLEANUP`
en Fase 7 describe el checkpoint previo; el cierre definitivo está registrado en
el informe técnico. El DOWN no compacta automáticamente tablas ni restituye el
estado físico de Phase 3. No se repitieron benchmarks para el cierre.

## Reproducción y límites

Los SQL están limitados al laboratorio autorizado, contienen guardas y no son
migraciones automáticas del proyecto. Leer sus precondiciones y secciones UP/DOWN
antes de cualquier nueva ejecución. El SQL de Parte 2 exige además la fecha
2026-09-23, roles ausentes y dataset previsto; no cambiar esas guardas para repetir
una medición sin un nuevo protocolo autorizado. No ejecutar sobre otras bases.

TPI quedó excluido del baseline primario; esto no lo declara obsoleto. No se
probó integración TPI, alta carga ni ausencia universal de deadlocks. Cinco
corridas warm-cache describen este ensayo, no significancia estadística ni
rendimiento de producción.

## Antecedentes preservados

La [evidencia del cierre 2026-09-20](informes/evidencia_modelo_oficial.md) y el
[informe histórico anterior](informes/informe_u4_fnbc_desnormalizacion_historico.md)
se conservan por trazabilidad. Sus laboratorios, fixtures y métricas no son el
baseline canónico actual. El informe técnico distingue ese contenido histórico
de la decisión vigente; no se reescribieron sus resultados.
