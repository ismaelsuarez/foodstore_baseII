# Informe técnico — TPI Food Store — Modelo oficial

**La integración vigente pasó instalación, pruebas funcionales, tres escenarios
concurrentes y consulta HAVING en PostgreSQL 17.11.** El resultado tiene límites
explícitos y conserva una incidencia no productiva del arnés de pruebas. Este
informe interpreta la [evidencia consolidada](evidencia_modelo_oficial.md); no
reemplaza sus registros. El cierre posterior TPI-A de normalización y ventana
tiene [evidencia propia](evidencia_cierre_objetivos_3_5.md), separada de aquellos
ensayos funcionales y concurrentes.

## 1. Introducción y alcance

Trabajo de Avalos Pablo, Blangetti Sofia y Suarez Ismael, Base de Datos II.
La Primera Entrega integra U1–U3 y los complementos del TPI. U4 es trabajo
académico posterior/complementario, no una migración obligatoria ni un reemplazo
de la cobertura requerida. El [README TPI](README.md) contiene navegación,
mapa de objetivos y reproducción exacta desde PowerShell.

Se distinguen tres niveles:

| Nivel | Fuente y uso |
|---|---|
| Contrato vigente | [schema.sql](../schema.sql), [seed](../datos_iniciales.sql), [modelo](modelo/modelo_relacional.md) y [objetos TPI](sql/objetos_programables.sql) |
| Evidencia vigente | [TPI](evidencia_modelo_oficial.md), [informe U3](../unidades/unidad-3/informes/informe_mediciones.md), [informe U4](../unidades/unidad-4/informes/informe_u4_fnbc_desnormalizacion.md) |
| Evidencia histórica evaluada | TP1–TP4, preservados íntegramente; no se presentan sus scripts como compatibles automáticamente con el schema actual |

La alineación posterior con DER/material oficial corrigió U3 (`da5f3e4`,
`fix(tp5): alinear con modelo oficial y validar resultados`) y U4 (`95fbfbf`,
`fix(u4): alinear modelo oficial y cerrar evaluacion`). El esquema raíz y la
integración TPI actuales continúan esa reparación sin reescribir TP1–TP4.
No se atribuye a esos trabajos históricos una estructura que no tenían.

## 2. Modelo oficial, ER y transformación relacional

El [ER](modelo/modelo_er.md) y el [modelo relacional](modelo/modelo_relacional.md)
representan exactamente las cinco entidades actuales.

| Entidad | Contrato destacado |
|---|---|
| `categoria` | Agrupación del catálogo; nombre único, descripción y baja lógica |
| `usuario` | Nombre, apellido, mail único, celular, contrasena, rol y baja lógica |
| `producto` | Precio de catálogo, stock, imagen, disponibilidad y categoría obligatoria |
| `pedido` | Usuario obligatorio, fecha DATE, estado, total físico y forma de pago |
| `detalle_pedido` | PK `id`, FK a pedido/producto, UK conjunta, cantidad, precio histórico y subtotal físico |

Todas tienen `id BIGINT GENERATED ALWAYS AS IDENTITY`, `eliminado` y
`created_at TIMESTAMPTZ`. `pedido.fecha` es **DATE**, no la marca temporal
administrativa. `disponible` expresa disponibilidad comercial; `eliminado`,
baja lógica: no son equivalentes.

Las relaciones son categoría 1:N producto, usuario 1:N pedido, pedido 1:N
detalle y producto 1:N detalle. Las FK NOT NULL obligan a cada hijo a tener
exactamente un padre; el padre admite cero o muchos hijos. Una FK no obliga
al pedido a tener líneas. La relación N:M pedido–producto se resuelve mediante
la entidad asociativa con **PK propia `id`** y
`UNIQUE(pedido_id, producto_id)`: un producto aparece como máximo una vez en un
pedido, también considerando líneas eliminadas lógicamente.

## 3. Normalización y redundancias deliberadas

El [análisis de DF](modelo/normalizacion.md) separa restricciones, reglas de
dominio y redundancias. No deriva claves de coincidencias del seed.

