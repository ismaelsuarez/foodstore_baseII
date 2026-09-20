# Unidad 2 — TP4

Trabajo sobre consultas analíticas, JOIN, lectura de planes,
EXPLAIN ANALYZE y optimización comparativa sobre Food Store.

## Contenido

- `sql/` — scripts SQL de este TP.
- `specs/` — especificaciones utilizadas como contrato antes de generar SQL.
- `informes/` — informes de consultas, joins y competencia de optimización.
- `duia/` — Declaración de Uso de IA de este TP.

## Artefactos

- [specs/spec_consultas_tp4.md](specs/spec_consultas_tp4.md)
- [sql/consultas_tp4_ia.sql](sql/consultas_tp4_ia.sql)
- [sql/consulta_a_tp4_alternativa.sql](sql/consulta_a_tp4_alternativa.sql)
- [sql/consulta_b_tp4_alternativa.sql](sql/consulta_b_tp4_alternativa.sql)
- [informes/informe_consultas_tp4.md](informes/informe_consultas_tp4.md)
- [informes/informe_optimizacion_joins_tp4.md](informes/informe_optimizacion_joins_tp4.md)
- [informes/lectura_critica_joins_tp4.md](informes/lectura_critica_joins_tp4.md)
- [informes/competencia_optimizacion_tp4.md](informes/competencia_optimizacion_tp4.md)
- [duia/duia_tp4.md](duia/duia_tp4.md)

## Clasificación de SQL

### Consultas principales

`sql/consultas_tp4_ia.sql` contiene las consultas principales
evaluadas para este TP.

### Consultas alternativas / experimentales

- `sql/consulta_a_tp4_alternativa.sql`
- `sql/consulta_b_tp4_alternativa.sql`

Son variantes utilizadas para comparación y optimización. No son
migraciones, no forman parte del esquema base y no deben ejecutarse
como una cadena de cambios estructurales.

## Base canónica

La base sigue definida por:

- [../../../schema.sql](../../../schema.sql)
- [../../../datos_iniciales.sql](../../../datos_iniciales.sql)

## Reproducción segura

1. Crear una base de laboratorio.
2. Aplicar `schema.sql`.
3. Aplicar `datos_iniciales.sql`.
4. Preparar el volumen de datos requerido por el ejercicio si corresponde.
5. Ejecutar las consultas principales.
6. Comparar contra las variantes.
7. Analizar los planes con `EXPLAIN ANALYZE`.

Los tiempos documentados en `informes/` son evidencia del entorno de
prueba en el que se midieron, no valores universales reproducibles de
forma idéntica en otro entorno.

## Evidencia

- `informe_consultas_tp4.md` — consultas principales y alternativas, con equivalencia verificada.
- `informe_optimizacion_joins_tp4.md` — optimización de JOIN medida con `EXPLAIN ANALYZE`.
- `lectura_critica_joins_tp4.md` — lectura crítica de planes de JOIN.
- `competencia_optimizacion_tp4.md` — competencia de optimización de la Parte 4.

Sus resultados no se reinterpretan acá; se conservan tal como fueron
medidos y documentados en su momento.

## Para un revisor / IA

1. Leer primero este README.
2. No tratar las consultas alternativas como migraciones.
3. Revisar `spec_consultas_tp4.md` antes de evaluar el SQL.
4. Preservar las mediciones históricas documentadas.
5. Consultar `duia/duia_tp4.md` para trazabilidad del uso de IA.
6. Verificar el schema real antes de proponer columnas o JOIN nuevos.
