# Informe de auditoría — Unidad 5, Parte B

Activación y prueba del primer nivel de auditoría nativa de PostgreSQL sobre Food Store.
Ejecutado el 2026-11-02 en un laboratorio descartable. Fragmento de log:
[`log_auditoria_prueba.txt`](log_auditoria_prueba.txt). Operaciones:
[`../sql/auditoria_test.sql`](../sql/auditoria_test.sql).

## 1. Entorno

| Aspecto | Valor |
|---|---|
| Motor | PostgreSQL 17.11 (imagen `postgres:17`, `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`) |
| Instancia | Contenedor descartable `foodstore_u5_auditoria_b`, sin red (`--network none`) ni puertos publicados; destruido al terminar |
| Base | `foodstore_auditoria_b`, con `schema.sql`, `datos_iniciales.sql` y `objetos_programables.sql` sin cambios |
| Bases anteriores | No se usaron ni se modificaron |

## 2. Parámetros modificados

Se aplicaron con `ALTER SYSTEM`, que los escribe en `postgresql.auto.conf`, y se activaron con
`SELECT pg_reload_conf()`, sin reiniciar. `pg_settings` confirmó cada valor con origen
`configuration file`.

| Parámetro | Valor | Qué registra |
|---|---|---|
| `log_connections` | `on` | Cada intento de conexión: llegada (`connection received`, con host y puerto), autenticación (método y regla de `pg_hba.conf`) y autorización (usuario, base y aplicación). También registra los intentos rechazados |
| `log_disconnections` | `on` | El fin de cada sesión, con su duración, usuario, base y origen |
| `log_statement` | `mod` | El texto de las sentencias que modifican datos o estructura: DDL más `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE` y `COPY FROM`. **No registra los `SELECT`** |
| `log_line_prefix` | `'%m [%p] %q%u@%d %r '` | Antepone a cada línea la hora con milisegundos, el PID del proceso, `usuario@base` y `host(puerto)` de origen |

`log_line_prefix` no lo exige la consigna, pero se agregó porque el valor por defecto
(`'%m [%p] '`) no dice quién ejecutó cada sentencia ni desde dónde.

Otros ajustes del laboratorio, necesarios para la prueba y no de auditoría:

- **Registro en archivo.** `logging_collector = on`, `log_filename = postgresql.log` y
  `log_file_mode = 0600`, fijados al arrancar el contenedor.
- **Autenticación por contraseña.** Una regla `host all all 127.0.0.1/32 scram-sha-256` al
  principio de `pg_hba.conf`. La imagen trae `trust` para el loopback por TCP, que acepta
  cualquier conexión: sin este cambio, el inicio de sesión fallido no podía fallar.

## 3. Operaciones de prueba

`auditoria_test.sql` se ejecutó por TCP (`host=127.0.0.1`) para que el log registrara el origen.
Ejecutó una lectura de `producto`, una inserción en `categoria` y una actualización del stock de
un producto. La inserción y la actualización corrieron dentro de una transacción que termina en
`ROLLBACK`, así que no quedó ningún cambio: la comprobación final devolvió 0 categorías de prueba.
El script terminó con exit 0.

El intento fallido usó un rol inexistente (`auditor_inexistente`) y una contraseña sintética
generada al azar. El servidor respondió `FATAL: password authentication failed` y psql terminó
con exit 2.

Ninguna contraseña aparece en el log: SCRAM nunca envía la contraseña al servidor. Una búsqueda
exacta de la contraseña del superusuario sobre el log completo dio 0 coincidencias.

## 4. Lectura del fragmento (punto 3)

