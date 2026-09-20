# Modelo Relacional — Food Store

El pasaje del [modelo ER](modelo_er.md) al modelo relacional conserva las
cinco tablas y restricciones de [schema.sql](../../schema.sql). Esta
documentación no propone nuevas columnas, restricciones ni cambios de DDL.

## Reglas de transformación ER → modelo relacional

| Elemento del ER | Representación relacional en Food Store |
|---|---|
| Entidad fuerte | Tabla: `categoria`, `cliente`, `producto` o `pedido`. |
| Identificador | `PRIMARY KEY`: `id` en esas cuatro tablas. |
| Relación 1:N | FK en el lado N: `producto.categoria_id` y `pedido.cliente_id`. |
| Relación N:M | Tabla intermedia `detalle_pedido`, con FK hacia ambos participantes y PK compuesta. |
| Atributos de la relación N:M | Columnas `cantidad` y `precio_unitario` de `detalle_pedido`. |

## Relaciones y dominios

Las mayúsculas de la notación siguiente son una convención expositiva; los
nombres reales son los identificadores en minúscula de `schema.sql`.
`UK` representa `UNIQUE`. En `DETALLE_PEDIDO`, las dos marcas `PK/FK`
integran conjuntamente la PK `(pedido_id, producto_id)`.

```text
CATEGORIA(id PK, nombre UK, activo, created_at)

CLIENTE(id PK, nombre, email UK, telefono, created_at)

PRODUCTO(
    id PK,
    categoria_id FK -> CATEGORIA(id),
    nombre, descripcion, precio, stock, activo, created_at
)

PEDIDO(
    id PK,
    cliente_id FK -> CLIENTE(id),
    fecha, forma_pago
)

DETALLE_PEDIDO(
    pedido_id PK/FK -> PEDIDO(id),
    producto_id PK/FK -> PRODUCTO(id),
    cantidad, precio_unitario
)
```

En las tablas siguientes, `—` significa que no hay `DEFAULT` explícito.
Los cuatro `id` se declaran `GENERATED ALWAYS AS IDENTITY`: es generación
por identidad, no una cláusula `DEFAULT` escrita en el esquema. La PK
implica `NOT NULL`, aunque esa expresión no se repita en su declaración.

### CATEGORIA

| Atributo | Tipo real | NOT NULL | DEFAULT / generación | Clave |
|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK |
| `nombre` | `VARCHAR(100)` | Sí | — | UNIQUE |
| `activo` | `BOOLEAN` | Sí | `TRUE` | — |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — |

Representa la categoría, lado 1 de `categoria` → `producto`. No declara
FK ni `CHECK` propios.

### CLIENTE

| Atributo | Tipo real | NOT NULL | DEFAULT / generación | Clave |
|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK |
| `nombre` | `VARCHAR(120)` | Sí | — | — |
| `email` | `VARCHAR(255)` | Sí | — | UNIQUE |
| `telefono` | `VARCHAR(30)` | No | — | — |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — |

Representa al cliente, lado 1 de `cliente` → `pedido`. No declara FK ni
`CHECK` propios; el esquema no impone unicidad al nombre o al teléfono.

### PRODUCTO

| Atributo | Tipo real | NOT NULL | DEFAULT / generación | Clave |
|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK |
| `categoria_id` | `BIGINT` | Sí | — | FK → `categoria(id)` |
| `nombre` | `VARCHAR(120)` | Sí | — | — |
| `descripcion` | `VARCHAR(255)` | No | — | — |
| `precio` | `NUMERIC(12,2)` | Sí | — | — |
| `stock` | `INTEGER` | Sí | `0` | — |
| `activo` | `BOOLEAN` | Sí | `TRUE` | — |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — |

Representa al producto, lado N de `categoria` → `producto` y lado 1 de
`producto` → `detalle_pedido`. Su nombre no tiene `UNIQUE`.

### PEDIDO

| Atributo | Tipo real | NOT NULL | DEFAULT / generación | Clave |
|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK |
| `cliente_id` | `BIGINT` | Sí | — | FK → `cliente(id)` |
| `fecha` | `TIMESTAMPTZ` | Sí | `now()` | — |
| `forma_pago` | `forma_pago` | Sí | — | — |

Representa al pedido, lado N de `cliente` → `pedido` y lado 1 de
`pedido` → `detalle_pedido`. El tipo `forma_pago` es el `ENUM` con valores
`EFECTIVO`, `TARJETA` y `TRANSFERENCIA`; no es una tabla adicional ni un
`CHECK`. No hay `UNIQUE` sobre combinaciones de cliente, fecha y pago.

### DETALLE_PEDIDO

| Atributo | Tipo real | NOT NULL | DEFAULT / generación | Clave |
|---|---|---|---|---|
| `pedido_id` | `BIGINT` | Sí | — | Parte de PK; FK → `pedido(id)` |
| `producto_id` | `BIGINT` | Sí | — | Parte de PK; FK → `producto(id)` |
| `cantidad` | `INTEGER` | Sí | — | — |
| `precio_unitario` | `NUMERIC(12,2)` | Sí | — | — |

Es el lado N de las relaciones con `pedido` y `producto`. La restricción
`pk_detalle_pedido` declara `PRIMARY KEY (pedido_id, producto_id)`; no
existe una columna `id` adicional ni generación por identidad.

## Integridad referencial y restricciones de dominio

Todas las FK tienen `ON DELETE RESTRICT`: no se puede borrar un padre
referenciado por filas hijas. No implican borrado automático de esas filas.

| Restricción | Columna → referencia |
|---|---|
| `fk_producto_categoria` | `producto.categoria_id` → `categoria(id)` |
| `fk_pedido_cliente` | `pedido.cliente_id` → `cliente(id)` |
| `fk_detalle_pedido_pedido` | `detalle_pedido.pedido_id` → `pedido(id)` |
| `fk_detalle_pedido_producto` | `detalle_pedido.producto_id` → `producto(id)` |

| CHECK declarado | Expresión |
|---|---|
| `chk_producto_precio` | `precio >= 0` |
| `chk_producto_stock` | `stock >= 0` |
| `chk_detalle_pedido_cantidad` | `cantidad > 0` |
| `chk_detalle_pedido_precio_unitario` | `precio_unitario >= 0` |

Los únicos `UNIQUE` declarados además de las PK son `categoria.nombre` y
`cliente.email`, ambos `NOT NULL`. Los índices `idx_pedido_cliente` sobre
`pedido(cliente_id)` e `idx_producto_categoria` sobre `producto(categoria_id)`
son de acceso, no restricciones adicionales de unicidad.

## Resolución de PEDIDO ↔ PRODUCTO (N:M)

Un pedido admite varios productos y un producto puede estar en distintos
pedidos. `DETALLE_PEDIDO` convierte esa asociación N:M en dos relaciones
1:N mediante sus FK; cada fila representa una pareja pedido/producto.

La PK compuesta `(pedido_id, producto_id)` garantiza que el mismo producto
aparezca como máximo una vez como línea dentro del mismo pedido. Ninguna FK
aislada es única: imponerlo impediría pedidos con varios productos o ventas
del mismo producto en distintos pedidos. No se agrega un identificador
sustituto (*surrogate*).

`cantidad` y `precio_unitario` son atributos propios de la asociación:
expresan las unidades y el precio registrado para esa línea de venta.
El precio actual está en `producto.precio`; la diferencia histórica y sus
dependencias se justifican en [normalización](normalizacion.md).
