# Insumos para BITACORA.md — POC de permisos (Parte A)

Material preparado para que el equipo redacte `BITACORA.md`, que va en la raíz del repositorio
(design.md §11). Este archivo no es la bitácora. La redacción final, la selección de prompts y
la validación pertenecen al equipo.

## Herramientas

| Etapa | Herramienta |
|---|---|
| Especificaciones iniciales (commit `edf3c3f`) | Kiro, según el prompt del 2026-10-26 12:59 |
| Revisión de la Parte A, POC y consolidación (2026-10-25 a 2026-11-02) | Claude Code, modelo Claude Opus 5.5 (`claude-opus-5-5`), autorizado por la cátedra como reemplazo de OpenCode |
| Motor de la POC | PostgreSQL 17.11 en contenedor descartable (`postgres:17`) |

## Prompts registrados

Fuente: registro de prompts de la sesión de Claude Code. Los textos largos se identifican por su
título. Para la bitácora hay que copiarlos completos desde el registro original, no reconstruirlos.

| Fecha y hora | Prompt | Tipo |
|---|---|---|
| 2026-10-25 20:58 | «Repositorio objetivo … Realizá una auditoría técnica integral de este repositorio» | Auditoría (solo lectura) |
| 2026-10-25 21:06 | «Food Store — Unidad 5 — Análisis de brechas» | Análisis (solo lectura) |
| 2026-10-25 21:17 | «Food Store — Unidad 5 — Diseño de seguridad previo a la implementación» | Diseño |
| 2026-10-25 21:34 | «Food Store — TP5 — Ajustes finales de arquitectura» | Revisión de D1–D3 |
| 2026-10-26 12:59 | «Food Store — Unidad 5 — Cierre de arquitectura y preparación de POC» | Corrección de specs y plan de POC |
| 2026-10-26 13:32 | «Apruebo D14, D15, D16, D17 y D18» | Validación humana |
| 2026-10-26 13:36 | «Sí, autorizo la POC en la instancia descartable» | Autorización humana |
| 2026-11-02 13:21 | «Hola, que fue lo ultimo realizado y que se esta trabajandi» | Consulta de estado |
| 2026-11-02 | «Si por favor» (respuesta a «¿Querés que arranquemos por la POC?») | Inicio de la ejecución |
| 2026-11-02 | Opción «Carpeta hermana del repo» para las salidas | Decisión humana |
| 2026-11-02 | «Consulta este fue el ultimo prompt que se envio, esto quedo todo resuelto: …» | Verificación del cierre del prompt del 2026-10-26 |
| 2026-11-02 | «Food Store — Unidad 5 — Consolidación documental de POC» | Consolidación documental |

El registro también contiene un mensaje automático de la herramienta del 2026-10-26 13:31, que
avisa que se restableció el límite de uso. No es un prompt del equipo.

## Resultados

- POC ejecutada una vez (2026-11-02). Casos T01–T14: PASS; T11 por la variante corregida y T14
  con su resultado esperado corregido.
- P6: 66/66 PASS en la corrida aceptada. T07: 23/23 ablaciones con 42501.
- D11 comprobada: `FOR SHARE` sobre `usuario` exige UPDATE sobre alguna columna, y
  `UPDATE (celular)` es necesario en la matriz propuesta. La columna sigue pendiente de aprobación.
- Instancia destruida. P8 sin roles ni API residuales, con el límite A-3.
- Detalle en `design.md` §13.7; evidencia en `evidencia/`.

## Errores e imprecisiones detectados

Casos para cumplir el requisito de registrar al menos un error o imprecisión de la IA:

| Origen | Error | Cómo se detectó | Tratamiento |
|---|---|---|---|
| Plan de POC propuesto por la IA (§13.5) | T03 decía «once casos» y enumeraba diez (D-1) | Al escribir los scripts | Corregido en el plan |
| Plan de POC | T11 usaba `LIKE public.producto`, que falla por falta de SELECT y no prueba lo que dice (D-2) | En la ejecución: 42501 `permission denied for table producto` | Variante con columnas explícitas; literal registrado como observación |
| Plan de POC | T12 quedaba después de P5, donde fallaría por duplicado (D-3) | Al ordenar los pasos | Paso P4b |
| Plan de POC | El resultado esperado de T14 omitía la API nueva y el ACL de `public` (D-4) | En el diff F0/F1 | Criterio corregido |
| Arnés escrito por la IA | Concatenación de `"char"` sin cast (A-1) | Error de PostgreSQL en P2 | Corregido y repetido |
| Arnés | 4 aserciones mal formuladas (A-2) | FAIL con valores observados correctos | Corregidas; P6 repetido: 66/66 |
| Arnés | Aserción de membresías sin filtrar (A-3) | FAIL en P8 | No repetido (instancia destruida); queda como límite |
| Informe externo | Valores de VP-06, VP-07, VP-08 y VP-11 redactados antes de leer esa parte de la salida | Revisión durante la consolidación | Verificados contra la evidencia: coinciden |
| Consolidación | Un valor de `proconfig` escrito como literal de arreglo «observado», cuando lo observado fue `array_to_string` | Relectura antes de entregar | Corregido en design.md |
| Specs anteriores (revisión del 2026-10-26) | Interpretación errónea de SECURITY DEFINER → INVOKER y de los triggers; afirmación incorrecta sobre PostgreSQL 15 y EXECUTE | Revisión técnica | Corregido en design.md §5.0 y §3.2 |

## Validación humana

- Aprobación de D1–D3 (diseño) y de D14–D18 (2026-10-26).
- Autorización separada para ejecutar la POC (2026-10-26) y orden de inicio (2026-11-02).
- Elección de la ubicación de las salidas (2026-11-02).
- Aceptación de la consolidación documental antes del siguiente commit (2026-11-02).
- **Pendiente:** revisión humana de esta consolidación y aprobación de D4, D6, D8 (resto), D9
  y la columna de D11.