| Relación | Claves candidatas respaldadas | Formas normales con las DF identificadas |
|---|---|---|
| usuario | `{id}`, `{mail}` | 1FN, 2FN, 3FN y FNBC |
| categoria | `{id}`, `{nombre}` | 1FN, 2FN, 3FN y FNBC |
| producto | `{id}` | 1FN, 2FN, 3FN y FNBC |
| pedido | `{id}` | 1FN, 2FN, 3FN y FNBC para sus DF internas |
| detalle_pedido | `{id}`, `{pedido_id, producto_id}` | 1FN/2FN; no 3FN/FNBC estrictas al incluir la DF del subtotal |

En detalle, `id`, `pedido_id` y `producto_id` son primos. La regla conceptual
`{cantidad, precio_unitario} → subtotal` tiene determinante que no es superclave
y dependiente no primo. Por eso impide 3FN/FNBC estrictas, aunque no hay una
DF parcial de un no primo respecto de una parte propia de la clave compuesta.
**Subtotal es REDUNDANCIA DERIVADA DELIBERADA Y CONTROLADA**, exigida por el
modelo oficial; no se elimina para aparentar una normalización más alta.
El modelo lógico separa los hechos y sus claves; la representación física
conserva conscientemente el importe derivado de cada línea para trazabilidad
y reportes. No se afirma que todas las tablas físicas estén estrictamente
en 3FN/FNBC ni se utiliza el ejercicio aislado de U4 para sostenerlo.

`subtotal` se deriva dentro de una línea. En cambio, `pedido.total` es un
**agregado físico entre filas de otra relación**: suma los subtotales de las
líneas vigentes, o cero si no hay ninguna. Esa regla cruzada no demuestra por
sí sola una DF interna problemática entre atributos no clave de pedido.
Ambos datos requieren consistencia, pero no son el mismo tipo de dependencia.

El schema impone no negatividad, no la igualdad derivada. `fn_set_subtotal`
y `trg_subtotal` mantienen la igualdad dentro de la sentencia/transacción;
`calcular_total_pedido` y los triggers AFTER mantienen el total. Estos objetos
están implementados y tienen evidencia previa propia; una base con solo schema
y seed no los instala automáticamente ni adquiere sus garantías.

La defensa de normalización incluye una descomposición **solo teórica** del
detalle en `(cantidad, precio_unitario, subtotal)` y el resto de atributos
sin subtotal. La intersección cantidad/precio determina la primera proyección,
por lo que el JOIN es sin pérdida para instancias que cumplen la DF. No se crea
un catálogo artificial de multiplicaciones ni se altera el contrato oficial;
las otras cuatro relaciones no requieren nueva descomposición bajo sus DF
internas identificadas. La demostración y sus límites están en el
[análisis de normalización](modelo/normalizacion.md).

## 4. Integridad y seed

El catálogo se verificó después de instalar el schema: **3 ENUM, 5 tablas,
40 columnas, 5 PK sobre id, 4 FK, 6 CHECK y 3 índices base explícitos**.

- ENUM `forma_pago`: EFECTIVO, TARJETA, TRANSFERENCIA.
- ENUM `rol`: ADMIN, USUARIO; default de usuario: USUARIO.
- ENUM `estado_pedido`: PENDIENTE, CONFIRMADO, TERMINADO, CANCELADO; default:
  PENDIENTE, decisión de implementación para altas.
- FK `fk_producto_categoria`, `fk_pedido_usuario`,
  `fk_detalle_pedido_pedido`, `fk_detalle_pedido_producto`: `ON DELETE RESTRICT`.
- UNIQUE de `usuario.mail`, `categoria.nombre` y
  `uq_detalle_pedido_pedido_producto`. No se declara unicidad case-insensitive.
- CHECK de precio/stock de producto, total de pedido, cantidad positiva,
  precio unitario y subtotal del detalle no negativos.
- Índices base: `idx_producto_categoria`, `idx_pedido_usuario`,
  `idx_producto_nombre_vig`. No incluyen los candidatos U3 como instalación
  mínima ni crean claves nuevas.

El seed contiene **3 usuarios / 2 categorías / 3 productos / 5 pedidos /
7 detalles**. Todos los pedidos son TERMINADO por convención explícita del
seed, no por un estado recuperado de una iteración anterior.

| Usuario | Fecha | Total real |
|---|---|---:|
| Ana Gómez | 2026-03-01 | 2800.00 |
| Luis Paz | 2026-03-01 | 1500.00 |
| Ana Gómez | 2026-03-05 | 3150.00 |
| Marta Ruiz | 2026-03-06 | 6200.00 |
| Luis Paz | 2026-03-07 | 1050.00 |

