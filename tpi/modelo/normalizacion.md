# Normalización del Modelo Oficial — Food Store

La autoridad vigente es [schema.sql](../../schema.sql), representada en el
[ER](modelo_er.md) y el [modelo relacional](modelo_relacional.md).
**No todas las relaciones cumplen FNBC si se incluye la regla de negocio
del subtotal.** El detalle contiene una redundancia derivada deliberada;
pedido almacena un agregado físico cuya consistencia cruza relaciones.

## Criterio y fuentes de dependencias

Una dependencia funcional (DF) `X → Y` establece que un valor de `X`
determina un único valor de `Y` dentro de una relación. Una clave candidata
es una superclave mínima. Un atributo primo pertenece a alguna clave
candidata, no solo a la PK elegida.

| Nivel | Fuente | Alcance |
|---|---|---|
| A. DF por restricciones | PK y UNIQUE con NOT NULL de `schema.sql` | Garantías estructurales actuales |
| B. Reglas del dominio | Subtotal como cantidad por precio histórico; total de detalles vigentes | Reglas conceptuales que la capa programable debe mantener |
| C. Redundancias deliberadas | Subtotal físico y total físico del modelo oficial | Se conservan y requieren consistencia; no se eliminan para ocultar el resultado del análisis |

El archivo `schema.sql` por sí solo no impone automáticamente la igualdad
del subtotal ni la conciliación del total. Los CHECK de no negatividad no
equivalen a esas reglas. La capa TPI ya implementada en
[objetos_programables.sql](../sql/objetos_programables.sql) mantiene ambas
reglas cuando se instala; su ejecución anterior está registrada en la
[evidencia oficial](../evidencia_modelo_oficial.md). Una base que solo carga
schema y seed no tiene esos triggers instalados automáticamente.

- **1FN:** atributos escalares, sin grupos repetitivos.
- **2FN:** 1FN y ausencia de dependencia parcial de un atributo no primo
  respecto de una parte propia de cualquier clave candidata compuesta.
- **3FN:** en cada DF no trivial `X → A`, `X` es superclave o `A` es primo.
- **FNBC:** en cada DF no trivial el determinante es superclave.

Las FK no implican unicidad del lado hijo. Defaults y coincidencias del
seed tampoco crean DF. Los campos opcionales `descripcion`, `celular` e
`imagen` admiten NULL, sin representar listas ni claves. El análisis usa
atributos escalares y DF identificadas; no inventa reglas a partir de una muestra.

## 1. usuario

Relación: `usuario(id, nombre, apellido, mail, celular, contrasena, rol, eliminado, created_at)`.

- **Claves candidatas:** `{id}` por PK; `{mail}` por UNIQUE NOT NULL.
- **Primos:** `id`, `mail`.
- **No primos:** `nombre`, `apellido`, `celular`, `contrasena`, `rol`,
  `eliminado`, `created_at`.
- **DF respaldadas:** `id → resto de atributos`; `mail → resto de atributos`.

| Forma normal | Resultado | Fundamento |
|---|---|---|
| 1FN | CUMPLE | Valores escalares, sin colecciones de pedidos en una fila. |
| 2FN | CUMPLE | Las dos claves son simples, sin dependencias parciales. |
| 3FN | CUMPLE | Todos los determinantes identificados son superclaves. |
| FNBC | CUMPLE | `id` y `mail` son claves candidatas. |

No se asume `celular → usuario` ni `{nombre, apellido} → usuario`. Tampoco
se declara clave a `lower(mail)`. El ENUM de rol restringe valores pero
no identifica usuarios. La vista pública U3 omite `contrasena` y `celular`
sin retirarlos del modelo base.

## 2. categoria

Relación: `categoria(id, nombre, descripcion, eliminado, created_at)`.

- **Claves candidatas:** `{id}` por PK; `{nombre}` por UNIQUE NOT NULL.
- **Primos:** `id`, `nombre`.
- **No primos:** `descripcion`, `eliminado`, `created_at`.
- **DF respaldadas:** `id → resto`; `nombre → resto`.

