# Bitácora de uso de IA — Unidad 5: Administración y Seguridad de Food Store

Registro de prompts relevantes, respuestas de la IA y validaciones humanas (design.md §11).
Solo incluye interacciones verificables en el registro de prompts de la herramienta, en el
historial de Git o en las evidencias del repositorio. La responsabilidad final de las
propuestas, pruebas y decisiones pertenece al equipo.

| Parte | Estado |
|---|---|
| A — Roles y permisos | Implementada y validada en laboratorio; SEC-04 pendiente de aceptación formal del equipo |
| B — Auditoría | **Pendiente**: sin interacciones registradas |
| C — Simulacro de incidente | **Pendiente**: sin interacciones registradas; el mecanismo de §7.3 sigue sin elegir |
| D — Anonimización | **Pendiente**: sin interacciones registradas |

## Herramientas

| Etapa | Herramienta |
|---|---|
| Especificaciones iniciales (commit `edf3c3f`) | Kiro |
| Auditoría, diseño, POC, implementación y validación de la Parte A (2026-10-25 a 2026-11-02) | Claude Code, modelo Claude Opus 5.5 (`claude-opus-5-5`), autorizado por la cátedra como reemplazo de OpenCode. Parte del trabajo lo hicieron subagentes de escritura y de verificación lanzados desde la misma sesión; no se registró su modelo exacto |
| Motor de laboratorio | PostgreSQL 17.11 en contenedores descartables (`postgres:17`) |

## Parte A — Prompts y respuestas

Los textos largos se identifican por su título. El texto completo está en el registro de prompts
de la herramienta; no se reconstruye aquí.

| Fecha | Prompt | Respuesta de la IA | Validación humana |
|---|---|---|---|
| 2026-10-25 20:58 | «Realizá una auditoría técnica integral de este repositorio» | Auditoría de solo lectura: la Primera Entrega del TPI ya estaba cerrada; `psql` no estaba instalado en la estación | Base para las etapas siguientes |
| 2026-10-25 21:06 | «Food Store — Unidad 5 — Análisis de brechas» | Matriz de cumplimiento A–E: sin artefactos de U5; objetos del material de clase inexistentes en el repositorio | — |
| 2026-10-25 21:17 | «Food Store — Unidad 5 — Diseño de seguridad previo a la implementación» | Propuesta de diseño con las decisiones D1–D3 | — |
| 2026-10-25 21:34 | «Food Store — TP5 — Ajustes finales de arquitectura» | Revisiones propuestas: esquema `reportes`, `search_path` fijo, prevención de contraseñas en logs, privilegios de `admin_datos` | Aceptación conceptual de D1–D3, solo para diseño |
| 2026-10-26 12:59 | «Food Store — Unidad 5 — Cierre de arquitectura y preparación de POC» | Corrección de specs, matriz mínima, plan de POC (§13) e inventario VP (§14); sin ejecutar SQL | — |
| 2026-10-26 13:32 | «Apruebo D14, D15, D16, D17 y D18» | — | Aprobación de cinco decisiones |
| 2026-10-26 13:36 | «Sí, autorizo la POC en la instancia descartable» | — | Autorización de la POC |
| 2026-11-02 13:21 | Consulta del estado del trabajo | Resumen: specs sin commitear; POC autorizada y sin ejecutar | — |
| 2026-11-02 | «Si por favor» (iniciar la POC) | POC ejecutada en un contenedor descartable: T01–T14 PASS, 23/23 ablaciones | Elección de la carpeta de salidas fuera del repositorio |
| 2026-11-02 | Consulta sobre si el prompt del 26/10 quedó resuelto | Verificación entregable por entregable: resuelto; decisiones abiertas | — |
| 2026-11-02 | «Food Store — Unidad 5 — Consolidación documental de POC» | §13.7 en design.md, corrección D-1 a D-4, evidencia en `poc_permisos/` | Aceptación de la consolidación |
| 2026-11-02 | «Food Store — Unidad 5 — Cierre documental y versionado de la POC» | Commits `165e3d7` y `68689db` | Autorización de los dos commits y, por separado, del push |
| 2026-11-02 | «Food Store — Unidad 5 — Implementación controlada de la Parte A» | `roles.sql`, `funciones_seguridad.sql`, precondiciones y 23 archivos de pruebas, sin ejecutar; primera auditoría independiente: FAIL estático por dos bloqueos, corregidos | Aprobación de D6 y de D11 (`UPDATE (celular)`) |
| 2026-11-02 | «Food Store — Unidad 5 — Cierre estático de implementación Parte A» | Resolución de siete puntos; segunda auditoría: 13 PASS y C11 FAIL, corregido | Aceptación documental de C11 sin tercera auditoría |
| 2026-11-02 | «Food Store — Unidad 5 — Validación integral de la Parte A» | Corrida 1 BLOCKED por el arnés antes de SQL; corrida 2: 207 PASS / 0 FAIL, TPI 29/37/30 | Autorización de contenedores descartables |
| 2026-11-02 | «Food Store — Unidad 5 — Cierre experimental de la Parte A» | M04, M05 y SCRAM PASS; revisión de SEC-04 | Aceptación provisional del uso académico de datos sintéticos y agregados para SEC-04 |
| 2026-11-02 | «Food Store — Unidad 5 — Consolidación y commits de Parte A» | Esta bitácora, la exportación de specs, la actualización de §15 y cuatro commits | Pendiente: revisión de este cierre y autorización del push |

