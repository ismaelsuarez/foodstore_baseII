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

El esquema todavía no impone automáticamente la igualdad del subtotal ni
la conciliación del total. Los CHECK de no negatividad no equivalen a esas
reglas. Se distingue el contrato estructural actual del dominio que debe
mantenerse en la siguiente fase.

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
mediante la futura capa programable: el DEFAULT 0 y `CHECK(total >= 0)`
no realizan la conciliación.

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

Clasificación: **REDUNDANCIA DERIVADA DELIBERADA**.

El subtotal físico es obligatorio en el modelo oficial. No se propone
eliminarlo ni sustituirlo permanentemente por una expresión en consultas.
Requiere mantenimiento automático de cantidad por precio histórico de la
misma fila. La fase posterior deberá implementar un mecanismo equivalente
a `fn_set_subtotal` y su trigger; no se afirma que ya esté instalado o
adaptado en el TPI actual.

El CHECK presente solo garantiza subtotal no negativo. Cambios de cantidad
o precio pueden dejarlo inconsistente si no se mantiene. El
[seed](../../datos_iniciales.sql) calcula sus subtotales explícitamente y
reconcilia sus totales como una fotografía inicial; esa carga no reemplaza
la futura lógica de operaciones posteriores.

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
