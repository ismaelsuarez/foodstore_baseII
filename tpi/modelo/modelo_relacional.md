# Modelo Relacional — Food Store

Esta representación deriva directamente de [schema.sql](../../schema.sql):
cinco tablas, 40 columnas, tres ENUM, cuatro FK, seis CHECK y tres índices
explícitos de acceso. No propone cambios al esquema ni instala objetos
programables. Complementa el [modelo ER](modelo_er.md).

## Relaciones

Las mayúsculas son una convención expositiva; los identificadores reales
son minúsculos. PK es clave primaria; UK es UNIQUE; FK es referencia.

```text
CATEGORIA(id PK, nombre UK, descripcion, eliminado, created_at)
USUARIO(id PK, nombre, apellido, mail UK, celular, contrasena, rol, eliminado, created_at)
PRODUCTO(id PK, nombre, precio, descripcion, stock, imagen, disponible,
         categoria_id FK, eliminado, created_at)
PEDIDO(id PK, fecha, estado, total, forma_pago, usuario_id FK, eliminado, created_at)
DETALLE_PEDIDO(id PK, cantidad, precio_unitario, subtotal, pedido_id FK,
               producto_id FK, eliminado, created_at)
UK DETALLE_PEDIDO: (pedido_id, producto_id)
```

Cada entidad tiene PK `id`. Las relaciones 1:N se materializan con una FK
en el lado N. La asociación N:M pedido–producto usa detalle con PK propia
y UK conjunta del par, no con las FK como PK.

## ENUM y defaults

| Tipo ENUM | Valores en el orden declarado | Columna | DEFAULT |
|---|---|---|---|
| `forma_pago` | `EFECTIVO`, `TARJETA`, `TRANSFERENCIA` | `pedido.forma_pago` | Sin DEFAULT |
| `rol` | `ADMIN`, `USUARIO` | `usuario.rol` | `'USUARIO'` |
| `estado_pedido` | `PENDIENTE`, `CONFIRMADO`, `TERMINADO`, `CANCELADO` | `pedido.estado` | `'PENDIENTE'` |

Son tipos, no tablas adicionales ni CHECK. `PENDIENTE` es una decisión de
implementación para pedidos nuevos, no un estado recuperado de datos
históricos. El seed usa expresamente `TERMINADO` como convención para sus
ventas completas.

## Atributos por tabla

`—` en DEFAULT significa que no existe cláusula explícita. Los cinco `id`
usan `GENERATED ALWAYS AS IDENTITY`, generación por identidad, no un DEFAULT
escrito en el DDL. La PK implica NOT NULL.

### CATEGORIA

| Atributo | Tipo exacto | NOT NULL | DEFAULT / generación | PK / FK / UK | Observación |
|---|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK | Identidad propia |
| `nombre` | `VARCHAR(100)` | Sí | — | UK | Clave candidata alternativa |
| `descripcion` | `VARCHAR(255)` | No | — | — | Opcional |
| `eliminado` | `BOOLEAN` | Sí | `FALSE` | — | Baja lógica |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — | Marca temporal técnica |

### USUARIO

| Atributo | Tipo exacto | NOT NULL | DEFAULT / generación | PK / FK / UK | Observación |
|---|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK | Identidad propia |
| `nombre` | `VARCHAR(80)` | Sí | — | — | No es único |
| `apellido` | `VARCHAR(80)` | Sí | — | — | No identifica por sí solo |
| `mail` | `VARCHAR(120)` | Sí | — | UK | No se declara UNIQUE sobre `lower(mail)` |
| `celular` | `VARCHAR(30)` | No | — | — | Opcional, no único |
| `contrasena` | `VARCHAR(255)` | Sí | — | — | No implica autenticación implementada |
| `rol` | `rol` | Sí | `'USUARIO'` | — | ENUM de negocio |
| `eliminado` | `BOOLEAN` | Sí | `FALSE` | — | Baja lógica |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — | Marca temporal técnica |

La vista pública de Unidad 3 omite `contrasena` y `celular`; ambas columnas
siguen perteneciendo a la tabla base.

### PRODUCTO

| Atributo | Tipo exacto | NOT NULL | DEFAULT / generación | PK / FK / UK | Observación |
|---|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK | Identidad propia |
| `nombre` | `VARCHAR(120)` | Sí | — | — | Sin UNIQUE |
| `precio` | `NUMERIC(12,2)` | Sí | — | — | Catálogo actual; CHECK no negativo |
| `descripcion` | `VARCHAR(255)` | No | — | — | Opcional |
| `stock` | `INTEGER` | Sí | `0` | — | CHECK no negativo |
| `imagen` | `VARCHAR(255)` | No | — | — | Opcional |
| `disponible` | `BOOLEAN` | Sí | `TRUE` | — | Condición comercial/operativa |
| `categoria_id` | `BIGINT` | Sí | — | FK → `categoria(id)` | Categoría obligatoria |
| `eliminado` | `BOOLEAN` | Sí | `FALSE` | — | Baja lógica, distinta de disponibilidad |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — | Marca temporal técnica |

### PEDIDO

| Atributo | Tipo exacto | NOT NULL | DEFAULT / generación | PK / FK / UK | Observación |
|---|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK | Identidad propia |
| `fecha` | `DATE` | Sí | `CURRENT_DATE` | — | Fecha comercial sin hora |
| `estado` | `estado_pedido` | Sí | `'PENDIENTE'` | — | ENUM de ciclo de vida |
| `total` | `NUMERIC(12,2)` | Sí | `0` | — | Agregado físico; CHECK no negativo |
| `forma_pago` | `forma_pago` | Sí | — | — | ENUM obligatorio |
| `usuario_id` | `BIGINT` | Sí | — | FK → `usuario(id)` | Usuario obligatorio |
| `eliminado` | `BOOLEAN` | Sí | `FALSE` | — | Baja lógica |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — | Marca temporal técnica distinta de fecha |

