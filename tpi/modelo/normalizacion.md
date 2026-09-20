# Normalización del Modelo Base — Food Store

Las cinco relaciones del modelo base satisfacen 1FN, 2FN, 3FN y FNBC
respecto de las dependencias funcionales documentadas a continuación.
El análisis se limita a [schema.sql](../../schema.sql), su estructura,
claves y `UNIQUE`, y a la semántica explícita del
[README raíz](../../README.md). No afirma que no puedan existir otras
reglas de negocio no documentadas.

## Criterio de análisis

Una dependencia funcional (DF) `X → Y` significa que un valor de `X`
determina un único valor de `Y` dentro de la relación. Una clave candidata
es una superclave mínima. Un atributo primo pertenece a alguna clave
candidata; uno no primo no pertenece a ninguna, aunque sea una FK.

- **1FN:** atributos con valores escalares, sin grupos repetitivos.
- **2FN:** 1FN y ningún atributo no primo depende de una parte propia de
  una clave candidata compuesta.
- **3FN:** para cada DF no trivial `X → A`, `X` es superclave o `A` es primo.
- **FNBC / BCNF:** en cada DF no trivial el determinante es superclave.

Se estudian las DF de cada relación, no las de una combinación de tablas.
Las FK expresan referencias, no unicidad del lado hijo. Ni los `DEFAULT`
ni coincidencias accidentales del dataset establecen nuevas DF. Los campos
opcionales `telefono` y `descripcion` admiten `NULL`; esto no los convierte
en listas ni en claves candidatas.

## 1. categoria

Relación: `categoria(id, nombre, activo, created_at)`.

- **Claves candidatas:** `{id}` por PK y `{nombre}` por `UNIQUE NOT NULL`.
- **Atributos primos:** `id`, `nombre`.
- **Atributos no primos:** `activo`, `created_at`.
- **DF:** `id → nombre, activo, created_at` y
  `nombre → id, activo, created_at`.

| Forma normal | Justificación |
|---|---|
| 1FN | Cada fila tiene atributos escalares y no contiene grupos repetitivos de productos. |
| 2FN | Ambas claves candidatas son simples: no tienen componentes propios no vacíos que originen dependencias parciales. |
| 3FN | Los determinantes de las DF identificadas son claves candidatas; no se documentan dependencias transitivas entre atributos no primos. |
| FNBC | Tanto `id` como `nombre` determinan la relación completa y son superclaves. |

## 2. cliente

Relación: `cliente(id, nombre, email, telefono, created_at)`.

- **Claves candidatas:** `{id}` por PK y `{email}` por `UNIQUE NOT NULL`.
- **Atributos primos:** `id`, `email`.
- **Atributos no primos:** `nombre`, `telefono`, `created_at`.
- **DF:** `id → nombre, email, telefono, created_at` y
  `email → id, nombre, telefono, created_at`.

| Forma normal | Justificación |
|---|---|
| 1FN | Nombre, correo, teléfono y fecha son atributos escalares; no se almacena un grupo repetitivo de pedidos. |
| 2FN | Las dos claves candidatas son simples; no presentan dependencias parciales. |
| 3FN | Cada determinante identificado es una clave candidata; no se respalda una DF entre los atributos no primos. |
| FNBC | `id` y `email` son superclaves y determinan todos los atributos. |

No se supone que `nombre` o `telefono` identifiquen al cliente: no tienen
`UNIQUE` ni una regla de negocio documentada que permita afirmarlo.

## 3. producto

Relación: `producto(id, categoria_id, nombre, descripcion, precio, stock, activo, created_at)`.

- **Clave candidata respaldada:** `{id}` por PK.
- **Atributo primo:** `id`.
- **Atributos no primos:** `categoria_id`, `nombre`, `descripcion`,
  `precio`, `stock`, `activo`, `created_at`.
- **DF:** `id → categoria_id, nombre, descripcion, precio, stock, activo, created_at`.

| Forma normal | Justificación |
|---|---|
| 1FN | Todos los atributos son escalares; se referencia una categoría, no una colección almacenada en una celda. |
| 2FN | La clave candidata documentada es simple; no hay dependencia parcial respecto de ella. |
| 3FN | `id` es superclave y no se documentan dependencias entre atributos no primos; los atributos propios de la categoría están en otra relación. |
| FNBC | El determinante de la DF identificada es la clave candidata `id`. |

