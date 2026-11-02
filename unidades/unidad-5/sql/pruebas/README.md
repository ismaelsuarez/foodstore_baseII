# Verificación preparada — Unidad 5, Parte A

**Estado (2026-11-02): batería ejecutada en laboratorio.** Se corrió completa en dos
instalaciones limpias de PostgreSQL 17.11, descartables y aisladas: 207 RESULT PASS y 0 FAIL
en cada una. Resultados y evidencia: [`design.md` §15](../../specs/design.md) y
[`validacion_parte_a/`](../../validacion_parte_a/README.md). Estos archivos son los mismos
que se ejecutaron (sha256 registrado en cada corrida), por eso sus encabezados conservan el
texto de la etapa de escritura. Las secciones marcadas «futuro» o «no ejecutado» describen
el procedimiento tal como se escribió; su ejecución está en la evidencia. Volver a
ejecutarlos requiere una autorización nueva y una instancia aislada.

Autoridades: [requirements](../../specs/requirements.md), [design](../../specs/design.md)
§2–§8, §10, §12–§14 y [AGENTS](../../../../AGENTS.md). No se modifica ni se repite
la [POC registrada](../../poc_permisos/README.md). No se incluyen contraseñas ni
hashes literales; `SEED_NO_AUTH` y `hash_no_valido` son marcadores académicos.

## Condiciones y orden (aplicados en la validación integral)

- Instancia **aislada y descartable**, destino autorizado explícitamente, sin
  otros escritores. Los roles son globales del clúster: una base distinta no
  aísla roles. No usar cuentas ni datos reales. No crear/recrear bases desde
  esta batería; no usar el arnés histórico de POC para ejecutar estos archivos.
- Servidor PostgreSQL 17.x, cliente psql **16 o superior** para `\bind`, `-X`,
  `ON_ERROR_STOP=1`. No `-a`, `-e`, eco de consultas/variables ni captura de
  credenciales. Salidas en ubicación nueva fuera del repositorio y revisadas
  antes de entregarlas a otra persona o IA. No sobrescribir evidencia anterior.
- La variable psql `u5_base_objetivo` es **obligatoria**, no tiene default y se
  compara con `current_database()`. Es la misma variable de precondiciones e
  instalación; pasar `-v u5_base_objetivo="$u5_base_objetivo"` y
  `-d "$u5_base_objetivo"` a psql. Ausente, vacía o distinta provoca
  `RAISE EXCEPTION` bajo `ON_ERROR_STOP`; nunca hay default ni guarda con `\quit`.
  Coincidir en nombre no acredita autorización.
- Instalar previamente schema/seed/TPI y dependencias U3/pgcrypto solo si se
  autorizaron por separado. Los cinco triggers deben estar activos (`origin`).
  No se instala/mueve/duplica la materializada desde estas pruebas: se descubre
  exactamente una en `public` o `reportes`, según design §4.
- Antes de **cualquier llamada** a autenticación/reset, incluso con NULL,
  verificar `log_parameter_max_length=0`, `log_parameter_max_length_on_error=0`,
  `log_statement=mod` (no `all`), `log_file_mode=0600` y
  `password_encryption=scram-sha-256` (design §7.1). La batería solo
  verifica esos parámetros, no los modifica; falta de controles detiene el paso.

Orden de instalación: **`00_precondiciones.sql` → `roles.sql` →
`funciones_seguridad.sql` → pruebas**. Hay una excepción necesaria de observación:
**capturar `01_f0.sql` entre precondiciones y roles**, antes de cualquier GRANT,
REVOKE o creación U5. No reconstruir F0 después de instalar. Si la materializada
no existía en F0, design §4.2 permite que la instalación la cree en `reportes`:
02 admite únicamente esa fila analítica nueva; 11 exige una sola materializada.
Si ya existía, conserva ubicación, propietario y definición íntegros en la huella.

Mantener **una misma sesión de control superusuario** con autocommit normal:

| Orden | Archivo/acción | Ejecutor y efectos previstos |
|---|---|---|
| 1 | `../00_precondiciones.sql` | Superusuario; atender sus propias guardas/variables |
| 2 | `01_f0.sql` | Superusuario; guarda VP-01/VP-02 y huella canónica en TEMP |
| 3 | `../roles.sql`, después `../funciones_seguridad.sql` | Superusuario; instalación fuera de estos archivos |
| 4 | `02_f1.sql` | Compara F0/F1 y propietarios reales; ACL contrastados en 11 |
| 5 | `10_catalogo.sql`, `11_matriz.sql`, `16_matriz_efectiva.sql` | Superusuario; catálogos, matriz exacta, ADP y permisos heredados/PUBLIC |
| 6 | `12_reservar_ids.sql` | Superusuario; una vez por corrida; reserva IDs reales |
| 7 | `20_permisos.sql` | Setup superusuario, `SET ROLE` por caso, ROLLBACK final |
| 8 | `30_equivalencia.sql` | CALL como superusuario y API como app_web; dos transacciones revertidas |
| 9 | `40_credenciales.sql` | Setup superusuario, `SET ROLE app_web`/soporte; parámetros enlazados y ROLLBACK |
| 10 | Pasos manuales M01–M06 siguientes | No se sustituyen por los pasos anteriores |
| 11 | `99_cierre.sql` | Misma sesión superusuario: VP-01 + nueve roles U5, membresías, matriz, huella y residuos |

Los nombres de archivos auxiliares y de objetos **pg_temp** son internos a esta
batería, no nombres de implementación exigidos al otro escritor. `13_fixtures`,
`14_identidades` y `15_limpieza` solo se incluyen desde sus llamantes; no ejecutarlos
solos ni envolver la batería con `-1`. Los instaladores administran su propia
atomicidad: respetar sus instrucciones, no superponer otra transacción.

Si cualquier aserción falla, se emite diagnóstico sin parámetros y se eleva una
excepción: detener, preservar el diagnóstico y cerrar la conexión para revertir
la transacción pendiente. **No continuar ni limpiar ciegamente identidades** de
una corrida ajena. Los pasos 20/40 crean y retiran sus roles dentro de la misma
transacción; desconectarse revierte también esas creaciones. En el paso manual
49 sí hay COMMIT de roles: requiere completar 52 en la sesión de procedencia.

`nextval` no revierte: pueden quedar huecos de identidad aunque los fixtures se
reviertan. No se promete restitución de contadores ni se usa `setval`. No hay
escrituras permanentes de datos de negocio desde los ensayos automáticos.

## Casos y trazabilidad REQ → archivo:ID

Los IDs omiten guiones solo en el texto de los NOTICE (`SEC03` = `SEC-03`).
`MATRIZ.*` es transversal; cubre ambas direcciones de EXCEPT, columnas, rutinas,
esquemas, membresías, ADP, permisos efectivos por herencia y por PUBLIC.