Usuario y fecha distinguen esas filas solo en el dataset controlado, no son
una clave candidata. El seed calcula subtotales con precio histórico y
reconcilia totales; no vuelve a descontar stock por ventas pasadas. Es una
fotografía inicial. `SEED_NO_AUTH` es exclusivamente un marcador académico,
no una credencial real ni un mecanismo de autenticación.

Muzzarella cuesta actualmente **1050**, pero conserva una línea histórica a
**1000**. El ejemplo muestra por qué no se asume
`producto_id → precio_unitario` en el detalle: el precio puede variar entre
ventas. Una baja posterior de usuario, producto o categoría no destruye las
filas históricas ni justifica ocultarlas de sus reportes.

## 5. Objetos programables: autoridades únicas

[objetos_programables.sql](sql/objetos_programables.sql) instala exactamente
**7 rutinas y 5 triggers**, sin tablas ni columnas adicionales.

| Objeto | Tipo | Responsabilidad |
|---|---|---|
| `calcular_total_pedido(bigint)` | Función SQL STABLE | Sumar subtotal físico no eliminado; devuelve cero sin líneas |
| `fn_set_subtotal()` | Función trigger | Derivar subtotal de cantidad y precio unitario |
| `fn_validar_detalle_vigente()` | Función trigger | Validar pedido, usuario y producto al insertar/reasignar referencias |
| `fn_recalcular_total_insert()` | Función trigger | Recalcular pedidos de NEW TABLE |
| `fn_recalcular_total_update()` | Función trigger | Recalcular unión de pedidos de OLD/NEW TABLE |
| `fn_recalcular_total_delete()` | Función trigger | Recalcular pedidos de OLD TABLE |
| `registrar_detalle_pedido(bigint,bigint,integer)` | Procedimiento | Registrar venta con precio histórico, validaciones y descuento de stock |
| `trg_subtotal` | BEFORE, por fila | Invocar la autoridad de subtotal |
| `trg_detalle_vigente` | BEFORE, por fila | Invocar validación de vigencia |
| `trg_total_detalle_insert` | AFTER INSERT, por sentencia | Invocar recálculo con transition table nueva |
| `trg_total_detalle_update` | AFTER UPDATE, por sentencia | Invocar recálculo con transition tables anterior/nueva |
| `trg_total_detalle_delete` | AFTER DELETE, por sentencia | Invocar recálculo con transition table anterior |

**STOCK:** el procedimiento. **SUBTOTAL:** `fn_set_subtotal` / `trg_subtotal`.
**TOTAL:** `calcular_total_pedido` y triggers AFTER. **VIGENCIA DE NUEVAS
LÍNEAS:** `fn_validar_detalle_vigente` / `trg_detalle_vigente`.

El BEFORE completa precio NULL desde catálogo, conserva un precio explícito
y sobrescribe una manipulación directa del subtotal. Ante cambio de producto,
si el precio no cambió respecto de OLD, adopta el precio del nuevo producto;
si es explícito y distinto, lo conserva. Un valor igual al anterior no permite
distinguir si el llamante lo escribió expresamente.

Los AFTER recalculan una vez por pedido afectado en cada sentencia. UPDATE
incluye pedidos de origen y destino para cubrir movimientos de líneas;
INSERT, baja/reactivación y DELETE físico mantienen el agregado. La función
de total no multiplica de nuevo ni filtra entidades padre por bajas posteriores.

La vigencia se valida en nuevas líneas o cambios efectivos de pedido/producto,
no al cambiar solo `eliminado`. Esto permite modificar la baja de una línea
histórica sin invalidarla por una baja posterior de sus padres. FK/UNIQUE/CHECK
siguen siendo autoridades estructurales; las validaciones no las sustituyen.

## 6. Transacciones, stock y atomicidad

`CALL registrar_detalle_pedido` valida parámetros y vigencia, fija el precio
histórico bajo lock, inserta sin pasar subtotal, deja que los triggers mantengan
los derivados y descuenta stock. La duplicación del par se rechaza incluso si
la línea anterior está eliminada; UNIQUE es la garantía declarativa definitiva.

