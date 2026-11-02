# POC de permisos — Unidad 5

Evidencia reproducible de la POC definida en [design.md §13](../specs/design.md#13-plan-técnico-de-la-poc-de-permisos).
La POC se ejecutó una vez, el 2026-11-02, en una instancia descartable que ya fue destruida.
Los resultados por caso, la contrastación de la matriz y las decisiones derivadas se registran en
[design.md §13.7](../specs/design.md#137-resultados-observados-2026-11-02). Esta carpeta
conserva los scripts y las salidas.

> La POC no instala nada en bases del proyecto ni de unidades anteriores. `run_poc.sh` crea un
> contenedor propio y su ejecución requiere autorización explícita (D14). Esta carpeta no es una
> migración y no forma parte de la instalación de U5.

## Entorno de la ejecución registrada

| Aspecto | Valor observado (`evidencia/corrida_final/00_instancia.txt`) |
|---|---|
| Instancia | Contenedor `foodstore_u5_poc`, `--network none`, acceso solo por `docker exec` |
| Imagen | `postgres:17`, `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3` |
| Servidor y cliente | PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2); `psql -X -v ON_ERROR_STOP=1` |
| Base | `foodstore_u5_poc`, única además de `postgres`, `template0` y `template1` |
| Instalación | `schema.sql` y `tpi/sql/objetos_programables.sql` con `-1`, sin modificar; sin seed |
| Autenticación | `trust` dentro del contenedor sin red; los roles de la POC no tienen contraseña |
| Destrucción | `docker rm -f -v` tras P8; el contenedor y su volumen anónimo no existen |

No se publicó ningún puerto. D14 pide un puerto distinto para no compartir una instancia; sin red,
el aislamiento es mayor.

## Contenido

| Ruta | Contenido |
|---|---|
| `run_poc.sh` | Arnés por pasos (`instancia`, `p0`, `p1`, `p2`, `p3p4`, `t12`, `p5`, `p6`, `t07`, `p7`, `p8`, `destruir`). Respecto del arnés ejecutado solo cambian `REPO_DIR` y `OUT`: las salidas nuevas van a `salidas_nueva_corrida/` (o a `$POC_OUT`) y no sobrescriben `evidencia/` |
| `sql/` | Scripts en el estado de la corrida final: guardas, IDs, funciones auxiliares `pg_temp`, inventario VP, huella, fixtures, roles y matriz, T12, API, pruebas, T07 y limpieza |
| `evidencia/corrida_final/` | Salida de cada paso de la corrida aceptada, huellas F0/F1, `t14_diff.txt`, `acl_tablas_f1.txt` y log del servidor |
| `evidencia/intentos_arnes/` | Salidas de los intentos con defectos del arnés y el script P6 original, sin cambios |
| `evidencia/arnes_ejecutado/run_poc.sh` | Arnés tal como se ejecutó, con las rutas de su ubicación original fuera del repositorio |

Formato de evidencia de las pruebas: `NOTICE: RESULT|<caso>|PASS/FAIL|esperado=… observado=…|<mensaje>`;
los errores se acompañan de `CONTEXT|<caso>|…` con la pila de llamadas. `OBSERVADO|…` registra un
resultado sin veredicto.

## Orden de ejecución registrado

`instancia` → `p0` → `p1` → `p2` (F0 y fixtures) → `p3p4` → `t12` → `p5` → `p6` → `t07` → `p7`
(F1 y diff) → `p8` → `destruir`. T12 se ejecuta entre P4 y P5 (design.md §13.3).

## Incidencias del arnés

No son fallos del producto. Las salidas originales se conservan sin editar en `evidencia/intentos_arnes/`.

| ID | Paso | Qué pasó | Corrección | Estado |
|---|---|---|---|---|
| A-1 | P2 (F0) | `huella.sql` concatenaba columnas `"char"` (`attidentity`, `tgenabled`) sin cast: `operator is not unique: text \|\| "char"`. El paso era de solo lectura y abortó antes de cargar fixtures | Se agregó `::text` en esas dos expresiones y se repitió P2. El `huella.sql` previo no se conservó como archivo; su única diferencia son esos dos casts | Corregido; salida original en `f0_huella_intento1_error_arnes.txt` |
| A-2 | P6 | 4 FAIL de aserción con valores observados correctos: `format('%s', boolean)` imprime `t`/`f` (T04.1_fila, T13.rol_propietario_atributos); `ORDER BY 1` dentro de `string_agg` ordena por una constante (T13.acl); la consulta de membresías incluía las de `pg_monitor` (T13.membresia_app_web) | Se corrigieron solo esas cuatro aserciones y se repitió P6, que no deja estado: **66/66 PASS** | Corregido; `07_pruebas_intento1.sql` y `07_pruebas_intento1.txt` conservan el original (89 PASS / 4 FAIL contando T12 y T07) |
| A-3 | P8 | `P8.membresias` FAIL (esperado 0, observado 3): mismo defecto que A-2. Las 3 filas son las membresías predefinidas de `pg_monitor`, presentes desde P0 (VP-10 en `01_p0_inventario.txt`) | **No se repitió**: la instancia ya estaba destruida | Abierto como límite. La ausencia de residuos se sostiene en `P8.roles`, `P8.api` y la guarda sin roles posterior al DROP; la aserción de membresías queda sin comprobación corregida |

## Excepción de espacios finales

Las salidas de `psql` en `evidencia/` conservan los espacios finales que genera el formato
alineado de las tablas y la línea en blanco que `psql` escribe después de `(N rows)` al final del
archivo. `git diff --check` los informa como `trailing whitespace` y `new blank line at EOF`. Al
versionarlas (2026-11-02) hubo 375 avisos de espacios finales en 11 archivos y 7 de línea en
blanco final, todos en `.txt` de `evidencia/`. Son parte de la evidencia original y no se
eliminan. La excepción vale solo para los archivos `.txt` de salida
de `psql` dentro de `evidencia/`. Un aviso en cualquier otro archivo sí es un defecto.

## Revisión de información sensible

Se revisaron todos los archivos antes de incorporarlos al repositorio. No contienen rutas
personales, correos reales, contraseñas ni hashes. Los correos `poc.u*@ejemplo.test` y el marcador
`POC_SIN_CREDENCIAL` son sintéticos. `servidor.log` incluye el texto genérico con el que la imagen
oficial advierte sobre `POSTGRES_HOST_AUTH_METHOD=trust`; ese texto menciona `POSTGRES_PASSWORD`,
pero no es una credencial. El identificador del contenedor y el digest de la imagen se conservan
como datos de trazabilidad. No fue necesario anonimizar nada, y la evidencia no se editó.