`producto.nombre` no tiene `UNIQUE`, por lo que no se lo considera clave
candidata. `categoria_id` es una FK y puede repetirse; tampoco es clave del
producto. No se infiere que la categoría determine su precio o stock.

## 4. pedido

Relación: `pedido(id, cliente_id, fecha, forma_pago)`.

- **Clave candidata respaldada:** `{id}` por PK.
- **Atributo primo:** `id`.
- **Atributos no primos:** `cliente_id`, `fecha`, `forma_pago`.
- **DF:** `id → cliente_id, fecha, forma_pago`.

| Forma normal | Justificación |
|---|---|
| 1FN | Cliente, fecha y forma de pago son valores escalares; las líneas se representan por separado. |
| 2FN | La clave candidata es simple y no admite dependencias parciales respecto de sus componentes. |
| 3FN | El determinante identificado es superclave; no se documenta una DF entre cliente, fecha y forma de pago. |
| FNBC | `id` determina todos los atributos y es clave candidata. |

No se supone que un cliente tenga una única fecha o forma de pago.
La combinación `(cliente_id, fecha, forma_pago)` tampoco es una clave
candidata respaldada por el esquema.

## 5. detalle_pedido

Relación: `detalle_pedido(pedido_id, producto_id, cantidad, precio_unitario)`.

- **Clave candidata documentada:** `{pedido_id, producto_id}`, por la PK.
- **Atributos primos:** `pedido_id`, `producto_id`.
- **Atributos no primos:** `cantidad`, `precio_unitario`.
- **DF principal:** `(pedido_id, producto_id) → cantidad, precio_unitario`.

Un pedido admite varios productos, con cantidades y precios distintos;
por tanto, `pedido_id` solo no determina `cantidad` ni `precio_unitario`.
Un producto puede venderse en pedidos distintos con cantidades y precios
distintos; por tanto, `producto_id` solo tampoco los determina.

Ambos atributos no primos describen la línea identificada por la pareja
completa. No existe una dependencia parcial documentada sobre un componente
aislado de la clave compuesta. Ninguno de esos componentes es por sí solo
clave candidata de la relación.

| Forma normal | Justificación |
|---|---|
| 1FN | Cada fila representa una pareja pedido/producto con cantidad y precio escalares; no hay listas de productos dentro de una fila. |
| 2FN | `cantidad` y `precio_unitario` dependen de la clave completa, no de un componente aislado. |
| 3FN | La pareja es superclave y no se documenta una DF entre `cantidad` y `precio_unitario` ni otra dependencia transitiva problemática. |
| FNBC | El determinante no trivial identificado es la clave candidata completa `(pedido_id, producto_id)`. |

## Precio histórico frente a precio actual

`producto.precio` es el precio actual del producto.
`detalle_pedido.precio_unitario` es el precio registrado para esa línea al
momento de la venta, como explicita el [README raíz](../../README.md).
Son hechos distintos: el precio de catálogo puede cambiar entre ventas.

[datos_iniciales.sql](../../datos_iniciales.sql) ilustra esta semántica:
Muzzarella tiene precio actual `1050.00`, una línea de venta a `1000.00`
y otras a `1050.00`. Estos valores se leen del archivo; no son resultados
de una ejecución realizada para este documento.

Por eso no se asume `producto_id → precio_unitario` en `detalle_pedido` ni
se califica ese atributo como redundancia incorrecta. Permite preservar el
importe histórico aunque cambie `producto.precio`. El esquema no obliga a
sincronizar ambos precios ni impide modificar manualmente el precio de una
línea: representación histórica no equivale a inmutabilidad automática.

## Conclusión y alcance

Respecto de las DF documentadas, todas las relaciones cumplen 1FN, 2FN,
3FN y FNBC. Los determinantes no triviales identificados son claves
candidatas; sus ampliaciones son superclaves. No se identifica una DF con
determinante que no sea superclave que obligue a descomponer estas tablas.

La conclusión no reemplaza el relevamiento de futuras reglas de negocio.
Si aparecen nuevas DF justificadas, deberá revisarse el análisis: no se
deduce su inexistencia de una muestra de datos ni del uso de una PK simple.

Como material complementario, la
[spec de FNBC de Unidad 4](../../unidades/unidad-4/specs/u4_fnbc_control_lote.md)
estudia una violación de FNBC en `control_lote_almacen`, con reglas propias.
Es un caso separado de laboratorio y no se utiliza para justificar la
normalización del modelo base analizado aquí.