Orden de locks del procedimiento: **pedido FOR UPDATE → usuario FOR SHARE →
producto FOR UPDATE**. El pedido serializa CALL sobre un mismo pedido; el
producto protege la lectura de stock antes del descuento. Este orden no
constituye una prueba universal de ausencia de deadlocks.

El procedimiento no confirma ni revierte internamente: la transacción pertenece
al llamante. La batería verificó detalle, subtotal, total y stock dentro de un
subbloque; provocó `P0099` y comprobó la reversión conjunta. **P0099 pertenece
solo al test**, no a los objetos productivos. Estos usan `22023`, `23503`,
`23505` y `23514` para parámetros, referencias, duplicados y reglas de negocio.

DML directo de detalle **no administra stock**. Baja/reactivación, DELETE o
cambio directo de producto no reponen ni concilian inventario: no se inventó
una política de cancelación o reposición. La ruta soportada de venta es el CALL.
El DOWN comentado retira exclusivamente triggers, funciones y procedimiento;
no borra tablas, datos, ENUM ni índices base y no se ejecuta automáticamente.

## 7. Ejecución funcional y batería

Entorno registrado: **PostgreSQL 17.11, x86_64-windows, msvc-19.44.35228,
64-bit**, base descartable **foodstore_tpi_oficial**. La instalación real de
schema, seed y objetos terminó con exit code 0 y se contrastó con catálogo.
La [batería](pruebas/pruebas_objetos_programables.sql) ejecutó **29 grupos /
37 variantes**, produjo **30 NOTICE PASS** (29 de grupos y uno global) y
terminó con **exit code 0**, sin errores SQL inesperados.

> PASS: batería completa de objetos programables del modelo oficial

| Familia de pruebas | Propiedades verificadas |
|---|---|
| Venta y rechazos | CALL válido, cantidades inválidas, stock insuficiente, producto eliminado/no disponible, pedido y usuario eliminados |
| Integridad declarativa | Duplicados, FK, CHECK y mail UNIQUE, con nombres de constraints donde corresponde |
| Precio/subtotal | Precio NULL, histórico explícito, cambios de cantidad/precio/producto, protección ante subtotal manipulado |
| Total y líneas | Total cero, baja/reactivación, DELETE, movimiento entre pedidos, función de agregado y operaciones masivas |
| Reversibilidad | Atomicidad conjunta, rollback de fixtures y conservación de objetos |

Se capturan exclusivamente los SQLSTATE esperados; un error inesperado hace
fallar la ejecución. Después del rollback quedaron cero fixtures; conteos,
stocks y totales del seed permanecieron iguales, al igual que las huellas de
sus cinco tablas. Los doce objetos siguieron instalados y habilitados cuando
corresponde. Reconciliaciones globales: **0 subtotales / 0 totales inconsistentes**.
Las secuencias pueden conservar huecos.

Esta batería es de **una sesión**. No demuestra por sí sola concurrencia: la
validación multisesión siguiente fue independiente y posterior. Los comentarios
estáticos previos en los scripts no reemplazan esta evidencia de ejecución.

## 8. Concurrencia real ensayada

Cada escenario empleó dos procesos psql independientes y una tercera conexión
de monitoreo. Se usó explícitamente **READ COMMITTED**. B comenzó después de
observar a A con la transacción abierta tras el CALL; en los tres casos se
registró **Lock / transactionid**, no solo una demora percibida.

| Escenario | Intercalado y respuesta de B | Estado final verificado |
|---|---|---|
| Mismo producto / pedidos distintos | Stock inicial 5; A vende 4, B intenta 4; tras esperar, B recibe `23514` por stock insuficiente | Stock 1; total A 400; B sin detalles y total 0 |
| Mismo pedido / productos distintos | A vende 2 × 200; B vende 3 × 300; B espera y ambos CALL confirman | Subtotales 400/900; total almacenado y calculado 1300; stocks 8/7 |
| Mismo pedido / mismo producto | A vende 2 × 150; B intenta una unidad; espera y recibe `23505` por duplicado | Una línea, subtotal/total 300, stock 8; sin segundo descuento |

**CONCURRENCY_VALIDATION: PASS, tres escenarios de tres.** En estos ensayos el
lock de producto evitó sobreventa; el del pedido serializó las modificaciones
y evitó pérdida de actualización del total y doble registro. No se extrapola
este resultado a todas las operaciones o intercalados posibles.

### Incidencia del harness de cleanup