| Requisito | Archivo:casos |
|---|---|
| REQ-A01 | `10_catalogo.sql:SEC01.P.grupos`, `SEC02.P.SEC06.P.SEC20.P.atributos`, `SEC07.P.N.SEC10.P.membresias`; `14_identidades.sql:SEC19.P.aislamiento` |
| REQ-A02 | `10_catalogo.sql:SEC02.P.SEC06.P.SEC20.P.atributos`, `SEC07.P.N.SEC10.P.membresias`; `11_matriz.sql:MATRIZ.*`, `SEC09.P`; `16_matriz_efectiva.sql:MATRIZ.efectiva.*`; `20_permisos.sql:MINIMO.N.*`, `SEC05.N.*`, `SEC09.N.*`, `SEC10.N.*` |
| REQ-A03 | `11_matriz.sql:MATRIZ.EXCEPT.bidireccional`; `20_permisos.sql:SEC08.P.SEC14.P.insert_returning`, `SEC08.P.defaults`, `SEC14.N.*` |
| REQ-A04 | `11_matriz.sql:SEC11.R.SEC12.R.*`; `20_permisos.sql:SEC11.*`, `SEC12.*` |
| REQ-A05 | `11_matriz.sql:REQ05.usage_efectivo`, `MATRIZ.*`; `16_matriz_efectiva.sql:MATRIZ.efectiva.esquemas` |
| REQ-A06 | `10_catalogo.sql:SEC07.P.N.SEC10.P.membresias`; `11_matriz.sql:MATRIZ.*`, vistas information_schema y consulta §6; `16_matriz_efectiva.sql:MATRIZ.efectiva.*` |
| REQ-A07 | `11_matriz.sql:SEC13.R.diez_rutinas`, `MATRIZ.EXCEPT.bidireccional`; `20_permisos.sql:SEC03.N.SEC13.N.call`, `SEC13.N.total`; `30_equivalencia.sql:REG02.*` |
| REQ-A08 | `11_matriz.sql:MATRIZ.*`; `20_permisos.sql:SEC04.*`, `SEC06.P.create_reportes`, `SEC11.P.*`; `50_login_reportes.sql:SEC04.*.login_*` |
| REQ-A09 | `10_catalogo.sql:SEC04.R.analitica_sin_columnas_personales`; `20_permisos.sql:SEC04.N.*`, `SEC06.N.contrasena`; **M03** (indispensable) |
| REQ-A10 | `10_catalogo.sql:SEC17.P.*`; `20_permisos.sql:SEC05.P.*`, `SEC17.N.*`; `30_equivalencia.sql:SEC03.P.*`; `40_credenciales.sql:AUTH.*`, `SEC18.*`; M04/M05 |
| REQ-A11 | `14_identidades.sql`, `15_limpieza.sql:P8.membresias.*`; `40_credenciales.sql`; `49`–`52`; `99_cierre.sql`; M02 |
| REQ-A12 | `01_f0.sql:F0.*`; `02_f1.sql:SEC15.N.huella`, `REG05.VP02`; `30_equivalencia.sql`; `99_cierre.sql:SEC15.R.huella_final`; **M01** |

## SEC → positivos, negativos y regresión

