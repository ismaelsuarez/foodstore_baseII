# TPI Food Store — Evidencia del modelo oficial

La ejecución funcional del Bloque 6 y los tres escenarios de concurrencia del
Bloque 7 pasaron. El arnés temporal del Bloque 7 registró una incidencia de
limpieza, documentada separadamente: no fue un fallo de los objetos productivos.
Este documento consolida resultados observados; no sustituye el informe técnico
final ni convierte los ensayos en una garantía universal.

## Entorno y alcance

| Dato | Valor observado |
|---|---|
| Motor | PostgreSQL 17.11 |
| Plataforma | x86_64-windows |
| Compilador | msvc-19.44.35228 |
| Arquitectura | 64-bit |
| Base descartable | `foodstore_tpi_oficial` |
| Rama | `fix/alinear-foodstore-der-oficial` |
| Fecha del ensayo multisesión | 2026-09-21 |

La base es exclusivamente de laboratorio, no productiva. El Bloque 6 reconstruyó
el esquema e instaló el seed, los objetos y la batería. El Bloque 7 reutilizó esa
base sin recrearla. En el Bloque 8 se consolidó esta evidencia sin repetir la
batería ni los escenarios concurrentes; su única consulta ejecutada se identifica
por separado al final.

## Bloque 6 — Ejecución funcional de una sesión

### Instalación e inventario

[`schema.sql`](../schema.sql), [`datos_iniciales.sql`](../datos_iniciales.sql) y
[`objetos_programables.sql`](sql/objetos_programables.sql) finalizaron con
**PASS**, código de salida **0**. Se utilizó `ON_ERROR_STOP=1`; schema y objetos
se instalaron transaccionalmente, mientras el seed administró su propia
transacción. El éxito de instalación se contrastó con el catálogo.

| Verificación del esquema | Resultado |
|---|---|
| ENUM | 3: `forma_pago`, `rol`, `estado_pedido` |
| Tablas | 5 |
| Columnas | 40: categoria 5, usuario 9, producto 10, pedido 8, detalle_pedido 8 |
| PK | 5, todas sobre `id` |
| FK | 4, con `ON DELETE RESTRICT` |
| CHECK | 6 |
| Unicidad del detalle | `uq_detalle_pedido_pedido_producto`: `UNIQUE(pedido_id, producto_id)` |
| Índices base explícitos | `idx_producto_categoria`, `idx_pedido_usuario`, `idx_producto_nombre_vig` |

Los tres índices base no incluyen los índices automáticos de PK/UNIQUE. También
se observaron las unicidades de `usuario.mail` y `categoria.nombre`.

### Seed y precio histórico

| Tabla | Filas |
|---|---:|
| usuario | 3 |
| categoria | 2 |
| producto | 3 |
| pedido | 5 |
| detalle_pedido | 7 |

Se verificaron Ana Gómez, Luis Paz y Marta Ruiz con sus mails del seed, rol
`USUARIO` y `eliminado = FALSE`. El marcador documental de contraseña coincidió;
no fue tratado como credencial de autenticación.

Los cinco pedidos estaban `TERMINADO`, sin baja lógica, con asociaciones y
formas de pago correctas. Usuario y fecha identifican estas filas dentro del
dataset controlado; no constituyen una clave candidata del modelo.

| Usuario | Fecha | Total verificado |
|---|---|---:|
| Ana Gómez | 2026-03-01 | 2800.00 |
| Luis Paz | 2026-03-01 | 1500.00 |
| Ana Gómez | 2026-03-05 | 3150.00 |
| Marta Ruiz | 2026-03-06 | 6200.00 |
| Luis Paz | 2026-03-07 | 1050.00 |

- Subtotales distintos de `cantidad * precio_unitario`: **0**.
- Totales distintos de la suma de subtotales de detalles no eliminados: **0**.
- Muzzarella: precio actual de catálogo **1050.00**, una línea histórica a
  **1000.00**. `HISTORICAL_PRICE_SEED: PASS`.

### Objetos programables

Inventario confirmado: **7 rutinas y 5 triggers habilitados, 12 objetos**.