**NON_PRODUCT_TEST_HARNESS_INCIDENT**, SQLSTATE **42601**, archivo temporal
`21_cleanup.sql`. Después de finalizar los tres ensayos, el helper intentó
abrir un bloque PL/pgSQL con sintaxis inválida (`BEGIN;`). PostgreSQL lo rechazó
antes de eliminar filas y la transacción quedó revertida.

No fue un fallo del schema, de los objetos productivos ni de la batería
versionada, y no alteró los resultados concurrentes. Se ejecutó únicamente
`24_safe_cleanup.sql`, **sin repetir escenarios**. Eliminó 4 detalles, 4 pedidos,
4 productos, 1 usuario y 1 categoría, exclusivamente fixtures. Luego se
verificaron cero fixtures, seed intacto, doce objetos presentes y conciliación
0/0. El error afectó el arnés y requirió atención: no se oculta ni se minimiza.

Se separan **PRODUCT_OBJECT_FAILURES: 0** y **TEST_HARNESS_INCIDENTS: 1** del
resultado productivo PASS. El estado global FAIL del resumen inicial agrupaba
ambos niveles; la [evidencia consolidada](evidencia_modelo_oficial.md) registra
esa clasificación y su procedencia sin borrar el incidente.

### Cierre TPI-B — SAVEPOINT y aislamientos canónicos

La [evidencia nueva del objetivo 8](evidencia_cierre_objetivo_8.md) registra dos
ejecuciones del [arnés versionado](pruebas/transacciones/README.md) sobre
`foodstore_tpi_cierre_b`, construido desde schema, seed y objetos vigentes.
SAVEPOINT mostró stock **50 → 49 → 47 → 49 → 50**, con rollback parcial y
rollback final. Bajo REPEATABLE READ, A leyó 50 antes y después del COMMIT de B
en 51; una nueva transacción vio 51. Bajo SERIALIZABLE, ambas sesiones leyeron
50; A confirmó 52 y B recibió **40001**, después de observar su espera
`Lock / transactionid` sobre A. No se aceptó un deadlock como resultado válido.

Se restauró el stock a 50 y coincidieron las huellas de las cinco tablas,
secuencias y catálogo; no quedaron sesiones del ensayo. El objetivo 8 queda
**PASS en el alcance académico documentado**, combinando esta ejecución con
atomicidad y los tres ensayos READ COMMITTED previos, que no se repitieron.
El conflicto sobre una misma fila también puede ocurrir bajo REPEATABLE READ:
no se presenta como prueba exclusiva de SSI ni como validación del CALL bajo
todos los aislamientos. La consolidación integral del informe queda para TPI-C.

## 9. Consultas vigentes y cobertura histórica

La [consulta vigente HAVING](sql/consultas_cobertura_tpi.sql) agrupa `usuario`
con `pedido`, conserva `p.eliminado = FALSE` mediante WHERE antes de agrupar y
selecciona grupos con `HAVING COUNT(p.id) > 1`. Es decir, excluye los pedidos
eliminados y conserva los no eliminados. No filtra usuarios eliminados para
preservar historia; tampoco filtra estados ni une detalle, evitando multiplicar
pedidos por número de líneas.

Resultado real del Bloque 8: **Ana Gómez 2, Luis Paz 2; dos filas, exit code 0,
cero errores SQL**. Marta tiene un pedido y no supera el umbral. HAVING actúa
después de GROUP BY y no se reemplaza por un WHERE sobre COUNT en el mismo nivel.

| Evidencia histórica evaluada | Aporte académico que se conserva |
|---|---|
| [TP2 / U1](../unidades/unidad-1/tp2/README.md), [concurrencia](../unidades/unidad-1/tp2/informes/informe_concurrencia.md) | Integridad, transacciones y experimentos de aislamiento de aquella etapa |
| [TP3 / U2](../unidades/unidad-2/tp3/README.md), [consultas](../unidades/unidad-2/tp3/informes/informe_consultas_tp3.md) | JOIN, agregaciones y subconsulta correlacionada |
| [TP4 / U2](../unidades/unidad-2/tp4/README.md), [consultas](../unidades/unidad-2/tp4/informes/informe_consultas_tp4.md) | JOIN analíticos y función de ventana RANK con empates |

