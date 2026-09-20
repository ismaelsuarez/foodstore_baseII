# Unidad 1 — TP2

Trabajo de integridad, concurrencia, lectura crítica y protocolo de
seguridad sobre Food Store.

## Contenido

- `sql/` — scripts SQL de este TP.
- `specs/` — especificaciones utilizadas como contrato antes de generar SQL.
- `informes/` — informes y evidencia de los ejercicios realizados.
- `duia/` — Declaración de Uso de IA por cada parte del TP.

## Artefactos

- [specs/spec_restricciones.md](specs/spec_restricciones.md)
- [sql/restricciones_integridad.sql](sql/restricciones_integridad.sql)
- [informes/protocolo_seguridad.md](informes/protocolo_seguridad.md)
- [informes/informe_concurrencia.md](informes/informe_concurrencia.md)
- [informes/ejercicio_lectura_critica.md](informes/ejercicio_lectura_critica.md)
- [duia/duia_parte1.md](duia/duia_parte1.md)
- [duia/duia_parte2.md](duia/duia_parte2.md)
- [duia/duia_parte3.md](duia/duia_parte3.md)

## Estado del SQL

`sql/restricciones_integridad.sql` es evidencia histórica del ejercicio
de integridad. NO debe ejecutarse ciegamente sobre el `schema.sql`
actual porque esas restricciones ya se encuentran incorporadas en el
esquema base.

## Base canónica

La base actual del proyecto sigue definida en la raíz por:

- [../../../schema.sql](../../../schema.sql)
- [../../../datos_iniciales.sql](../../../datos_iniciales.sql)

## Seguridad

Los laboratorios se realizaron sobre copias de trabajo, utilizando
transacciones y `ROLLBACK` según el protocolo documentado en
`informes/protocolo_seguridad.md`.

## Para un revisor / IA

1. Leer primero este README.
2. No asumir que todo SQL es una migración pendiente.
3. Consultar las DUIA para distinguir lo generado por IA de las
   decisiones/verificaciones humanas.
4. No ejecutar scripts de laboratorio sobre una base importante.
5. Tratar los informes como evidencia histórica del ejercicio realizado.