| Forma normal | Resultado | Fundamento |
|---|---|---|
| 1FN | CUMPLE | Atributos escalares, sin grupos de productos en una columna. |
| 2FN | CUMPLE | Ambas claves son simples. |
| 3FN | CUMPLE | Los determinantes identificados son superclaves. |
| FNBC | CUMPLE | `id` y `nombre` determinan la relación completa. |

## 3. producto

Relación: `producto(id, nombre, precio, descripcion, stock, imagen, disponible, categoria_id, eliminado, created_at)`.

- **Clave candidata respaldada:** `{id}`.
- **Primo:** `id`.
- **No primos:** `nombre`, `precio`, `descripcion`, `stock`, `imagen`,
  `disponible`, `categoria_id`, `eliminado`, `created_at`.
- **DF respaldada:** `id → resto`.

| Forma normal | Resultado | Fundamento |
|---|---|---|
| 1FN | CUMPLE | Todos los atributos son escalares. |
| 2FN | CUMPLE | La clave candidata identificada es simple. |
| 3FN | CUMPLE | La DF identificada tiene determinante superclave. |
| FNBC | CUMPLE | El determinante es `id`, clave candidata. |

`nombre` no es UNIQUE y no se supone `nombre → resto`. `categoria_id`
puede repetirse y no determina al producto ni su precio o stock.
`disponible` expresa condición comercial/operativa; `eliminado` expresa
baja lógica. No son sinónimos ni uno determina al otro.

## 4. pedido

Relación: `pedido(id, fecha, estado, total, forma_pago, usuario_id, eliminado, created_at)`.

- **Clave candidata respaldada:** `{id}`.
- **Primo:** `id`.
- **No primos:** `fecha`, `estado`, `total`, `forma_pago`, `usuario_id`,
  `eliminado`, `created_at`.
- **DF interna respaldada:** `id → resto`.

| Forma normal | Resultado | Fundamento |
|---|---|---|
| 1FN | CUMPLE | Datos escalares; las líneas están en otra relación. |
| 2FN | CUMPLE | La clave candidata es simple. |
| 3FN | CUMPLE con las DF internas identificadas | El determinante es superclave. |
| FNBC | CUMPLE con las DF internas identificadas | `id` determina el resto. |

Ni `usuario_id`, `fecha`, `forma_pago`, `estado`, ni sus combinaciones son
claves respaldadas. La fecha comercial es DATE y `created_at` es TIMESTAMPTZ.
Que el seed use ciertas fechas y formas de pago no establece unicidad.

### Total: agregado entre relaciones

`pedido.total` es un **DATO AGREGADO FÍSICO** y una redundancia deliberada.
Debe representar la suma de `detalle_pedido.subtotal` para el pedido y las
líneas con `eliminado = FALSE`; sin líneas vigentes, el resultado conceptual
es cero. No se elimina porque pertenece al modelo oficial.

Esta regla cruza relaciones y por sí sola no demuestra una DF interna
entre atributos no clave de pedido. Por ello, la presencia de total no
basta para declarar una violación de FNBC. Sí obliga a mantener consistencia
mediante `calcular_total_pedido` y los tres triggers AFTER de detalle de la
capa TPI: el DEFAULT 0 y `CHECK(total >= 0)` no realizan la conciliación.

## 5. detalle_pedido

Relación: `detalle_pedido(id, cantidad, precio_unitario, subtotal, pedido_id, producto_id, eliminado, created_at)`.

- **Claves candidatas:** `{id}` por PK; `{pedido_id, producto_id}` por
  `uq_detalle_pedido_pedido_producto` más ambas columnas NOT NULL.
- **Primos:** `id`, `pedido_id`, `producto_id`.
- **No primos:** `cantidad`, `precio_unitario`, `subtotal`, `eliminado`,
  `created_at`.
- **DF por claves:** `id → resto`; `{pedido_id, producto_id} → resto`.
- **DF conceptual del dominio:** `{cantidad, precio_unitario} → subtotal`,
  cuando se mantiene `subtotal = cantidad * precio_unitario`.