Estos ejercicios pertenecen a una versión anterior del modelo. Se mantienen
como evidencia evaluada, no como SQL actualizado ni una secuencia de migración.
Su RANK histórico no sustituye una ventana ejecutable sobre el modelo actual.

La sección de ventana de [consultas_cobertura_tpi.sql](sql/consultas_cobertura_tpi.sql)
agrega `SUM(p.total)` por usuario y aplica
`RANK() OVER (ORDER BY gasto_total DESC)`. Usa `usuario` y `pedido.usuario_id`,
excluye pedidos eliminados y conserva el historial de usuarios dados de baja.
No filtra estados ni incorpora detalles que multipliquen el total de pedido.
El `ORDER BY ranking, id` final estabiliza la presentación; id no participa
en OVER, por lo que no rompe empates del ranking. Los iguales comparten puesto
y el siguiente rango deja el salto correspondiente. La ejecución y sus límites
se registran en la [evidencia TPI-A](evidencia_cierre_objetivos_3_5.md), sin
atribuir resultados actuales a los SQL históricos.

Resultado real sobre `foodstore_tpi_cierre_a`, construido desde schema y seed
canónicos en PostgreSQL 17.11: **Marta Ruiz 6200.00, ranking 1; Ana Gómez
5950.00, ranking 2; Luis Paz 2550.00, ranking 3**. Dos ejecuciones devolvieron
el mismo orden. No hubo empates en el seed: el comportamiento de RANK frente
a ellos se explica, pero no se presenta como un caso empírico ejecutado.
Tampoco se ensayó una baja nueva de usuario en esta fase. La base no instaló
objetos programables; la protección de subtotal conserva su evidencia previa.

## 10. Unidad 3: índices y costo de escritura

Resultados del [informe vigente U3](../unidades/unidad-3/informes/informe_mediciones.md),
no del seed TPI: PostgreSQL 17.11, `foodstore_tp5_oficial`, 8 categorías,
50.000 productos, 20.000 usuarios, 200.000 pedidos y 500.000 detalles.
Protocolo: tres ejecuciones por caso, primera de calentamiento y promedio
estable de las dos restantes. Los tiempos son específicos del dataset/máquina;
dos corridas válidas no son una garantía estadística ni universal.

| Índice aceptado para el TP | Antes, ms | Después, ms | Mejora observada | Plan final |
|---|---:|---:|---:|---|
| `idx_producto_stock_bajo` | 9.4390 | 0.2975 | 31.73x | Index Only Scan |
| `idx_pedido_fecha_reciente` | 264.3715 | 1.2250 | 215.81x | Index Only Scan |
| `idx_usuario_mail_lower` | 10.8865 | 0.1360 | 80.05x | Bitmap Heap Scan + Bitmap Index Scan |

Stock bajo usa `eliminado = FALSE`, no disponibilidad: un producto no disponible
puede requerir reposición. Pedidos recientes utiliza fecha DATE y eliminación
lógica; la cobertura INCLUDE se observó, no se supuso. La unicidad exacta de
mail no implica UNIQUE sobre `lower(mail)`: esa expresión no incorpora una
regla de negocio nueva.

INSERT de 1.000 filas con rollback mostró costos adicionales:

| Tabla indexada | Antes → después, ms | Variación |
|---|---|---:|
| producto | 16.9725 → 19.5120 | +14.96 % |
| pedido | 9.5240 → 10.4330 | +9.54 % |
| usuario | 7.6655 → 14.7085 | +91.88 % |

`idx_usuario_mail_lower_covering` fue descartado: **999.424 bytes** del simple
frente a **2.621.440 bytes**, **2.62x**, para una consulta de una fila y sin
beneficio temporal adicional medido. La aceptación del índice simple depende
de la carga asumida de pocas altas frente a búsquedas interactivas frecuentes;
esa frecuencia no fue medida y la decisión debe revisarse si cambia el uso.

## 11. Unidad 3: cuatro vistas, seguridad y materializada

Definiciones: [views.sql](../unidades/unidad-3/sql/views.sql).

| Vista vigente | Semántica | Filas; EXCEPT en ambos sentidos |
|---|---|---|
| `v_productos_vigentes` | Producto y categoría no eliminados; no exige disponible | 43.299; 0/0 |
| `v_pedidos_resumen` | Pedido vigente con usuario; no oculta historia por baja del usuario | 198.059; 0/0 |
| `v_pedido_detalle` | Detalle vigente, producto y subtotal físico; no filtra baja del producto | 495.327; 0/0 |
| `v_usuarios_publico` | Usuario vigente; expone id/nombre/apellido/mail/rol, no contrasena ni celular | 19.802; 0/0 |

