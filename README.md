# Food Store — Base de Datos II

## 1. Presentación

Food Store es un proyecto académico de PostgreSQL, desarrollado
progresivamente a lo largo de distintas unidades y trabajos prácticos
de la materia Base de Datos II. No es una aplicación productiva: es un
ejercicio de modelado, integridad, concurrencia, optimización de
consultas, indexado, vistas y normalización avanzada sobre un esquema
relacional de comercio (categorías, clientes, productos, pedidos y
detalle de pedido).

## 2. Integrantes

- Avalos Pablo
- Blangetti Sofia
- Suarez Ismael

## 3. Tecnología

- PostgreSQL 17
- SQL para PostgreSQL
- `psql` como cliente de línea de comandos
- Git para control de versiones

Características de PostgreSQL realmente presentes en `schema.sql`:

- `GENERATED ALWAYS AS IDENTITY` para claves primarias autogeneradas
- `TIMESTAMPTZ` para columnas de fecha/hora con zona horaria
- `NUMERIC` para valores monetarios (`precio`, `precio_unitario`)
- Tipo `ENUM` propio (`forma_pago`: `EFECTIVO`, `TARJETA`, `TRANSFERENCIA`)
- Claves primarias (`PRIMARY KEY`, incluyendo una compuesta en
  `detalle_pedido`) y claves foráneas (`FOREIGN KEY`)
- Restricciones `CHECK` (por ejemplo, `precio >= 0`, `cantidad > 0`)
- `ON DELETE RESTRICT` en todas las claves foráneas del esquema base
- Índices sobre columnas de clave foránea

No hay stack de aplicación (backend, frontend, ORM): este es un
proyecto puramente de base de datos.

## 4. Base canónica

`schema.sql` y `datos_iniciales.sql`, en la raíz del repositorio, son
la **fundación canónica actual** del proyecto:

- `schema.sql` → define el esquema base actual (tipos, tablas,
  restricciones, índices).
- `datos_iniciales.sql` → carga el dataset inicial mínimo sobre ese
  esquema.

**Importante:** no todo el SQL que vive bajo `unidades/` es una
migración pendiente sobre esta base canónica. La mayor parte son:

- ejercicios académicos de una unidad específica;
- evidencia histórica de un TP ya cerrado;
- consultas experimentales o alternativas usadas para comparación;
- scripts de laboratorio ejecutados sobre una copia de la base;
- objetos (índices, vistas, vistas materializadas, triggers) creados
  deliberadamente para un TP puntual.

**Nunca ejecutar todos los archivos `.sql` del repositorio en
secuencia.** Cada unidad documenta, en su propio README local, qué es
seguro ejecutar y en qué orden.

## 5. Modelo base

El esquema base (`schema.sql`) define exactamente estas tablas:

- **`categoria`** — agrupación de productos (`nombre`, `activo`).
- **`cliente`** — identificado por `email` único (`nombre`, `telefono`).
- **`producto`** — pertenece a una `categoria` (`categoria_id`),
  con `precio`, `stock` y `activo`.
- **`pedido`** — pertenece a un `cliente` (`cliente_id`), con `fecha`
  y `forma_pago`.
- **`detalle_pedido`** — línea de un pedido: referencia a `pedido` y
  a `producto` (clave primaria compuesta `pedido_id, producto_id`),
  con `cantidad` y `precio_unitario` (precio al momento de la venta).

No hay tablas `usuario`, `deposito` ni `lote` en el esquema base — esas
solo existen dentro del laboratorio específico de Unidad 4 (ver
sección 8).

## 6. Reconstrucción mínima de Food Store

Desde la **raíz** del repositorio:

```powershell
createdb -U postgres foodstore

psql -U postgres -d foodstore -v ON_ERROR_STOP=1 -f .\schema.sql

psql -U postgres -d foodstore -v ON_ERROR_STOP=1 -f .\datos_iniciales.sql
```

