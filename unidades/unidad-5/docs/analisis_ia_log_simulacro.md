# Análisis del log por IA — prompt y respuesta completa

- Fecha: 2026-11-03
- Herramienta: Claude Code (modelo Claude Opus 5.5, `claude-opus-5-5`)
- Archivo analizado: `log_simulacro_anonimizado.txt` (18 líneas)

---

## Prompt enviado (texto exacto, tal como se pegó)

~~~~text
Hola: 

   Analizá exclusivamente el archivo de log adjunto (PostgreSQL). No tenés otro contexto
   y no debés suponerlo.

   A partir de la información contenida en ese archivo:
   log_simulacro_anonimizado.txt
   1. Reconstruí cronológicamente lo que ocurrió.
   2. Identificá los eventos relevantes para la seguridad y explicá por qué lo son.
   3. Indicá qué usuarios, sesiones y orígenes intervienen.
   4. Para cada afirmación, distinguí si está demostrada por una línea concreta del log
      (citá la marca de tiempo) o si es una inferencia tuya.
   5. Señalá qué no puede determinarse con este log y qué información faltaría.
   6. Proponé posibles medidas de contención, justificadas en la evidencia.
 ```

 - El punto 4 es la clave para el contraste del punto 5. Te deja ver qué afirmó la IA con respaldo en el log y qué inventó. Es justo el criterio que ya
   fija la sección 10 del informe: qué acertó, qué omitió y qué afirmó sin sustento.
 - El punto 6 le pide solo propuestas. La decisión de contención la sigue tomando el equipo, como dice el informe.

 Si la consigna oficial trae un texto propio para el punto 4, usá ese en lugar de este. Guardá el prompt exacto que mandes y la respuesta completa, porque
 los dos van al informe.
~~~~

---

## Respuesta completa de la IA

Analicé solo el archivo `log_simulacro_anonimizado.txt`, que tiene 18 líneas, y no usé ningún otro contexto. Las citas usan la marca de tiempo y el número de línea (L#). La notación **[D]** significa que la afirmación está demostrada por esa línea, y **[I]** que es una inferencia mía.

---

## 1. Cronología

Todo transcurre el 2026-11-02 en UTC, entre 20:18:53.781 y 20:18:53.801, es decir, en unos 20 ms.

| Hora (.ms) | L# | Sesión (PID) | Evento |
|---|---|---|---|
| .781 | 1 | 174 | Llega una conexión desde 127.0.0.1, puerto 59610 |
| .781 | 2 | 174 | Se autentica `app_web` con `method=trust` (pg_hba.conf:119) |
| .781 | 3 | 174 | Se autoriza el acceso a la base `foodstore_simulacro_c` con `application_name=psql` |
| .782 | 4 | 174 | Ejecuta `SELECT current_database() = ... AND current_user = 'app_web' AS u5c_destino_ok` |
| .782 / .788 / .791 / .794 | 5–8 | 174 | Llama 4 veces a `public.fn_autenticar($1, $2)` |
| .799 | 9 | 175 | Llega una conexión desde 127.0.0.1, puerto 59624 |
| .799 | 10–11 | 175 | Se autentica `tst_u5_lector` con `method=trust` (pg_hba.conf:119) y se autoriza el acceso a la misma base, también con `psql` |
| .800 | 12 | 175 | Ejecuta `SELECT * FROM public.usuario;` |
| .800 | 13 | 174 | `app_web` se desconecta tras 0.019 s de sesión |
| .801 | 14 | 175 | Ejecuta `GRANT admin_datos TO tst_u5_lector;` |
| .801 | 15–17 | 175 | **ERROR**: `permission denied to grant role "admin_datos"` |
| .801 | 18 | 175 | `tst_u5_lector` se desconecta tras 0.002 s de sesión |

Las dos sesiones estuvieron abiertas al mismo tiempo entre .799 y .800. **[D]** (L9 y L13)

---

## 2. Eventos relevantes para la seguridad

**E1. Autenticación sin contraseña (`trust`) para los dos usuarios.** **[D]** (.781 L2 y .799 L10)
- Es relevante porque cualquier proceso que pueda conectarse a 127.0.0.1 entra con cualquiera de esos roles sin dar ninguna credencial. La base no verifica la identidad de quien se conecta.
- **[I]** Es probable que la regla de la línea 119 cubra más usuarios o bases, pero el log no muestra su contenido.

**E2. Cuatro llamadas a `fn_autenticar` en 12 ms.** **[D]** (.782–.794, L5–L8)
- Es relevante porque varios intentos de autenticación a nivel aplicación en tan poco tiempo son compatibles con un ataque de fuerza bruta o con la prueba de varias credenciales.
- **[I]** Ese ritmo no parece de un humano tipeando, sino de un proceso automatizado.
- Es una inferencia, y no puedo afirmarlo: el log no muestra los parámetros ni si alguno de los intentos tuvo éxito.

**E3. Uso del rol `app_web` desde un cliente que se declara `psql`.** **[D]** (.781 L3)
- **[I]** Por su nombre, `app_web` parece ser la cuenta de servicio de la aplicación web. Que se use desde `psql` sugiere un uso directo de esa cuenta, por fuera de la aplicación.
- Hay una salvedad: `application_name` lo informa el propio cliente, así que se puede falsificar.

**E4. Lectura completa de la tabla `public.usuario` por `tst_u5_lector`.** **[D]** que la sentencia se ejecutó (.800 L12).
- **[I]** Es muy probable que la lectura tuviera éxito. Después de L12 no aparece ningún ERROR, y el log sí registra errores, como se ve en L15.
- **[I]** Por el nombre, la tabla probablemente contiene datos de usuarios y quizá credenciales o hashes de contraseñas.
- **[I]** Un rol de prueba (`tst_`) con acceso a esa tabla sería un exceso de privilegio.

**E5. Intento de autoescalada de privilegios.** **[D]** `tst_u5_lector` intentó otorgarse a sí mismo el rol `admin_datos` (.801 L14), y PostgreSQL lo rechazó (.801 L15–L17).
- Es relevante porque es un intento explícito de escalar privilegios.
- El control funcionó: el rol no tiene la opción ADMIN sobre `admin_datos`. **[D]** (L16)
- **[D]** El rol `admin_datos` existe; si no existiera, el error sería otro.

**E6. Comprobación previa del objetivo (`u5c_destino_ok`).** **[D]** (.782 L4)
- **[I]** Indica un script preparado que comprueba que está conectado a la base y con el usuario esperados antes de actuar.
- **[I]** Encaja con el nombre de la base, `..._simulacro_c` **[D]**, por lo que parece un ejercicio planificado. No puedo confirmarlo.

---

## 3. Usuarios, sesiones y orígenes

| Elemento | Valor | Respaldo |
|---|---|---|
| Usuario 1 | `app_web`, sesión PID 174, puerto 59610 | [D] L1–L13 |
| Usuario 2 | `tst_u5_lector`, sesión PID 175, puerto 59624 | [D] L9–L18 |
| Rol mencionado sin conectarse | `admin_datos` | [D] L14–L17 |
| Base de datos | `foodstore_simulacro_c` | [D] L3, L11 |
| Origen | 127.0.0.1 (localhost) en ambas sesiones | [D] L1, L9 |
| Cliente declarado | `psql` en ambas sesiones | [D] L3, L11 |

- **[I]** Es plausible que ambas sesiones las haya abierto el mismo actor o script: comparten origen, cliente declarado, una ventana de 20 ms y puertos de origen cercanos.
- No está demostrado.
- **[I]** El origen 127.0.0.1 no identifica al actor real. Puede ser un proceso del mismo host o contenedor, un `docker exec`, un túnel o un proxy. El archivo además está "anonimizado", así que el valor original pudo haber sido reemplazado.

---

## 4. Demostrado frente a inferido

**Demostrado por el log:**
- Los dos usuarios entraron con `trust` mediante la regla de la línea 119. (L2, L10)
- Hubo 4 llamadas a `fn_autenticar` desde `app_web`. (L5–L8)
- Se ejecutó un `SELECT *` sobre `usuario`. (L12)
- Hubo un `GRANT` de `admin_datos` y fue rechazado. (L14–L17)
- Las duraciones de las sesiones y su solapamiento. (L13, L18)

**Inferido por mí:**
- Que el proceso fue automatizado.
- Que fue un posible ataque de fuerza bruta o de prueba de credenciales.
- Que el SELECT tuvo éxito.
- Que `usuario` contiene datos sensibles.
- Que ambas sesiones las abrió el mismo actor.
- Que `app_web` es la cuenta de la aplicación web.
- Que se trata de un simulacro planificado.

---

## 5. Lo que no se puede determinar y la información que falta

| No se puede determinar | Información que faltaría |
|---|---|
| Argumentos y resultado de cada `fn_autenticar` (qué cuentas, si alguna tuvo éxito) | Código de la función (¿es `SECURITY DEFINER`?, ¿registra intentos?) y logs de la aplicación. Ojo: registrar parámetros podría guardar contraseñas en claro. |
| Si el `SELECT` sobre `usuario` devolvió filas, cuántas y qué columnas | Auditoría por objeto (por ejemplo, pgaudit), `GRANT`s sobre `public.usuario` y esquema de la tabla |
| Quién está detrás de 127.0.0.1 (persona o proceso) | Logs del sistema operativo o del contenedor (`docker exec`, auth.log, historial de shell), configuración de red y de proxies |
| Qué permite exactamente `pg_hba.conf:119` | El archivo `pg_hba.conf` completo |
| Privilegios reales de `tst_u5_lector`, `app_web` y `admin_datos`, y quién tiene ADMIN sobre `admin_datos` | `pg_roles`, `pg_auth_members`, `\du`, `\dp public.usuario` |
| Qué pasó antes de .781 o después de .801 | Una ventana de log más amplia. Este fragmento puede estar recortado. |
| Si el log está completo y sin alterar (está anonimizado) | El original con hash y la cadena de custodia |
| Si las dos sesiones pertenecen al mismo actor | Correlación a nivel de sistema operativo y PID del cliente |
| La configuración de logging (`log_statement`, nivel de detalle) | `postgresql.conf`. **[I]** Probablemente `log_statement = 'all'`, porque se registran SELECT. |

---

## 6. Medidas de contención propuestas

Son propuestas; la decisión sigue siendo del equipo.

1. **Preservar la evidencia antes de cambiar nada.** Conviene copiar los logs originales, calcular su hash y exportar el estado de roles y privilegios. Se basa en que este archivo es un fragmento anonimizado (sección 5).
2. **Reemplazar `trust` por `scram-sha-256`** en la línea 119 de `pg_hba.conf` y recargar la configuración. Se basa en L2 y L10.
3. **Bloquear el rol `tst_u5_lector`** con `ALTER ROLE ... NOLOGIN` mientras se investiga, y revisar su `SELECT` sobre `public.usuario`. Se basa en L12 y L14.
4. **Revisar quién tiene ADMIN sobre `admin_datos`** para confirmar que el control que funcionó en L15–L16 no se puede evadir por otro rol.
5. **Restringir `app_web`** con una contraseña rotada, conexiones solo desde el host de la aplicación y sin uso interactivo, e investigar el uso con `psql`. Se basa en L3.
6. **Limitar la cantidad de intentos y registrar los resultados en `fn_autenticar`**, sin registrar las contraseñas. Se basa en L5–L8.
7. **Si se confirma que `usuario` contiene credenciales, evaluar un reseteo forzado de contraseñas.** Esta medida depende de verificar E4; hoy es una inferencia.
8. **Mejorar la trazabilidad** con pgaudit sobre las tablas sensibles y los cambios de rol, y conservando `log_connections`. Se basa en los vacíos de la sección 5.

---

¿Querés que guarde esta respuesta en un `.md` en `/home/devops/u5c_ciego` para pegarla en el informe junto con el prompt?