El par pedido/producto es una clave candidata alternativa, **no la PK**.
Un pedido admite productos con cantidades y precios diferentes; un producto
puede venderse en pedidos distintos con cantidades y precios diferentes.
No se identifica una DF parcial de un no primo respecto de `pedido_id`
o `producto_id` por separado.

### Formas normales del detalle

| Forma normal | Resultado | Fundamento |
|---|---|---|
| 1FN | CUMPLE | Atributos escalares; cada fila representa una línea identificable. |
| 2FN | CUMPLE respecto de ambas claves identificadas | No hay DF parcial respaldada de un no primo sobre una parte propia de la clave compuesta. Tener PK simple no elimina la necesidad de analizar la clave alternativa. |
| 3FN | NO CUMPLE estrictamente al incluir la regla del subtotal | `{cantidad, precio_unitario}` no es superclave y `subtotal` no es primo. |
| FNBC | NO CUMPLE estrictamente al incluir la regla del subtotal | La misma DF tiene un determinante que no es superclave. |

Distintos detalles pueden compartir cantidad y precio sin ser la misma fila;
ese par no identifica el detalle. La DF del subtotal es una regla conceptual
de negocio, **no una garantía ya implementada por `schema.sql`**.
Considerando solo las DF de claves actualmente impuestas por el DDL no
aparece esa violación; el análisis completo no debe omitir la regla del
dominio para obtener artificialmente una conclusión favorable.

### Subtotal: redundancia derivada deliberada

Clasificación: **REDUNDANCIA DERIVADA DELIBERADA Y CONTROLADA**.

El subtotal físico es obligatorio en el modelo oficial. No se propone
eliminarlo ni sustituirlo permanentemente por una expresión en consultas.
Su mantenimiento automático ya está implementado mediante `fn_set_subtotal`
y `trg_subtotal` en [objetos_programables.sql](../sql/objetos_programables.sql).
El trigger BEFORE por fila deriva `NEW.subtotal = NEW.cantidad *
NEW.precio_unitario` en INSERT y en UPDATE de cantidad, precio unitario,
producto o subtotal. Sustituye cualquier subtotal suministrado directamente;
el cálculo pertenece a la misma sentencia y transacción que modifica la línea.

El CHECK presente solo garantiza subtotal no negativo. Cambios de cantidad
o precio pueden dejarlo inconsistente si no se mantiene. El
[seed](../../datos_iniciales.sql) calcula sus subtotales explícitamente y
reconcilia sus totales como una fotografía inicial; esa carga no reemplaza
la instalación de los objetos para operaciones posteriores. Las pruebas de
cantidad, precio y manipulación directa de subtotal se conservan en la
[batería TPI](../pruebas/pruebas_objetos_programables.sql), grupos N, O y P;
su resultado previo está en la evidencia oficial, no se reejecuta aquí.

La decisión física responde al contrato oficial, no a un desconocimiento de
3FN: preserva el importe histórico usado por reportes junto a su cantidad y
precio, facilita su trazabilidad y mantiene una autoridad transaccional dentro
del motor, sin depender de que una aplicación externa recalcule correctamente.
No se afirma una mejora de rendimiento no medida. El control de consistencia
no convierte al detalle físico en 3FN/FNBC estricta.

## Normalización lógica y alcance de la descomposición

El modelo conceptual/lógico separa los hechos de usuario, categoría, producto,
pedido y línea de pedido, con claves y DF explícitas. Para usuario, categoría,
producto y pedido, las DF internas identificadas ya satisfacen 3FN/FNBC: no
existe una DF violatoria que obligue a una nueva descomposición en este análisis.
No se inventa una relación universal ni una migración anterior para afirmar
que se ejecutó un algoritmo que no está documentado.

En detalle se distingue el hecho lógico base, sin el atributo calculado, de
su representación física oficial con subtotal. La proyección sin subtotal
conserva las claves `{id}` y `{pedido_id, producto_id}`; bajo las DF por claves
identificadas no presenta la DF derivada que viola 3FN/FNBC. Esto no borra la
excepción del esquema físico realmente entregado.

### Demostración teórica de JOIN sin pérdida aplicada al detalle

