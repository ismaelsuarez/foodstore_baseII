# Unidad 2 — TP3

Trabajo sobre generación de volumen de datos, consultas, variantes de
consulta, EXPLAIN ANALYZE y optimización sobre Food Store.

## Contenido

- `sql/` — scripts SQL de este TP.
- `specs/` — especificaciones utilizadas como contrato antes de generar SQL.
- `informes/` — informes de optimización y consultas.
- `duia/` — Declaración de Uso de IA de este TP.

## Artefactos

- [specs/spec_consultas_tp3.md](specs/spec_consultas_tp3.md)
- [sql/carga_masiva_tp3.sql](sql/carga_masiva_tp3.sql)
- [sql/consultas_tp3_ia.sql](sql/consultas_tp3_ia.sql)
- [sql/consultas_tp3_alternativas.sql](sql/consultas_tp3_alternativas.sql)
- [sql/consulta_a_alternativa.sql](sql/consulta_a_alternativa.sql)
- [sql/consulta_b_correlacionada_optimizada.sql](sql/consulta_b_correlacionada_optimizada.sql)
- [informes/informe_consultas_tp3.md](informes/informe_consultas_tp3.md)
- [informes/informe_optimizacion_tp3.md](informes/informe_optimizacion_tp3.md)
- [informes/lectura_critica_plan_tp3.md](informes/lectura_critica_plan_tp3.md)
- [duia/duia_tp3.md](duia/duia_tp3.md)

## Clasificación de SQL

### Dataset

`sql/carga_masiva_tp3.sql` se utiliza para generar volumen de
laboratorio. No forma parte del esquema base.

### Consultas principales

`sql/consultas_tp3_ia.sql`

### Consultas alternativas / experimentales

- `sql/consultas_tp3_alternativas.sql`
- `sql/consulta_a_alternativa.sql`
- `sql/consulta_b_correlacionada_optimizada.sql`

Son consultas para comparación y medición. No son migraciones.

## Base canónica

La base del proyecto se crea desde la raíz con:

- [../../../schema.sql](../../../schema.sql)
- [../../../datos_iniciales.sql](../../../datos_iniciales.sql)

## Reproducción segura

1. Crear una base de laboratorio.
2. Ejecutar `schema.sql`.
3. Ejecutar `datos_iniciales.sql`.
4. Ejecutar `sql/carga_masiva_tp3.sql` si se necesita reproducir el
   volumen usado para rendimiento.
5. `ANALYZE` cuando corresponda.
6. Ejecutar las consultas de lectura/medición.

Los tiempos de `EXPLAIN ANALYZE` documentados en `informes/` dependen
del hardware, la caché, la versión de PostgreSQL y el estado de la
base en el momento de la medición — no deben tomarse como valores
universales reproducibles de forma idéntica.

## Dependencia posterior

Unidad 3 reutiliza `sql/carga_masiva_tp3.sql` como dataset para sus
benchmarks. Debe existir una única copia canónica, ubicada en este directorio; Unidad
3 no debe duplicar este archivo.

## Para un revisor / IA

1. Leer este README antes de interpretar los SQL.
2. No tratar `carga_masiva_tp3.sql` como parte del esquema base.
3. No asumir que las variantes alternativas son migraciones.
4. Preservar los resultados históricos de `EXPLAIN ANALYZE`.
5. Consultar `duia/duia_tp3.md` para trazabilidad del uso de IA.
6. No inventar columnas que no existan en `schema.sql`.