| Criterio | Positiva (P) | Negativa (N) | Regresión (R) |
|---|---|---|---|
| SEC-01 | 10:`SEC01.P.grupos`, `\du` | M06 conexión NOLOGIN | M05 reinstalación limpia y 10 |
| SEC-02 | 10:`SEC02.P.SEC06.P.SEC20.P.atributos` | N/A según diseño | Repetir 10 después de ALTER ROLE |
| SEC-03 | 30:`SEC03.P.*`, EXCEPT bidireccional | 20:`SEC03.N.*`, CALL 42501 y negocio 22023/23503/23505/23514 | Repetir 30 tras cambiar API/procedimiento |
| SEC-04 | 20:`SEC04.P.grupo/efimero`; 50 login real | 20:`SEC04.N.*`; 50 usuario/pedido | 10/11/16 + M03 tras nuevo analítico |
| SEC-05 | 20:`SEC05.P.SEC13.P.api`, `SEC05.P.estado` | 20:`SEC05.N.*` (42501) | 11 matriz e information_schema |
| SEC-06 | 10 atributos; 20:`SEC06.P.*` | 20:`SEC06.N.*` (42501) | Repetir 10/11/16 después de ALTER ROLE |
| SEC-07 | 10:`SEC07.P.N.SEC10.P.membresias` | 10:`SEC07.N.propietarios.SEC10.P.admin_datos` | Repetir 10 tras GRANT/REVOKE |
| SEC-08 | 20 INSERT RETURNING y defaults | 20:`SEC08.N.*`, `SEC05.N.select_detalle` | 11 matriz exacta por columna |
| SEC-09 | 11:`SEC09.P.sin_delete_truncate` | 20:`SEC09.N.delete/truncate` | Repetir 11/16 tras GRANT |
| SEC-10 | 10 membresías/admin_option | 20:`SEC10.N.efimero/grupo/app_admin/app_escritura/admin` | 10 atributos y 99 membresías |
| SEC-11 | 20:`SEC11.P.adp_tabla/select_automatico` | 20:`SEC11.N.public_sin_automaticos`, `SEC06.N.public` | 11 consulta pg_default_acl, dos entradas y EXCEPT |
| SEC-12 | 20:`SEC12.P.adp_funcion/sin_execute` | 20:`SEC12.N.control_precondicion/control_execute` | 11 ADP global sin PUBLIC |
| SEC-13 | 20 API; 30:`REG02.api.*` | 20 CALL y total 42501 | 11 ACL de diez rutinas con aclexplode/coalesce/acldefault |
| SEC-14 | 20:`SEC08.P.SEC14.P.insert_returning` | 20:`SEC14.N.fecha/total/estado/eliminado` | 11 columnas exactas; 16 permisos efectivos |
| SEC-15 | **M01 batería TPI existente** | 02:`SEC15.N.huella`, `REG05.VP02` | 99 huella y repetir M01 tras REVOKE |
| SEC-16 | 00_guardas_credenciales + 40 getenv y bind (generación externa M02) | **M02 inspección del log**, nunca sustituto preventivo | M02 antes de entregar log a IA |
| SEC-17 | 10:`SEC17.P.*`, 11 ACL | 20:`SEC17.N.*`; M04 atomicidad | 10/11 tras recreación, 99 huella |
| SEC-18 | 40:`SEC18.P.reset/formato_bcrypt/autentica_nueva/rechaza_anterior` | 40:`SEC18.N.*` | 10 propietarios, 11 ACL; repetir 40 |
| SEC-19 | 14:`SEC19.P.aislamiento`, SET ROLE en 20 | 20:`SEC19.N.*` (10 rutinas + tablas/vistas/materializada) | 15/20/40 sin roles efímeros |
| SEC-20 | 10 atributos de los nueve roles | N/A según diseño | 15/52 limpieza, 99 VP-01 + nueve, EXCEPT |

Los nombres completos de archivos 10/11/16/20/30/40/50/52/99 están en la tabla de
orden. Auxiliares: `00_destino.sql` destino/17.x; `00_guardas.sql` superusuario;
`00_guardas_credenciales.sql` prevención; `00_helpers.sql` NOTICE/subtransacciones;
`huella.sql` catálogo; `12_reservar_ids.sql` IDs; `13_fixtures.sql` datos sintéticos;
`14_identidades.sql` creación; `15_limpieza.sql` DROP OWNED/DROP ROLE y residuos.

**REG-01:** M01. **REG-02/03:** 30 (API/CALL, subtotal, stock y total), más M01
para las variantes completas de triggers y DML directo. **REG-04:** 20:`REG04.*`,
50/51 por conexión; `v_pedido_detalle` no tiene beneficiario U5 en la matriz:
solo se comprueba su consulta como superusuario. **REG-05:** 02/10/99.

## Procedimientos manuales pendientes

### M01 — SEC-15.P/R, REG-01: batería TPI independiente

Con autorización **nueva**, usar la batería existente, sin copiarla ni modificarla:

```text
psql -X -v ON_ERROR_STOP=1 -d foodstore_tpi_oficial -f tpi/pruebas/pruebas_objetos_programables.sql
```

Comando ilustrado **no ejecutado**, desde la raíz, como el superusuario autorizado
mediante la conexión de laboratorio (sin contraseñas en argumentos). La guarda
literal exige `foodstore_tpi_oficial` (D17); **no desactivar ni cambiar esa guarda**.
Si U5 usa otro nombre, solicitar una copia autorizada nueva en instancia aislada
con ese nombre, con instalación equivalente y F0 previo a U5. No reutilizar una
base histórica ni crear/borrar bases automáticamente. Los roles globales exigen
planificar esa copia sin colisionar con la corrida principal.

