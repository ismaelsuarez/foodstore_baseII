# Food Store — Base de Datos II

Proyecto académico de PostgreSQL de la UTN: modelado, integridad, transacciones,
concurrencia, consultas y evaluación de optimizaciones. **El contrato vigente es
el modelo oficial definido en [schema.sql](schema.sql)**. No hay aplicación,
backend ni frontend; los entregables son SQL y documentación.

## Ruta de lectura

| Recurso | Para qué consultarlo |
|---|---|
| [TPI — Primera Entrega](tpi/README.md) | Cobertura, reproducción exacta desde PowerShell y resultados resumidos |
| [Informe técnico TPI](tpi/informe_tecnico.md) | Interpretación de decisiones, pruebas y limitaciones |
| [Evidencia oficial TPI](tpi/evidencia_modelo_oficial.md) | Resultados reales de ejecución funcional, concurrencia y HAVING |
| [Modelo relacional](tpi/modelo/modelo_relacional.md) | Columnas, tipos, claves y restricciones vigentes |
| [AGENTS.md](AGENTS.md) | Contrato de trabajo para futuros agentes |

Integrantes: **Avalos Pablo, Blangetti Sofia y Suarez Ismael**.

## Modelo canónico vigente

| Entidad | Responsabilidad |
|---|---|
| `categoria` | Agrupación del catálogo; nombre único y baja lógica |
| `usuario` | Identidad, nombre, apellido, mail único, celular, contrasena, rol y baja lógica |
| `producto` | Precio actual, stock, categoría, disponibilidad comercial y baja lógica separadas |
| `pedido` | Usuario, fecha `DATE`, estado, total físico, forma de pago y baja lógica |
| `detalle_pedido` | Identidad propia, pedido/producto, cantidad, precio histórico, subtotal físico y baja lógica |

Las cinco tablas tienen `id BIGINT GENERATED ALWAYS AS IDENTITY` como PK,
`eliminado` y `created_at TIMESTAMPTZ`. El detalle tiene además
`UNIQUE(pedido_id, producto_id)`; sus FK no constituyen la PK. Las cuatro
relaciones son 1:N, obligatorias del lado hijo, con `ON DELETE RESTRICT`.
`disponible` y `eliminado` no son sinónimos.

El subtotal es una **redundancia derivada deliberada**. Considerando la regla
`{cantidad, precio_unitario} → subtotal`, el detalle cumple 1FN y 2FN, pero no se
presenta como 3FN/FNBC estricta. El total es un agregado físico entre filas de
otra relación; su existencia no prueba por sí sola una DF interna problemática
en pedido. Véase [normalización](tpi/modelo/normalizacion.md).

La capa [programable del TPI](tpi/sql/objetos_programables.sql) se instala por
separado: mantiene subtotal y total, valida nuevas líneas y ofrece
`CALL registrar_detalle_pedido(...)` como ruta de negocio para descontar stock.
El DML directo de detalles no constituye una API completa de inventario.

## Reproducción actual y seguridad

Seguir los [comandos PowerShell del TPI](tpi/README.md) sobre una base descartable
nueva llamada `foodstore_tpi_oficial`, en este orden:

1. `schema.sql`: instalación transaccional con `ON_ERROR_STOP=1` y `-1`.
2. `datos_iniciales.sql`: `ON_ERROR_STOP=1`, sin `-1`; administra su transacción.
3. `tpi/sql/objetos_programables.sql`: `ON_ERROR_STOP=1` y `-1`.
4. `tpi/pruebas/pruebas_objetos_programables.sql`: `ON_ERROR_STOP=1`, sin `-1`;
   prueba reversible con su propio rollback.
5. `tpi/sql/consultas_cobertura_tpi.sql`: consulta de lectura con `ON_ERROR_STOP=1`.

No ejecutar todos los SQL del repositorio en cadena. No recrear una base
existente sin autorización ni instalar laboratorios automáticamente. El seed
mínimo tiene **3 usuarios, 2 categorías, 3 productos, 5 pedidos y 7 detalles**.
`SEED_NO_AUTH` es un marcador académico, no una credencial real. El stock del
seed es una fotografía inicial, no una reproducción cronológica de ventas.

## Resultados TPI acreditados

Validación en **PostgreSQL 17.11**, base `foodstore_tpi_oficial`:

- Schema, seed y **12 objetos** — 7 rutinas y 5 triggers — instalados y verificados.
- Batería: **29 grupos, 37 variantes, 30 NOTICE PASS**, código de salida 0.
- Tres escenarios concurrentes bajo **READ COMMITTED**: mismo producto/pedidos
  distintos, mismo pedido/productos distintos y mismo par pedido/producto.
  Se observaron bloqueos reales `Lock / transactionid` y estados finales correctos.
- HAVING: Ana Gómez y Luis Paz, **2 pedidos cada uno**, dos filas reales.
- Fixtures eliminados, seed intacto y cero inconsistencias de subtotal/total.

