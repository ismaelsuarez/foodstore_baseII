# Informe Técnico — TPI Food Store — Primera Entrega

## 1. Introducción

La entrega integra el trabajo de Avalos Pablo, Blangetti Sofia y Suarez
Ismael. El [README del TPI](README.md) ofrece el mapa de los nueve objetivos
y la reproducción mínima. Este informe explica qué se implementó, cómo se
verificó y qué evidencia respalda cada conclusión, sin copiar los informes
históricos completos.

## 2. Alcance de la primera entrega

El alcance principal comprende las Unidades 1, 2 y 3. Unidad 4 es trabajo
posterior/complementario: no se utiliza para cubrir faltantes de esta entrega.
El motor requerido es PostgreSQL 16+; el repositorio histórico documenta
PostgreSQL 17, pero no se atribuye una versión exacta a las verificaciones
TPI sin un registro específico.

| Aporte | Implementación y evidencia reutilizada |
|---|---|
| Unidad 1 / TP2 | Restricciones de integridad, experimentos multisesión y protocolo de seguridad: [README](../unidades/unidad-1/tp2/README.md), [spec](../unidades/unidad-1/tp2/specs/spec_restricciones.md), [SQL histórico](../unidades/unidad-1/tp2/sql/restricciones_integridad.sql). |
| Unidad 2 / TP3 | Carga de laboratorio, agregaciones, subconsultas y optimización: [README](../unidades/unidad-2/tp3/README.md), [informe de consultas](../unidades/unidad-2/tp3/informes/informe_consultas_tp3.md), [informe de optimización](../unidades/unidad-2/tp3/informes/informe_optimizacion_tp3.md). |
| Unidad 2 / TP4 | JOIN analíticos, ranking y comparación de alternativas: [README](../unidades/unidad-2/tp4/README.md), [informe de consultas](../unidades/unidad-2/tp4/informes/informe_consultas_tp4.md), [optimización de JOIN](../unidades/unidad-2/tp4/informes/informe_optimizacion_joins_tp4.md). |
| Unidad 3 | Índices, tres vistas, una vista materializada y mediciones: [README](../unidades/unidad-3/README.md), [specs](../unidades/unidad-3/specs/), [informe de mediciones](../unidades/unidad-3/informes/informe_mediciones.md). |
| Integración TPI | Modelado y normalización explícitos, consulta HAVING, función/trigger, procedimiento, batería transaccional y documentación navegable. |

## 3. Modelo de datos

El [modelo ER](modelo/modelo_er.md) representa exclusivamente `categoria`,
`cliente`, `producto`, `pedido` y `detalle_pedido`, con todos sus atributos,
claves, cardinalidades y participación. Cada producto referencia una
categoría y cada pedido un cliente: relaciones 1:N con FK obligatoria en
el lado N. Una categoría puede carecer de productos y un cliente de pedidos.

La relación conceptual `pedido N:M producto` se transforma en dos relaciones
1:N mediante `detalle_pedido`. Su PK `(pedido_id, producto_id)` admite como
máximo una línea por pareja; `cantidad` y `precio_unitario` describen esa
asociación. No existe un identificador sustituto para el detalle. El
[modelo relacional](modelo/modelo_relacional.md) documenta la transformación,
dominios y restricciones reales; un pedido puede existir sin detalles.

## 4. Normalización

El [análisis de normalización](modelo/normalizacion.md) justifica 1FN, 2FN,
3FN y FNBC/BCNF para las cinco relaciones respecto de las DF documentadas,
respaldadas por claves, `UNIQUE`, estructura y semántica explícita.
`categoria` tiene claves candidatas `id` y `nombre`; `cliente`, `id` y
`email`; `producto` y `pedido`, `id`; el detalle, la pareja completa.
No se infieren reglas de negocio desconocidas ni unicidad de `producto.nombre`.

En el detalle, `(pedido_id, producto_id) → cantidad, precio_unitario`:
ningún componente aislado determina esos atributos. `producto.precio` es
el precio actual; `detalle_pedido.precio_unitario` conserva el precio de
la línea al venderse. No se presupone `producto_id → precio_unitario` ni
se considera ese dato histórico una redundancia incorrecta. Su representación
no implica una prohibición general de editar manualmente líneas históricas.

