# Project Structure

Árbol real actual (ver `README.md` de la raíz para el detalle expandido
con archivos individuales):

```
foodStore/
├── README.md            # Punto de entrada del proyecto completo
├── AGENTS.md             # Guía técnica para agentes/IA
├── schema.sql            # DDL: esquema base canónico actual
├── datos_iniciales.sql   # DML: dataset inicial mínimo
├── .kiro/
│   └── steering/         # product.md, structure.md, tech.md
├── tpi/                 # Capa integradora de la Primera Entrega
│   ├── README.md
│   ├── informe_tecnico.md
│   ├── modelo/
│   │   ├── modelo_er.md
│   │   ├── modelo_relacional.md
│   │   └── normalizacion.md
│   ├── sql/
│   │   ├── consultas_cobertura_tpi.sql
│   │   └── objetos_programables.sql
│   └── pruebas/
│       └── pruebas_objetos_programables.sql
└── unidades/
    ├── unidad-1/tp2/
    ├── unidad-2/tp3/
    ├── unidad-2/tp4/
    ├── unidad-3/
    └── unidad-4/
```

## Qué permanece en la raíz y por qué

`schema.sql` y `datos_iniciales.sql` son la fundación canónica: todas
las unidades dependen de ellos, así que viven donde cualquier
reconstrucción mínima del proyecto los espera, en la raíz. `README.md`
y `AGENTS.md` son los puntos de entrada para un humano o una IA que
recién llega al repositorio, y `.kiro/` es la configuración de
steering de la herramienta Kiro — ambos también pertenecen a la raíz
por convención de la herramienta y por ser transversales a todas las
unidades. El trabajo histórico específico de una unidad o TP vive bajo
`unidades/`; `tpi/` integra y complementa la evidencia de U1–U3 para la
Primera Entrega, sin constituir una nueva unidad académica ni reemplazar
los TPs históricos. Su README mapea y reproduce la entrega, el informe
técnico la justifica, y `modelo/`, `sql/` y `pruebas/` reúnen sus
artefactos específicos. Sus objetos adicionales se instalan explícitamente,
sin modificar la fundación canónica.

## Estructura interna de cada unidad/TP

Cada carpeta de unidad/TP bajo `unidades/` sigue el mismo patrón (con
variaciones menores cuando una unidad no generó cierto tipo de
artefacto):

- `README.md` — punto de entrada de esa unidad: qué hay, qué es
  seguro ejecutar, y en qué orden.
- `sql/` — scripts SQL: índices, vistas, laboratorios de migración,
  consultas principales y alternativas. No todo lo que hay acá es una
  migración sobre la base canónica — cada README local aclara la
  clasificación de cada script (dataset de laboratorio, definición de
  objeto vigente, evidencia histórica, o consulta experimental).
- `specs/` — especificaciones escritas como contrato antes de generar
  el SQL correspondiente.
- `informes/` — evidencia real: mediciones, planes de `EXPLAIN
  ANALYZE`, resultados de verificación de equivalencia.
- `duia/` — Declaración de Uso de IA de esa unidad (cuando existe).

Unidad 4 no tiene un directorio `duia/` propio porque en esa unidad no
se documentó una DUIA específica.

## Dependencia canónica entre unidades

`unidades/unidad-2/tp3/sql/carga_masiva_tp3.sql` es la única copia
canónica del dataset masivo de laboratorio. Fue creado durante TP3 y
es reutilizado, sin duplicarse, por:

- **Unidad 3**, para las mediciones de índices, vistas y vista
  materializada.
- **Unidad 4**, para el laboratorio de desnormalización controlada.

Ningún otro archivo del repositorio debe contener una copia de ese
script — las unidades que lo necesitan lo referencian por su ruta
canónica en su propio README.

## Convenciones (aplican dentro de cada `sql/`)

### Nomenclatura
- Todos los identificadores (tablas, columnas, restricciones, índices)
  en **español**, minúsculas, `snake_case`.
- Tablas en sustantivo singular: `categoria`, `cliente`, `producto`,
  `pedido`, `detalle_pedido` (base canónica); cada unidad documenta
  las tablas adicionales que introduce, si las hay.
- Columnas de clave foránea: `<tabla_referenciada>_id`.
- Nombres de restricciones:
  - Claves primarias: `pk_<tabla>` (nombradas solo cuando son compuestas).
  - Claves foráneas: `fk_<tabla>_<tabla_referenciada>`.
  - `CHECK`: `chk_<tabla>_<columna>`.
  - Índices: `idx_<tabla>_<columna>`.

### Diseño del esquema base (`schema.sql`)
- Toda tabla de la base canónica usa `BIGINT GENERATED ALWAYS AS
  IDENTITY PRIMARY KEY`, excepto `detalle_pedido`, que usa clave
  primaria compuesta (`pedido_id`, `producto_id`).
- `categoria`, `cliente` y `producto` incluyen `created_at TIMESTAMPTZ
  NOT NULL DEFAULT now()`; `pedido` usa `fecha` como marca temporal de
  la operación; `detalle_pedido` no incluye `created_at`.
- `precio_unitario` en `detalle_pedido` guarda el precio al momento de
  la venta (denormalizado por diseño, no una FK al precio actual).
- `activo BOOLEAN` se usa para soft-delete en `categoria` y `producto`.
- Todas las claves foráneas usan `ON DELETE RESTRICT`.

### Datos iniciales (`datos_iniciales.sql`)
- Las referencias a otras filas usan subconsultas sobre claves
  naturales (por ejemplo, `WHERE nombre = 'Pizzas'`, `WHERE email =
  '...'`), no IDs numéricos hardcodeados.
