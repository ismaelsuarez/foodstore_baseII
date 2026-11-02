# Food Store — Unidad 5 — Cierre experimental de la Parte A

Fecha UTC: 2026-11-02T19:27:22.754723+00:00

Instancias dedicadas: foodstore_u5_m04 y foodstore_u5_m05; imagen local sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3; PostgreSQL 17.11, red none, sin puertos, repo ro. Versiones/settings/IDs/volúmenes y comandos completos en cada subcarpeta.

## Resultados observados

- **M04_catalogo**: PASS
- **M04**: PASS: terminación real y ROLLBACK de control distintos; catálogo/ACL/owners intactos
- **M05**: PASS: 207 RESULT, mismos casos/veredictos/detalles y multiplicidades
- **SEC04**: aceptación provisional — pendiente de aceptación formal del equipo
- **SCRAM_cliente**: PASS
- **SCRAM**: PASS: require_auth=scram-sha-256, válida y 28P01 incorrecta; cero fugas exactas

## M04: mecanismo y evidencia

Instalación canónica/dependencias/pgcrypto/precondiciones/roles; stream literal de funciones_seguridad.sql con la única línea COMMIT retenida. SHA-256, línea retenida y conteo exacto en m04/stream_identidad.json; payload público en stream_original_sin_commit.txt. Catálogo propio acredita las tres funciones dentro de la transacción; segunda conexión acredita invisibilidad externa e idle in transaction. pg_terminate_backend desde esa segunda conexión interrumpe realmente al instalador. SELECT 1 posterior solo fuerza al cliente a leer el FATAL: NO se envía ROLLBACK en esa rama. Tercera conexión acredita cero funciones/ACL y catálogo anterior idéntico, incluyendo D3, tablas, columnas, owners, membresías y ADP. Control separado: mismo stream, ROLLBACK explícito, exit 0. Se activa SET LOCAL log_statement=all únicamente DESPUÉS del DDL del control, para registrar su ROLLBACK; vuelve a mod al revertirse. Logs de PID y diagnósticos en m04/85_log_interrupcion_vs_rollback.txt y raw. No se modificó el instalador ni se reemplaza una interrupción por rollback normal.

## M05: comparación con 20261102T190345Z

Mismo orden y scripts: schema -1, seed, objetos -1, TPI baseline/HAVING, vistas U3, materializada con índice propio, pgcrypto, precondiciones → F0 → roles → funciones → F1 → 10 → 11 → 16 → 12 → 20 → 30 → 40 → 49 → 50/51 reales por socket → M06 → 52 → 99 → huella final → TPI/HAVING posterior → inventario. 13/14/15 solo desde sus llamantes. La sesión conserva F0; 0 por paso compartido significa completado bajo ON_ERROR_STOP, exit real en control_session_exit.txt. Comparación por caso/veredicto/detalle/multiplicidad en m05/comparacion_caso_a_caso.tsv y comparacion_RESULT.json; TPI y huellas en comparacion_fingerprints_y_TPI.json. Se normalizan espacios finales/líneas vacías y transporte de NOTICE, no campos semánticos de huella. No se exige igualdad de timestamps, PIDs, OIDs, IDs de contenedor o huecos de secuencia. Esas identidades nuevas de instancia son diferencias de entorno, no defectos de producto. Cualquier diferencia real de catálogo/caso queda explícita en los JSON/diff; no se arregla ni se repite.

## SCRAM y credenciales

Reglas loopback explícitas antepuestas, pg_reload_conf y catálogo sin errores; password_encryption=scram-sha-256. Password aleatoria del shell, verificador calculado en cliente mediante PBKDF2-HMAC-SHA256/4096, salt aleatorio, StoredKey y ServerKey; nunca persistidos. Asignación en sesión superusuario con log_statement=none y log_min_error_statement=panic; el template contiene getenv/interpolación del verificador pero nunca su valor. Se imprime exclusivamente prefijo SCRAM-SHA-256$. La supresión es de ESA sesión, no global, porque mod registraría el DDL sensible. Conexión válida y contraseña incorrecta por TCP 127.0.0.1, require_auth=scram-sha-256 explícito. El servidor usa log_error_verbosity=verbose para acreditar 28P01; extractos en m05/86_scram_method_and_sqlstate.txt. TLS desactivado solo en loopback aislado; SCRAM no implica cifrado de todo el tráfico ni habilitación productiva.