| Tipo | Nombre |
|---|---|
| Función SQL | `calcular_total_pedido(bigint)` |
| Función trigger | `fn_set_subtotal()` |
| Función trigger | `fn_validar_detalle_vigente()` |
| Función trigger | `fn_recalcular_total_insert()` |
| Función trigger | `fn_recalcular_total_update()` |
| Función trigger | `fn_recalcular_total_delete()` |
| Procedimiento | `registrar_detalle_pedido(bigint,bigint,integer)` |
| Trigger | `trg_subtotal` |
| Trigger | `trg_detalle_vigente` |
| Trigger | `trg_total_detalle_insert` |
| Trigger | `trg_total_detalle_update` |
| Trigger | `trg_total_detalle_delete` |

Se comprobaron los tipos de rutina, sus firmas y las transition tables de los
triggers de total. La smoke de `calcular_total_pedido` devolvió **2800.00** para
un pedido con total almacenado **2800.00**, y **0** para un BIGINT inexistente.

### Batería y reversibilidad

Archivo ejecutado: [`pruebas_objetos_programables.sql`](pruebas/pruebas_objetos_programables.sql).

| Verificación | Resultado |
|---|---|
| Grupos definidos | 29 |
| Variantes definidas | 37 |
| NOTICE `PASS` observados | 30: 29 grupos y 1 global |
| Código de salida | 0 |
| Errores SQL inesperados | 0 |
| Fixtures restantes después de `ROLLBACK` | 0 |
| Seed intacto | PASS, huellas de las cinco tablas coincidentes |
| Objetos después del rollback | PASS, 7 rutinas y 5 triggers habilitados |
| Operación masiva | PASS |
| Reconciliación final de subtotal | 0 inconsistencias |
| Reconciliación final de total | 0 inconsistencias |

Se alcanzó exactamente el NOTICE global:

> PASS: batería completa de objetos programables del modelo oficial

Pasaron el caso feliz, los rechazos de parámetros/referencias/estados/stock,
duplicados, FK/UNIQUE/CHECK, precio histórico, actualizaciones de subtotal y
total, baja y reactivación de detalle, DELETE físico, movimiento entre pedidos,
operaciones masivas y atomicidad. Los errores esperados se capturaron por su
SQLSTATE específico y no se contaron como errores inesperados.

La prueba adicional de precio NULL se omitió como `SKIPPED_AS_DUPLICATE`: la
batería ya había validado ese flujo. El rollback no promete restaurar los
contadores IDENTITY, que pueden conservar huecos.

**Límite:** esta batería corre en una sola sesión; por sí sola no prueba
concurrencia multisesión. Esa evidencia corresponde al bloque siguiente.

## Bloque 7 — Concurrencia real multisesión

### Resultado y protocolo

```text
CONCURRENCY_VALIDATION: PASS
PRODUCT_OBJECT_FAILURES: 0
TEST_HARNESS_INCIDENTS: 1
INCIDENT: SQLSTATE 42601 en helper temporal 21_cleanup.sql
IMPACT_ON_PRODUCT_TESTS: NONE
```

Cada escenario empleó dos procesos `psql` independientes y una tercera conexión
de monitoreo. Ambas sesiones usaron explícitamente **READ COMMITTED**; el
aislamiento por defecto observado también era `read committed`.

Los fixtures fueron confirmados antes de abrir las sesiones y sus IDs se
obtuvieron mediante `RETURNING`. A mantuvo su transacción abierta con
`pg_sleep(5)` después del `CALL`. B comenzó tras observar que A había llegado a
esa espera. El bloqueo se comprobó en `pg_stat_activity`/`pg_locks` y mediante
el PID bloqueador, no se infirió solamente de una demora.

### Escenario 1 — Mismo producto, pedidos diferentes

Producto con precio **100.00** y stock inicial **5**. A vendió **4** unidades;
B intentó vender otras **4** sobre un pedido diferente.

B esperó con `wait_event_type = Lock`, `wait_event = transactionid`. Después
del commit de A, B recibió exactamente **SQLSTATE 23514**, por stock
insuficiente: disponible **1**, solicitado **4**.

| Estado final | Valor |
|---|---:|
| Stock | 1 |
| Detalles del pedido A | 1 |
| Cantidad / precio / subtotal A | 4 / 100.00 / 400.00 |
| Total A | 400.00 |
| Detalles del pedido B | 0 |
| Total B | 0.00 |

**PASS:** el lock de producto evitó sobreventa en el escenario ensayado.

### Escenario 2 — Mismo pedido, productos diferentes

A vendió **2 × 200.00**; B vendió **3 × 300.00**. Ambos productos partieron
de stock **10**. B esperó con `Lock / transactionid` sobre el pedido y ambos
`CALL` terminaron con commit.

