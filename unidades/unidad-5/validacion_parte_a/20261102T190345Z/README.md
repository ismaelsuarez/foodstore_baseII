# Unidad 5 — Parte A: validación de integración, intento corregido

**Resultado: PARCIAL.** Instalación y pruebas SQL ejecutadas sin fallos: **207
líneas RESULT PASS / 0 FAIL**; TPI antes y después: **30 NOTICE PASS / exit 0**.
No se declara PASS integral: M04 (interrupción de instalación), M05 (segunda
instalación limpia) y aprobación humana de la revisión M03 siguen pendientes.

El intento anterior `../20261102T185421Z/` permanece íntegro. Esta es la única
corrida corregida autorizada por el padre (opción B); no se repitió ninguna
prueba fallida del producto ni se cambió SQL. La recuperación ocurrió antes de
cualquier SQL en el intento anterior. Las dos evidencias no se sustituyen.

## 1. Identificación y configuración de instancia

| Campo | Observado |
|---|---|
| Rama | `feat/u5-seguridad` |
| Nombre | `foodstore_u5_validacion_a` |
| ID del nuevo contenedor | `e811c398fe83bbff2187437ff77c2a5de170596b416ef816380082205bc82410` |
| Imagen local | `postgres:17` |
| Digest | `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3` |
| `server_version` | `17.11 (Debian 17.11-1.pgdg13+2)` |
| Cliente | psql 17.11; salida completa en `01_psql_version.txt` |
| Base | `foodstore_tpi_oficial`; única de laboratorio además de postgres/template0/template1 |
| Red / puertos | `none` / `bindings={}`, sin publicaciones |
| Repositorio | `/repo`, bind mount `ro`, `RW=false` |
| Volumen anónimo exclusivo | `f42184736a81eee2eac5dc0f281ce9c38bd3c4f344ee7f19f7b6506023c9b6cd` |

Configuración efectiva consultada antes de instalar, con fuente `command line`:
`log_statement=mod`, `log_parameter_max_length=0`,
`log_parameter_max_length_on_error=0`, `log_file_mode=0600`,
`password_encryption=scram-sha-256`, `logging_collector=on`,
`log_connections=on`, `log_disconnections=on`. Archivo `log/u5-server.log`, sin
rotación durante el intervalo. No se modificó configuración global del host.

Fuentes: `01_container_isolation.txt`, `01_ready_sql.txt`,
`01_instance_settings.txt`, `01_postgres_version.txt`, `01_psql_version.txt`.

## 2. Preflight y precondiciones

| Control | Resultado | Evidencia |
|---|---|---|
| Raíz, rama y cambios preexistentes | PASS | `00_root`, `00_branch`, `00_git_status_before` |
| Docker y OpenSSL | PASS | `00_docker_version.txt`, `00_openssl_version.txt` |
| Ausencia del nombre autorizado | PASS | `00_container_names.txt`, `00_docker_ps_before.txt` |
| Imagen local/digest, sin pull | PASS | `00_image_id.txt`; `--pull=never` en JSON |
| Fuentes SQL presentes | PASS | `00_source_sha256_before.txt` |
| Guardas y variable de destino | PASS | Variable explícita en todas las invocaciones U5; guardas completadas en instalación/pruebas |
| Aislamiento y solo lectura | PASS | `01_container_isolation.txt` |
| Inicio final del servidor | PASS | Running=true, log `PostgreSQL init process complete`, pg_isready exit 0, SELECT version exit 0 |
| Versión servidor/cliente | PASS | 17.11 / 17.11 |
| Autenticación y logging | PASS del entorno de prueba | Settings efectivos y `pg_hba_file_rules` en `01_instance_settings.txt` |
| Scan de rastreados | PASS | `git grep -nE -I`: exit 1, sin literales PASSWORD, hashes bcrypt ni claves privadas |
| VP-00..VP-12, catálogo/ACL/propietarios | PASS de las guardas ejecutadas | `10_precondiciones.txt`, repetidas por roles en `12_roles.txt` |