Aclaración aprobada por el padre (opción A): tst_u5_scram no recibe GRANT directos ni membresías; conserva los defaults de PUBLIC, incluidos CONNECT, TEMPORARY, USAGE public y EXECUTE pgcrypto. No se modifica PUBLIC ni D9. Privilegios efectivos y ausencia de grants/membresías en scram/05_privilegios_catalogo.txt. DROP y ausencia en scram/08_drop_role.txt. Autenticación PostgreSQL SCRAM es distinta de fn_autenticar/usuario.contrasena bcrypt, cubierta por 40/SEC-18 en M05.

## SEC-04 / M03

**aceptación provisional — pendiente de aceptación formal del equipo**. Texto literal: «La revisión humana acepta provisionalmente el uso académico de datos sintéticos y agregados, pero no autoriza exposición de datos personales reales.» Inventario efectivo has_table_privilege sobre TODAS las relaciones, columnas/definiciones y cohortes por categoría/mes en sec04/. Riesgos de cohortes pequeñas, cruces y diferencias temporales; condiciones de aceptación en sec04/README.md. No se declara PASS de M03.

## SEC-01..SEC-20: cambio respecto de la primera instalación

| SEC | Estado/actualización |
|---|---|
| 01 | PASS si M05=PASS: segunda instalación limpia ejecutada; P/N/R antes pendientes de M05 ahora cubiertos |
| 02 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 03 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 04 | aceptación provisional — pendiente de aceptación formal del equipo; SQL de permisos PASS según M05 |
| 05 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 06 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 07 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 08 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 09 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 10 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 11 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 12 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 13 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 14 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 15 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 16 | PASS del intervalo si scans limpios: M05 con bind y SCRAM adicional; sin garantía universal |
| 17 | PASS si M04=PASS y M05=PASS: endurecimiento, suplantación y ahora interrupción real/control observados |
| 18 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 19 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |
| 20 | PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato |

Los condicionales de la tabla deben leerse junto a los estados realmente observados arriba; un paso BLOCKED/FAIL no queda convertido en PASS por la plantilla. Los RESULT originales y sus conteos son la autoridad. TPI esperado y comparado: 29 grupos/37 variantes/30 NOTICE PASS, exit 0, antes y después; P0099 solo en su prueba de atomicidad. P8 esperado y comparado: U5=3, efímeras=0, EXCEPT=0, post-COMMIT=3; 15/52/99 vuelven a acreditar limpieza.

## Auditoría, fallos y cleanup

Logs de servidor copiados solo tras scan dentro del contenedor y escaneados otra vez en host con grep -F de passwords exactas, verificador exacto, bcrypt y PASSWORD literal. No se entregan coincidencias sensibles. Todos los archivos nuevos, incluido este README, se escanean contra todos los secretos exactos antes de limpiar el entorno. Permisos SO de log 0600. Confirmación de captura antes de cada docker rm -f -v; ausencia de contenedor/volúmenes en 93_cleanup_verification.txt. Inventario Docker previo/posterior y manifiestos SHA-256 de ambos intentos previos y fuentes SQL deben coincidir; archivos de verificación en raíz. Un BLOCKED_o_fallo o BLOCKED_global debe preservarse y prevalece sobre expectativas. No se corrige producto/test ni se oculta un fallo.

TDD OFF por autorización de integración: RED/GREEN no activos. Sin commits, staging, push, merge, cambios en SQL/specs/históricos/odd ni configuración externa. No se acreditan tiempos bcrypt equivalentes, concurrencia de reset, estrés ni anonimización universal. Detenido al concluir; esperar revisión humana.