Esto no acredita ausencia universal de deadlocks, concurrencia segura del DML
directo, SERIALIZABLE, reposición automática por bajas/cancelaciones ni
rendimiento bajo estrés. La evidencia separa los ensayos productivos de una
incidencia del arnés temporal; el [informe técnico](tpi/informe_tecnico.md)
explica su alcance. No se declara una garantía de producción ni se sustituye
la auditoría final del TPI.

## Evolución del modelo

TP1–TP4 fueron desarrollados y evaluados sobre una iteración anterior. Se
preservan como **EVIDENCIA HISTÓRICA EVALUADA**, sin convertir retroactivamente
sus SQL o documentos al contrato actual. Posteriormente, la revisión humana
identificó la necesidad de alineación con el DER/material oficial: se corrigieron
Unidad 3, Unidad 4, el esquema raíz y el TPI.

| Área | Estado y punto de entrada |
|---|---|
| Unidad 1 / TP2 | [Integridad y concurrencia históricas](unidades/unidad-1/tp2/README.md) |
| Unidad 2 / TP3 | [Consultas y optimización históricas](unidades/unidad-2/tp3/README.md) |
| Unidad 2 / TP4 | [JOIN y análisis históricos](unidades/unidad-2/tp4/README.md) |
| Unidad 3 / TP5 | [Modelo oficial validado](unidades/unidad-3/README.md), commit `da5f3e4` |
| Unidad 4 | [FNBC validada; candidato descartado](unidades/unidad-4/README.md), commit `95fbfbf` |

Los avisos de U3/U4 que describen los archivos raíz como históricos registran
el estado de la raíz **al cerrar aquellos laboratorios**, antes de su reparación
para el TPI. Hoy la raíz es oficial. Sin embargo, el seed mínimo **no reproduce
las cargas masivas medidas ni contiene los usuarios 801/802 requeridos por el
ensayo FNBC**. Los resultados de laboratorio no deben atribuirse al seed del TPI.
La carga histórica de TP3 tampoco es una migración del modelo vigente.

## Unidad 3: resultados oficiales

El [informe vigente](unidades/unidad-3/informes/informe_mediciones.md) acredita
los índices `idx_producto_stock_bajo`, `idx_pedido_fecha_reciente` e
`idx_usuario_mail_lower`; cuatro vistas `v_productos_vigentes`,
`v_pedidos_resumen`, `v_pedido_detalle`, `v_usuarios_publico`; y la materializada
`mv_facturacion_categoria_mes`.

| Lectura | Antes → después | Mejora observada |
|---|---|---|
| Stock bajo | 9.4390 → 0.2975 ms | 31.73x |
| Pedidos recientes | 264.3715 → 1.2250 ms | 215.81x |
| Usuario por mail | 10.8865 → 0.1360 ms | 80.05x |
| Materializada, comparación homogénea | 1188.4945 → 0.2230 ms | Ver protocolo del informe |

Se verificaron EXCEPT bidireccionales, seguridad de la vista pública con un rol
de prueba retirado al finalizar y `REFRESH MATERIALIZED VIEW CONCURRENTLY`.
Los índices tienen costos de escritura; los tiempos dependen del dataset y la
máquina, no son universales. Sus objetos no se instalan desde el esquema mínimo.

## Unidad 4: experimento válido, no adoptado

FNBC: **PASS**. La desnormalización se conserva como **VALID_EXPERIMENT**, pero
su decisión es **REJECTED_AFTER_MEASUREMENT / DO_NOT_ADOPT**. El cambio de
mediana de 200.392 a 196.507 ms (-1.94 %) fue marginal; buffers +59.70 % e INSERT
+34.97 % no justificaron el costo y la complejidad. Véase el
[informe vigente U4](unidades/unidad-4/informes/informe_u4_fnbc_desnormalizacion.md).

`detalle_pedido.categoria_id` **no es canónica**; `producto.categoria_id` sigue
siendo la autoridad. `usuario` sí pertenece al modelo base; `lote` y `deposito`
son extensiones académicas del laboratorio, no tablas raíz.

## Organización y uso de IA

- Raíz: esquema, seed, entrada del proyecto y reglas de trabajo.
- `tpi/`: modelo, SQL adicional, pruebas, evidencia e informe integrador.
- `unidades/`: trabajos evaluados y laboratorios con sus propios contratos.
- `.kiro/steering/`: [producto](.kiro/steering/product.md),
  [tecnología](.kiro/steering/tech.md) y [estructura](.kiro/steering/structure.md).

Las DUIA registran propuestas y revisión, no una autoría única de todo el
proyecto. La [DUIA vigente U3](unidades/unidad-3/duia/duia.md) distingue Kiro,
OpenCode, revisión humana y reparación asistida por Codex. Las ejecuciones
producen resultados mediante PostgreSQL/psql bajo autorización del equipo;
no son estimaciones generadas por IA. La responsabilidad final y las decisiones
corresponden al equipo. Los relatos históricos de uso de herramientas se
conservan sin reescribirlos como si fueran la ejecución actual.
