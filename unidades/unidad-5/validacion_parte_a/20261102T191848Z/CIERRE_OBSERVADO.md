# Cierre observado — 2026-11-02 UTC

Complemento de resultados concretos del [README](README.md), sin modificar el
informe automático ni las salidas originales. **Etapa experimental ejecutada;
M03/SEC-04 NO es PASS: aceptación provisional, pendiente de aceptación formal.**
No se encontró ningún defecto del producto en los ensayos realizados.

## Instancias

Ambas usaron PostgreSQL 17.11, imagen local `postgres:17`, digest
`sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`,
`--pull=never`, `--network none`, sin puertos publicados y repositorio `/repo:ro`.
La base fue `foodstore_tpi_oficial`, exclusivamente dentro de cada clúster nuevo.

| Caso | Contenedor | ID | Volumen anónimo |
|---|---|---|---|
| M04 | foodstore_u5_m04 | 69c75a52b257f7c891a0d58895ddb8f05146ad95bc794510d5c58cce0041d1f3 | e360c44e58914e64b30b08e3a7d65103619fdaf338e794cb9f1fb6413f65369f |
| M05/SCRAM | foodstore_u5_m05 | 57754d1deec1203adb8138720eac5d246904642f23629e900c7af3590388a836 | cafdb64f3f7fd985c4a5ce630433c726c93139de1370270874324e4b8041bea0 |

Los dos nombres estaban libres antes de crear. Versiones, settings, mounts y
sondeos individuales están en `m04/01_*` y `m05/01_*`. Ninguna conexión se dirigió
al host ni a un contenedor preexistente.

## M04 — PASS, interrupción real y control diferentes

Se instaló schema → seed → objetos → vistas U3 → materializada/índice propio →
pgcrypto → precondiciones → roles. No se cambió ningún archivo SQL original.

Fuente: `unidades/unidad-5/sql/funciones_seguridad.sql`:
- SHA-256: `ea4de4ae43ca0941d8be7584e535196c4e309b111981d7c90a80c76ccacbd0e4`.
- 186 líneas originales; se enviaron **185 líneas originales por rama**, todas
  literalmente, reteniendo únicamente `COMMIT;` de la línea **185**.
- El stream conservado tiene SHA-256
  `dccf374d8a2307268236121172beb59ef7906354a6e1d53120f010486b8392a2`.
- Metacomandos de delimitación, consultas de observación y SELECT 1 de detección
  del FATAL son adicionales y están distinguidos del stream original.

El instalador veía sus tres funciones y ACL/propietarios dentro de su transacción.
La segunda conexión observó las tres firmas NULL, cero funciones/ACL externas y
backend **161**, estado **idle in transaction**, xid **751**. Desde esa misma
segunda conexión se ejecutó `pg_terminate_backend`; no ROLLBACK del instalador.
El cliente, al intentar SELECT 1 para procesar el mensaje asíncrono, terminó con
**exit 2** y FATAL. Este SELECT no reinstala ni confirma nada.

Log del servidor, literal:

```text
2026-11-02 19:27:13.676 UTC [161] u5_m04_terminate postgres@foodstore_tpi_oficial FATAL:  57P01: terminating connection due to administrator command
```

La tercera conexión comprobó nuevamente firmas ausentes y cero ACL U5. El
snapshot completo anterior/posterior fue idéntico: siete rutinas canónicas,
definiciones, propietarios, ACL D3, relaciones/columnas, esquemas, membresías y
ADP. No quedó instalada ninguna de las tres funciones nuevas ni un cambio de
privilegio no confirmado. No hubo un statement ROLLBACK en el log del PID 161.

Control separado, no repetición para ocultar fallo: stream equivalente en backend
**189**, invisibilidad externa también comprobada y **ROLLBACK explícito**, con
**exit 0**, funciones ausentes y snapshot idéntico. Para distinguirlo en el log se
usó `SET LOCAL log_statement='all'` DESPUÉS de todo el DDL del control; se revierte
junto con la transacción. No había credenciales en esa sesión.

```text
2026-11-02 19:27:14.051 UTC [189] u5_m04_rollback postgres@foodstore_tpi_oficial LOG:  00000: statement: ROLLBACK;
```

Evidencias: `m04/stream_identidad.json`, `30/31/32/33/34/35_*`,
`36_tercera_conexion_ausencia.txt`, snapshots `20/37/46_*`,
`43_control_rollback.txt`, `44_control_exit.txt`,
`85_log_interrupcion_vs_rollback.txt`, `resultado_transacciones.json`.

## M05 — PASS, segunda instalación limpia