Sin `-1`: la batería maneja BEGIN/ROLLBACK. Registrar exit y los **29 grupos /
37 variantes / 30 NOTICE PASS esperados**, no asumirlos observados. Revisar también
limpieza e inventario final de 12 objetos. Conservar F0/F1 de la MISMA base, no
comparar propietarios de clústeres distintos. P0099 pertenece solo al ensayo de
atomicidad de esa batería. No usar los scripts multisesión TPI-B como sustituto:
tienen otra guarda/base y otros objetivos.

### M02 — SEC-16.N/R: revisión de logs (no protección)

**Instrucciones futuras, no ejecutadas.** La protección es la configuración previa
más los parámetros enlazados; el grep posterior solo verifica ausencia en el
intervalo capturado. No buscar solo el prefijo del generador: produce falsos
positivos por texto SQL y no identifica los valores efectivamente usados.

1. Registrar antes los parámetros de design §7.1: ambos límites de parámetros en
   `0`, `log_statement=mod` (se rechaza `all` en esta batería), `log_file_mode=0600`
   y SCRAM. Verificar permisos reales del SO (design §7.4), no solo pg_settings.
   La opción A temporal de §7.3 no se activa durante estas pruebas; cualquier
   simulacro con otra configuración requiere su autorización separada.
2. **Antes de abrir la sesión de control** que conservará F0/IDs, generar dos
   valores distintos exclusivamente en memoria del shell local. Sin `set -x`,
   grabación de terminal, eco, impresión de entorno ni archivos de valores:

   ```sh
   set +x
   U5_SYN_PWD="u5syn_$(openssl rand -hex 16)" || exit 1
   U5_SYN_NUEVA="u5syn_$(openssl rand -hex 16)" || exit 1
   export U5_SYN_PWD U5_SYN_NUEVA
   trap 'unset U5_SYN_PWD U5_SYN_NUEVA' EXIT
   psql -X -v ON_ERROR_STOP=1 -v u5_base_objetivo="$u5_base_objetivo" -d "$u5_base_objetivo"
   ```

   Requiere Bash/OpenSSL disponibles y conexión de laboratorio seleccionada por
   el responsable (sin secretos en argumentos). `u5_base_objetivo` debe estar
   definido con el destino autorizado, sin default. No ejecutar el paso 40 en una
   sesión nueva aislada: seguir el orden completo en **esa misma sesión**.
   `40_credenciales.sql` usa `\getenv u5_pwd U5_SYN_PWD` y
   `\getenv u5_nueva U5_SYN_NUEVA`; valida que sean no vacíos/distintos con `\bind`.
   Todos sus usos posteriores viajan también con `\bind`, nunca con interpolación
   SQL de valores. No generarlos en SELECT ni pasarlos por `-v`. Nada se guarda
   en el repositorio ni en archivos de valores; el entorno del cliente también
   debe tratarse como sensible y limitarse a esta sesión.
3. Capturar fuera del repositorio el intervalo completo del log de servidor,
   incluidos errores, DETAIL y CONTEXT, por el mecanismo autorizado. Confirmar
   cobertura y actividad de auditoría: stdout de psql no sustituye el log. Tras
   cerrar psql, en el **mismo shell**, conservar los valores solo hasta inspeccionar
   localmente ese intervalo. Definir `U5_LOG` con la ruta del log capturado fuera
   del repositorio y comprobar que sea legible/completo. No entregar ese log a IA.