Este procedimiento reconstruye únicamente la base canónica (esquema +
dataset mínimo). No ejecuta automáticamente ningún script de las
unidades posteriores — cada unidad indica en su propio README cómo
reproducir su volumen de datos y sus objetos adicionales.

## 7. Estructura del repositorio

```
foodstore_baseII/
├── README.md
├── AGENTS.md
├── .gitignore
├── schema.sql
├── datos_iniciales.sql
├── .kiro/
│   └── steering/
│       ├── product.md
│       ├── structure.md
│       └── tech.md
└── unidades/
    ├── unidad-1/
    │   └── tp2/
    │       ├── README.md
    │       ├── sql/
    │       ├── specs/
    │       ├── informes/
    │       └── duia/
    ├── unidad-2/
    │   ├── tp3/
    │   │   ├── README.md
    │   │   ├── sql/
    │   │   ├── specs/
    │   │   ├── informes/
    │   │   └── duia/
    │   └── tp4/
    │       ├── README.md
    │       ├── sql/
    │       ├── specs/
    │       ├── informes/
    │       └── duia/
    ├── unidad-3/
    │   ├── README.md
    │   ├── sql/
    │   ├── specs/
    │   ├── informes/
    │   └── duia/
    └── unidad-4/
        ├── README.md
        ├── sql/
        ├── specs/
        └── informes/
```

## 8. Recorrido académico

| Unidad / TP | Tema principal | Punto de entrada | Artefactos principales |
|---|---|---|---|
| Unidad 1 / TP2 | Integridad, concurrencia, lectura crítica, protocolo de seguridad | [unidades/unidad-1/tp2/README.md](unidades/unidad-1/tp2/README.md) | Restricción `CHECK` histórica, escenarios de concurrencia, lectura crítica de scripts peligrosos |
| Unidad 2 / TP3 | Volumen de datos, consultas, `EXPLAIN ANALYZE`, optimización | [unidades/unidad-2/tp3/README.md](unidades/unidad-2/tp3/README.md) | Carga masiva, consultas principales y alternativas, informe de optimización |
| Unidad 2 / TP4 | JOIN, consultas analíticas, optimización comparativa | [unidades/unidad-2/tp4/README.md](unidades/unidad-2/tp4/README.md) | Consultas de ranking/facturación, lectura crítica de planes de JOIN, competencia de optimización |
| Unidad 3 | Índices, vistas, vista materializada, medición real | [unidades/unidad-3/README.md](unidades/unidad-3/README.md) | 3 índices, 3 vistas, 1 vista materializada, informe de mediciones |
| Unidad 4 | FNBC, descomposición sin pérdida, desnormalización controlada | [unidades/unidad-4/README.md](unidades/unidad-4/README.md) | Descomposición FNBC de `control_lote_almacen`, columna redundante con triggers de sincronización |

## 9. Dataset masivo compartido

[`unidades/unidad-2/tp3/sql/carga_masiva_tp3.sql`](unidades/unidad-2/tp3/sql/carga_masiva_tp3.sql)
es la **única copia canónica** del dataset masivo de laboratorio
(≈20.000 clientes, 50.000 productos, 200.000 pedidos, 500.000
detalles). Fue creado para TP3 y reutilizado posteriormente por Unidad
3 y por Unidad 4 sobre sus respectivas copias de base — no se duplica
en ningún otro lugar del repositorio.

## 10. Evidencia y metodología

El enfoque de trabajo seguido en la mayoría de las unidades fue:

```
especificar → generar/proponer → revisar → ejecutar manualmente
    cuando corresponde → medir → verificar → decidir → versionar
```

Según el caso, se utilizaron:

- `EXPLAIN (ANALYZE, BUFFERS)` para medir el impacto real de índices,
  vista materializada y reescrituras de consultas;
