# Informe técnico — Primera Entrega Parcial del TPI
## Base de Datos II — Food Store

**Integrantes:** Avalos Pablo, Blangetti Sofia y Suarez Ismael.

**Resultado consolidado: nueve objetivos cubiertos**, con evidencia ejecutada
cuando corresponde y alcance formal explícito para normalización. TPI-C es una
consolidación documental: no repite pruebas, cambia SQL ni modifica bases.
Los PASS indican cobertura académica trazable, no certificación de producción
ni aprobación de una rúbrica por parte de la cátedra.

## 1. Objetivo, requisitos y alcance

La entrega integra principalmente U1–U3: ER; transformación relacional;
normalización; DDL; DML y consultas; vistas, funciones y procedimientos; reglas
de negocio; transacciones/concurrencia; y soft delete. Incluye pruebas,
resultados, optimización antes/después y decisiones asistidas por IA.

La enumeración sigue los requisitos de cierre aportados por el equipo y el mapa
TPI. No se encontró un documento de consigna independiente versionado que deba
citarse como autoridad adicional. No se inventan exigencias para completar una
lista de tecnologías.

Orden de autoridad: [schema](../schema.sql), [seed](../datos_iniciales.sql),
[modelo](modelo/modelo_relacional.md), [objetos](sql/objetos_programables.sql),
[pruebas](pruebas/pruebas_objetos_programables.sql), documentación vigente y
evidencias. U1/U2 evaluadas se preservan como historia, no como migraciones del
modelo actual. [U4](../unidades/unidad-4/README.md) es complementaria: sus
experimentos y métricas no se utilizan para cerrar estos nueve objetivos.

## 2. Entorno técnico y procedencia

Entorno probado: **PostgreSQL 17.11**, Windows x86_64, 64 bits. Satisface el
requisito de PostgreSQL 16+; no implica que se haya ejecutado además en 16.
Herramientas: SQL, PL/pgSQL, psql, Git y PowerShell; TPI-B utilizó PowerShell
7.6.6. No hay aplicación, ORM, backend ni frontend.

| Evidencia | Base y alcance real |
|---|---|
| [TPI oficial](evidencia_modelo_oficial.md) | foodstore_tpi_oficial: schema/seed, batería funcional, tres ensayos READ COMMITTED y HAVING |
| [TPI-A](evidencia_cierre_objetivos_3_5.md) | foodstore_tpi_cierre_a: schema/seed, ventana ejecutada y defensa formal; sin objetos programables |
| [TPI-B](evidencia_cierre_objetivo_8.md) | foodstore_tpi_cierre_b: schema/seed/objetos; SAVEPOINT, REPEATABLE READ y SERIALIZABLE, dos ejecuciones |
| [U3 oficial](../unidades/unidad-3/informes/evidencia_modelo_oficial.md) | foodstore_tp5_oficial: laboratorio masivo independiente, índices, vistas, seguridad y materializada |

Características realmente utilizadas: ENUM, TIMESTAMPTZ, IDENTITY, PL/pgSQL,
CALL, transition tables, índices parciales/de expresión/INCLUDE, vistas y
materializadas con REFRESH CONCURRENTLY. No hay columnas JSONB en el modelo;
las salidas JSON de herramientas o auditorías no acreditan un modelo JSONB.

## 3. Modelo ER y transformación relacional

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

## 4. Normalización y redundancias deliberadas

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

## 5. DDL, integridad y seed

El catálogo se verificó después de instalar el schema: **3 ENUM, 5 tablas,
40 columnas, 5 PK sobre id, 4 FK, 3 UNIQUE adicionales, 6 CHECK y 3 índices base explícitos**.

- ENUM `forma_pago`: EFECTIVO, TARJETA, TRANSFERENCIA.
- ENUM `rol`: ADMIN, USUARIO; default de usuario: USUARIO.
- ENUM `estado_pedido`: PENDIENTE, CONFIRMADO, TERMINADO, CANCELADO; default:
  PENDIENTE, decisión de implementación para altas.
- FK `fk_producto_categoria`, `fk_pedido_usuario`,
  `fk_detalle_pedido_pedido`, `fk_detalle_pedido_producto`: `ON DELETE RESTRICT`.