La igualdad mediante EXCEPT acredita conjuntos iguales en esa carga, no una
prueba universal ni mejora de rendimiento automática de las vistas.

En el ensayo se creó temporalmente `rol_soporte NOLOGIN`; después se aplicó
[seguridad.sql](../unidades/unidad-3/sql/seguridad.sql), que concede SELECT a
la vista pero no crea el rol. Se comprobó lectura permitida. El acceso directo
a `usuario.contrasena` y `usuario.celular` fue
rechazado con **42501**. El rol temporal se eliminó al finalizar. No hay un rol
de despliegue configurado por esta evidencia; privilegios heredados futuros
requieren verificación propia. La proyección pública no elimina columnas del
modelo base ni sustituye el control de permisos.

[mv_facturacion_categoria_mes](../unidades/unidad-3/sql/materializadas.sql) usa
`SUM(dp.subtotal)`, excluye pedidos/detalles eliminados y no filtra la baja
actual de producto/categoría ni disponibilidad para conservar historia.

- Comparación homogénea: **1188.4945 → 0.2230 ms**, mismo ordenamiento.
- **0.1220 ms** pertenece al orden `categoria_id, mes`; no se usa para aquella
  comparación homogénea.
- 192 filas; EXCEPT 0/0 antes y después del refresh.
- `idx_mv_facturacion_categoria_mes_unique`, UNIQUE sobre `(categoria_id, mes)`,
  permitió `REFRESH MATERIALIZED VIEW CONCURRENTLY`: **PASS real**.

El refresh fue una ejecución manual de prueba, no un planificador instalado.
La propuesta heredada de cada 60 minutos sigue pendiente de ratificación
operativa; admite staleness y no garantiza un atraso máximo de una hora.
Las lecturas medidas no incluyen costo de construcción ni refresh.

## 12. Unidad 4: FNBC y candidato descartado

Fuente: [informe vigente U4](../unidades/unidad-4/informes/informe_u4_fnbc_desnormalizacion.md).
**FNBC: PASS.** ControlLoteAlmacen conserva las DF
`{LoteID, DepositoID} → ResponsableControlID` y
`ResponsableControlID → DepositoID`. Esta última viola FNBC porque su
determinante no es superclave. La descomposición en
`responsable_control_deposito` y `control_lote_responsable` es lossless; F2
queda preservada localmente, pero F1 requiere comprobar el JOIN. Se observaron
3 filas originales/reconstruidas y EXCEPT 0/0. Las DF provienen de reglas de
negocio, no se deducen únicamente del diagnóstico sin violaciones.

`usuario` pertenece al modelo oficial. Se reutilizaron 801/802 en el laboratorio;
solo `lote` y `deposito` son extensiones académicas. El seed TPI mínimo no
suministra esos usuarios ni reconstruye el volumen de U4.

El candidato `detalle_pedido.categoria_id` mantuvo a `producto.categoria_id`
como fuente de verdad mediante triggers, auditoría y DOWN documentado.
Consistencia, equivalencia, protección de manipulación y el ensayo concurrente
de dos cambios del mismo producto pasaron. No se ensayó allí la carrera
INSERT de detalle contra UPDATE de categoría del producto.

| Medida U4 | Baseline → candidato | Cambio |
|---|---|---:|
| Mediana de cinco corridas, ms | 200.392 → 196.507 | -1.94 % |
| Buffers | 8382 → 13386 | +59.70 % |
| INSERT de detalles sin/con trigger, ms | 21.3385 → 28.8015 | +34.97 % |

La mejora temporal fue marginal, con mayor dispersión, buffers, costo de
escritura y complejidad. **VALID_EXPERIMENT**, pero
**REJECTED_AFTER_MEASUREMENT / DO_NOT_ADOPT**. No se incorpora
`detalle_pedido.categoria_id` al modelo canónico. Un experimento correcto puede
justificar rechazar un diseño; no se considera fracaso académico.

Los avisos en README/evidencia de U3/U4 sobre el esquema raíz de aquella fase
corresponden a su contexto de ejecución: la raíz fue alineada después. El
schema vigente es ahora oficial; su seed mínimo sigue sin reproducir las
cargas de laboratorio. No se modifican retrospectivamente esos registros.