| Estado final | Valor |
|---|---:|
| Detalles vigentes | 2 |
| Subtotales | 400.00 y 900.00 |
| `pedido.total` | 1300.00 |
| `calcular_total_pedido` | 1300.00 |
| Stock producto A / B | 8 / 7 |

**PASS:** el lock de pedido serializó las operaciones ensayadas y evitó una
pérdida de actualización del total.

### Escenario 3 — Mismo pedido, mismo producto

Producto con precio **150.00** y stock inicial **10**. A solicitó **2** unidades;
B solicitó **1**. B esperó con `Lock / transactionid` y, después del commit de A,
recibió exactamente **SQLSTATE 23505**, por detalle duplicado.

| Estado final | Valor |
|---|---:|
| Detalles | 1 |
| Cantidad / precio / subtotal | 2 / 150.00 / 300.00 |
| `pedido.total` | 300.00 |
| Stock | 8 |

**PASS:** la segunda operación fue rechazada sin segundo descuento de stock.

### Evidencia de bloqueo y conciliación

| Escenario | PID A | PID B | Estado B | Espera B | PID bloqueador |
|---|---:|---:|---|---|---:|
| Stock | 15704 | 22704 | active | Lock / transactionid | 15704 |
| Total | 18204 | 16164 | active | Lock / transactionid | 18204 |
| Duplicado | 11432 | 6604 | active | Lock / transactionid | 11432 |

Son PIDs circunstanciales de esa ejecución, no identificadores persistentes.
Las seis sesiones finalizaron con código **0**; los rechazos esperados de B
se capturaron exclusivamente por `23514` y `23505`, comprobando también el
mensaje correspondiente.

Antes y después de la limpieza, la auditoría global registró **0 subtotales
inconsistentes y 0 totales inconsistentes**.

## Incidencia del harness de cleanup

Clasificación: **`NON_PRODUCT_TEST_HARNESS_INCIDENT`**.

Una vez finalizados los tres escenarios, `21_cleanup.sql` produjo
**SQLSTATE 42601**, error de sintaxis al abrir un bloque PL/pgSQL con `BEGIN;`.
El error se informó en la línea 13 del archivo temporal, señalando el punto y
coma después del `BEGIN` del bloque.

- No fue un error de `schema.sql`, de `objetos_programables.sql` ni de la batería
  versionada.
- PostgreSQL rechazó el helper antes de eliminar filas; la transacción quedó
  revertida. Una lectura posterior confirmó los fixtures y la conciliación.
- Se ejecutó únicamente `24_safe_cleanup.sql` para completar la limpieza
  autorizada. **No se repitieron los escenarios concurrentes.**

El helper pertenece al arnés temporal de pruebas, no al software SQL entregado.
La incidencia se conserva porque afectó la ejecución del arnés y requirió una
limpieza segura posterior; no se oculta ni se presenta como irrelevante.

El resumen original del Bloque 7 marcó `CONCURRENCY_STATUS = FAIL` al agrupar
los ensayos y la limpieza bajo un único estado. La clasificación consolidada
separa ambos resultados: **los tres ensayos productivos son PASS**, con
**una incidencia no productiva del arnés** y sin impacto en sus resultados.

### Limpieza segura y estado final de la base

`24_safe_cleanup.sql` finalizó con commit y eliminó exclusivamente fixtures:

| Objeto de prueba | Filas eliminadas |
|---|---:|
| detalle_pedido | 4 |
| pedido | 4 |
| producto | 4 |
| usuario | 1 |
| categoria | 1 |

`25_after_cleanup` y `post_cleanup_result.json` confirmaron:

- Fixtures restantes de las cinco tablas: **0**.
- Seed: **usuario 3 / categoria 2 / producto 3 / pedido 5 / detalle_pedido 7**.
- Stocks: **Muzzarella 50 / Napolitana 40 / Coca 1.5L 100**.
- Totales del seed: **2800 / 1500 / 3150 / 6200 / 1050**, sin cambios en las
  asociaciones y fechas detalladas anteriormente.
- Huellas de las cinco tablas iguales a las anteriores al ensayo.
- **12 objetos intactos**: 7 rutinas y 5 triggers habilitados.
- Reconciliación de subtotal y total: **0 / 0** inconsistencias.

## Límites de las conclusiones concurrentes