- `EXCEPT` bidireccional para verificar equivalencia semántica entre
  una consulta original y su alternativa (o entre una vista/vista
  materializada y su consulta manual equivalente);
- transacciones y `ROLLBACK` para probar cambios de forma reversible
  sobre copias de laboratorio;
- consultas de auditoría/conciliación para detectar desincronización
  en datos redundantes.

Los tiempos y planes documentados en los informes son **históricos**:
dependen del hardware, la caché, la versión de PostgreSQL y el estado
de la base en el momento exacto de la medición. No deben tratarse como
benchmarks universales ni reproducibles de forma idéntica en otro
entorno.

## 11. Uso de IA / DUIA

Distintos TPs de este repositorio documentan el uso de herramientas
como **Kiro**, **OpenCode** y **ChatGPT**, cada una solo en la medida
en que está efectivamente respaldada por la Declaración de Uso de IA
(DUIA) correspondiente a esa unidad — no se afirma que una única
herramienta haya generado todo el proyecto.

**Claude** está siendo utilizado actualmente para tareas de
mantenimiento y auditoría del repositorio (por ejemplo, esta
reestructuración de carpetas y la documentación maestra). Esto no
reescribe ni reinterpreta las DUIA históricas de cada TP — esas DUIA
siguen siendo, tal como fueron escritas en su momento, la fuente de
trazabilidad académica de cada pieza de trabajo.

Cuando existe, la DUIA local (`unidades/.../duia/`) documenta, para su
unidad: qué propuso la IA, qué fue revisado o corregido por el
estudiante, y qué decisiones finales no se delegaron a la IA.

## 12. Seguridad

- Los laboratorios que modifican estructura o datos deben realizarse
  sobre copias de la base, nunca sobre una base importante.
- Usar transacciones y `ROLLBACK` cuando corresponda probar un cambio
  sin dejarlo aplicado.
- Revisar cada script antes de ejecutarlo — no asumir que es seguro
  solo por estar en el repositorio.
- `backups/` no se versiona (ver sección 13).

Protocolo detallado:
[unidades/unidad-1/tp2/informes/protocolo_seguridad.md](unidades/unidad-1/tp2/informes/protocolo_seguridad.md)

## 13. Backups

El directorio `backups/` está excluido mediante `.gitignore`. Los
dumps locales (por ejemplo, el backup previo a los laboratorios de
Unidad 4) no forman parte del repositorio y no se versionan. Este
README no documenta datos sensibles ni credenciales.

## 14. Para un revisor humano o IA

Orden recomendado de lectura:

1. Leer este `README.md` raíz.
2. Leer `schema.sql`.
3. Leer `datos_iniciales.sql`.
4. Ir al README local de la unidad que se quiere auditar.
5. Leer su spec antes de evaluar cualquier implementación.
6. Leer los informes para la evidencia real (tiempos, planes, buffers).
7. Leer la DUIA correspondiente para la trazabilidad del uso de IA.
8. No asumir que todo SQL es una migración pendiente sobre la base
   canónica.
9. No inventar columnas que no existan en `schema.sql`.
10. No modificar evidencia histórica para hacerla coincidir con el
    estado actual del proyecto.

## 15. Estado actual

- La base canónica del proyecto sigue siendo `schema.sql` +
  `datos_iniciales.sql`.
- Unidad 4 contiene laboratorios (FNBC, desnormalización controlada)
  que **no** fueron fusionados a la base canónica: viven en sus propios
  scripts, ejecutados sobre una copia de laboratorio.
- El repositorio conserva evidencia histórica (informes, DUIA,
  consultas alternativas) para defensa académica y auditoría, no para
  ser reejecutada automáticamente.
- No existe dependencia de ninguna aplicación externa: todo el trabajo
  vive en SQL y Markdown.

No todos los ejercicios documentados acá deben ejecutarse para
reconstruir Food Store — solo `schema.sql` y `datos_iniciales.sql` son
necesarios para eso (sección 6).