## 5. Implementación SQL

[schema.sql](../schema.sql) es el DDL canónico: tipo `forma_pago`, cinco
tablas, identidades, PK, FK, `UNIQUE`, `CHECK` e índices de acceso.
[datos_iniciales.sql](../datos_iniciales.sql) es la carga DML inicial.
Ambos permanecen sin cambios por la integración.

Los objetos nuevos se instalan explícitamente desde
[objetos_programables.sql](sql/objetos_programables.sql), sobre la fundación
canónica y dentro de una transacción externa. No se crean tablas ni columnas.
El DOWN documentado elimina primero trigger, luego función y procedimiento;
no se ejecuta automáticamente ni revierte ventas previamente confirmadas.
El SQL histórico de restricciones de TP2 no se reaplica: sus restricciones
ya están en el esquema actual. Los demás laboratorios tampoco son una
cadena de migraciones pendientes.

## 6. Consultas y análisis

| Capacidad | Evidencia y criterio |
|---|---|
| JOIN, COUNT, AVG y GROUP BY | Consulta A de [TP3](../unidades/unidad-2/tp3/sql/consultas_tp3_ia.sql): preserva categorías sin productos activos mediante `LEFT JOIN` y filtro de producto en `ON`. |
| Subconsulta correlacionada | Consulta B de [TP3](../unidades/unidad-2/tp3/sql/consultas_tp3_ia.sql): compara el precio con el promedio de su categoría. [Spec](../unidades/unidad-2/tp3/specs/spec_consultas_tp3.md). |
| SUM y función de ventana | Consulta A de [TP4](../unidades/unidad-2/tp4/sql/consultas_tp4_ia.sql): `RANK() OVER` sobre gasto total, conservando puestos compartidos ante empates. [Spec](../unidades/unidad-2/tp4/specs/spec_consultas_tp4.md). |
| HAVING explícito | [Consulta TPI](sql/consultas_cobertura_tpi.sql): `cliente JOIN pedido`, `COUNT(p.id)`, `GROUP BY` y `HAVING COUNT(p.id) > 1`. |

`HAVING` filtra después de agregar; `WHERE` no puede sustituir ese filtro
sobre `COUNT` en el mismo nivel. El umbral es una condición del ejercicio,
no un resultado anticipado. No se agregó `ROW_NUMBER()` artificialmente:
`RANK()` ya cubre ventanas y respeta los empates requeridos.

Los informes de consultas de TP3 y TP4 documentan equivalencia mediante
`EXCEPT` bidireccional: completa para sus consultas A y limitada a una
muestra determinista de 100 productos exteriores para sus consultas B,
manteniendo el promedio sobre todos los productos activos de la categoría.
No se presenta esa muestra como una comprobación exhaustiva.

## 7. Vistas y objetos programables

Las definiciones verificadas de [Unidad 3](../unidades/unidad-3/sql/views.sql)
son `v_productos_vigentes` (catálogo con producto y categoría activos),
`v_pedidos_cliente` (datos mínimos del cliente, sin teléfono ni fecha de
creación) y `v_detalle_pedido_producto` (historial y subtotal calculado como
`cantidad * precio_unitario`, no una columna física del detalle).

[mv_facturacion_categoria_mes](../unidades/unidad-3/sql/materializadas.sql)
almacena el agregado por categoría y mes. Su índice único sobre
`(categoria_id, mes)` prepara `REFRESH CONCURRENTLY`, pero el
[README U3](../unidades/unidad-3/README.md) aclara que ese refresh no se
ejecutó en el TP. La política propuesta de 60 minutos admite atraso;
no equivale a una actualización automática ni a información en tiempo real.

Los [objetos específicos del TPI](sql/objetos_programables.sql) separan:

- `fn_validar_producto_activo_detalle()` y `trg_detalle_producto_activo`:
  validan actividad con `FOR SHARE` antes de `INSERT` o `UPDATE OF producto_id`,
  también por rutas directas. Si el producto no existe, la función devuelve
  `NEW` y deja que la FK rechace la referencia. No administran inventario.