4. Buscar los dos **valores sintéticos exactos**, el patrón bcrypt `$2a$` y la
   construcción `PASSWORD '` como cadenas fijas, sin imprimir coincidencias:

   ```sh
   : "${U5_SYN_PWD:?valor sintético ausente}" "${U5_SYN_NUEVA:?valor sintético ausente}"
   : "${U5_LOG:?falta la ruta del log autorizado}"
   if grep -F -q -e "$U5_SYN_PWD" -e "$U5_SYN_NUEVA" -e '$2a$' -e "PASSWORD '" -- "$U5_LOG"; then
       printf '%s\n' 'DETENER: coincidencia sensible; preservar el log con acceso restringido'
   else
       u5_grep_estado=$?
       case "$u5_grep_estado" in
           1) printf '%s\n' 'Sin coincidencias; falta contrastar cobertura y configuración' ;;
           *) printf '%s\n' 'DETENER: error de lectura/grep; verificación no acreditada' ;;
       esac
   fi
   unset U5_SYN_PWD U5_SYN_NUEVA U5_LOG u5_grep_estado
   ```

   `grep -F` compara cada valor completo como subcadena del log (no el prefijo,
   ni una expresión regular ni una línea entera). Código 1 significa ausencia de
   coincidencias, no prueba de auditoría activa; un error de lectura no equivale
   a ausencia. No usar grep sin `-q`, ni copiar coincidencias a evidencia pública.
5. Limpiar **siempre** las variables exportadas, también si SQL falla o se cancela.
   El SQL hace `\unset` de sus copias al terminar; en un aborto, cerrar psql para
   descartarlas. El shell debe hacer `unset U5_SYN_PWD U5_SYN_NUEVA` después del
   análisis, o al abandonar la corrida (el trap cubre la salida del shell). Si se
   perdieron los valores antes del grep, la comprobación exacta no está acreditada:
   no sustituirla por una búsqueda de `u5syn_`. Si hay filtración, detenerse y
   corregir el control preventivo antes de otra corrida autorizada.

### M03 — REQ-A09/SEC-04.R: reidentificación y objetos analíticos

Revisar definiciones, columnas y agregaciones que muestra 10. La ausencia de
nombres prohibidos no descarta alias ni reidentificación en grupos pequeños.
Comprobar que no puedan reconstruirse usuarios individuales por cruces o valores
singulares. No imprimir datos reales para esta revisión. Repetir tras instalar
cualquier objeto en `reportes`.

`v_resumen_ventas_rol_mes` es **propuesta futura, fuera de la Parte A** (design
§4.2); no existe un REQ-A aprobado que obligue a implementarla. 11 informa y
rechaza relaciones inesperadas en `reportes`, incluida esa propuesta, aun sin
GRANT a roles U5. 11/16 no incluyen excepciones por nombre ni por propietario.
Objetos futuros requieren autorización y revisión de su matriz, no tolerancia
silenciosa en esta batería. Los objetos transitorios de ADP de 20 se revierten
antes de volver a comparar la matriz.

### M04 — SEC-17: creación atómica y referencias calificadas

En una copia limpia autorizada, revisar el texto de `funciones_seguridad.sql`:
CREATE, ALTER OWNER, REVOKE PUBLIC y GRANT deben estar dentro de una única
transacción; todas las referencias nuevas deben estar calificadas. Para probar
interrupción, autorizar otra corrida controlada, interrumpir la instalación antes
del COMMIT y comprobar desde otra conexión que no existe ninguna de las tres
funciones. Reinstalar completa solo con autorización y repetir 10/11.
No intentar CREATE de la API después de instalarla: sería 42723, no una prueba de
atomicidad (incidencia D-3). Esta preparación no toca el instalador paralelo.

La serialización de reset (FOR UPDATE) y los tiempos de autenticación D16/RR-06
requieren inspección del código y ensayos multisesión/mediciones separados: estos
scripts de una sesión no acreditan concurrencia ni igualdad temporal. Comparar
ramas válida/incorrecta/mail inexistente/hash inválido, costos y dispersión, sin
registrar valores de contraseña. No atribuir garantías universales a esos ensayos.

### M05 — instalación limpia y conexiones reales (D12)

- SEC-01.R y regresiones de atributos: repetir el orden completo en otra instancia
  limpia autorizada; no reejecutar CREATE ROLE sobre una instalación existente.