- ON UPDATE no está especificado: rige NO ACTION; no se declara cascada.
- UNIQUE de `usuario.mail`, `categoria.nombre` y
  `uq_detalle_pedido_pedido_producto`. No se declara unicidad case-insensitive.
- CHECK de precio/stock de producto, total de pedido, cantidad positiva,
  precio unitario y subtotal del detalle no negativos.
- Índices base: `idx_producto_categoria`, `idx_pedido_usuario`,
  `idx_producto_nombre_vig`. No incluyen los candidatos U3 como instalación
  mínima ni crean claves nuevas.

Los importes usan NUMERIC(12,2); los cinco id son GENERATED ALWAYS AS IDENTITY.
Los cinco created_at tienen DEFAULT now(); pedido.fecha, DEFAULT CURRENT_DATE.
NOT NULL protege atributos obligatorios; descripción, celular e imagen son
opcionales según tabla. Defaults adicionales: stock/total 0 y disponible TRUE.
Forma de pago no tiene default; el modelo relacional enumera todos los tipos.

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

## 6. DML y consultas canónicas

| Elemento | Implementación vigente y verificación |
|---|---|
| INSERT | Seed de las cinco tablas; CALL y batería, grupo A; instalaciones registradas |
| UPDATE | Conciliación del seed; cantidad/precio N/O, baja/reactivación S y movimiento U de batería |
| DELETE físico | Grupo T: retira detalle, recalcula total y no repone stock |
| SELECT y JOIN | HAVING/ventana usuario–pedido; conciliación mediante LATERAL del seed |
| Agregaciones y GROUP BY | COUNT de pedidos y SUM de gasto por usuario; función SQL de total |
| Subconsultas | UPDATE correlacionado del seed con SUM/COALESCE; auditoría de totales en TPI-B |
| HAVING | COUNT(p.id) > 1 después de agrupar; Ana Gómez 2, Luis Paz 2 |
| Ventana | RANK sobre el gasto agregado; tres filas comprobadas en TPI-A |

Fuentes ejecutables: [seed](../datos_iniciales.sql), [consultas de cobertura](sql/consultas_cobertura_tpi.sql),
[batería](pruebas/pruebas_objetos_programables.sql) y [auditoría TPI-B](pruebas/transacciones/auditoria.sql).
La evidencia es [oficial](evidencia_modelo_oficial.md), [TPI-A](evidencia_cierre_objetivos_3_5.md)
y [TPI-B](evidencia_cierre_objetivo_8.md); no depende del viejo RANK sobre cliente.

### HAVING y ventana: historial de compras

La [consulta vigente HAVING](sql/consultas_cobertura_tpi.sql) agrupa `usuario`
con `pedido`, conserva `p.eliminado = FALSE` mediante WHERE antes de agrupar y
selecciona grupos con `HAVING COUNT(p.id) > 1`. Es decir, excluye los pedidos
eliminados y conserva los no eliminados. No filtra usuarios eliminados para
preservar historia; tampoco filtra estados ni une detalle, evitando multiplicar
pedidos por número de líneas.

Resultado real del Bloque 8: **Ana Gómez 2, Luis Paz 2; dos filas, exit code 0,
cero errores SQL**. Marta tiene un pedido y no supera el umbral. HAVING actúa
después de GROUP BY y no se reemplaza por un WHERE sobre COUNT en el mismo nivel.

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

## 7. Objetos programables: autoridades únicas

[objetos_programables.sql](sql/objetos_programables.sql) instala exactamente
**7 rutinas y 5 triggers**, sin tablas ni columnas adicionales.

| Objeto | Tipo | Responsabilidad |
|---|---|---|
| `calcular_total_pedido(bigint)` | Función SQL STABLE | Sumar subtotal físico no eliminado; devuelve cero sin líneas |
| `fn_set_subtotal()` | Función trigger PL/pgSQL | Derivar subtotal de cantidad y precio unitario |
| `fn_validar_detalle_vigente()` | Función trigger PL/pgSQL | Validar pedido, usuario y producto al insertar/reasignar referencias |
| `fn_recalcular_total_insert()` | Función trigger PL/pgSQL | Recalcular pedidos de NEW TABLE |
| `fn_recalcular_total_update()` | Función trigger PL/pgSQL | Recalcular unión de pedidos de OLD/NEW TABLE |
| `fn_recalcular_total_delete()` | Función trigger PL/pgSQL | Recalcular pedidos de OLD TABLE |
| `registrar_detalle_pedido(bigint,bigint,integer)` | Procedimiento PL/pgSQL | Registrar venta con precio histórico, validaciones y descuento de stock |
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