- `registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)`: valida parámetros y
  existencia del pedido; lee precio, stock y actividad con `FOR UPDATE`;
  rechaza inactividad, stock insuficiente o pareja duplicada; inserta el
  precio leído como dato histórico y luego descuenta stock. Se invoca con
  `CALL` en las [pruebas](pruebas/pruebas_objetos_programables.sql).

El INSERT del procedimiento también dispara el trigger: ambas validaciones
de actividad son intencionales y protegen rutas distintas. El trigger no
valida `categoria.activo`, regla de catálogo que no se estableció como
condición de venta. `UPDATE OF producto_id` puede activarse incluso si el
valor asignado coincide con el anterior.

## 8. Integridad y reglas de negocio

Las capas se complementan; el procedimiento no reemplaza los constraints.

| Capa | Definición real / responsabilidad |
|---|---|
| PK | `id` en cuatro tablas; `pk_detalle_pedido` sobre `(pedido_id, producto_id)`, garantía definitiva frente a duplicados. |
| FK | `fk_producto_categoria`, `fk_pedido_cliente`, `fk_detalle_pedido_pedido` y `fk_detalle_pedido_producto`, todas con `ON DELETE RESTRICT`. |
| UNIQUE | `categoria.nombre` y `cliente.email`, ambos `NOT NULL`; no se supone unicidad de nombres de producto. |
| CHECK | `chk_producto_precio`: `precio >= 0`; `chk_producto_stock`: `stock >= 0`; `chk_detalle_pedido_cantidad`: `cantidad > 0`; `chk_detalle_pedido_precio_unitario`: `precio_unitario >= 0`. |
| Trigger | Impide insertar o reasignar una línea hacia un producto existente inactivo. |
| Procedimiento | Ofrece la ruta controlada de registro y descuento de stock con errores explícitos. |

Fuente de constraints: [schema.sql](../schema.sql). Los SQLSTATE productivos
son `22023` (parámetros), `23503` (referencia), `23505` (duplicado) y
`23514` (regla de actividad o stock); los mensajes distinguen cada motivo.

## 9. Transacciones, atomicidad y concurrencia

**Evidencia histórica:** el [informe de concurrencia U1](../unidades/unidad-1/tp2/informes/informe_concurrencia.md)
documenta lecturas no repetibles y fantasmas bajo `READ COMMITTED`, su
estabilidad bajo `REPEATABLE READ` y espera entre dos sesiones con
`SELECT ... FOR UPDATE`, liberada al confirmar. Incluye `COMMIT` y
`ROLLBACK`. `SERIALIZABLE` se analiza conceptualmente; no se presenta aquí
como un experimento ejecutado. El [protocolo de seguridad](../unidades/unidad-1/tp2/informes/protocolo_seguridad.md)
registra además carga reversible y posterior confirmación.

**Evidencia TPI:** el INSERT de detalle y el UPDATE de stock pertenecen a la
misma transacción llamante, sin `COMMIT` ni `ROLLBACK` internos. El caso I
verifica ambos cambios, provoca después `P0099` y comprueba que el bloque
con `EXCEPTION` revirtió detalle y stock juntos. El rollback general limpia
el resto de los datos de prueba.

Por diseño, `FOR UPDATE` mantiene bloqueada la fila del producto para
evitar descuentos simultáneos basados en el mismo stock previo; `FOR SHARE`
coordina la validación del trigger con actualizaciones del producto.
La batería de una sesión demuestra atomicidad e integridad, **no una
ejecución multisesión de dos CALL**; no reemplaza los experimentos de U1.

## 10. Baja lógica e índices

`categoria.activo` y `producto.activo` permiten marcar baja lógica sin
borrar la fila ni romper referencias históricas. El borrado físico es una
operación diferente, restringida por las FK si existen filas dependientes.

El catálogo y las consultas de vigencia filtran actividad; la vista histórica
del detalle no lo hace. La materializada conserva los filtros de producto
y categoría activos del reporte original: no debe confundirse con un
reporte histórico sin filtros, y refleja cambios solo después de refrescarse.

