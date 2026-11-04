# Informe del simulacro de incidente — Unidad 5, Parte C

Cubre los puntos 1 a 5 de la Parte C: simulacro, verificación del escalamiento, log anonimizado,
reconstrucción con IA a partir de [`log_simulacro_anonimizado.txt`](log_simulacro_anonimizado.txt)
y contraste humano. El punto 6 (decisión de contención) contiene la decisión del equipo,
aprobada el 2026-11-03.

Archivos: [`../sql/simulacro_incidente.sql`](../sql/simulacro_incidente.sql) (secuencia del
incidente) y [`../sql/simulacro_incidente.sh`](../sql/simulacro_incidente.sh) (preparación del
laboratorio, registro temporal, anonimización y limpieza).

## 1. Entorno

| Aspecto | Valor |
|---|---|
| Motor | PostgreSQL 17.11 (imagen `postgres:17`, `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`) |
| Instancia | Contenedor descartable `foodstore_u5_simulacro_c`, sin red ni puertos publicados; destruido al terminar. Los contenedores de otros proyectos no cambiaron |
| Base | `foodstore_simulacro_c`, con `schema.sql`, el seed, `objetos_programables.sql`, las vistas y la materializada de U3, `pgcrypto`, y la Parte A instalada con `roles.sql` y `funciones_seguridad.sql`. Las precondiciones pasaron |
| Fecha | 2026-11-02, entre 20:18:53 y 20:18:55 UTC |

## 2. Preparación

Se hizo antes de activar el registro completo, así que no forma parte del fragmento:

- **Cuenta de la víctima.** Un usuario sintético de Food Store: nombre «Cliente Simulacro», mail
  `cliente.simulacro@ejemplo.test` y contraseña aleatoria guardada con `crypt(…, gen_salt('bf'))`.
  La contraseña se envió como parámetro enlazado.
- **Rol temporal `tst_u5_lector`.** Un LOGIN sin contraseña al que se le otorgó a propósito
  `SELECT` sobre `public.usuario`, solo para poder reproducir la lectura masiva. `app_web` no
  tiene ese permiso en la Parte A y **no se amplió**. Al terminar, el rol se revocó y se eliminó:
  `rol_temporal_existe=false`.
- **Credenciales.** Las cuatro contraseñas del simulacro y la del superusuario se generaron al
  azar en el shell, viajaron solo por variables de entorno y se enviaron con `\bind`.

**Dos autenticaciones distintas.** La autenticación **funcional** de Food Store es
`fn_autenticar`, que compara la contraseña con el hash bcrypt de `usuario.contrasena`. Los
intentos fallidos del simulacro son de ese tipo. La autenticación de **conexión** a PostgreSQL la
resuelve `pg_hba.conf`: en este laboratorio, el loopback por TCP usa `trust`, que es la
configuración de la imagen, así que `app_web` y `tst_u5_lector` se conectaron sin contraseña.

## 3. Mecanismo de auditoría

Se usó la opción más simple: `log_statement = 'all'`, activado con `ALTER SYSTEM` y
`pg_reload_conf()` solo durante la secuencia y vuelto después a `'mod'`. Además:

- `log_connections = on` y `log_disconnections = on`;
- `log_line_prefix = '%m [%p] %q%u@%d %r '`, con hora, PID, `usuario@base` y origen;
- `log_parameter_max_length = 0` y `log_parameter_max_length_on_error = 0`, para que no se
  registren los valores enlazados.

pgaudit no se instaló.

Comprobado: el fragmento no tiene líneas `parameters:`, y una búsqueda exacta de las cinco
contraseñas sobre el **log completo** dio 0 coincidencias.

## 4. Secuencia ejecutada (punto 1)

Lo que **realmente se ejecutó**, según la salida de psql:

| # | Paso | Quién | Resultado observado |
|---|---|---|---|
| 1 | Tres llamadas a `fn_autenticar` con la cuenta de la víctima y contraseñas incorrectas | `app_web` | 0 filas cada una |
| 2 | Una llamada con la contraseña correcta | `app_web` | 1 fila: `usuario_id = 4`, `rol = USUARIO` |
| 3 | `SELECT * FROM public.usuario` (filas no mostradas) | `tst_u5_lector` | 4 filas leídas: los 3 usuarios del seed y la víctima |
| 4 | `GRANT admin_datos TO tst_u5_lector` | `tst_u5_lector` | `ERROR: permission denied to grant role "admin_datos"`, SQLSTATE `42501` |

El script terminó con exit 0, porque el error del paso 4 era el resultado esperado.

## 5. Escalamiento (punto 2)

**El intento de escalamiento falló.** PostgreSQL lo rechazó con `42501` y este detalle: «Only roles
with the ADMIN option on role "admin_datos" may grant this role.» Después del simulacro,
`admin_datos` tiene 0 miembros. Por lo tanto, para este caso **no hay un hallazgo de defecto** en
el esquema de permisos de la Parte A: un rol de bajo privilegio no puede otorgarse `admin_datos`.

## 6. Qué permite demostrar el log

| Hecho | ¿Lo muestra el log? | Detalle |
|---|---|---|
| Cuatro llamadas a `fn_autenticar` | Sí | Cuatro líneas `execute <unnamed>: SELECT * FROM public.fn_autenticar($1, $2)` de `app_web`, PID 174, entre 20:18:53.782 y .794 |
| Cuáles fallaron y cuál funcionó | **No** | Las cuatro líneas son idénticas: el log no guarda el resultado ni los parámetros (mail y contraseña) |
| Que fue siempre la misma cuenta | **No** | El mail viajó como parámetro y no se registró |
| La lectura masiva | Sí, como ejecución | `statement: SELECT * FROM public.usuario;` de `tst_u5_lector`, PID 175, a las 20:18:53.800 |
| Cuántas filas se leyeron | **No** | El log no registra resultados. Las 4 filas salen de la salida del script, no del log |
| El rechazo del escalamiento | Sí | `ERROR`, `DETAIL` y `STATEMENT` del GRANT a las 20:18:53.801 |
| Quién y desde dónde | Sí | `app_web` y `tst_u5_lector`, ambos desde `127.0.0.1`, con puertos distintos; conexión por `trust` |
| Orden y tiempos | Sí | El orden coincide con el script. Toda la secuencia ocupa unos 20 ms, entre .781 y .801 |
| Relación entre las dos sesiones | **No** | El log no dice que fue el mismo script ni la misma persona; solo que fueron dos sesiones seguidas desde el mismo origen |

En el log, la desconexión de `app_web` (PID 174) aparece después de la lectura de `tst_u5_lector`
(PID 175). Es porque `\connect`, en psql, abre la conexión nueva antes de cerrar la anterior.

## 7. Anonimización (punto 3)

El fragmento abarca desde la primera conexión de la secuencia hasta la última desconexión, filtrado
por la hora de inicio y fin del script. Se extrajo dentro del contenedor y se anonimizó antes de
escribirlo fuera, con el criterio de `usuario_anon`: mails → `usuarioN@anon.test` y nombres
personales → `Usuario N`. Se conservan las fechas, los PID, los puertos, los roles técnicos, el
origen, las sentencias y los errores, que hacen falta para la reconstrucción.

**Resultado: 0 reemplazos.** El fragmento no contenía mails ni nombres, porque:

- el mail y las contraseñas viajaron como parámetros enlazados y no se registraron;
- el log no registra las filas que devolvió la lectura masiva.

Verificación del archivo final:

| Búsqueda | Coincidencias |
|---|---|
| Mails | 0 |
| Nombres del seed y de la víctima | 0 |
| Celulares del seed | 0 |
| Hashes bcrypt (`$2a$`) | 0 |
| Las cinco contraseñas sintéticas | 0 |

No se agregó ninguna línea ni explicación al fragmento. Cuatro líneas `execute` terminan con un
espacio, que es parte de la salida original.

## 8. Incidencia del arnés