Solo se acreditan los tres escenarios ejecutados bajo READ COMMITTED. No se
demostró ausencia universal de deadlocks, concurrencia segura de DML directo,
garantías bajo SERIALIZABLE, reposición de stock, cancelaciones, carga masiva
concurrente ni rendimiento bajo estrés.

## Fuentes y conservación de la evidencia

Los resultados anteriores se contrastaron con salidas y resúmenes temporales
de las ejecuciones, no se generaron repitiendo las pruebas en este bloque.

- Bloque 6: `C:\Users\facu\AppData\Local\Temp\foodstore-tpi-b6-0UFKNL`.
  Fuentes: `04_schema_inventory.txt`, `06_seed_validation.txt`,
  `08_objects_smoke.txt`, `foodstore_tpi_oficial_pruebas.txt`,
  `notice_verification.json`, `10_post_tests.txt` y `final_validation.json`.
- Bloque 7: `C:\Users\facu\AppData\Local\Temp\foodstore-tpi-b7-KMjMGd`.
  Fuentes: `stock_blocked.json`, `total_blocked.json`, `dup_blocked.json`,
  `stock_result.json`, `total_result.json`, `dup_result.json` y los archivos de
  sesión `stock_a/b`, `total_a/b`, `dup_a/b` (`.sql`, `.stdout.txt`, `.stderr.txt`,
  `.meta.json` con timestamps y códigos de salida). Para la incidencia y su
  cierre: `21_cleanup.stderr.txt`, `23_cleanup_error_state.stdout.txt`,
  `24_safe_cleanup.stdout.txt`, `25_after_cleanup.stdout.txt`,
  `post_cleanup_result.json` y `summary.json`.

Estas rutas son de procedencia temporal, no enlaces persistentes ni requisitos
para leer este documento. Se preservan aquí los resultados relevantes y la
incidencia sin copiar logs completos, planes extensos o todas las variantes.

## Bloque 8 — Consulta de cobertura HAVING

La consulta vigente de [`consultas_cobertura_tpi.sql`](sql/consultas_cobertura_tpi.sql)
se ejecutó una sola vez contra `foodstore_tpi_oficial`, el **2026-09-21 a las
20:54:55 -03:00**. Esta salida pertenece al modelo oficial, no a las consultas
históricas del TPI.

```sql
SELECT
    u.id AS usuario_id,
    u.nombre,
    u.apellido,
    u.mail,
    COUNT(p.id) AS cantidad_pedidos
FROM usuario u
JOIN pedido p
    ON p.usuario_id = u.id
WHERE p.eliminado = FALSE
GROUP BY
    u.id,
    u.nombre,
    u.apellido,
    u.mail
HAVING COUNT(p.id) > 1
ORDER BY
    cantidad_pedidos DESC,
    usuario_id ASC;
```

`WHERE` excluye pedidos eliminados antes de agrupar; `HAVING` filtra los grupos
después de `GROUP BY`. No se excluyen usuarios eliminados, para conservar el
historial de pedidos realizados. No se filtra por estado, porque no existe ese
requisito, ni se une `detalle_pedido`, para no multiplicar pedidos por sus líneas.

Comando ejecutado desde la raíz:

```text
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f ./tpi/sql/consultas_cobertura_tpi.sql
```

Resultado real devuelto por PostgreSQL:

| usuario_id | nombre | apellido | mail | cantidad_pedidos |
|---:|---|---|---|---:|
| 1 | Ana | Gómez | ana.gomez@foodstore.test | 2 |
| 2 | Luis | Paz | luis.paz@foodstore.test | 2 |

**2 filas, código de salida 0, errores SQL 0, stderr vacío: PASS.** Marta no
aparece: su único pedido del seed no supera `HAVING COUNT(p.id) > 1`.

Fuente temporal: `C:\Users\facu\AppData\Local\Temp\foodstore-tpi-b8-JauY0I`,
archivos `coverage_result.json`, `coverage.stdout.txt` y `coverage.stderr.txt`.
La tabla anterior conserva el resultado sin depender de la permanencia del log.
En este bloque no se reinstaló SQL productivo ni se repitieron la batería o la
concurrencia.

## Alcance del cierre

En los Bloques 6 y 7 los hashes de los siete archivos previamente modificados
permanecieron idénticos; las ejecuciones no editaron el repositorio ni el índice
Git. Esta evidencia no declara todavía un cierre global del TPI.