El registro también contiene un mensaje automático de la herramienta del 2026-10-26 13:31, que
avisa que se restableció el límite de uso. No es un prompt del equipo.

## Parte A — Errores e imprecisiones detectados

| Origen | Error o imprecisión | Cómo se detectó | Tratamiento |
|---|---|---|---|
| Specs iniciales | Interpretación errónea de SECURITY DEFINER → INVOKER y de los triggers; afirmación incorrecta sobre EXECUTE en PostgreSQL 15 | Revisión técnica del 26/10 | Corregido en design.md §5.0 y §3.2 |
| Plan de POC propuesto por la IA | T03 decía «once casos» y enumeraba diez; T11 usaba `LIKE`, que exige SELECT; T12 quedaba después de P5; T14 omitía diferencias esperadas | Escritura y ejecución de la POC | Correcciones D-1 a D-4 (design.md §13.7.4) |
| Arnés de la POC | Concatenación de `"char"` sin cast; cuatro aserciones mal formuladas; aserción de membresías sin filtrar (A-1 a A-3) | Errores y FAIL con valores observados correctos | Corregidos y repetidos sin estado; A-3 quedó como límite y se resolvió en la validación integral |
| Guarda de pruebas escrita por la IA | `\quit 3` no detenía la ejecución: en psql 17, dentro de un archivo incluido, solo termina ese archivo | Primera auditoría independiente, confirmada con la documentación de psql 17 | Reemplazado por `RAISE EXCEPTION` bajo `ON_ERROR_STOP` |
| Guardas de CREATE escritas por la IA | Falso positivo sobre el esquema temporal de la sesión, que PostgreSQL 17 concede a quien tiene TEMP | Primera auditoría, confirmada con `aclchk.c` de PostgreSQL 17 | Exclusión de `pg_my_temp_schema()` |
| Documentación de la IA | El procedimiento RR-07 permitía crear funciones; quedaban afirmaciones de equivalencia temporal no acreditada | Segunda auditoría (C11) | El procedimiento se detiene ante una función ausente; textos matizados |
| Informe de la IA | Un valor de `proconfig` presentado como «observado» cuando lo observado era `array_to_string`; un conteo de 382 avisos cuando eran 375 | Relectura antes de entregar | Corregido antes del commit |
| Consigna de la IA a un subagente | Pidió «sin privilegios más allá de CONNECT vía PUBLIC», imposible conservando D9 | El subagente preguntó antes de ejecutar | Aclarado: sin GRANT directos ni membresías, con los permisos heredados registrados |
| Arnés de captura de la validación | Control de arranque con `readlink /proc/1/exe` defectuoso; secuencia de escape inválida en Python | Abortos antes de ejecutar SQL | Conservados con su diagnóstico; corrida nueva con el arnés corregido |

## Parte A — Validaciones humanas

- Aprobación de D1–D3 (diseño) y de D14–D18 (2026-10-26).
- Autorización separada de la POC (2026-10-26) y orden de inicio (2026-11-02).
- Aceptación de la consolidación de la POC y autorización de los commits `165e3d7` y `68689db`
  y de su publicación.
- Aprobación de D6 y D11 para la implementación de laboratorio (2026-11-02).
- Aceptación documental de las correcciones de C11 (2026-11-02).
- Autorización de las validaciones en contenedores descartables (2026-11-02).
- Aceptación provisional del uso académico de datos sintéticos y agregados para SEC-04
  (2026-11-02). **La aceptación formal del equipo sigue pendiente.**
- Pendientes: D4, D8 (resto), D9 y el mecanismo de auditoría de §7.3.

## Parte A — Resultados

Ver [design.md §13.7](unidades/unidad-5/specs/design.md) (POC) y
[§15](unidades/unidad-5/specs/design.md) (validación integral). Las evidencias están en
`unidades/unidad-5/poc_permisos/` y `unidades/unidad-5/validacion_parte_a/`.

## Partes B, C y D

Pendientes. Se registrarán aquí cuando se trabajen.