`pgcrypto` se instaló explícitamente en `public` antes de precondiciones.
VP-07 además tiene comprobación de formato bcrypt durante 40; **no se publicó
una sal ni un hash, ni se midieron costos/tiempos**. No se extrapolan resultados
de la POC. `SEED_NO_AUTH` sigue siendo solo un marcador académico.

Los sondeos de arranque tienen cada salida y exit separados en `01_probe_*`;
no se descartan diagnósticos de un sondeo anterior.

## 3. Instalación y ejecución por pasos

Todos los psql usan `-X -w -v ON_ERROR_STOP=1`; los pasos U5 llevan
`-v u5_base_objetivo=foodstore_tpi_oficial`. Acceso únicamente por `docker exec`.
`-1` se usó solo para schema y objetos canónicos. Los datos son el seed académico
y fixtures sintéticos, revertidos por sus respectivos scripts.

**Semántica de exit:** `0*` significa archivo completado bajo ON_ERROR_STOP en
la sesión compartida, no un proceso psql independiente. Se conservó una sola
sesión superusuario desde precondiciones/F0 hasta 99 y las capturas finales;
su exit real final fue **0** (`control_session_exit.txt`). No se inventan exits
individuales de procesos que no existieron. Los demás números son exits reales.

| Paso / archivo | Raw | Exit / resultado |
|---|---|---|
| schema.sql, `-1` | `02_schema.txt` | 0 |
| datos_iniciales.sql, sin `-1` | `03_seed.txt` | 0 |
| tpi/sql/objetos_programables.sql, `-1` | `04_objetos.txt` | 0 |
| Batería TPI baseline | `05_tpi_baseline.txt` | 0 |
| HAVING/ventana baseline | `06_having_baseline.txt` | 0 |
| U3 views.sql | `07_u3_views.txt` | 0 |
| U3 materializadas.sql, incluido su índice UNIQUE | `08_u3_materializada.txt` | 0 |
| CREATE EXTENSION pgcrypto WITH SCHEMA public | `09_pgcrypto.txt` | 0 |
| 00_precondiciones.sql | `10_precondiciones.txt` | 0* |
| 01_f0.sql | `11_f0.txt` | 0* |
| roles.sql | `12_roles.txt` | 0* |
| funciones_seguridad.sql | `13_funciones.txt` | 0* |
| 02_f1.sql | `14_f1.txt` | 0* |
| 10_catalogo.sql | `15_catalogo.txt` | 0* |
| 11_matriz.sql | `16_matriz.txt` | 0* |
| 16_matriz_efectiva.sql | `17_matriz_efectiva.txt` | 0* |
| 12_reservar_ids.sql | `18_reservar_ids.txt` | 0* |
| 20_permisos.sql | `19_permisos.txt` | 0* |
| 30_equivalencia.sql | `20_equivalencia.txt` | 0* |
| 40_credenciales.sql | `21_credenciales.txt` | 0* |
| 49_preparar_logins.sql | `22_preparar_logins.txt` | 0* |
| 50_login_reportes.sql, conexión real | `23_login_reportes.txt` | 0 |
| 51_login_soporte.sql, conexión real | `24_login_soporte.txt` | 0 |
| M06 NOLOGIN, conexión independiente | `25_nologin.txt` | **2 esperado**, rechazo por NOLOGIN |
| Catálogo NOLOGIN posterior | `26_nologin_catalogo.txt` | 0*, rolcanlogin=f |
| 52_limpiar_logins.sql | `27_limpiar_logins.txt` | 0* |
| 99_cierre.sql | `28_cierre.txt` | 0* |
| Huella final / inspección M03 | `29_huella_final.txt`, `29_analitica.txt` | 0* |
| Batería TPI posterior | `30_tpi_after.txt` | 0 |
| HAVING/ventana posterior | `31_having_after.txt` | 0 |
| Inventario final | `32_final_inventory.txt` | 0 |

