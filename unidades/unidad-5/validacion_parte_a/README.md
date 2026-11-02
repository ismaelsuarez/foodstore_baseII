# Validación integral de la Parte A — evidencias

Evidencia de la ejecución de `unidades/unidad-5/sql/` en laboratorio. Resultados consolidados
en [`design.md` §15](../specs/design.md). Cada carpeta es una corrida identificada por su hora
UTC de inicio. Su contenido se conserva tal como se capturó: no se editó ni se reemplazó.

| Corrida | Instancias | Alcance | Resultado | Informe |
|---|---|---|---|---|
| `20261102T185421Z` | `foodstore_u5_validacion_a` | Primera validación integral | BLOCKED antes de ejecutar SQL (control del arnés de captura) | `20261102T185421Z/README.md` |
| `20261102T190345Z` | `foodstore_u5_validacion_a` | Validación integral, arnés corregido | 207 RESULT PASS / 0 FAIL; TPI 29/37/30, exit 0; SEC-01, 04 y 17 parciales | `20261102T190345Z/README.md` |
| `20261102T191848Z` | `foodstore_u5_m04`, `foodstore_u5_m05` | M04, M05, SCRAM y revisión SEC-04 | M04, M05 y SCRAM PASS; SEC-04 en aceptación provisional | `20261102T191848Z/CIERRE_OBSERVADO.md` |

Todas las instancias usaron la imagen `postgres:17`
(`sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`, PostgreSQL 17.11),
`--network none`, ningún puerto publicado y el repositorio montado en solo lectura. Se
destruyeron con su volumen después de capturar la evidencia. Los contenedores preexistentes de
otros proyectos no se tocaron: cada corrida compara `docker ps -a` antes y después.

Cada corrida guarda el sha256 de los fuentes ejecutados antes y después, y la corrida
`20261102T191848Z` comprueba que las dos anteriores siguen byte a byte iguales.

## Incidencias del arnés

Las incidencias de los scripts de captura (`ejecutar_*.py`) se conservan junto con su
diagnóstico y el diff de la corrección: el control de arranque de la primera corrida y una
secuencia de escape de Python, detectada antes de crear contenedores, en la tercera. Ninguna
fue un fallo del producto, y ninguna llevó a modificar archivos de `unidades/unidad-5/sql/`.

## Credenciales

Las contraseñas sintéticas se generaron en memoria, viajaron solo por variables de entorno y se
borraron al terminar. Cada corrida verificó con `grep -F`, sobre los valores exactos, que no
aparecen en logs ni en evidencias. Los únicos textos parecidos son los comandos grep, que
contienen nombres de variables y no valores.

## Excepción de espacios finales

Las salidas crudas de `psql` (`*.txt`) conservan los espacios finales que genera el formato
alineado de las tablas, y algunas terminan con una línea en blanco después de `(N rows)`.
`git diff --check` los informa como `trailing whitespace` y `new blank line at EOF`. Al
versionar se contaron 483 líneas con espacios finales en 28 archivos de `20261102T190345Z` y
3441 líneas en 52 archivos de `20261102T191848Z`, todas en archivos `.txt` de salida. Son parte
de la evidencia original y no se eliminan. Un aviso en cualquier otro tipo de archivo sí es un
defecto.
