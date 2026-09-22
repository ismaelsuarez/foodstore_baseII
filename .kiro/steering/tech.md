# Food Store — Tecnología y contratos de ejecución

## Entorno validado

PostgreSQL **17.11**, x86_64-windows, msvc-19.44.35228, 64-bit. Herramientas:
SQL, PL/pgSQL, `psql`, PowerShell y Git. No hay ORM, backend, frontend ni
framework externo de pruebas. La base TPI `foodstore_tpi_oficial` es descartable.

## Esquema mínimo oficial

La autoridad es [schema.sql](../../schema.sql), no los scripts históricos.

| Tipo / mecanismo | Contrato vigente |
|---|---|
| PK | Las cinco tablas usan `id BIGINT GENERATED ALWAYS AS IDENTITY` |
| Fecha comercial | `pedido.fecha DATE NOT NULL DEFAULT CURRENT_DATE` |
| Marca técnica | `created_at TIMESTAMPTZ NOT NULL DEFAULT now()` en las cinco tablas |
| Importes | `NUMERIC(12,2)` en precio, precio_unitario, subtotal y total |
| Baja lógica | `eliminado BOOLEAN NOT NULL DEFAULT FALSE` en todas las tablas |
| Disponibilidad | `producto.disponible BOOLEAN NOT NULL DEFAULT TRUE`, independiente de la baja |
| FK | Cuatro, NOT NULL, todas con ON DELETE RESTRICT |
| Unicidad | usuario.mail, categoria.nombre y el par pedido/producto del detalle |
| CHECK | Precio y stock no negativos; total no negativo; cantidad positiva; precio_unitario y subtotal no negativos |

ENUM y valores exactos:

- `forma_pago`: EFECTIVO, TARJETA, TRANSFERENCIA; sin default en pedido.
- `rol`: ADMIN, USUARIO; usuario.rol NOT NULL DEFAULT USUARIO.
- `estado_pedido`: PENDIENTE, CONFIRMADO, TERMINADO, CANCELADO;
  pedido.estado NOT NULL DEFAULT PENDIENTE.

Índices base: `idx_producto_categoria`, `idx_pedido_usuario`,
`idx_producto_nombre_vig`. Las PK/UNIQUE generan además sus índices de soporte.
Los candidatos de U3 no forman parte de este mínimo. La columna redundante de
U4 `detalle_pedido.categoria_id` no se incorpora al contrato.

## Capa programable TPI

[objetos_programables.sql](../../tpi/sql/objetos_programables.sql) instala
**7 rutinas y 5 triggers** aparte del DDL base:

| Responsabilidad | Autoridad |
|---|---|
| Subtotal de línea | fn_set_subtotal / trg_subtotal, BEFORE por fila |
| Vigencia de nuevas líneas o reasignaciones | fn_validar_detalle_vigente / trg_detalle_vigente |
| Total de líneas vigentes | calcular_total_pedido, función SQL STABLE, y tres triggers AFTER por sentencia |
| Stock de una venta | registrar_detalle_pedido, procedimiento PL/pgSQL |

Las funciones fn_recalcular_total_insert/update/delete usan transition tables
para recalcular una vez cada pedido afectado por sentencia; UPDATE incluye
pedidos anteriores y nuevos. El cálculo único de total suma subtotal físico,
no vuelve a definir la multiplicación de la línea.

El procedimiento bloquea en orden **pedido FOR UPDATE → usuario FOR SHARE →
producto FOR UPDATE**. La transacción pertenece al caller. No contiene cierre
transaccional propio; detalle, subtotal, total y stock revierten juntos si falla.
DML directo de detalles no ofrece serialización completa del stock ni reposición.

## Reproducción y verificación

Seguir [README TPI](../../tpi/README.md) desde la raíz y detenerse ante cualquier
error. Usar siempre `ON_ERROR_STOP=1`: schema y objetos con `-1`; seed y batería
sin `-1`, porque administran sus propias transacciones. La consulta HAVING es
solo lectura. No publicar credenciales ni ejecutar laboratorios sobre bases
importantes. El seed se instala antes de los objetos programables.

Evidencia real: 29 grupos / 37 variantes / 30 NOTICE PASS, exit code 0 y tres
escenarios concurrentes READ COMMITTED con bloqueo observado. No extrapolar a
SERIALIZABLE, ausencia universal de deadlocks, DML directo concurrente ni estrés.

U3 utiliza índices parciales/de expresión/INCLUDE, cuatro vistas, seguridad y
materializada con índice UNIQUE para REFRESH CONCURRENTLY. U4 mantiene SQL
experimental de sincronización por triggers, **descartado como diseño permanente**.
Sus EXPLAIN, EXCEPT y resultados pertenecen a sus copias y datasets específicos;
no son garantías de rendimiento universal ni migraciones automáticas.