13_fixtures, 14_identidades y 15_limpieza se ejecutaron exclusivamente mediante
sus llamantes, no aisladamente. No se instaló seguridad.sql de U3, índices
candidatos de U3, objetos U4 ni ningún objeto fuera de las dependencias aprobadas.

Argumentos completos, tiempos, exits y entradas de la sesión compartida:
`comandos_y_salidas_final.json` y `comandos_observados.jsonl`.

## 4. SEC-01..SEC-20: tabla de veredictos

PASS se limita a los casos realmente ejecutados. BLOCKED en un criterio con
casos PASS significa **cobertura manual pendiente**, no fallo del producto.
Los negativos SQL fueron comprobados contra su SQLSTATE exacto por el arnés
existente; no se interpretó cualquier error como éxito.

| SEC | Veredicto global | Evidencia ejecutada P/N/R y límites |
|---|---|---|
| 01 | **BLOCKED parcial** | 10:`SEC01.P.grupos` 7/7; `\du`; M06 FATAL NOLOGIN y catálogo f. M05 segunda instalación limpia no ejecutada |
| 02 | PASS | 10:`SEC02.P.SEC06.P.SEC20.P.atributos` 0 diferencias; N=N/A; no se alteraron atributos de los nueve roles |
| 03 | PASS | 30 equivalencia EXCEPT 0/0, stock/subtotal/total; 20 negativos 42501, 22023, 23503, 23514 y 23505; sin efectos |
| 04 | **BLOCKED parcial** | 20 lecturas y denegaciones PASS; 50 login real PASS; 10 barrera estructural PASS; M03 revisada técnicamente, aprobación humana y garantía frente a fuentes auxiliares pendientes |
| 05 | PASS | 20 API y estado PASS; DML/SELECT directo detalle 42501; matriz 11/16 sin accesos extra |
| 06 | PASS | Atributos 10; lectura y CREATE reportes en 20; CREATE ROLE/DML/contraseña/CREATE public 42501 |
| 07 | PASS | 10 EXCEPT membresías 0; opciones false/true/false; sin propietarios/admin_datos; cierre 99 |
| 08 | PASS | INSERT RETURNING y defaults en 20; lecturas/UPDATE vedados 42501; 11/16 columnas exactas |
| 09 | PASS | 11 sin DELETE/TRUNCATE; 20 ambos 42501; 16 sin extras |
| 10 | PASS | 10 sin ADMIN OPTION/CREATEROLE; cinco intentos GRANT de 20 con 42501; membresías finales intactas |
| 11 | PASS | 20 tabla ADP y SELECT automático; public sin privilegios automáticos; 11 dos ADP y EXCEPT 0 |
| 12 | PASS | 20 función sin EXECUTE público y control positivo del superusuario; 11 ADP global exacto |
| 13 | PASS | API autorizada en 20/30; CALL/total directo 42501; diez rutinas y ACL exactos en 11/16 |
| 14 | PASS | INSERT columnas permitidas; fecha/total/estado/eliminado 42501; 11/16 exactos |
| 15 | PASS | TPI antes/después 29 grupos/37 variantes, 30 NOTICE PASS, exit 0; 02 huella 0; 99 huella final 0 |
| 16 | PASS del intervalo ensayado | Guardas/settings previos, getenv/bind en 40; M02 grep exacto sin coincidencias; permisos 0600; sin afirmar garantía universal |
| 17 | **BLOCKED parcial** | 10 definer/owner/search_path/CREATE PASS; 11 ACL; 20 suplantación TEMP PASS; M04 interrupción dinámica no ejecutada |
| 18 | PASS | 40 reset bcrypt/autenticación nueva/rechazo anterior PASS; ADMIN 42501, baja/ausente 23503, valores inválidos 22023, acceso directo 42501 |
| 19 | PASS | 14 identidad aislada; 20 diez rutinas y relaciones negativas 42501; 15/52 cero efímeros |
| 20 | PASS | 10 atributos; 15/52 limpieza; 99 VP01+nueve y membresías EXCEPT 0; N=N/A |