El primer intento no registró los SELECT. El script fijaba `log_statement = mod` como opción de
línea de comandos al arrancar el contenedor, y esa opción tiene prioridad sobre el valor que
después escribe `ALTER SYSTEM`. Por eso no quedaron en el log las cuatro llamadas a
`fn_autenticar` ni la lectura masiva. La secuencia sí se ejecutó, con los mismos resultados, y el
GRANT fue rechazado con `42501`.

Ese fragmento se conserva sin cambios en
[`log_simulacro_intento1_sin_select.txt`](log_simulacro_intento1_sin_select.txt). Se corrigió solo
el arnés: se quitó esa opción de arranque y se agregó una guarda que aborta si `log_statement` no
queda en `all`. Después se repitió la corrida completa en un contenedor nuevo.
`simulacro_incidente.sql` no cambió entre las dos corridas.

## 9. Limitaciones

- La autenticación de conexión fue `trust`: en un caso real habría contraseñas y otro origen.
- La lectura masiva se hizo con un rol al que se le dio el permiso a propósito. En un caso real,
  ese acceso vendría de un error de configuración o de una cuenta comprometida.
- La secuencia la ejecutó un script en unos 20 ms. Un ataque real tendría otros tiempos.
- Los nombres de los roles técnicos (`app_web`, `tst_u5_lector`) y de la base se conservaron:
  no son datos personales y hacen falta para entender el escalamiento.
- `log_statement = 'all'` registra los valores literales que aparecen en el texto de las
  sentencias, como el nombre de la base en la guarda inicial. Por eso las credenciales se
  mandaron siempre como parámetros.

## 10. Reconstrucción con IA (punto 4)

El prompt exacto y la respuesta completa se conservan sin cambios en
[`analisis_ia_log_simulacro.md`](analisis_ia_log_simulacro.md).

**Entorno.** Claude Code (modelo Claude Opus 5.5), sesión nueva abierta el 2026-11-03 a las
10:16 (UTC−3) en un directorio vacío fuera del repositorio (`~/u5c_ciego`), que solo contenía una
copia de `log_simulacro_anonimizado.txt` verificada con `cmp`. El prompt pide distinguir, en cada
afirmación, lo demostrado por una línea del log ([D]) de lo inferido ([I]).

**Fidelidad de la evidencia.** El prompt y la respuesta conservados se compararon con la
transcripción de la sesión. El prompt coincide con el texto enviado; solo difieren la sangría de la
primera línea y las marcas `<pasted_content>` con que la herramienta encierra un texto pegado. La
respuesta conservada coincide con la respuesta de la sesión.

**Contenido del prompt.** Además de las seis instrucciones, el texto pegado incluyó por error tres
párrafos de comentario de la sesión de asistencia. Mencionan el informe, el contraste del punto 5,
al equipo y la consigna oficial. Revelan que se trata de un trabajo académico, pero ningún hecho
del escenario: ni el resultado de las autenticaciones, ni las filas leídas, ni los permisos de los
roles. No se repitió la reconstrucción; queda registrado como limitación. Este prompt tampoco es el
que el equipo redactó el 2026-11-02; el detalle está en [`BITACORA.md`](../../../BITACORA.md).

**Aislamiento.** La sesión no tenía acceso al repositorio, al informe ni a sesiones anteriores.
Engram estaba activo en esa herramienta, por lo que se verificó, con autorización, la
transcripción de la sesión:

| Comprobación | Resultado |
|---|---|
| Contexto inyectado por Engram al inicio | Solo «Recent Sessions: u5c_ciego [0 observations]»: proyecto nuevo, sin observaciones |
| Herramientas usadas | Tres: listado del directorio (`ls`, `wc`), lectura del log y escritura del análisis |
| Llamadas a `mem_search` o `mem_context` | 0 |
| Menciones a `foodstore_baseii` en la transcripción | 0 |
| Memoria propia de Claude Code para ese directorio | Vacía |

La respuesta también es coherente con ese aislamiento: declara como no determinables los hechos
que solo constan en la salida del script (cuál de las cuatro llamadas tuvo éxito, cuántas filas
se leyeron).

## 11. Contraste humano (punto 5)

