# TPI Food Store — Primera Entrega

## Objetivo y alcance

Esta carpeta integra la evidencia de las **Unidades 1, 2 y 3** y completa
los faltantes de la primera entrega, sin reemplazar ni reescribir los TPs
históricos. [schema.sql](../schema.sql) y
[datos_iniciales.sql](../datos_iniciales.sql) siguen siendo la base canónica.
Los objetos programables de `tpi/` son artefactos específicos del TPI.

**Integrantes:** Avalos Pablo, Blangetti Sofia y Suarez Ismael.

**Motor:** PostgreSQL 16+; cliente `psql`. El proyecto histórico documenta
PostgreSQL 17, sin convertir esa versión en requisito obligatorio del TPI.

**Lectura ampliada:** [Informe técnico](informe_tecnico.md).

## Mapa de cobertura

| # | Objetivo | Evidencia principal |
|---|----------|--------------------|
| 1 | Modelo ER: entidades, atributos, claves, cardinalidades y participación | [Diagrama y explicación](modelo/modelo_er.md) |
| 2 | ER → relacional: 1:N y N:M mediante tabla intermedia | [Modelo relacional](modelo/modelo_relacional.md) |
| 3 | DF, 1FN, 2FN, 3FN y FNBC/BCNF | [Normalización del modelo base](modelo/normalizacion.md) |
| 4 | DDL completo | [Esquema canónico](../schema.sql) |
| 5 | DML, JOIN, agregaciones, subconsultas, GROUP BY, HAVING y ventanas | [Carga inicial](../datos_iniciales.sql), [TP3](../unidades/unidad-2/tp3/sql/consultas_tp3_ia.sql), [RANK() de TP4](../unidades/unidad-2/tp4/sql/consultas_tp4_ia.sql), [HAVING del TPI](sql/consultas_cobertura_tpi.sql) |
| 6 | Vistas, función PL/pgSQL, procedimiento y CALL | [Vistas U3](../unidades/unidad-3/sql/views.sql), [objetos TPI](sql/objetos_programables.sql), [pruebas con CALL](pruebas/pruebas_objetos_programables.sql) |
| 7 | CHECK, UNIQUE, FK y trigger de negocio | [Constraints](../schema.sql), [función y trigger](sql/objetos_programables.sql), [pruebas](pruebas/pruebas_objetos_programables.sql) |
| 8 | COMMIT, ROLLBACK, aislamiento, concurrencia y atomicidad | [Concurrencia U1](../unidades/unidad-1/tp2/informes/informe_concurrencia.md), [protocolo](../unidades/unidad-1/tp2/informes/protocolo_seguridad.md), [atomicidad TPI](pruebas/pruebas_objetos_programables.sql) |
| 9 | Baja lógica y efecto sobre consultas e índices | [Vistas](../unidades/unidad-3/sql/views.sql), [índice parcial](../unidades/unidad-3/sql/indices.sql), [mediciones U3](../unidades/unidad-3/informes/informe_mediciones.md) |

## Reproducción en laboratorio

Comandos para **PowerShell desde la raíz del repositorio**, sobre una base
nueva y vacía. Ejecutar cada paso solamente si el anterior terminó sin error.
Si `foodstore_tpi` ya está preparada, no repetir su creación, carga ni
instalación: ejecutar solo las consultas o pruebas que se deseen verificar.

```powershell
createdb -U postgres foodstore_tpi
psql -U postgres -d foodstore_tpi -v ON_ERROR_STOP=1 -1 -f .\schema.sql
psql -U postgres -d foodstore_tpi -v ON_ERROR_STOP=1 -1 -f .\datos_iniciales.sql
psql -U postgres -d foodstore_tpi -v ON_ERROR_STOP=1 -1 -f .\tpi\sql\objetos_programables.sql
psql -U postgres -d foodstore_tpi -v ON_ERROR_STOP=1 -f .\tpi\pruebas\pruebas_objetos_programables.sql
psql -U postgres -d foodstore_tpi -v ON_ERROR_STOP=1 -f .\tpi\sql\consultas_cobertura_tpi.sql
```

La instalación usa `-1` para no dejar objetos parcialmente creados y
`CREATE` simple: falla si ya existen. La batería administra su propio
`BEGIN`/`ROLLBACK`, por eso no lleva `-1`. Revierte sus datos, no los objetos
previamente instalados; las secuencias pueden conservar huecos normales.
El DOWN está comentado en el SQL de objetos y **no se ejecuta automáticamente**.

Esta ruta reproduce la base y la integración TPI, no instala todas las
vistas ni reproduce los benchmarks históricos. Para esos laboratorios,
seguir los README de [TP2](../unidades/unidad-1/tp2/README.md),
[TP3](../unidades/unidad-2/tp3/README.md),
[TP4](../unidades/unidad-2/tp4/README.md) y
[Unidad 3](../unidades/unidad-3/README.md). No ejecutar todos los SQL en cadena.

## Verificaciones TPI realizadas

Resultados comunicados expresamente por el equipo para esta integración:
las pruebas fueron ejecutadas externamente mediante `psql` y revisadas
antes de versionar los archivos. No son ejecuciones de Codex ni una nueva
ejecución realizada al redactar estos documentos.

| Verificación | Resultado registrado |
|---|---|
| Consulta HAVING con `ON_ERROR_STOP=1` | Ana Gómez: **2 pedidos**; Luis Paz: **2 pedidos**. |
| Ensayo de instalación transaccional | `BEGIN` → `CREATE FUNCTION` → `CREATE TRIGGER` → `CREATE PROCEDURE` → `ROLLBACK`; **0 objetos TPI persistidos** tras revertir. |
| Instalación posterior en `foodstore_tpi` | Función y procedimiento instalados; trigger instalado y habilitado. |
| Batería de objetos | **13 grupos / 15 variantes**; todos los `PASS` alcanzados y `ROLLBACK` final ejecutado. |
| Limpieza y conservación de objetos | Categoría de prueba: **0**; cliente de prueba: **0**; función: **TRUE**; procedimiento: **TRUE**; trigger instalado y habilitado: **TRUE**. |

La batería prueba atomicidad en una sesión, **no dos CALL concurrentes**.
La evidencia multisesión permanece en el informe histórico de Unidad 1.

> Ejecutar los scripts de prueba únicamente sobre una base de laboratorio,
> sin escrituras concurrentes y nunca sobre una base importante.