Todas las líneas originales, con `psql:/repo/...:línea` y caso, están en
`RESULT_resumen.txt`: **207 PASS / 0 FAIL**. Incluyen auxiliares y aserciones de
limpieza repetidas por distintos llamantes; no son 207 criterios únicos.

Ejemplos literales (el resumen conserva también el prefijo completo de origen):

```text
RESULT|MATRIZ.EXCEPT.bidireccional|PASS|esperado=0 observado=0|aserción
RESULT|SEC03.P.EXCEPT.bidireccional|PASS|esperado=0 observado=0|aserción
RESULT|SEC18.P.reset|PASS|esperado=sin_error observado=sin_error|aserción
RESULT|SEC20.R.roles_VP01_mas_nueve|PASS|esperado=0 observado=0|aserción
```

**Límite de segmentación:** algún NOTICE final quedó capturado en el raw del
paso siguiente (por ejemplo, 30:`SEC03.P.EXCEPT.bidireccional` aparece en
`21_credenciales.txt`, y 40:`CREDENCIALES.R.sin_roles` en `22_preparar_logins.txt`).
No se movió ni editó la salida. Se atribuye por el archivo/caso embebido en el
NOTICE, no solo por el nombre del raw. Los 207 RESULT se conservaron completos.

## 5. Regresión TPI y huellas

| Control | Baseline | Posterior |
|---|---|---|
| Grupos/variantes del contrato ejecutado íntegramente | 29 / 37 | 29 / 37 |
| NOTICE PASS observados | 30 | 30 |
| Exit psql | 0 | 0 |
| Fixtures restantes | 0 / 0 / 0; limpieza_ok=t | 0 / 0 / 0; limpieza_ok=t |
| Objetos canónicos inventariados | 12, todos t | 12, todos t |
| HAVING | Ana 2; Luis 2 | Ana 2; Luis 2 |
| RANK | Marta 6200/1; Ana 5950/2; Luis 2550/3 | Idéntico |

29/37 describe los grupos y variantes de la batería ejecutada; el conteo
independiente de salida es 30 NOTICE, no 37 NOTICE. Los raw TPI anterior/posterior
son idénticos byte a byte; también los raw HAVING/ventana.

F0 se tomó antes de roles en la misma sesión. `14_f1.txt` muestra EXCEPT
bidireccional **0 filas** excluyendo solo las ACL esperadas; propietarios,
definiciones, tablas, columnas, restricciones, índices, secuencias, tipos,
triggers y definiciones U3 permanecieron intactos. `REG05.VP02=0`; 99 confirmó
`SEC15.R.huella_final=0` y `MATRIZ.R.final=0`.

Diferencias ACL observadas en las siete rutinas, autorizadas por D3:
- Todas partían de proacl NULL (propietario + PUBLIC).
- calcular_total_pedido y registrar_detalle_pedido quedaron con EXECUTE para
  postgres y rol_propietario_ventas, sin PUBLIC.
- Las cinco funciones trigger quedaron solo con EXECUTE del propietario postgres.

Las tres funciones nuevas y los GRANT/USAGE previstos no pertenecen a la huella
canónica comparada; se verificaron explícitamente en 10/11/16. Materializada
conservada en public, no movida ni duplicada. La transacción sigue perteneciendo
al llamante. P0099 solo se usó internamente en la atomicidad de la batería TPI.

## 6. P8.membresias, 15/52/99 y residuos

Se ejecutó la aserción corregida, sin contar las membresías predefinidas de
pg_monitor. En 20, 40 y 52:

```text
RESULT|P8.membresias.efimeras|PASS|esperado=0 observado=0|aserción
RESULT|P8.membresias.U5_filtradas|PASS|esperado=3 observado=3|aserción
RESULT|P8.membresias.EXCEPT|PASS|esperado=0 observado=0|aserción
```

Después del COMMIT de 52:

```text
RESULT|P8.membresias.post_commit|PASS|esperado=3 observado=3|aserción
RESULT|D12.post_commit.sin_roles|PASS|esperado=0 observado=0|aserción
```

99 confirmó roles previos+nueve, cero efímeros, membresías intactas y ningún
fixture. Antes de destruir, el inventario independiente tenía 2 categorías,
3 usuarios, 3 productos, 5 pedidos y 7 detalles; las únicas tres membresías U5
eran las de app_web. Pueden quedar huecos en secuencias por nextval, según contrato;
no se usó setval. No se confunde esta aserción con una repetición del P8 de la POC,
que retiraba también sus roles U5.

## 7. Seguridad, auditoría y manuales

### M01

Ejecutada antes y después de U5, sin `-1`, con la guarda literal intacta.
Resultados en §5. No se ejecutó TPI-B como sustituto.

### M02

Valores sintéticos generados con OpenSSL en memoria antes de la sesión de control.
Se pasaron mediante entorno, se importaron con getenv y se enviaron con bind.
No se imprimieron ni se pasaron con `-v`. El script 40 y el shell limpiaron sus
variables; el entorno existió exclusivamente durante el proceso de la corrida.

| Comprobación | Observado |
|---|---|
| Settings previos efectivos y guardas | PASS, `01_instance_settings.txt` y 20/40/51 |
| Archivo SO | `600 postgres postgres` (`40_log_permissions.txt`) |
| Copia restringida dentro del contenedor | Exit 0, `41_log_snapshot.txt` |
| grep -F exacto, dos valores de negocio + password bootstrap + bcrypt + PASSWORD literal | Exit **1**, sin coincidencias (`42_m02_container_scan.txt`) |
| docker cp tras ese scan | Exit 0; `servidor.txt` |
| Mismo grep sobre la copia host | Exit **1**, sin coincidencias (`44_m02_host_scan.txt`) |
| Intervalo copiado | 1528 líneas; 199 statements, 20 autorizaciones y 19 desconexiones |
| Scan exacto de todos los archivos generados antes de destruir | Sin coincidencias, `46_evidence_secret_scan.txt` |
| Scan exacto final del proceso | Sin coincidencias, `94_final_secret_scan.txt` |

La diferencia autorizaciones/desconexiones no se ocultó: el snapshot se tomó
mientras el servidor seguía activo, antes de destruir. El log incluye errores,
DETAIL/CONTEXT y actividad del intervalo de pruebas; no incluye el apagado forzado
posterior. `log_statement=mod` no acredita auditoría de todas las lecturas SELECT.
El grep posterior verifica el intervalo, no sustituye los controles preventivos.

### M03: revisión técnica y límite humano

`29_analitica.txt` conserva la definición y las dos filas de la única
materializada: categoría, mes, cantidad de pedidos, unidades y facturación; no
usuario_id, nombre personal, mail, celular ni contraseña. reportes no tenía otras
relaciones preinstaladas. Las matrices exactas impiden al rol_reportes consultar
usuario/pedido para reconstruir el detalle.

En este seed, Pizzas agrupa 3 usuarios y Bebidas 2: no hay grupos unitarios en el
snapshot, pero son cohortes pequeñas. **No se acredita imposibilidad de
reidentificar con conocimiento auxiliar, diferencias temporales u otros datasets.**
La inspección técnica está realizada; la aceptación humana del riesgo sigue
pendiente, por eso SEC-04 no recibe PASS integral.

### M04

Revisión estática de funciones_seguridad.sql: un BEGIN/COMMIT engloba las tres
altas con OWNER/REVOKE/GRANT; referencias nuevas calificadas y search_path fijo.
Los catálogos resultantes pasaron. **Interrupción antes del COMMIT y observación
desde otra sesión: BLOCKED/no ejecutada**, pues requiere otra corrida limpia
controlada. No se simuló con CREATE duplicado después de instalar.

### M05 y M06

