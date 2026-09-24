# TPI Food Store — Primera Entrega

**Modelo oficial y ejecución real validados en PostgreSQL 17.11.** La entrega
integra las Unidades 1–3, preserva los TP1–TP4 evaluados y documenta Unidad 4
como trabajo complementario. La [evidencia consolidada](evidencia_modelo_oficial.md)
registra instalación, pruebas funcionales, tres escenarios concurrentes y HAVING;
el [informe técnico](informe_tecnico.md) interpreta sus resultados y límites.

**Integrantes:** Avalos Pablo, Blangetti Sofia y Suarez Ismael.

## Modelo vigente y archivos principales

La autoridad estructural es [schema.sql](../schema.sql), con cinco entidades:
`categoria`, `usuario`, `producto`, `pedido` y `detalle_pedido`.

- Todas tienen PK `id` y baja lógica `eliminado`; `producto.disponible` expresa
  una condición comercial diferente.
- `pedido` referencia `usuario_id`, usa `fecha DATE`, estado y total físico.
- El detalle tiene identidad propia y `UNIQUE(pedido_id, producto_id)`; conserva
  cantidad, precio histórico y subtotal físico.
- El subtotal es una **redundancia derivada deliberada**: el detalle cumple
  1FN/2FN, pero no 3FN/FNBC estrictas considerando la DF del subtotal. El total
  es un agregado entre relaciones, no por sí solo una DF interna problemática.

| Archivo | Función |
|---|---|
| [Modelo ER](modelo/modelo_er.md) | Entidades, atributos, cardinalidades y participación |
| [Modelo relacional](modelo/modelo_relacional.md) | Tipos, claves y restricciones del schema |
| [Normalización](modelo/normalizacion.md) | DF, claves candidatas y redundancias deliberadas |
| [Seed](../datos_iniciales.sql) | Fotografía inicial: 3 usuarios, 2 categorías, 3 productos, 5 pedidos y 7 detalles |
| [Objetos programables](sql/objetos_programables.sql) | 7 rutinas y 5 triggers: subtotal, total, vigencia y venta con stock |
| [Batería](pruebas/pruebas_objetos_programables.sql) | 29 grupos / 37 variantes, fixtures reversibles |
| [Consulta HAVING](sql/consultas_cobertura_tpi.sql) | Usuarios con más de un pedido no eliminado |
| [Evidencia](evidencia_modelo_oficial.md) | Resultados reales y procedencia; no sustituye el análisis |

## Mapa de cobertura

| # | Objetivo | Evidencia y alcance |
|---|---|---|
| 1 | ER, atributos, claves y cardinalidades | [Modelo ER vigente](modelo/modelo_er.md) |
| 2 | Transformación relacional y N:M | [Modelo relacional](modelo/modelo_relacional.md): detalle con PK propia y UK del par |
| 3 | DF y formas normales | [Normalización](modelo/normalizacion.md), sin afirmar FNBC universal |
| 4 | DDL completo | [Schema oficial](../schema.sql): 3 ENUM, 5 tablas, PK/FK/UK/CHECK e índices base |
| 5 | DML, JOIN, agregaciones, subconsultas, HAVING y ventanas | [Seed vigente](../datos_iniciales.sql), [HAVING vigente](sql/consultas_cobertura_tpi.sql); [TP3](../unidades/unidad-2/tp3/README.md) y [TP4](../unidades/unidad-2/tp4/README.md) como evidencia histórica evaluada |
| 6 | Vistas, funciones, triggers, procedimiento y CALL | [Cuatro vistas U3](../unidades/unidad-3/sql/views.sql), [objetos TPI](sql/objetos_programables.sql) y [pruebas](pruebas/pruebas_objetos_programables.sql) |
| 7 | Integridad declarativa y de negocio | [Schema](../schema.sql), [batería](pruebas/pruebas_objetos_programables.sql) y [evidencia funcional](evidencia_modelo_oficial.md) |
| 8 | Transacciones, aislamiento, atomicidad y concurrencia | [Evidencia TPI](evidencia_modelo_oficial.md): atomicidad y tres ensayos READ COMMITTED; [cierre TPI-B](evidencia_cierre_objetivo_8.md): SAVEPOINT, REPEATABLE READ y conflicto SERIALIZABLE, con [arnés reproducible](pruebas/transacciones/README.md) |
| 9 | Baja lógica, índices y reportes | [U3 vigente](../unidades/unidad-3/informes/informe_mediciones.md), [HAVING](sql/consultas_cobertura_tpi.sql) y triggers de total |

**Historia protegida:** TP1–TP4 pertenecen a una iteración anterior del modelo.
Son evidencia histórica evaluada, no scripts convertidos retroactivamente ni
migraciones pendientes para el schema actual. U3 fue alineada en `da5f3e4`;
U4 en `95fbfbf`. El esquema raíz y el TPI actuales continúan esa alineación.

## Reproducción funcional en laboratorio

Comandos para **PowerShell desde la raíz del repositorio**, con PostgreSQL
17.11 y autenticación local ya configurada. Esta secuencia es para una base
**nueva, inexistente** llamada `foodstore_tpi_oficial`. Si ya existe la base
validada, **no ejecutar la creación ni reinstalar**: detenerse y acordar un
nuevo ensayo. No se incluye ningún borrado ni recreación automática.