### DETALLE_PEDIDO

| Atributo | Tipo exacto | NOT NULL | DEFAULT / generación | PK / FK / UK | Observación |
|---|---|---|---|---|---|
| `id` | `BIGINT` | Sí, por PK | `GENERATED ALWAYS AS IDENTITY` | PK | Identidad de la línea |
| `cantidad` | `INTEGER` | Sí | — | — | CHECK positivo |
| `precio_unitario` | `NUMERIC(12,2)` | Sí | — | — | Histórico; CHECK no negativo |
| `subtotal` | `NUMERIC(12,2)` | Sí | — | — | Derivado físico; CHECK no negativo |
| `pedido_id` | `BIGINT` | Sí | — | FK → `pedido(id)`; parte de UK conjunta | No integra la PK |
| `producto_id` | `BIGINT` | Sí | — | FK → `producto(id)`; parte de UK conjunta | No integra la PK |
| `eliminado` | `BOOLEAN` | Sí | `FALSE` | — | Baja lógica |
| `created_at` | `TIMESTAMPTZ` | Sí | `now()` | — | Marca temporal técnica |

`uq_detalle_pedido_pedido_producto` declara `UNIQUE (pedido_id, producto_id)`.
Ninguna FK es individualmente única. El mismo producto aparece como máximo
una vez por pedido y `cantidad` expresa sus unidades. La unicidad también
se aplica a filas eliminadas lógicamente.

## Claves candidatas

| Tabla | PK elegida | Claves candidatas respaldadas |
|---|---|---|
| `categoria` | `{id}` | `{id}`, `{nombre}` |
| `usuario` | `{id}` | `{id}`, `{mail}` |
| `producto` | `{id}` | `{id}` |
| `pedido` | `{id}` | `{id}` |
| `detalle_pedido` | `{id}` | `{id}`, `{pedido_id, producto_id}` |

UNIQUE más NOT NULL respalda las claves alternativas. Clave candidata no
significa necesariamente clave primaria. No existe unicidad de nombre de
producto ni de combinaciones de usuario, fecha, forma de pago o estado.

## Integridad referencial

Todas las FK son NOT NULL y usan `ON DELETE RESTRICT`.

| Restricción | Columna → referencia |
|---|---|
| `fk_producto_categoria` | `producto.categoria_id` → `categoria(id)` |
| `fk_pedido_usuario` | `pedido.usuario_id` → `usuario(id)` |
| `fk_detalle_pedido_pedido` | `detalle_pedido.pedido_id` → `pedido(id)` |
| `fk_detalle_pedido_producto` | `detalle_pedido.producto_id` → `producto(id)` |

Cada hijo tiene exactamente un padre; un padre puede tener cero o muchos
hijos. La FK no obliga a un pedido a tener detalles. RESTRICT impide borrar
físicamente un padre referenciado; no borra hijos en cascada ni impide por
sí mismo la baja lógica.

## CHECK realmente declarados

| Restricción | Tabla | Expresión |
|---|---|---|
| `chk_producto_precio` | `producto` | `precio >= 0` |
| `chk_producto_stock` | `producto` | `stock >= 0` |
| `chk_pedido_total` | `pedido` | `total >= 0` |
| `chk_detalle_pedido_cantidad` | `detalle_pedido` | `cantidad > 0` |
| `chk_detalle_pedido_precio_unitario` | `detalle_pedido` | `precio_unitario >= 0` |
| `chk_detalle_pedido_subtotal` | `detalle_pedido` | `subtotal >= 0` |

No existe CHECK que imponga `subtotal = cantidad * precio_unitario`.
Tampoco hay mantenimiento automático de `pedido.total` en `schema.sql`.
Estas reglas ya están implementadas en la
[capa programable TPI](../sql/objetos_programables.sql), de instalación separada. El
[seed](../../datos_iniciales.sql) calcula sus subtotales con el precio histórico
y reconcilia sus totales explícitamente; no instala triggers.

## Índices base de acceso

| Índice explícito | Definición de acceso |
|---|---|
| `idx_producto_categoria` | `producto(categoria_id)` |
| `idx_pedido_usuario` | `pedido(usuario_id)` |
| `idx_producto_nombre_vig` | `producto(nombre)` con `WHERE eliminado = FALSE` |

Son índices no únicos, no claves. Los índices que respaldan PK y UNIQUE
no agregan restricciones nuevas. Los candidatos `idx_producto_stock_bajo`,
`idx_pedido_fecha_reciente` e `idx_usuario_mail_lower` pertenecen a Unidad 3,
no al esquema mínimo raíz.

## Historia y límites del modelo

`eliminado` conserva físicamente la fila. Bajas posteriores de usuario,
producto o categoría no deben destruir el historial de pedidos. No se
establecen reglas nuevas de cancelación, reposición de stock o reactivación.

`detalle_pedido.categoria_id` no integra el esquema canónico: el candidato
U4 quedó `VALID_EXPERIMENT` / `REJECTED_AFTER_MEASUREMENT` / `DO_NOT_ADOPT`.
TP1–TP4 son evidencia histórica de etapas anteriores, no se reinterpreta su
estructura como si siempre hubiera sido la actual.

El análisis de DF y redundancias está en [normalización](normalizacion.md).
Esta documentación se verifica estáticamente; no acredita ejecución de PostgreSQL.