[idx_producto_stock_bajo](../unidades/unidad-3/sql/indices.sql) usa claves
`(stock ASC, nombre ASC)`, `INCLUDE (id, precio)` y predicado parcial
`WHERE activo = TRUE`. El umbral `stock <= 5` pertenece a la consulta,
no al predicado del índice. La baja modifica la pertenencia lógica al índice.
En la medición histórica todos los productos estaban activos: el predicado
no reducía entonces la cantidad de entradas; no se atribuye la mejora a
una exclusión de inactivos que no existían en ese dataset.

## 11. Optimización de consultas

Promedios estables transcritos del [informe de mediciones U3](../unidades/unidad-3/informes/informe_mediciones.md):
tres ejecuciones con `EXPLAIN (ANALYZE, BUFFERS)`, descartando calentamiento
y promediando las dos restantes, sobre `foodstore_tp5` con carga masiva de
TP3. No son mediciones de `foodstore_tpi` ni predicciones para otro entorno.

| Caso | Antes | Después | Evidencia |
|---|---|---|---|
| Stock bajo | 10.030 ms; Seq Scan + Sort | 0.2675 ms; Index Only Scan, sin Sort | [U3, sección 3](../unidades/unidad-3/informes/informe_mediciones.md) |
| Pedidos por fecha | 12.8805 ms; Seq Scan + Sort | 0.313 ms; Index Only Scan, sin Sort | [U3, sección 4](../unidades/unidad-3/informes/informe_mediciones.md) |
| Email normalizado con `lower(email)` | 10.272 ms; Seq Scan | 0.1075 ms; Index Scan de expresión | [U3, sección 5](../unidades/unidad-3/informes/informe_mediciones.md) |
| Facturación por categoría/mes | 1131.224 ms; JOIN y agregación originales | 0.060 ms; lectura de la vista materializada | [U3, sección 12](../unidades/unidad-3/informes/informe_mediciones.md) |

Las [consultas de referencia](../unidades/unidad-3/sql/queries.sql) y el
informe conservan planes y buffers. Las tres vistas convencionales y la
materializada obtuvieron cero diferencias en ambos sentidos mediante
`EXCEPT`; las vistas convencionales encapsulan criterios, no se presentan
como mejoras de rendimiento por sí mismas. La materializada reduce lectura
a cambio de almacenamiento y actualización diferida. Se descartó un índice
cubridor de email por sobreindexación; tampoco se atribuye causalmente a
los índices la diferencia favorable del benchmark de escritura.

## 12. Pruebas y resultados

**Procedencia:** los siguientes resultados TPI fueron comunicados
expresamente por el equipo para esta entrega. Las ejecuciones se realizaron
externamente mediante `psql` y se revisaron antes de versionar los archivos;
no fueron ejecutadas por Codex ni repetidas durante esta documentación.

| Etapa | Resultado real informado |
|---|---|
| [HAVING](sql/consultas_cobertura_tpi.sql), con `ON_ERROR_STOP=1` | Ana Gómez: 2 pedidos; Luis Paz: 2 pedidos. |
| Instalación de ensayo | `BEGIN`, `CREATE FUNCTION`, `CREATE TRIGGER`, `CREATE PROCEDURE`, `ROLLBACK`; verificación posterior: 0 objetos TPI persistidos. |
| Instalación posterior real | Función y procedimiento instalados en `foodstore_tpi`; trigger instalado y habilitado. |
| [Batería TPI](pruebas/pruebas_objetos_programables.sql) | 13 grupos / 15 variantes; todos los `PASS` alcanzados, incluido el de batería completa. |
| Limpieza | `ROLLBACK` final ejecutado; categoría de prueba restante = 0 y cliente de prueba restante = 0. |
| Objetos después del rollback | Función instalada = TRUE; procedimiento instalado = TRUE; trigger instalado y habilitado = TRUE. |

La batería crea datos propios con IDs obtenidos por `RETURNING`, valida
los objetos antes de comenzar y verifica: CALL válido; cantidades cero,
negativa y NULL; stock insuficiente; inactividad por procedimiento e INSERT
directo; duplicados por procedimiento y PK directa; UPDATE a inactivo;
pedido/producto inexistentes y FK directa; precio histórico; atomicidad.
Captura únicamente errores esperados, sin `WHEN OTHERS`; en PK/FK directas
comprueba además el nombre del constraint. Los errores inesperados se propagan.
El rollback no elimina los objetos previamente instalados ni garantiza
retroceder secuencias: los huecos de identidad son normales.