## 8. Trazabilidad de reglas de negocio

Los grupos corresponden a la [batería ejecutada](pruebas/pruebas_objetos_programables.sql),
con resultados conservados en la [evidencia oficial](evidencia_modelo_oficial.md).

| Regla | Mecanismo | Prueba específica / alcance |
|---|---|---|
| Cantidad positiva | chk_detalle_pedido_cantidad; validación CALL | X aísla CHECK; B rechaza 0, -1 y NULL en CALL |
| Stock no negativo | chk_producto_stock | Y: negativo directo rechazado por CHECK |
| Stock suficiente | CALL, comparación bajo FOR UPDATE | C y escenario READ COMMITTED de competencia por stock |
| Mail único | UNIQUE(usuario.mail) | MAIL_UNIQUE: duplicado rechazado |
| Producto único por pedido | uq_detalle_pedido_pedido_producto | H: CALL/directo; escenario concurrente de duplicado |
| Integridad referencial | Cuatro FK ON DELETE RESTRICT | I/J/K: referencias pedido/producto inexistentes; no cuatro negativas individuales |
| Producto vigente/disponible | CALL y fn_validar_detalle_vigente | D/E: rechazo por ambas rutas |
| Pedido/usuario vigente | CALL y fn_validar_detalle_vigente | F/G: rechazo por ambas rutas |
| Subtotal coherente | fn_set_subtotal / trg_subtotal | N/O/P: cantidad, precio y manipulación directa; L/M/Q/R: precios |
| Total de pedido coherente | calcular_total_pedido + tres AFTER | S/T/U/V/W/TOTAL_CERO: bajas, DELETE, movimiento, masivas y cero |
| Total no negativo | chk_pedido_total | Z: CHECK aislado; distinto de mantener la suma |
| Venta y stock atómicos | Transacción del llamante y error propagado | ATOMICIDAD: reversión conjunta de línea, subtotal, total y stock |

Los restantes CHECK (precio de producto, precio_unitario y subtotal) y UNIQUE
de categoría existen y se inventariaron; **no se atribuye a cada uno una prueba
negativa individual inexistente**. Las auditorías TPI-B verifican cero violaciones
en los datos ensayados, lo cual no sustituye esas pruebas negativas.

## 9. Transacciones, stock y atomicidad

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

BEGIN/COMMIT del seed y los COMMIT de sesiones del Bloque 7 están acreditados.
La batería usa BEGIN/ROLLBACK final; el rollback implícito del subbloque de
atomicidad no se presenta como SAVEPOINT SQL explícito. La sección siguiente
separa las nuevas pruebas explícitas de la evidencia anterior.

## 10. Aislamiento y concurrencia real ensayada

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
B terminó con exit 3 esperado; las demás sesiones con exit 0. No se observó
40P01 en esas ejecuciones ni se implementó retry automático.
El conflicto sobre una misma fila también puede ocurrir bajo REPEATABLE READ:
no se presenta como prueba exclusiva de SSI ni como validación del CALL bajo
todos los aislamientos. Los resultados se consolidan aquí sin repetir la ejecución.

Los tres scripts READ COMMITTED anteriores fueron temporales y no quedaron
íntegramente versionados: se conserva ese límite de reproducción, sin reconstruir
retrospectivamente ni reemplazar sus resultados. El arnés TPI-B sí conserva
completamente sus propios casos. Usa respuestas por barrera y monitoreo de locks,
no sleeps ciegos; verifica los niveles efectivos y códigos de salida.

