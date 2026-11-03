# Informe del simulacro de incidente — Unidad 5, Parte C

Cubre los puntos 1, 2 y 3 de la Parte C: simulacro, verificación del escalamiento y log
anonimizado. Los puntos 4, 5 y 6 (reconstrucción con IA, contraste y decisión de contención)
quedan pendientes y se completan en una sesión nueva, usando solo
[`log_simulacro_anonimizado.txt`](log_simulacro_anonimizado.txt).

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

## 10. Pendiente

- **Punto 4 — Reconstrucción con IA.** Pendiente. Se hará en una sesión nueva, entregando solo
  `log_simulacro_anonimizado.txt`, sin contexto adicional.
- **Punto 5 — Contraste humano.** Pendiente. Comparar la reconstrucción con las secciones 4 a 6 de
  este informe: qué acertó la IA, qué omitió y qué afirmó sin sustento en el log.
- **Punto 6 — Decisión de contención.** Pendiente. La toma el equipo a partir de la evidencia, no
  como una acción automática derivada de la IA.
