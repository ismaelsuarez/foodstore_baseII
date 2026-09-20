# AGENTS.md — Food Store / Base de Datos II

## Propósito

Proyecto académico PostgreSQL (UTN — Base de Datos II). No hay
aplicación, backend, frontend ni test framework: todo el trabajo es
SQL y documentación Markdown, organizado por unidad/TP bajo
`unidades/`, con la integración de la Primera Entrega en `tpi/`.

## Fuentes de verdad

En orden de autoridad:

1. `schema.sql` — esquema base canónico actual.
2. `datos_iniciales.sql` — dataset inicial mínimo.
3. `README.md` de la raíz — punto de entrada del proyecto completo.
4. README local de cada unidad (`unidades/.../README.md`).
5. `specs/` de cada unidad — contrato previo a la generación de SQL.
6. `informes/` de cada unidad — evidencia real medida.
7. `duia/` de cada unidad, cuando exista — trazabilidad de uso de IA y decisiones humanas.

## Primera Entrega del TPI

Para evaluar la Primera Entrega, comenzar por
[tpi/README.md](tpi/README.md) y usar
[tpi/informe_tecnico.md](tpi/informe_tecnico.md) como mapa detallado
de evidencias. El alcance principal es U1–U3; Unidad 4 permanece como
trabajo posterior/complementario.

Cuando la tarea sea sobre el TPI, aplicar este orden de autoridad:

1. `schema.sql` — autoridad estructural canónica.
2. `datos_iniciales.sql` — dataset inicial canónico.
3. `tpi/README.md` — cobertura y reproducción de la entrega.
4. `tpi/modelo/` — ER, modelo relacional y normalización.
5. `tpi/sql/` — consultas y objetos adicionales específicos del TPI.
6. `tpi/pruebas/` — batería de verificación de esos objetos.
7. Evidencia histórica de `unidades/` referenciada por el informe técnico.
8. DUIA correspondientes — trazabilidad histórica.

`tpi/` integra y complementa: no modifica el contrato de `schema.sql`.
Los objetos TPI se instalan explícitamente; no son migraciones automáticas.
No inventar campos para satisfacer consignas, no tratar scripts históricos
como migraciones pendientes ni reescribir evidencia histórica sin una
instrucción explícita.

## Regla crítica

**No asumir que todo SQL bajo `unidades/` es una migración pendiente**
sobre `schema.sql`. La mayoría son ejercicios académicos cerrados,
evidencia histórica, consultas experimentales o scripts de laboratorio
ejecutados sobre una copia de la base — no forman parte de la base
canónica salvo que el README local de esa unidad diga lo contrario.

## Antes de proponer SQL

- Leer `schema.sql` real — no asumir columnas o tablas de memoria.
- Verificar nombres de tablas y columnas reales antes de escribir una
  consulta o un `ALTER TABLE`.
- Revisar las restricciones (`CHECK`, `FOREIGN KEY`, `UNIQUE`) ya
  existentes antes de proponer una nueva.
- Revisar el README de la unidad involucrada.
- Revisar la spec correspondiente, si existe, antes de generar o
  modificar una implementación.

## Prohibiciones

- No inventar columnas que no existan en el esquema real.
- No inventar resultados, tiempos ni planes de ejecución.
- No modificar mediciones históricas ya documentadas.
- No reescribir prompts históricos citados en una DUIA.
- No ejecutar scripts destructivos sin autorización explícita.
- No trabajar sobre una base importante para probar un laboratorio —
  usar una copia.
- No duplicar archivos canónicos (por ejemplo,
  `unidades/unidad-2/tp3/sql/carga_masiva_tp3.sql` tiene una única
  ubicación; otras unidades lo referencian, no lo copian).
- No mover archivos sin actualizar las referencias de ruta que queden
  rotas por el movimiento.

## Convenciones

- Identificadores en **español**, `snake_case`.
- Tablas en singular (`categoria`, `cliente`, `producto`, `pedido`,
  `detalle_pedido`).
- Columnas de clave foránea: `<tabla_referenciada>_id`.
- PostgreSQL como motor exclusivo — no asumir compatibilidad con otro
  motor.

## Validación

- **Equivalencia semántica:** `EXCEPT` bidireccional entre la consulta
  original y su alternativa, o entre una vista/vista materializada y
  su consulta manual equivalente.
- **Rendimiento:** `EXPLAIN (ANALYZE, BUFFERS)`, con protocolo de
  varias corridas descartando la primera como calentamiento cuando así
  se documenta.
- **Migraciones y laboratorios:** transacciones, consulta de auditoría
  cuando corresponda, y plan de reversión documentado.

## Estructura

Ver `.kiro/steering/structure.md` para el árbol completo. En resumen:
`schema.sql`, `datos_iniciales.sql`, `README.md`, `AGENTS.md` y
`.kiro/` viven en la raíz; los TPs históricos se organizan bajo
`unidades/unidad-N/[tpX]/{sql,specs,informes,duia}/`, y `tpi/` reúne
la capa integradora de la Primera Entrega.

## Contexto histórico

Los informes y las DUIA son evidencia histórica de trabajo ya
evaluado. No deben reescribirse para "actualizarlos" ni para que
parezcan generados en el estado actual del repositorio — solo se
corrigen errores de ruta cuando un archivo se reubica físicamente.

## Unidad 4

Atención especial en esta unidad:

- `usuario`, `lote` y `deposito` **no** forman parte del esquema base
  (`schema.sql`) — son tablas mínimas creadas exclusivamente dentro del
  laboratorio de Unidad 4 para hacerlo reproducible.
- `detalle_pedido.categoria_id` tampoco forma parte del esquema base —
  es una columna redundante agregada solo dentro de ese laboratorio.
- Ambas extensiones pertenecen únicamente al laboratorio de Unidad 4,
  ejecutado sobre una copia (`foodstore_u4`), no a la base canónica.
- `producto.categoria_id` sigue siendo la única fuente de verdad en el
  esquema de desnormalización controlada de esa unidad.

## Git

- Cambios pequeños y descriptivos.
- No hacer `push` sin autorización explícita del usuario.
- Verificar `git diff --check` antes de dar por cerrado un cambio.
- Preservar historial usando `git mv` al reubicar archivos, en vez de
  borrar y recrear.