| Caso TPI-B | Valores reales en ambas ejecuciones | Interpretación |
|---|---|---|
| SAVEPOINT explícito | 50 → 49 → 47 → 49 → 50 | ROLLBACK TO conserva el primer cambio y deshace el segundo; ROLLBACK final restaura todo |
| REPEATABLE READ | A lee 50; B confirma 51; A relee 50; nueva transacción ve 51 | Snapshot estable en A, visibilidad posterior del COMMIT |
| SERIALIZABLE | A y B leen 50; A confirma 52; B recibe 40001; control ve 52 | Escritura concurrente abortada; restauración posterior controlada a 50 |

Las dos ejecuciones TPI-B finalizaron con exit global 0. La base quedó
PRESERVED, con datos lógicos y secuencias restituidos, sin fixtures ni sesiones
del ensayo. No se promete igualdad física después de UPDATE/rollback.

## 11. Soft delete e historia

Las cinco tablas tienen **eliminado BOOLEAN NOT NULL DEFAULT FALSE**.
Es baja lógica, no DELETE físico; las filas y sus FK permanecen. RESTRICT
protege el borrado físico de padres referenciados, no impide su baja lógica.

| Uso | Política vigente |
|---|---|
| HAVING y ranking | Excluir pedidos eliminados; conservar usuarios históricos aunque estén eliminados |
| Total de pedido | Sumar detalles no eliminados; no ocultarlos por bajas posteriores de padres |
| Altas/reasignaciones | Validar pedido/usuario/producto vigentes y producto disponible |
| Baja/reactivación del detalle | Excluir/reincorporar subtotal al total; no reponer/descontar stock |
| Catálogo y vistas públicas | Filtrar vigencia según contrato de cada vista (sección 13) |
| Índices parciales | idx_producto_nombre_vig y candidatos U3 indexan filas con eliminado = FALSE |
| Facturación histórica | Filtrar pedido y detalle, no baja actual de producto/categoría ni disponibilidad |

`disponible` no equivale a `eliminado`: una reposición puede incluir productos
no disponibles. No hay una política automática de cancelación o reposición por
baja, reactivación o DELETE. La vista de detalle filtra la línea, no el pedido:
un reporte que requiera ambos vigentes debe aplicar también la condición de pedido.

## 12. Optimización U3: índices y costo de escritura

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

Consultas medidas: stock <= 5, pedidos con fecha >= CURRENT_DATE - 30 y
usuario con lower(mail) = lower('usuario8452@foodstore.test'). En los tres
casos se exige eliminado = FALSE; los literales y planes exactos están en
la evidencia U3, no se sustituyen por los ejemplos estáticos de queries.sql.

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

La fuente detallada de consultas, corridas y planes es la
[evidencia U3](../unidades/unidad-3/informes/evidencia_modelo_oficial.md).
Los buffers se toman de la raíz, no se suman entre padres e hijos: shared hit
869 → 14 para stock, 4001 → 72 para pedidos y 344 → 3 para mail.
La métrica temporal es Execution Time. No se afirma significancia estadística.

## 13. Vistas, seguridad y materialización U3

Definiciones: [views.sql](../unidades/unidad-3/sql/views.sql).

| Vista vigente | Semántica | Filas; EXCEPT en ambos sentidos |
|---|---|---|
| `v_productos_vigentes` | Producto y categoría no eliminados; no exige disponible | 43.299; 0/0 |
| `v_pedidos_resumen` | Pedido vigente con usuario; no oculta historia por baja del usuario | 198.059; 0/0 |
| `v_pedido_detalle` | Detalle vigente, producto y subtotal físico; no filtra baja del producto ni del pedido | 495.327; 0/0 |
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
No se midieron su duración ni bloqueos entre sesiones.
La propuesta heredada de cada 60 minutos sigue pendiente de ratificación
operativa; admite staleness y no garantiza un atraso máximo de una hora.
Las lecturas medidas no incluyen costo de construcción ni refresh.

## 14. Pruebas y resultados consolidados

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
validación multisesión de la sección 10 fue independiente y posterior. Los comentarios
estáticos previos en los scripts no reemplazan esta evidencia de ejecución.