```powershell
createdb -w -h 127.0.0.1 -p 5432 -U postgres foodstore_tpi_oficial
if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la base; detener la instalación.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -1 -f .\schema.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló schema.sql.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -f .\datos_iniciales.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló datos_iniciales.sql.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -1 -f .\tpi\sql\objetos_programables.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló la instalación de objetos.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -f .\tpi\pruebas\pruebas_objetos_programables.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló la batería; no continuar.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -f .\tpi\sql\consultas_cobertura_tpi.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló la consulta HAVING.' }
```

`-1` corresponde solo a schema y objetos. El seed administra su propio
`BEGIN/COMMIT`; la batería usa `BEGIN/ROLLBACK` y debe correr sin otras
escrituras. `CREATE` simple y la guarda del seed hacen visibles las
instalaciones repetidas. Ante un error, detenerse y diagnosticar, no parchear
ni continuar automáticamente.

El seed precede a los objetos y no reproduce cronológicamente ventas: el stock
es una fotografía inicial. `SEED_NO_AUTH` es un marcador académico, no una
credencial real ni autenticación implementada. La batería revierte sus fixtures,
no los objetos instalados; las secuencias IDENTITY pueden conservar huecos.
El DOWN comentado no se ejecuta automáticamente.

Esta secuencia **no reproduce concurrencia multisesión** ni instala U3/U4.
Los tres ensayos requieren conexiones independientes y monitoreo según la
[evidencia](evidencia_modelo_oficial.md). El seed mínimo tampoco reconstruye
las cargas masivas medidas de U3/U4 ni proporciona los usuarios 801/802 de U4.

El [arnés TPI-B](pruebas/transacciones/README.md) tiene una reproducción separada
en `foodstore_tpi_cierre_b`: SAVEPOINT explícito, snapshot REPEATABLE READ y
conflicto SERIALIZABLE `40001`. No reemplaza los tres ensayos READ COMMITTED
anteriores; sus resultados y límites están en la [nueva evidencia](evidencia_cierre_objetivo_8.md).

## Resultados reales resumidos

Fuente: [evidencia de Bloques 6, 7 y 8](evidencia_modelo_oficial.md), sobre
`foodstore_tpi_oficial`, PostgreSQL **17.11**. Este cierre documental no repite
las ejecuciones.

| Verificación | Resultado |
|---|---|
| Schema, seed y objetos | PASS; catálogo contrastado, 12 objetos presentes |
| Batería de una sesión | 29 grupos / 37 variantes; 30 NOTICE PASS, exit code 0 |
| NOTICE global | `PASS: batería completa de objetos programables del modelo oficial` |
| Atomicidad y operación masiva | PASS; detalle, subtotal, total y stock revierten juntos |
| Concurrencia real | 3/3 escenarios PASS bajo READ COMMITTED, con espera `Lock / transactionid` observada |
| HAVING | Ana Gómez: 2 pedidos; Luis Paz: 2 pedidos; 2 filas, exit code 0 |
| Limpieza y conciliación | Cero fixtures; seed y 12 objetos intactos; cero inconsistencias de subtotal/total |

La batería cubre ventas válidas, rechazos, integridad declarativa, precio
histórico, subtotal, total, modificaciones directas controladas, bajas y
reactivaciones, DELETE, movimientos entre pedidos y sentencias masivas.
La concurrencia se ensayó después, separadamente: sobreventa, total del mismo
pedido y duplicado de pareja. El helper temporal de cleanup registró una
incidencia no productiva, explicada sin ocultarla en el
[informe técnico](informe_tecnico.md) y la evidencia.

## Unidades 3 y 4: decisiones vigentes

- **U3:** tres índices aceptados para la carga evaluada, cuatro vistas equivalentes,
  seguridad de `v_usuarios_publico` probada y materializada con
  `REFRESH CONCURRENTLY` exitoso. Consultar [informe vigente U3](../unidades/unidad-3/informes/informe_mediciones.md)
  para métricas y costos de escritura; no son resultados del seed mínimo TPI.
- **U4:** FNBC PASS. La desnormalización fue `VALID_EXPERIMENT`, pero quedó
  `REJECTED_AFTER_MEASUREMENT` / `DO_NOT_ADOPT`. `detalle_pedido.categoria_id`
  no pertenece al esquema canónico. Véase [informe vigente U4](../unidades/unidad-4/informes/informe_u4_fnbc_desnormalizacion.md).

## Límites y lectura posterior

La ruta de negocio que administra stock es `CALL registrar_detalle_pedido`.
DML directo del detalle mantiene derivados mediante triggers, pero **no**
administra inventario. No hay política de reposición por bajas, cancelación
ni DELETE. No se acreditaron ausencia universal de deadlocks, seguridad
concurrente de DML directo arbitrario, garantías generales del CALL bajo
SERIALIZABLE, carga masiva concurrente ni rendimiento bajo estrés o alta
concurrencia. TPI-B sí acredita el conflicto `40001` del caso canónico acotado,
no una garantía universal ni una estrategia automática de reintentos.

Los comentarios de validación pendiente en scripts/modelos registran su fase
de autoría anterior; la ejecución posterior se acredita en la evidencia, no
por reescribir esos artefactos durante este cierre. El
[informe técnico](informe_tecnico.md) amplía decisiones, uso de IA, resultados
y reservas. La [raíz](../README.md) permite recorrer el proyecto completo.