Sea `D` la relación detalle completa y `X = {cantidad, precio_unitario}`.
Para una instancia que satisface `X → subtotal`, considerar las proyecciones:

```text
D1(cantidad, precio_unitario, subtotal)
D2(id, cantidad, precio_unitario, pedido_id, producto_id, eliminado, created_at)
```

Se cumple `D1 ∩ D2 = X` y `X → D1`: X determina sus propios atributos por
reflexividad y determina subtotal por la regla del dominio. El criterio de
descomposición binaria garantiza entonces que
`π_D1(D) JOIN π_D2(D) = D`: la descomposición es **sin pérdida** bajo esa DF.
Cada línea conserva su id en D2; al reconstruirla existe un único subtotal
para su par cantidad/precio. El razonamiento usa proyecciones relacionales
sin duplicados y atributos del cálculo NOT NULL; no presupone que un JOIN de
dos copias SQL con duplicados tenga esa propiedad.

Las DF por claves quedan en D2 para sus atributos; combinadas con
`X → subtotal` de D1 permiten deducir las DF originales por claves sobre D.
La regla aritmética `subtotal = cantidad * precio_unitario` es más fuerte que
la mera DF: una tabla D1 hipotética tendría que imponer también esa igualdad,
no solo unicidad del par. La prueba lossless no sustituye esa regla ni afirma
una clasificación exhaustiva de otras DF aritméticas de D1.

**No se implementa esta descomposición.** D1 sería un catálogo artificial de
combinaciones cantidad/precio, no una entidad independiente del negocio;
mantenerlo agregaría relaciones y operaciones sin necesidad funcional. La
alternativa lógica de calcular subtotal sin almacenarlo es clara, pero el
contrato oficial exige persistirlo. La defensa académica consiste en reconocer
la DF, demostrar su consecuencia formal y justificar la excepción controlada,
no en cambiar `schema.sql` para satisfacer artificialmente una rúbrica.

La [evidencia de cierre de objetivos 3 y 5](../evidencia_cierre_objetivos_3_5.md)
separa esta demostración documental de la ejecución real de consultas.

## Precio histórico frente a precio de catálogo

`producto.precio` representa el precio actual; `detalle_pedido.precio_unitario`
representa el precio histórico de esa línea. No se asume
`producto_id → precio_unitario` dentro de detalle: el mismo producto puede
haberse vendido a precios diferentes en pedidos distintos.

El seed ilustra la intención con Muzzarella: catálogo `1050.00` y una línea
histórica a `1000.00`. Es un ejemplo leído del archivo, no una definición
de DF ni un resultado de ejecución para este bloque. La representación
histórica no equivale a una prohibición automática de modificar precios.

## Síntesis y alcance

| Relación | 1FN | 2FN | 3FN | FNBC |
|---|---|---|---|---|
| usuario | Cumple | Cumple | Cumple | Cumple |
| categoria | Cumple | Cumple | Cumple | Cumple |
| producto | Cumple | Cumple | Cumple | Cumple |
| pedido | Cumple | Cumple | Cumple con las DF internas identificadas | Cumple con las DF internas identificadas |
| detalle_pedido | Cumple | Cumple | No estricta al incluir la regla del subtotal | No estricta al incluir la regla del subtotal |

Subtotal deriva dentro de una fila; total agrega filas de otra relación.
Ambos son físicos y requieren mantenimiento, pero no representan el mismo
tipo de dependencia funcional.

El borrado lógico mediante `eliminado` no retira físicamente las filas.
Bajas posteriores de usuario, producto o categoría no deben destruir la
historia de pedidos. Este análisis no introduce reglas adicionales de
cancelación, reposición de stock o reactivación.

TP1–TP4 se conservan como evidencia histórica de etapas anteriores, sin
afirmar que siempre tuvieron el modelo actual. La columna experimental
`detalle_pedido.categoria_id` de Unidad 4 no integra el esquema canónico:
`VALID_EXPERIMENT` / `REJECTED_AFTER_MEASUREMENT` / `DO_NOT_ADOPT`.
Ese candidato rechazado es distinto de las redundancias físicas exigidas
por el modelo oficial. No se ejecutó PostgreSQL para este análisis.