| Complemento | Resultado conservado |
|---|---|
| HAVING oficial | Ana Gómez 2; Luis Paz 2; dos filas |
| TPI-A | Ventana canónica: tres filas, ranking desde 1, sin empates; repeticiones idénticas; defensa formal explícita |
| TPI-B | Dos ejecuciones completas PASS; SAVEPOINT, snapshot RR y 40001; integridad final sin cambios lógicos |
| U3 | Planes/costos medidos, vistas/MV EXCEPT 0/0, permisos 42501 y refresh concurrente PASS |

Comentarios como «validación pendiente» en SQL o evidencias previas corresponden
a su momento de autoría. La ejecución posterior se acredita en evidencia, no
reescribiendo historia. TPI-A dejó Objetivo 8 fuera de su alcance; TPI-B lo cerró.
No es un pendiente actual. En cambio, refresh automático, reintentos, estrés y
garantías universales siguen fuera del alcance probado.

## 15. Uso de IA y decisiones de ingeniería

La IA asistió análisis, propuestas, revisión, generación controlada y
consolidación documental. Las decisiones se contrastaron con SQL, PostgreSQL,
Git y resultados reales; **la responsabilidad final corresponde al equipo**.
No se atribuyen mediciones al texto generado por una herramienta.

La [DUIA U3 vigente](../unidades/unidad-3/duia/duia.md) registra Kiro para specs
originales, OpenCode para candidatos iniciales, revisión humana y Codex para
corrección/ejecución autorizada. Las DUIA históricas preservan sus relatos.
El contrato oficial externo fue aportado por el usuario; no se atribuye a una
herramienta inspección directa de material que no recibió. El cierre TPI empleó
asistencia de Codex; PostgreSQL mediante psql produjo las salidas conservadas.

| Decisión verificable | Resultado y fundamento |
|---|---|
| Corregir la iteración histórica hacia usuario/usuario_id/subtotal físico | Aceptada; alineación con contrato oficial, sin reescribir U1/U2 |
| Conservar subtotal con autoridad única | Aceptada; excepción formal reconocida y pruebas N/O/P |
| Ventana canónica, no el RANK histórico | Aceptada; SQL actual y resultado real TPI-A |
| CALL con stock y derivados en transacción del llamante | Aceptada en el alcance probado; atomicidad y READ COMMITTED |
| Tres índices U3 | Aceptados para el workload medido, explicitando costo de escritura |
| Covering de mail U3 | Descartado por tamaño y ausencia de beneficio temporal adicional medido |
| Reposición/cancelación y garantías universales | No implementadas ni inferidas sin contrato/evidencia |

## 16. Reproducción: tres recorridos separados

**Guía operativa:** [README TPI](README.md), desde la raíz, autenticación local
configurada sin publicar secretos. No ejecutar comandos durante una revisión
solo documental ni recrear bases existentes sin autorización.

1. **TPI mínimo, foodstore_tpi_oficial nueva:** schema (-1), seed (sin -1),
   objetos (-1), batería (sin -1) y consultas de cobertura (solo lectura).
   Todos con ON_ERROR_STOP=1. La batería tiene guarda literal y rollback propio.
2. **Aislamientos, foodstore_tpi_cierre_b nueva:** preparar schema/seed/objetos
   según [README del arnés](pruebas/transacciones/README.md), cerrar otras
   sesiones y ejecutar `pwsh -NoProfile -File .\tpi\pruebas\transacciones\ejecutar.ps1`.
   Logs bajo TEMP; comprobar exit 0 y resultados, no solo ausencia de mensajes.
3. **U3 opcional y separado:** seguir [guía U3](../unidades/unidad-3/README.md)
   y evidencia (Anexo B de bootstrap/carga, protocolo e inventario). Medir BEFORE
   antes de instalar candidatos; vistas, seguridad y materializada tienen pasos
   propios. No instalar índices antes del baseline ni ejecutar DROP/recreación
   sin autorización específica sobre esa copia.

Schema/seed TPI no reproducen la carga masiva U3 ni sus tiempos. Los avisos U3
que describían el schema raíz como antiguo pertenecen al momento previo a su
reparación; hoy la autoridad es schema.sql, pero la procedencia de mediciones
sigue siendo aquel laboratorio. No se modifican esos documentos protegidos.

## 17. Matriz final de los nueve objetivos

PASS significa implementación o razonamiento formal verificable, con evidencia
adecuada a cada objetivo, no una simple declaración documental.