Se repitió íntegramente el orden documentado de la corrida `20261102T190345Z`,
con una sola sesión superusuario conservando F0/IDs hasta el cierre. Todos los
archivos SQL completaron sin error. El exit real de esa sesión fue **0**;
los ceros individuales de pasos compartidos significan terminación bajo
ON_ERROR_STOP, no procesos psql independientes.

- **207 RESULT PASS / 0 FAIL**, mismos casos, veredictos, detalles y multiplicidad.
  `comparacion_RESULT.json`: `solo_anterior=[]`, `solo_actual=[]`.
- F0, F1 y huella final: **idénticos**, incluso byte a byte en sus raw.
- Tablas de catálogo/matriz 10/11/16: igualdad normalizada. Diferencia de bytes
  exclusivamente en el orden/transporte de NOTICE; sus casos y detalles se
  contrastaron por separado. No se descartan campos semánticos de la huella.
- TPI baseline y posterior: ambos **29 grupos / 37 variantes / 30 NOTICE PASS,
  exit 0**, limpieza true e inventario de 12 objetos habilitados. Sus raw también
  coinciden byte a byte con la primera instalación.
- HAVING/ventana e inventario final: idénticos. Se preservaron los defaults y los
  propietarios canónicos; F1/99 no encontraron diferencias no autorizadas.
- P8 corregido: U5 **3**, efímeras **0**, EXCEPT **0**, post-COMMIT **3**.
  52 y 99 acreditan ausencia de roles efímeros y conservación de VP01+nueve.
- Conexiones reales 50/51 por socket y M06 NOLOGIN se ejecutaron otra vez;
  el exit **2** de M06 es el rechazo esperado por NOLOGIN, no un fallo genérico.

**Diferencias reales:** solo identidades/tiempos de las nuevas instancias y
transporte de salidas. No se encontró diferencia semántica de producto/catálogo
ni de resultado de prueba. No se exige igualdad de PIDs, OIDs, timestamps, IDs de
contenedor o secuencias; no fue necesario borrar campos de huella para obtener
coincidencia. Detalle por caso en `m05/comparacion_caso_a_caso.tsv`; comparación
por artefacto en `m05/comparacion_fingerprints_y_TPI.json`.

## SCRAM-SHA-256 — PASS

Reglas explícitas 1 y 2: host loopback IPv4/IPv6 con SCRAM, antes de las reglas
previas; reload exitoso, cero errores de pg_hba_file_rules y
`password_encryption=scram-sha-256`.

El valor aleatorio se generó en shell/OpenSSL y el verificador se calculó en
cliente con PBKDF2-HMAC-SHA256, **4096** iteraciones y salt aleatorio. El ASCII
aleatorio no requiere transformaciones de normalización de contraseña.
Asignación en sesión superusuario con logging de sentencias desactivado y
log_min_error_statement=panic para evitar exponer el verificador DDL. Solo se
imprimió `SCRAM-SHA-256$`; nunca el verificador completo. Una nueva sesión
confirmó después los defaults globales `mod` / `error` / `scram-sha-256`.

- TCP válido: `127.0.0.1`, usuario real tst_u5_scram, backend **264**, exit **0**,
  cliente con **require_auth=scram-sha-256** explícito.
- Servidor: `connection authenticated: identity="tst_u5_scram" method=scram-sha-256`
  y regla `/var/lib/postgresql/data/pg_hba.conf:1`.
- Contraseña incorrecta: exit **2**, backend **271**, FATAL **28P01** en el servidor.
- Sin TLS únicamente dentro del loopback del contenedor aislado: ssl=false.
  SCRAM no implica cifrado de todo el tráfico ni acredita seguridad productiva.
- Rol retirado; `roles_scram_restantes=0`.
- Cero coincidencias de passwords exactas/verificador exacto en ambos logs y en
  TODOS los archivos generados hasta el scan final, incluidos README/SEC04/arnés.

Aclaración del padre antes de crear recursos: **sin GRANT directos y sin
membresías**, conservando defaults PUBLIC. Catálogo: membresías 0, grants directos
de relación/base 0; CONNECT/TEMP/USAGE public/crypt/gen_salt efectivos true.
No se modificó PUBLIC ni D9. No se pretende que un rol pueda negar individualmente
privilegios que ya recibe de PUBLIC.

Esto prueba autenticación de conexión PostgreSQL; no sustituye fn_autenticar,
que verifica bcrypt en usuario.contrasena y está cubierto por 40/SEC-18.
El caso opcional de require_auth incompatible no se ejecutó ni se marca PASS.

## SEC-04 / M03

**aceptación provisional — pendiente de aceptación formal del equipo**.

Texto humano literal: «La revisión humana acepta provisionalmente el uso académico
de datos sintéticos y agregados, pero no autoriza exposición de datos personales
reales.»