## 13. Uso de IA y responsabilidad

La trazabilidad diferencia propuesta, auditoría, coordinación, ejecución y
aceptación. Las herramientas no producen resultados experimentales por el
solo hecho de generar SQL: **PostgreSQL, invocado mediante psql bajo control
y autorización del equipo, produjo los resultados**. En los bloques corregidos
Codex asistió en la implementación y la orquestación autorizada de comandos;
no se presenta esa asistencia como medición manual del estudiante ni como
resultado calculado por una IA. La responsabilidad final pertenece al equipo.

| Participación registrada | Alcance |
|---|---|
| Kiro | Especificación original, según DUIA históricas |
| OpenCode | Generación inicial de candidatos a partir de specs |
| Claude | Auditoría/revisión de cobertura, según trazabilidad previa comunicada por el equipo |
| ChatGPT | Análisis, revisión y coordinación comunicados para la integración |
| Codex | Implementación controlada, revisión estática, asistencia documental y ejecución de comandos autorizados |
| Equipo | Contrato oficial, límites, revisión, decisiones finales y aceptación |

No se atribuye a una herramienta acceso directo al DER/material externo si
solo recibió el contrato aportado por el usuario. Las
[DUIA de U1](../unidades/unidad-1/tp2/duia/),
[TP3](../unidades/unidad-2/tp3/duia/duia_tp3.md),
[TP4](../unidades/unidad-2/tp4/duia/duia_tp4.md) y la
[DUIA vigente U3](../unidades/unidad-3/duia/duia.md) conservan la procedencia
por etapa, sin reescribir prompts ni ocultar la corrección posterior del modelo.

## 14. Limitaciones y decisiones

No se demostró ausencia universal de deadlocks, concurrencia segura de DML
directo arbitrario, reposición automática por bajas, cancelaciones, carga
masiva concurrente, comportamiento bajo estrés ni rendimiento con alta
concurrencia. El TPI acredita tres escenarios READ COMMITTED, una batería
funcional y los casos acotados TPI-B de SAVEPOINT, REPEATABLE READ y conflicto
SERIALIZABLE; no seguridad universal de toda escritura posible. Un UPDATE directo
a `pedido.total` tampoco se presenta como protegido contra toda manipulación:
la autoridad automática actúa ante cambios de detalles.

| Decisión | Estado y razón |
|---|---|
| Modelo oficial, PK propia del detalle y UK del par | Aceptada; compatibilidad estructural y regla de unicidad explícita |
| Subtotal y total físicos con autoridades únicas | Aceptada; contrato oficial con consistencia en capa programable |
| Precio histórico separado del catálogo | Aceptada; preserva condiciones de cada línea |
| CALL con orden de locks y transacción del llamante | Aceptada; stock y total correctos en los ensayos realizados |
| Historia U1/U2 intacta y resultados nuevos separados | Aceptada; trazabilidad verificable sin reconstrucción retroactiva |
| Tres índices U3 | Aceptados para el workload medido, con costos de escritura y reservas |
| Covering de mail U3 | Descartado por tamaño sin beneficio adicional medido |
| Columna redundante de categoría U4 | Descartada tras medir costo/beneficio |
| Duplicar cálculo de total en el procedimiento | No adoptado; única función de agregado invocada por triggers AFTER |
| Reposición/cancelación y garantías universales | No implementadas ni inferidas sin contrato/evidencia |

## 15. Conclusiones y siguiente verificación

La entrega vigente alinea modelo, integridad, derivados, pruebas y documentación
con el contrato oficial. Los resultados funcionales y concurrentes se apoyan
en evidencia real diferenciada de la historia; la incidencia de cleanup
permanece explícita. U3 aporta mejoras observadas con costos, y U4 demuestra
que consistencia experimental no obliga a aceptar una optimización.

La reproducción se encuentra en el [README](README.md); resultados detallados
y procedencia, en la [evidencia](evidencia_modelo_oficial.md). Este cierre no
repite aquellos ensayos ni altera esa evidencia; la consulta de ventana TPI-A
tiene su ejecución registrada por separado. Corresponde realizar la auditoría
final de la entrega antes de decidir su commit; no se declara una aprobación
académica universal ni un commit realizado.