| # | Objetivo | Implementación | Evidencia / prueba o razonamiento | Estado |
|---|---|---|---|---|
| 1 | Modelo ER | [DER](modelo/modelo_er.md), cinco entidades y atributos | Correspondencia con [schema](../schema.sql); inventario de 40 columnas en [evidencia oficial](evidencia_modelo_oficial.md) | PASS |
| 2 | Modelo relacional | [Relaciones](modelo/modelo_relacional.md), PK/FK/UK, N:M | Cuatro FK NOT NULL, clave alternativa del detalle y catálogo registrado | PASS |
| 3 | Normalización | [DF, claves y formas normales](modelo/normalizacion.md) | [TPI-A](evidencia_cierre_objetivos_3_5.md): análisis formal, excepción subtotal y lossless teórico | PASS académico, no FNBC física universal |
| 4 | DDL completo | [Schema](../schema.sql), tipos/constraints/índices | [Instalación y catálogo](evidencia_modelo_oficial.md), exit 0 | PASS |
| 5 | DML y consultas | [Seed](../datos_iniciales.sql), [batería](pruebas/pruebas_objetos_programables.sql), [HAVING/RANK](sql/consultas_cobertura_tpi.sql) | Grupos A/N/O/S/T; seed con subconsulta; HAVING oficial y ventana [TPI-A](evidencia_cierre_objetivos_3_5.md) ejecutados | PASS |
| 6 | Vistas, funciones y procedimientos | [Objetos TPI](sql/objetos_programables.sql), [vistas U3](../unidades/unidad-3/sql/views.sql) | 7 rutinas/5 triggers, CALL real; vistas EXCEPT 0/0 en [U3](../unidades/unidad-3/informes/informe_mediciones.md) | PASS |
| 7 | Reglas de negocio | CHECK/UNIQUE/FK, procedimiento y triggers | Tabla regla–mecanismo–prueba, sección 8; [batería PASS](evidencia_modelo_oficial.md) sin atribuir negativas no ejecutadas | PASS |
| 8 | Transacciones y concurrencia | [Batería](pruebas/pruebas_objetos_programables.sql) y [arnés multisesión](pruebas/transacciones/README.md) | Atomicidad/READ COMMITTED previos; SAVEPOINT/RR/SERIALIZABLE 40001 en [TPI-B](evidencia_cierre_objetivo_8.md) | PASS, alcance ensayado |
| 9 | Soft delete | Cinco eliminado; filtros, triggers, índices y vistas | Batería D–G/S/TOTAL_CERO; semántica histórica y equivalencias [U3](../unidades/unidad-3/informes/informe_mediciones.md) | PASS |

## 18. Límites explícitos

No se afirma FNBC estricta de todas las tablas físicas, seguridad concurrente
de DML directo arbitrario, ausencia universal de deadlocks, retry automático,
CALL seguro bajo cualquier aislamiento, reposición/cancelación ni rendimiento
bajo estrés. Una escritura directa de pedido.total queda fuera de los triggers
de detalle. Las pruebas TPI-B sobre stock son fixtures, no otra API de ventas.

Los scripts temporales READ COMMITTED no quedaron completamente versionados;
sus resultados y protocolos permanecen en evidencia. La reproducción multisesión
íntegra nueva corresponde a SAVEPOINT/RR/SERIALIZABLE. Las métricas U3 dependen
de su dataset/protocolo y no son promesas operativas. El cierre no modifica
históricos ni integra SQL experimental U4 al modelo.

## 19. Conclusión

La Primera Entrega presenta los nueve objetivos con artefactos y evidencia
trazables: modelo oficial, integridad, consultas canónicas, reglas programables,
transacciones y análisis de optimización con costos. La normalización se defiende
sin ocultar la excepción de subtotal; la concurrencia se explica sin convertir
casos aprobados en garantías universales. Las propuestas asistidas por IA se
aceptan o descartan por contrato y evidencia, no por autoridad de la herramienta.

TPI-C consolida los resultados existentes sin nuevas ejecuciones. La revisión
final independiente de entrega corresponde a TPI-D y no se declara realizada
por esta consolidación documental.