> Compara la respuesta de la IA con las secciones 4 a 6 y con el log. Las listas de aciertos,
> afirmaciones y puntos ya tratados se redactaron como borrador asistido por IA; la evaluación de
> omisiones y la conclusión son del equipo, que es responsable del contraste.

**Aciertos.**

- La cronología, con marcas de tiempo, PID, puertos y líneas, coincide con el log y con el orden
  de la sección 4.
- Declara como no determinables los mismos hechos que la sección 6 marca con **No**: cuál de las
  cuatro llamadas a `fn_autenticar` funcionó, con qué cuenta y cuántas filas devolvió la lectura.
- Infiere, marcándolo como [I], que la lectura masiva tuvo éxito (fueron 4 filas), que las dos
  sesiones pertenecen al mismo actor o script y que se trata de un ejercicio planificado (el prompt
  mencionaba el contexto académico; ver §10). Las tres
  inferencias son correctas.
- Interpreta las cuatro llamadas seguidas como un patrón compatible con prueba de credenciales,
  coherente con lo ejecutado: tres fallidas y una correcta.
- Advierte que `127.0.0.1` no identifica al actor real. La secuencia corrió dentro del contenedor.
- Describe correctamente el rechazo del escalamiento a partir de `ERROR` y `DETAIL` (sección 5).

**Afirmaciones con sustento débil o sin contexto.**

- «El rol `admin_datos` existe» está marcado como [D], pero no figura en el log. Se deduce de cómo
  responde PostgreSQL a un rol inexistente, por lo que corresponde a [I].
- El solapamiento de las dos sesiones está bien marcado como [D], pero sin contexto no podía
  saber que se debe a `\connect` de psql (sección 6) y no a actividad concurrente.

**Puntos que la IA destacó y el informe ya trataba.**

- La autenticación `trust` (E1 de la IA) figura en la sección 9 como condición del laboratorio.
  La IA la presenta como hallazgo de seguridad, que es lo esperable sin contexto del entorno.
- El uso de `app_web` desde psql (E3) es propio del simulacro, que reemplaza a la aplicación.

### Punto 5 — Omisiones y evaluación humana

Al comparar el análisis de la IA con los resultados reales del simulacro, consideramos que no hubo omisiones importantes en la reconstrucción cronológica.

Claude identificó los cuatro intentos de autenticación, la lectura de la tabla `usuario` y el intento fallido de escalamiento de privilegios.

Sin embargo, el log no permitía identificar que las primeras tres autenticaciones fallaron y la cuarta fue exitosa, ni que la lectura devolvió cuatro registros. Estos resultados solamente pudieron comprobarse mediante la salida del script ejecutado.

También observamos que algunas conclusiones sobre los permisos y los posibles responsables eran inferencias, no hechos confirmados.

En general, la IA realizó un análisis adecuado, pero comprobamos que un log no siempre contiene toda la información necesaria para reconstruir un incidente.

### Propuestas de contención de la IA

Se consideran insumo para el punto 6, no decisiones.
`tst_u5_lector` ya fue eliminado y `admin_datos` quedó con 0 miembros (sección 5), por lo que las
propuestas 3 y 4 no se pueden aplicar tal como están redactadas.

## 12. Decisión de contención (punto 6)

### Punto 6 — Decisión propuesta de contención

Como equipo, proponemos que ante un incidente real con estas características primero se conserven los registros de auditoría y se investigue el origen de las conexiones.

También revisaríamos los permisos de las cuentas involucradas, especialmente el acceso a información de usuarios. Si se detectara una cuenta comprometida, se bloquearía temporalmente y se evaluarían los cambios de contraseña necesarios.

En nuestro simulacro, PostgreSQL rechazó correctamente el intento de obtener permisos administrativos. Además, el rol temporal utilizado para la lectura fue eliminado al finalizar.

Por tratarse de un ejercicio controlado con datos sintéticos, no consideramos necesario ejecutar otras medidas de contención.

La decisión final corresponde al equipo y no se aplicará automáticamente ninguna recomendación de la inteligencia artificial.

**Estado: Aprobado por el equipo** (2026-11-03).