- Después de 40, en la sesión de control ejecutar **solo con autorización de este
  paso** `49_preparar_logins.sql`. Crea identidades LOGIN de soporte y reportes sin
  PASSWORD; conserva sus OID en TEMP como procedencia para limpiar.
- Si la autenticación exige contraseña, asignarla **fuera del repositorio** por
  `\password tst_u5_soporte` / `\password tst_u5_reportes`, con SCRAM. No incluirla
  en SQL, argumentos, variables de shell ni evidencia; tampoco publicar verificadores.
- Abrir conexiones nuevas como esas identidades, con `-X`, la variable obligatoria
  de destino y `ON_ERROR_STOP=1`; ejecutar `50_login_reportes.sql` y
  `51_login_soporte.sql` respectivamente. No usar SET ROLE para simular este paso.
  40 ya verifica reset de negocio con valores sintéticos; 51 comprueba conexión,
  vistas, EXECUTE y denegación de UPDATE sin requerir fixtures compartidos.
- Cerrar ambas conexiones. Volver a la **misma sesión de control** y ejecutar
  `52_limpiar_logins.sql`; DROP OWNED/DROP ROLE, sin CASCADE, seguido de comprobación
  post-COMMIT. No abandonar la corrida con identidades abiertas. Si se perdió la
  sesión de procedencia, detenerse y acordar recuperación, no adoptar roles.
- D9 sigue pendiente: no se revoca CONNECT/TEMP ni se presupone su revocación.
  Inventariar `has_database_privilege` y configuración de autenticación para los
  logins; si falta CONNECT, solicitar autorización específica, no ampliar GRANT
  automáticamente. Los ensayos con SET ROLE no prueban autenticación de red.

`P8.membresias` se prepara con el filtro corregido (A-3): solo filas cuyo rol **o**
miembro pertenece a los nueve roles U5 o al prefijo `tst_u5_`. Como aquí **no** se
retiran los nueve roles instalados, el resultado esperado tras limpiar es **3**,
exactamente las membresías de app_web; las que involucran efímeros deben ser **0**.
Se compara además el conjunto con EXCEPT en ambos sentidos. No contar las tres
membresías predefinidas de `pg_monitor` ni presentar esto como repetición ya ejecutada
del P8 histórico, que retiraba también sus roles U5 y por eso esperaba cero.

**Membresías — design §3.4/SEC-07:** 10 contrasta por EXCEPT las tres opciones de
`app_web`: `admin_option=false`, `inherit_option=true`, `set_option=false`.
14 concede y contrasta las mismas opciones para las identidades soporte/reportes;
la identidad sin privilegios no tiene membresías. La herencia permite los accesos
positivos; ninguna prueba exige SET ROLE al grupo desde app_web o desde un efímero.
Los SET ROLE a identidades/grupos parten del superusuario de control, por lo que
SET FALSE en estas membresías no los impide. ADMIN FALSE mantiene SEC-10.

### M06 — SEC-01.N: rechazo de login NOLOGIN

En conexión independiente, intentar iniciar sesión como `rol_app_lectura`, sin
asignarle contraseña ni LOGIN. Conservar el diagnóstico de autenticación real y
confirmar que sigue NOLOGIN en catálogo. Un fallo de transporte/pg_hba previo a
la evaluación del rol no acredita este caso. No se fuerza SQLSTATE 42501 a un
rechazo de conexión: ese código se exige en los casos SQL de acceso prohibido.

## Límites de esta preparación

Todos los REQ y SEC tienen SQL o procedimiento documentado; **ninguno tiene
resultado de ejecución nuevo**. Permanecen manuales logs/SO, conexiones reales,
reidentificación, interrupción atómica, reinstalación limpia y mediciones/concurrencia.
No se implementan D4, D8 adicional ni D9: solo se contrasta la matriz escrita,
las restricciones de reset ya aprobadas y la rama TEMP observada.
No se cambia ninguna evidencia, objeto TPI/U3/U4 ni archivo `odd/`.