## 13. Uso de Inteligencia Artificial

En esta integración, según la trazabilidad comunicada por el equipo:

| Herramienta | Finalidad |
|---|---|
| Claude | Auditoría del repositorio y revisión de cobertura. |
| Codex | Generación controlada de artefactos, revisión estática de SQL y documentación. |
| ChatGPT | Análisis, revisión y coordinación de la secuencia de implementación y pruebas. |

La generación/propuesta y la auditoría no equivalen a ejecución ni aceptación.
Las decisiones fueron revisadas por el equipo; la validación final y las
ejecuciones SQL relevantes mediante `psql` permanecieron bajo control humano.

La evidencia histórica también respalda Kiro para especificación y OpenCode
para generación, junto con revisiones de ChatGPT donde cada DUIA lo indica.
Se conservan sin reescribir: U1 [parte 1](../unidades/unidad-1/tp2/duia/duia_parte1.md),
[parte 2](../unidades/unidad-1/tp2/duia/duia_parte2.md) y
[parte 3](../unidades/unidad-1/tp2/duia/duia_parte3.md);
[TP3](../unidades/unidad-2/tp3/duia/duia_tp3.md);
[TP4](../unidades/unidad-2/tp4/duia/duia_tp4.md);
[Unidad 3](../unidades/unidad-3/duia/duia.md).

## 14. Decisiones aceptadas y descartadas

| Decisión | Estado | Motivo |
|---|---|---|
| Mantener `schema.sql` como contrato y agregar `tpi/` sin reescribir historia | Aceptada | Integrar evidencia sin cambios retroactivos. |
| SQLSTATE estándar en objetos productivos | Aceptada | Errores identificables de parámetros, referencia, duplicado y regla de negocio. |
| `FOR UPDATE` para stock y `FOR SHARE` en el trigger | Aceptada | Coordinar operaciones sobre la fila del producto. |
| `precio_unitario` histórico y PK compuesta como garantía definitiva | Aceptada | Preservar precio de venta y unicidad de la pareja. |
| Pruebas dentro de `BEGIN`/`ROLLBACK` | Aceptada | Aserciones reproducibles sin dejar filas permanentes. |
| Reutilizar `RANK() OVER` existente | Aceptada | Ya demuestra ventanas y respeta empates. |
| Inventar columnas, agregar `estado`, `eliminado`, `total` o `subtotal` físico | Descartada | No pertenecen al esquema canónico. |
| Modificar el esquema base para satisfacer artificialmente la rúbrica | Descartada | Los faltantes se resuelven con la capa integradora. |
| SQLSTATE productivos `P1001`/`P1002` | Descartada | Se utilizan códigos estándar. |
| Agregar `ROW_NUMBER()` solo para duplicar evidencia | Descartada | No aporta cobertura faltante. |
| `ON CONFLICT DO NOTHING` para ocultar duplicados | Descartada | La operación debe fallar explícitamente. |
| `COMMIT`/`ROLLBACK` internos en el procedimiento | Descartada | La transacción pertenece al llamante. |
| Afirmar concurrencia multisesión desde una prueba de una sesión | Descartada | Excede la evidencia obtenida. |
| JSONB o transition tables sin requisito funcional | No implementada | No son necesarios para esta entrega. |

`P0099` existe únicamente como excepción deliberada del test de atomicidad,
después del CALL; no es un SQLSTATE de los objetos productivos.

## 15. Conclusiones

La primera entrega permite recorrer los nueve objetivos desde evidencia
concreta de U1–U3 y los complementos mínimos del TPI. Se mantienen separados
el contrato canónico, los laboratorios históricos y los objetos integradores.
Las cifras de optimización conservan su contexto; los resultados TPI tienen
procedencia explícita y no se atribuyen a una ejecución de IA. La revisión
y aceptación académica final corresponden al equipo y a la cátedra.