Inventario mediante has_table_privilege sobre TODAS las relaciones, incluidas las
del sistema, con columnas y definiciones. La única analítica no-sistema legible
es public.mv_facturacion_categoria_mes, agrupada por categoría/mes. Cohortes:
Pizzas 3 usuarios, Bebidas 2, ambas marzo 2026. Ausencia de identificadores directos
no acredita anonimización. Riesgos y condiciones de aceptación: [sec04/README.md](sec04/README.md).

## SEC-01..SEC-20 actualizados

PASS se limita a los ensayos observados, no a garantías universales.

| SEC | Veredicto actual | Cambio respecto de la primera instalación |
|---|---|---|
| 01 | PASS | M05 completa la segunda instalación limpia; P/N también reiterados |
| 02 | PASS | Atributos reiterados, sin diferencia |
| 03 | PASS | Equivalencia y errores exactos reiterados |
| 04 | aceptación provisional — pendiente de aceptación formal del equipo | Revisión final realizada; NO PASS de M03 |
| 05 | PASS | API/DML y matriz reiterados |
| 06 | PASS | Administración mínima reiterada |
| 07 | PASS | Membresías y opciones exactas reiteradas |
| 08 | PASS | INSERT/defaults y denegaciones reiterados |
| 09 | PASS | Ausencia DELETE/TRUNCATE reiterada |
| 10 | PASS | Intentos de escalamiento rechazados otra vez |
| 11 | PASS | ADP de tablas y control público reiterados |
| 12 | PASS | ADP de funciones y control de EXECUTE reiterados |
| 13 | PASS | Diez rutinas y ACL exactos reiterados |
| 14 | PASS | Permisos por columna reiterados |
| 15 | PASS | TPI antes/después, F0/F1 y propietarios nuevamente intactos |
| 16 | PASS del intervalo ensayado | M02 reiterado; SCRAM y protección del verificador añadidos |
| 17 | PASS | M04 completa interrupción real y control ROLLBACK; endurecimiento reiterado en M05 |
| 18 | PASS | Reset/auth bcrypt reiterados; no se afirma equivalencia temporal |
| 19 | PASS | Identidad aislada y limpieza reiteradas |
| 20 | PASS | Nueve roles, membresías y ausencia de efímeros reiteradas |

## Incidencias del arnés y límites

No hubo fallo del producto ni fallo de prueba SQL. Sí hubo una **incidencia de
sintaxis del nuevo arnés durante su preflight**, antes de crear recursos:
`\unset` en un string Python no raw provocó SyntaxError Unicode. Se conservó
`ejecutar_cierre.py` como borrador NO ejecutado, el diagnóstico en
`incidencia_preflight_arnes.txt` y el diff de la copia corregida en
`diff_preflight_arnes.txt`. Se ejecutó solamente `ejecutar_cierre_v2.py`, una vez.
No se editó ni repitió ningún SQL por esa incidencia.

El scan de rastreados adicional de esta etapa se registró en la verificación
final (exit 1 sin coincidencias); no se presenta como una ejecución previa al
laboratorio. Los scans de valores exactos, en cambio, se realizaron con valores
aún en memoria antes de copiar logs, destruir y limpiar el entorno.
Este complemento posterior contiene únicamente resultados y metadatos ya revisados;
no se regeneraron ni recuperaron secretos para escribirlo.

Se mantienen fuera del alcance mediciones de tiempos bcrypt, serialización de
reset multisesión, carga/estrés, anonimización universal y exposición productiva.
No se implementaron D4, D8 adicional ni D9.

## Cleanup, preservación y Git

Ambos logs tuvieron modo 0600 y se copiaron tras scan restringido en contenedor;
segundo scan en host limpio. Se confirmó captura antes de cada
`docker rm -f -v` (**exit 0**). Los dos contenedores y sus dos volúmenes están
ausentes. Docker ps antes/después es idéntico byte a byte: libreria-pg,
taller-db-1 y tpi_ssd-db-1 no se tocaron.

Manifiestos SHA-256 antes/después y comprobación independiente final: los dos
directorios anteriores permanecen byte-idénticos; también todas las fuentes SQL.
Ningún archivo previo se modificó. Solo se crearon archivos de esta nueva etapa.
`git diff --check`: exit 0. Sin staging, commits, push, merge ni publicación.
TDD OFF: RED/GREEN no activos, validación de integración separada.

```text
 M unidades/unidad-5/specs/design.md
 M unidades/unidad-5/specs/requirements.md
?? odd/
?? unidades/unidad-5/sql/
?? unidades/unidad-5/validacion_parte_a/
```

**Detenido al concluir. La aceptación formal de SEC-04 corresponde al equipo.**