49 creó los logins y guardó procedencia en la sesión original; 50/51 usaron
conexiones reales independientes como tst_u5_reportes/tst_u5_soporte, sin SET ROLE.
Se usó el socket trust exclusivo del contenedor, sin contraseña necesaria; no se
acredita negociación SCRAM ni autenticación de red. No se cambió pg_hba después
de la inicialización. Ambos psql terminaron antes de 52, que validó procedencia
y completó el cleanup en la misma sesión de control.

M06 devolvió exit 2 con diagnóstico exacto:

```text
FATAL:  role "rol_app_lectura" is not permitted to log in
```

Catálogo posterior: rolcanlogin=f. No fue un fallo de transporte ni una denegación
previa de pg_hba. La **segunda instalación limpia de M05 no se ejecutó**: solo
hubo esta instalación exitosa, no otra repetición autorizada adicional.

## 8. Fallos, limitaciones y riesgos residuales

- Ningún instalador ni aserción SQL emitió FAIL. M06 exit 2 y grep exit 1 son
  resultados esperados, no fallos del producto ni del ambiente.
- Intento anterior: fallo del control readlink/PID antes de SQL, preservado sin
  cambios. Solo se corrigió el arranque en la copia del arnés de esta corrida.
- No se realizaron M04 dinámico ni segunda instalación M05. No se declara PASS
  por esos pasos ausentes. No se inicia una tercera corrida.
- El estado global es PARCIAL aunque el arnés Python termine en 0: el exit del
  envoltorio no expresa cobertura de manuales. La evidencia de cada caso manda.
- La segmentación stdout/stderr puede dejar un NOTICE en el archivo siguiente;
  se conserva el origen `psql:/repo/...` y el resumen completo. No se arregló el
  arnés ni se repitieron casos por ello.
- No se midieron concurrencia, serialización multisesión de reset, tiempos bcrypt,
  costos exactos por rama ni estrés. RR-06 sigue vigente; no se promete igualdad
  temporal ni ausencia universal de deadlocks.
- D11 U(celular), alcance de usuario final de la API, enumeración de IDs y
  reidentificación siguen siendo riesgos del diseño; no se amplían garantías.
- D4, D8 adicional y D9 permanecieron sin implementar. CONNECT/TEMP se conservaron;
  la rama TEMP probada utilizó public.producto sin tocar su homónima temporal.
- Los scans de rastreados y formatos no son una auditoría universal de secretos;
  sí se comprobaron los valores sintéticos exactos generados durante la corrida.

## 9. Captura, destrucción exclusiva y conservación

Antes de destruir estaban capturados salidas SQL, huellas, matriz, RESULT,
conexiones, regresiones, inventario, settings, permisos y log revisado. Se guardó
`47_confirmacion_captura.txt`; en esta corrida sí hubo evidencia SQL completa
para los pasos de su tabla, con las limitaciones manuales anteriores.

`docker rm -f -v foodstore_u5_validacion_a`: **exit 0**. Nombre ausente después;
volumen propio ausente en el inventario de volúmenes y en
`53_volume_absence.txt`. Solo se eliminó el recurso creado por esta corrida.

`00_docker_ps_before.txt` y `50_docker_ps_after.txt` son **idénticos byte a byte**:
los mismos IDs y estados para tpi_ssd-db-1 (Up, healthy), taller-db-1 (Exited 0)
y libreria-pg (Exited 0). No se conectó, inició, paró ni inspeccionó individualmente
ninguno de ellos: únicamente `docker ps -a`.

El manifiesto del intento anterior antes/después coincide byte a byte:
`intento_anterior_sha256_antes.txt` / `intento_anterior_sha256_despues.txt`.
Las fuentes SQL de la corrida también conservan sus SHA-256 originales.
Ver `95_verificacion_evidencias.txt`.

## 10. Git, alcance y cierre

Solo se crearon archivos nuevos bajo este directorio UTC. Ningún archivo de
schema, seed, TPI, U1–U4, SQL U5, specs, poc_permisos, odd ni del intento anterior
fue editado. Cambios previos preservados:

