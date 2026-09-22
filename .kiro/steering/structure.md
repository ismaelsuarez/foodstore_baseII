# Food Store — Estructura y convenciones

## Mapa del repositorio

```text
foodStore/
├── README.md
├── AGENTS.md
├── schema.sql
├── datos_iniciales.sql
├── .kiro/steering/
│   ├── product.md
│   ├── tech.md
│   └── structure.md
├── tpi/
│   ├── README.md
│   ├── informe_tecnico.md
│   ├── evidencia_modelo_oficial.md
│   ├── modelo/
│   │   ├── modelo_er.md
│   │   ├── modelo_relacional.md
│   │   └── normalizacion.md
│   ├── sql/
│   │   ├── objetos_programables.sql
│   │   └── consultas_cobertura_tpi.sql
│   └── pruebas/pruebas_objetos_programables.sql
└── unidades/
    ├── unidad-1/tp2/             # Histórico evaluado
    ├── unidad-2/tp3/             # Histórico evaluado
    ├── unidad-2/tp4/             # Histórico evaluado
    ├── unidad-3/                # TP5 oficial corregido
    └── unidad-4/                # FNBC y candidato experimental descartado
```

## Autoridad y lectura

El [esquema raíz](../../schema.sql) y el [seed](../../datos_iniciales.sql) definen
la base oficial; el [modelo TPI](../../tpi/modelo/modelo_relacional.md) la explica.
[README TPI](../../tpi/README.md) guía la reproducción,
[informe técnico](../../tpi/informe_tecnico.md) interpreta y
[evidencia](../../tpi/evidencia_modelo_oficial.md) conserva resultados reales.
Los objetos TPI se instalan explícitamente; no convierten SQL histórico en
migraciones pendientes. [AGENTS](../../AGENTS.md) fija las reglas para cambios.

Las unidades organizan sus artefactos en README, `sql/`, `specs/`, `informes/`
y `duia/` cuando existe. U4 no tiene una DUIA propia. TP1–TP4, bajo U1/U2,
son **EVIDENCIA HISTÓRICA EVALUADA**: no se modifican salvo instrucción explícita.
La carga masiva histórica de TP3 permanece en su ubicación original, no se
copia ni se presenta como carga compatible con el modelo oficial actual.

## Unidad 3: nombres vigentes

| Área | Artefactos / objetos |
|---|---|
| SQL | indices.sql, queries.sql, views.sql, materializadas.sql, seguridad.sql |
| Índices | idx_producto_stock_bajo, idx_pedido_fecha_reciente, idx_usuario_mail_lower |
| Vistas | v_productos_vigentes, v_pedidos_resumen, v_pedido_detalle, v_usuarios_publico |
| Materializada | mv_facturacion_categoria_mes |
| Specs de índices | indice_producto_stock_bajo.md, indice_pedido_fecha_reciente.md, indice_usuario_mail_lower.md |
| Specs de vistas | vista_productos_vigentes.md, vista_pedidos_resumen.md, vista_pedido_detalle.md, vista_usuarios_publico.md |
| Spec materializada | vista_materializada_facturacion_categoria_mes.md |

Entrada: [README U3](../../unidades/unidad-3/README.md).
Documentos vigentes: informe_mediciones.md, evidencia_modelo_oficial.md y duia.md
bajo sus respectivas carpetas. informe_mediciones_historico.md y
duia_historica.md son trazabilidad anterior, no resultados vigentes.

## Unidad 4: límite del laboratorio

[README U4](../../unidades/unidad-4/README.md) distingue FNBC PASS del candidato
VALID_EXPERIMENT / REJECTED_AFTER_MEASUREMENT / DO_NOT_ADOPT. Se preservan las
specs y SQL del experimento, su evidencia, informe vigente e informe histórico.
`usuario` pertenece al modelo oficial; `lote` y `deposito` son extensiones
académicas. No instalar automáticamente `detalle_pedido.categoria_id` ni los
triggers experimentales sobre el esquema canónico.

## Convenciones del contrato vigente

- Identificadores en español, `snake_case`; tablas singulares: categoria,
  usuario, producto, pedido y detalle_pedido.
- Toda tabla tiene PK `id`; el detalle también UK `(pedido_id, producto_id)`.
  No confundir clave primaria con candidata alternativa.
- FK `<tabla>_id`, restricciones `fk_...`, `chk_...` y
  `uq_detalle_pedido_pedido_producto`; usar los nombres reales de schema.sql.
  Las PK simples usan los nombres asignados por PostgreSQL, no una convención
  inventada de nombres explícitos.
- `eliminado` en todas las tablas; `disponible` solamente expresa la condición
  comercial de producto. `fecha DATE` en pedido y `created_at TIMESTAMPTZ` en todas.
- Subtotal físico derivado dentro de la línea; total físico agregado entre
  líneas vigentes. No duplicar las autoridades de mantenimiento del TPI.
- El seed usa RETURNING para pedidos; los nombres de producto solo identifican
  filas dentro del dataset controlado, no constituyen claves del modelo.
- No incorporar contraseñas reales ni logs temporales como documentación.
  Preservar evidencia medida y diferenciarla de propuestas o validación pendiente.
