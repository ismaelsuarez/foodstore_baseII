# Food Store — Producto y alcance académico

Food Store modela un comercio de comidas para Base de Datos II (UTN). El contrato
vigente está en [schema.sql](../../schema.sql); el proyecto entrega SQL y
Markdown, no una aplicación productiva.

## Dominio vigente

| Entidad | Función |
|---|---|
| `categoria` | Agrupar productos; nombre único y eliminación lógica |
| `usuario` | Identidad, nombre/apellido, mail único, celular, contrasena, rol y eliminación lógica |
| `producto` | Catálogo con precio, stock, categoría, disponibilidad y eliminación lógica separadas |
| `pedido` | Usuario, fecha DATE, estado, forma de pago y total físico |
| `detalle_pedido` | Línea con id propio, cantidad, precio histórico y subtotal físico |

Todas las entidades tienen `eliminado` y `created_at`. El detalle posee PK `id`
y `UNIQUE(pedido_id, producto_id)`. La cantidad expresa las unidades de esa
línea; una baja posterior de una entidad padre no debe destruir historia.
`disponible` es una condición comercial, no sinónimo de eliminación lógica.

El precio de catálogo puede cambiar sin alterar el histórico de una línea.
El subtotal es una redundancia derivada deliberada, mantenida por trigger; el
total agrega subtotales vigentes. La ruta de venta soportada es
`registrar_detalle_pedido`, responsable del descuento de stock. Las escrituras
directas de detalles no administran inventario completo.

## Evolución y decisiones

- **TP1–TP4 / U1–U2:** EVIDENCIA HISTÓRICA EVALUADA sobre una iteración anterior.
  Se preservan, no se reescriben como si siempre hubieran usado el modelo actual.
- **U3:** modelo oficial corregido y validado, commit `da5f3e4`. Tres índices,
  cuatro vistas, seguridad real y materializada con refresh concurrente probado.
- **U4:** FNBC PASS. Candidato de desnormalización implementado y medido:
  mejora temporal real, pero aumento de buffers e incumplimiento de su gate
  predeclarado. Decisión REJECT / DO_NOT_ADOPT.
  `detalle_pedido.categoria_id` no es canónico.
- **TPI:** modelo oficial y 12 objetos (7 rutinas + 5 triggers) validados en
  PostgreSQL 17.11; nueve objetivos documentados con alcance explícito en el
  informe final. Batería 29 grupos / 37 variantes / 30 NOTICE PASS; tres
  escenarios READ COMMITTED PASS y HAVING con Ana y Luis, dos pedidos cada uno.
  TPI-A acredita el RANK canónico `RANK() OVER (ORDER BY gasto_total DESC)`.
  TPI-B acredita SAVEPOINT, REPEATABLE READ y un escenario SERIALIZABLE con
  SQLSTATE 40001; dos ejecuciones completas del arnés PASS. Los cierres A/B
  tienen bases y evidencias separadas de la validación oficial anterior.

El TPI integra principalmente U1–U3; U4 es complementaria. Las cargas de los
laboratorios corregidos son diferentes del seed mínimo. No se instala SQL de
las unidades como una cadena automática de migraciones.

## Evidencia y responsabilidad

Las evidencias [TPI oficial](../../tpi/evidencia_modelo_oficial.md),
[TPI-A](../../tpi/evidencia_cierre_objetivos_3_5.md) y
[TPI-B](../../tpi/evidencia_cierre_objetivo_8.md) registran resultados;
el [informe técnico](../../tpi/informe_tecnico.md) consolida los nueve objetivos
y sus límites. Los [informes U3](../../unidades/unidad-3/informes/informe_mediciones.md) y
[U4](../../unidades/unidad-4/informes/informe_entrega_u4_modelo_canonico.md)
son las fuentes de sus mediciones y decisiones vigentes.

La IA asistió especificación, propuestas, auditoría e implementación según las
DUIA; PostgreSQL ejecutó las pruebas autorizadas. El equipo revisa y decide.
No inventar resultados ni atribuir a un ensayo garantías universales.
SERIALIZABLE sí se probó en un escenario controlado y se observó 40001; ese
conflicto también puede ocurrir bajo REPEATABLE READ. No se acreditan seguridad
de DML directo arbitrario concurrente, ausencia universal de deadlocks ni
rendimiento bajo estrés; tampoco garantías para cualquier intercalado posible.
No se implementan retry automático ni reposición/cancelación automática.