```text
 M unidades/unidad-5/specs/design.md
 M unidades/unidad-5/specs/requirements.md
?? odd/
?? unidades/unidad-5/sql/
?? unidades/unidad-5/validacion_parte_a/
```

`git diff --check`: exit 0; no acredita los raw no rastreados, cuyos espacios de
psql se conservan literalmente. Sin git add, commit, push, merge ni publicación.
TDD OFF por autorización explícita: RED no activo; GREEN no activo. Evidencia
observada de integración separada de cualquier afirmación de ciclo TDD.

**Detenido al concluir. Esperar revisión humana; no se modifica código ni se
inicia otra corrida.**

## Diferencias del arnés respecto del intento anterior

Único cambio: sustituir el control readlink/PID por las señales documentadas de
arranque y capturar cada sondeo de inmediato. El diff literal siguiente coincide
con `diff_arnes.txt`; no se introdujo ninguna otra modificación al arnés copiado.

```diff
--- 20261102T185421Z/ejecutar_validacion.py
+++ 20261102T190345Z/ejecutar_validacion.py
@@ -205,21 +205,24 @@
     created = True
     require('01_container_isolation', ['docker', 'inspect', NAME, '--format',
             'id={{.Id}} image={{.Image}} network={{.HostConfig.NetworkMode}} bindings={{json .HostConfig.PortBindings}} mounts={{json .Mounts}}'])
-    ready_lines = []
-    for _ in range(90):
-        r = subprocess.run(['docker', 'exec', NAME, 'pg_isready', '-U', 'postgres', '-d', DB],
-                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
-        ready_lines.append(r.stdout + 'exit_code=' + str(r.returncode) + '\n')
-        if r.returncode == 0:
-            # Initdb's temporary server has a socket too: wait for final PID 1 postgres.
-            pid = subprocess.run(['docker', 'exec', NAME, 'sh', '-c', 'test "$(readlink /proc/1/exe)" = /usr/lib/postgresql/17/bin/postgres'],
-                                 capture_output=True)
-            if pid.returncode == 0:
+    for probe in range(90):
+        running = require('01_probe_%02d_running' % probe,
+                          ['docker', 'inspect', '-f', '{{.State.Running}}', NAME]).strip()
+        if running != 'true':
+            raise RuntimeError('BLOCKED: contenedor no está running; ver diagnóstico del sondeo')
+        logs = require('01_probe_%02d_init_log' % probe, ['docker', 'logs', NAME])
+        if 'PostgreSQL init process complete' in logs:
+            ready = invoke('01_probe_%02d_pg_isready' % probe,
+                           ['docker', 'exec', NAME, 'pg_isready', '-U', 'postgres', '-d', DB],
+                           expected=(0, 1, 2))
+            if ready.returncode == 0:
+                require('01_ready_sql', psql() + ['-c',
+                        "SELECT version(), current_setting('server_version');"])
                 break
         time.sleep(1)
     else:
-        raise RuntimeError('BLOCKED: servidor no listo')
-    save('01_ready.txt', ''.join(ready_lines))
+        raise RuntimeError('BLOCKED: arranque no confirmado; ver todos los diagnósticos 01_probe')
+    save('01_ready.txt', 'running=true; init process complete; pg_isready exit 0; SELECT version/server_version exit 0\n')
     require('01_postgres_version', ['docker', 'exec', NAME, 'postgres', '--version'])
     require('01_psql_version', ['docker', 'exec', NAME, 'psql', '--version'])
     require('01_instance_settings', psql() + ['-c', "SELECT version(); SELECT name,setting,source FROM pg_settings WHERE name IN ('server_version','log_statement','log_parameter_max_length','log_parameter_max_length_on_error','log_file_mode','password_encryption','logging_collector','log_connections','log_disconnections','log_directory','log_filename','log_rotation_age','log_rotation_size'); SELECT datname FROM pg_database ORDER BY datname; SELECT type,database,user_name,address,auth_method,error FROM pg_hba_file_rules;"])
```