| Evento | Quién | Qué | Cuándo | Desde dónde |
|---|---|---|---|---|
| Conexión de la prueba (PID 174) | `postgres`, autenticado con `scram-sha-256` | Abre una sesión en `foodstore_auditoria_b` con `application_name=auditoria_test` | 19:56:37.456 a .462 UTC | `127.0.0.1`, puerto 47058 |
| Inserción | `postgres` | `INSERT INTO public.categoria …`, con el texto completo | 19:56:37.464 UTC | `127.0.0.1(47058)` |
| Actualización | `postgres` | `UPDATE public.producto SET stock = stock + 1 …` | 19:56:37.465 UTC | `127.0.0.1(47058)` |
| Desconexión | `postgres` | Fin de la sesión, que duró 0,010 s | 19:56:37.466 UTC | `127.0.0.1(47058)` |
| Inicio de sesión fallido (PID 186) | Se presentó como `auditor_inexistente` | Rechazado: `password authentication failed`. El `DETAIL` aclara que el rol no existe y qué regla de `pg_hba.conf` se aplicó | 19:56:37.548 UTC | `127.0.0.1`, puerto 47064 |

El PID permite relacionar todas las líneas de una misma sesión.

**Lo que este mecanismo no muestra:**

- **La lectura no aparece.** Con `log_statement = mod`, el `SELECT` sobre `producto` no quedó
  registrado. Una lectura masiva de datos personales pasaría desapercibida.
- **No se ve que los cambios se revirtieron.** `BEGIN` y `ROLLBACK` no son modificaciones, así que
  no se registran. El log muestra el INSERT y el UPDATE, pero no que se deshicieron: leído solo,
  parecería que los cambios quedaron guardados.
- **No hay detalle de las filas.** El log guarda el texto de la sentencia, no qué filas cambiaron
  ni sus valores anteriores y nuevos. No se puede saber qué producto tenía el `id` mínimo ni qué
  stock tenía antes.
- **No se ve qué hacen las rutinas por dentro.** Un `SELECT` que llama a una función que modifica
  datos no se registra con `mod`, y las sentencias que ejecuta una rutina tampoco aparecen como
  sentencias propias.
- **El origen se puede falsear o repetir.** `application_name` lo elige el cliente, y si varios
  usuarios entran con el mismo rol, el log no los distingue.

**pgaudit (nociones; no se instaló).** pgaudit es una extensión que escribe registros de auditoría
estructurados en el mismo log. Permite:

- registrar por clase de sentencia (`READ`, `WRITE`, `DDL`, `ROLE`, `FUNCTION`), incluidas las
  lecturas;
- registrar qué objeto tocó cada sentencia, también cuando ocurre dentro de funciones;
- auditar solo tablas o roles elegidos, con la auditoría por objeto (`pgaudit.role`), por ejemplo
  todos los `SELECT` sobre `usuario`.

Así cubre la falta de lecturas y de granularidad por objeto. pgaudit **no** registra los valores
de las filas, ni anteriores ni nuevos. Si se necesitara un historial fila por fila, haría falta
otro mecanismo, como triggers de auditoría o decodificación lógica.

## 5. ¿El log es un activo sensible? (punto 4)

Sí. El log revela quién se conecta, desde dónde y cuándo, la estructura de la base y el texto de
cada modificación, incluidos los valores literales de las sentencias, que pueden contener datos
personales o, por error, contraseñas. Además es la evidencia para reconstruir un incidente, así
que también importa que nadie pueda alterarlo. Debería leerlo solo el administrador de la base y
el responsable de auditoría o seguridad: en el sistema operativo, archivos propiedad del usuario
`postgres` con permisos `0600` (`log_file_mode`, como en esta prueba: `-rw------- postgres
postgres`) o `0640` con un grupo de auditoría dedicado. En el motor, nunca roles de aplicación:
leer el log desde SQL (`pg_read_file`, `pg_ls_logdir`) exige ser superusuario o tener roles
predefinidos como `pg_read_server_files` o `pg_monitor`, que no deben otorgarse a esos roles.

## 6. Límites de esta prueba

- Se ejecutó en un laboratorio descartable, no en un servidor de desarrollo persistente. En otra
  instancia hay que aplicar los mismos parámetros y comprobarlos con `pg_settings`.
- Las operaciones se hicieron como `postgres`, para que la prueba fuera simple. En un uso real las
  haría un rol de aplicación (Parte A), y el log mostraría ese rol.
- Las conexiones por socket local siguieron en `trust`, que es la configuración de la imagen.
- No se probaron la rotación del log, el envío a syslog ni la protección contra borrado.
