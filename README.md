# Food Store — Base de Datos II

## TP Unidad 3 — Semana 5
## Índices, vistas y vistas materializadas

## Integrantes

- Avalos Pablo
- Blangetti Sofia
- Suarez Ismael

Este trabajo continúa el proyecto Food Store de semanas anteriores.
Evalúa:

- diseño e implementación de índices B-tree (simples, compuestos,
  parciales y de expresión);
- medición real del impacto de cada índice mediante
  `EXPLAIN (ANALYZE, BUFFERS)`;
- vistas convencionales para encapsular reglas de negocio;
- minimización de datos en una de esas vistas;
- una vista materializada para un reporte analítico costoso;
- verificación de equivalencia semántica mediante `EXCEPT`
  bidireccional;
- el flujo de trabajo Kiro (especificación) → OpenCode (generación) →
  revisión humana → medición real → decisión → versionado en Git.

---

## Requisitos

- PostgreSQL 17 (recomendado).
- `psql` disponible en el `PATH`.
- Git.
- Una base PostgreSQL local de pruebas.

Este README no documenta contraseñas ni credenciales.

---

## Base de datos de trabajo

Las mediciones de este TP se realizaron sobre una base llamada
`foodstore_tp5`. Esa base fue creada por el estudiante como copia de
una versión previa del proyecto Food Store; no se asume que otra
persona ya la tenga disponible.

El dataset usado durante las mediciones de este TP no proviene
únicamente de los datos iniciales del proyecto: fue ampliado con una
carga masiva heredada de TP3. Para reproducir ese mismo volumen desde
cero, el orden real es:

1. `schema.sql` — crea el esquema (tablas, restricciones).
2. `datos_iniciales.sql` — aporta el dataset inicial del proyecto:
   2 categorías, 3 clientes, 3 productos, 5 pedidos, 7 detalles.
3. `carga_masiva_tp3.sql` — agrega el volumen masivo usado para las
   pruebas de rendimiento: 20.000 clientes, 50.000 productos, 200.000
   pedidos, 500.000 detalles.
4. Los objetos de este TP (`indices.sql`, `views.sql`,
   `materializadas.sql`), aplicados sobre esa base ya poblada.

Sumando los pasos 2 y 3, el dataset de `foodstore_tp5` queda
aproximadamente con los conteos utilizados durante este TP:

- `categoria`: 2
- `cliente`: 20.003
- `producto`: 50.003
- `pedido`: 200.005
- `detalle_pedido`: 500.007

Ejemplo de reproducción desde PowerShell:

```powershell
createdb -U postgres foodstore_tp5

psql -U postgres -d foodstore_tp5 -f .\schema.sql

psql -U postgres -d foodstore_tp5 -f .\datos_iniciales.sql

psql -U postgres -d foodstore_tp5 -v ON_ERROR_STOP=1 -1 -f .\carga_masiva_tp3.sql
```

- `-v ON_ERROR_STOP=1` detiene la carga apenas ocurre un error, en
  lugar de seguir ejecutando el resto del script.
- `-1` ejecuta todo el archivo dentro de una única transacción, para
  que un error a mitad de la carga masiva no deje datos parciales.

Estos pasos reproducen el volumen de datos utilizado, no
necesariamente los mismos tiempos: los tiempos medidos dependen del
entorno y la máquina donde se ejecuten.

---

## Parte A — Índices

Los índices de este TP se encuentran en:

```
indices.sql
```

Nombres:

- `idx_producto_stock_bajo`
- `idx_pedido_fecha_reciente`
- `idx_cliente_email_lower`

**Importante:** `indices.sql` usa `CREATE INDEX` sin `IF NOT EXISTS`.
Antes de ejecutarlo, hay que revisar si esos índices ya existen en la
base de destino — ejecutarlo dos veces sobre la misma base falla.

Las mediciones reales (antes/después, buffers, planes) están
documentadas en:

```
informe_mediciones.md
```

No se repiten acá los `EXPLAIN` completos; están en ese informe.

**Orden para reproducir las mediciones "antes/después":** no alcanza
con ejecutar `indices.sql` y comparar. El orden correcto es:

1. preparar la base con `schema.sql` + `datos_iniciales.sql` + `carga_masiva_tp3.sql`;
2. ejecutar las consultas baseline **antes** de crear los índices de
   `indices.sql` — ese es el estado "antes";
3. recién ahí crear los índices y repetir las mismas consultas para
   obtener el estado "después";
4. el protocolo de medición y las consultas exactas usadas en cada
   caso están documentados en `informe_mediciones.md`.

Crear los índices antes de medir el estado "antes" invalida la
comparación, porque ya no habría una línea base real contra la cual
medir la mejora.

---

## Parte B — Vistas

Archivo:

```
views.sql
```

Vistas:

- `v_productos_vigentes`
- `v_pedidos_cliente`
- `v_detalle_pedido_producto`

Instalación desde PowerShell:

```powershell
psql -U postgres -d foodstore_tp5 -f .\views.sql
```

Al usar `CREATE OR REPLACE VIEW`, `views.sql` puede volver a aplicarse
sobre las vistas ya existentes sin necesidad de borrarlas primero.

La equivalencia semántica de cada vista contra su consulta manual fue
validada con `EXCEPT` bidireccional; los resultados están documentados
en `informe_mediciones.md`.

