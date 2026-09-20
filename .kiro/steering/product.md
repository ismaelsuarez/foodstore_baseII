# Food Store

Food Store es un proyecto relacional académico de PostgreSQL (UTN —
Base de Datos II). Modela el flujo básico de comercio de un local de
comidas: catálogo de productos organizado por categorías, gestión de
clientes, y procesamiento de pedidos con su detalle ítem por ítem.

## Flujo de comercio base

- **Categorías** — agrupaciones de productos (por ejemplo, Pizzas,
  Bebidas).
- **Productos** — artículos a la venta, con precio, stock y categoría.
- **Clientes** — identificados por email.
- **Pedidos** — vinculados a un cliente, con una forma de pago.
- **Detalle de pedido** — líneas que componen cada pedido (cantidad y
  precio unitario al momento de la venta).

Esto sigue siendo, en `schema.sql` y `datos_iniciales.sql`, la base
canónica del proyecto.

## Evolución pedagógica del proyecto

A partir de esa base, el proyecto avanzó a través de distintas
unidades/TP de la materia, cada una agregando una capa de trabajo
académico sin modificar el modelo de comercio base salvo cuando la
propia unidad lo requirió explícitamente:

- **Integridad y concurrencia** (Unidad 1): restricciones adicionales
  sobre `detalle_pedido`, escenarios de concurrencia entre
  transacciones, y lectura crítica de scripts potencialmente
  peligrosos, bajo un protocolo de seguridad documentado.
- **Consultas y optimización** (Unidad 2, TP3 y TP4): generación de
  volumen de datos de laboratorio, consultas analíticas con JOIN y
  agregación, variantes de consulta para comparación, y lectura de
  planes reales (`EXPLAIN ANALYZE`) para justificar decisiones de
  optimización.
- **Índices, vistas y vistas materializadas** (Unidad 3): diseño de
  índices B-tree (simples, compuestos, parciales, de expresión),
  vistas convencionales para encapsular reglas de negocio y aplicar
  minimización de datos, y una vista materializada para un reporte
  analítico costoso — todo medido con `EXPLAIN (ANALYZE, BUFFERS)` y
  verificado con `EXCEPT` bidireccional.
- **Normalización avanzada** (Unidad 4): demostración de una violación
  de la Forma Normal de Boyce-Codd (FNBC) sobre una relación académica,
  su descomposición sin pérdida, y — como contraste deliberado — una
  desnormalización controlada (columna redundante mantenida por
  triggers) para acelerar un reporte, con su costo y sus riesgos
  documentados explícitamente.

## Medición y revisión asistida por IA

A lo largo de estas unidades se usaron distintas herramientas de IA
(documentadas caso por caso en cada Declaración de Uso de IA — DUIA)
para proponer especificaciones, generar SQL candidato y ayudar a
redactar informes.

Ninguna decisión final quedó delegada a la IA sin revisión humana.
Cuando correspondió al tipo de ejercicio, las propuestas fueron ejecutadas
y verificadas realmente sobre PostgreSQL mediante técnicas como
`EXPLAIN (ANALYZE, BUFFERS)`, `EXCEPT` bidireccional, transacciones y
consultas de auditoría antes de aceptar las conclusiones. Las propuestas
descartadas también se conservaron cuando formaban parte de la evidencia
académica.

Este es un proyecto académico/educativo, no un producto comercial: el
foco es demostrar comprensión de integridad, concurrencia,
optimización, indexado y normalización sobre una base de datos real,
no construir una aplicación de e-commerce funcional.