---

## Parte C — Vista materializada

Archivo:

```
materializadas.sql
```

Objetos:

- `mv_facturacion_categoria_mes`
- `idx_mv_facturacion_categoria_mes_unique`

Instalación sobre una base limpia que todavía no tenga esos objetos:

```powershell
psql -U postgres -d foodstore_tp5 -f .\materializadas.sql
```

**Advertencia importante:** `materializadas.sql` contiene
`CREATE MATERIALIZED VIEW` y `CREATE UNIQUE INDEX` sin
`IF NOT EXISTS`. No debe ejecutarse dos veces sobre una base que ya
tenga `mv_facturacion_categoria_mes` — fallará.

El índice `UNIQUE` sobre `(categoria_id, mes)` permite posteriormente
ejecutar:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY
    mv_facturacion_categoria_mes;
```

Ese `REFRESH CONCURRENTLY` **no** fue ejecutado durante este TP; el
índice solo deja preparada la posibilidad de hacerlo más adelante.

### Política de refresh

Política propuesta: refrescar la vista materializada cada 60 minutos
mientras el sistema esté en operación.

- La vista materializada **no** se actualiza automáticamente cuando
  cambian los datos base.
- Puede existir hasta aproximadamente una hora de atraso (staleness)
  entre dos refresh.
- No debe utilizarse como fuente transaccional en tiempo real; es un
  reporte agregado para análisis y gestión.

---

## Mediciones (resumen)

**Índices:**

| Índice | Antes | Después |
|---|---:|---:|
| `idx_producto_stock_bajo` | 10.030 ms | 0.2675 ms |
| `idx_pedido_fecha_reciente` | 12.8805 ms | 0.313 ms |
| `idx_cliente_email_lower` | 10.272 ms | 0.1075 ms |

**Vista materializada:**

| Consulta | Promedio estable |
|---|---:|
| Original (JOIN + agregación) | 1131.224 ms |
| Sobre la vista materializada | 0.060 ms |

Estas cifras corresponden al entorno y al dataset utilizados durante
esta medición puntual — no se presentan como valores universales ni se
afirma que se reproducirán con tiempos idénticos en otra corrida u
otra máquina.

Para la evidencia completa (planes reales, buffers, protocolo de
medición, propuestas descartadas) ver:

```
informe_mediciones.md
```

---

## DUIA — Declaración de Uso de IA

El archivo:

```
duia.md
```

documenta:

- el uso de Kiro para especificar cada objeto antes de generarlo;
- el uso de OpenCode para generar SQL y documentación a partir de esas
  specs;
- las propuestas que fueron revisadas y corregidas antes de aceptarse;
- el caso de un índice descartado explícitamente por sobreindexación;
- las decisiones que tomó el estudiante y no se delegaron a la IA;
- las verificaciones de equivalencia semántica realizadas;
- la trazabilidad de commits de cada pieza del trabajo.

---

## Specs

El directorio `specs/` conserva las especificaciones escritas antes de
generar cada índice, cada vista y la vista materializada. Cada spec
define el objetivo, el esquema real involucrado, las restricciones de
diseño y el criterio de aceptación de esa pieza.

Esto permite demostrar el flujo de trabajo seguido en todo el TP:

```
especificar → generar → revisar → medir → decidir → versionar
```

---

## Archivos principales

| Archivo | Propósito |
|---|---|
| `schema.sql` | Esquema base del proyecto Food Store (tablas, restricciones). |
| `datos_iniciales.sql` | Datos base heredados del proyecto Food Store. |
| `carga_masiva_tp3.sql` | Genera el volumen de datos utilizado para las pruebas de rendimiento, heredado desde TP3. |
| `queries.sql` | Consultas de referencia utilizadas en el TP5 para las mediciones de índices, equivalencia de vistas y reporte de la vista materializada. |
| `indices.sql` | Definición de los tres índices de este TP, documentados con su spec, justificación y resultado medido. |
| `views.sql` | Definición de las tres vistas convencionales de la Parte B. |
| `materializadas.sql` | Definición de la vista materializada y su índice UNIQUE de la Parte C. |
| `informe_mediciones.md` | Evidencia completa de mediciones (`EXPLAIN ANALYZE`), equivalencias `EXCEPT` y planes reales. |
| `duia.md` | Declaración de uso de IA y bitácora de decisiones. |
| `specs/` | Especificaciones previas de cada índice, vista y vista materializada. |

---

## Notas para la defensa

El estudiante debe poder justificar oralmente, para cada pieza:

- por qué se creó cada índice y qué columnas se eligieron como clave o
  como `INCLUDE`;
- qué nodo del plan cambió realmente (no solo qué se esperaba que
  cambiara);
- el costo de mantenimiento de cada índice sobre `INSERT`/`UPDATE`;
- por qué se descartó la variante *covering* de
  `idx_cliente_email_lower` por sobreindexación;
- por qué `v_pedidos_cliente` no expone (ni inventa) una columna de
  contraseña;
- por qué `v_detalle_pedido_producto` no filtra por
  `producto.activo`;
- por qué la vista materializada acepta staleness de hasta
  aproximadamente una hora, y por qué eso es aceptable para ese
  reporte en particular.
