# Unidad 5 — Parte A: instalación de seguridad

**Estado (2026-11-02): instalado y validado en laboratorio.** Estos scripts se instalaron
siguiendo este procedimiento en dos instancias limpias de PostgreSQL 17.11, descartables y
aisladas, y se validaron con `pruebas/` (207 RESULT PASS / 0 FAIL en cada instalación). También
se ejecutaron la interrupción antes del COMMIT (M04) y la autenticación SCRAM. Resultados en
[`design.md` §15](../specs/design.md); evidencia en
[`../validacion_parte_a/`](../validacion_parte_a/README.md). Los `.sql` son byte a byte los que
se ejecutaron (sha256 registrado en cada corrida); por eso sus encabezados conservan el texto
«no ejecutado» de la etapa de escritura. Nunca se instalaron en una base compartida. SEC-04
sigue pendiente de aceptación formal del equipo. Motor objetivo: PostgreSQL 17.x; referencia del proyecto: 17.11.

Autoridades: [requirements.md](../specs/requirements.md),
[design.md](../specs/design.md) y [POC](../poc_permisos/README.md).
No se modifican el schema raíz, las definiciones/propietarios del TPI ni objetos U3/U4.

## Antes de autorizar una ejecución

- Confirmar una base de laboratorio y su instancia explícitamente autorizadas.
  **Los roles son globales del clúster: crear otra base NO aísla los roles de una
  instancia compartida.** La variable `u5_base_objetivo` comprueba el nombre de la base,
  no acredita aislamiento ni autorización de la instancia.
- Deben existir las cinco tablas, tres ENUM, siete rutinas y cinco triggers canónicos;
  las cuatro vistas U3 en `public`; una única `mv_facturacion_categoria_mes` en
  `public` o `reportes`; y `pgcrypto` instalada en `public`.
- La ausencia de U3 o de `pgcrypto` **detiene** la instalación. No se ejecutan scripts
  históricos ni `CREATE EXTENSION` automáticamente. Su instalación requiere otra
  autorización (§5.2, VP-07/VP-11). No se crea ni duplica la materializada ausente,
  aunque §4.2 contemple esa alternativa: esta etapa la excluye expresamente.
- Instalador: superusuario efectivo, no `admin_datos`. Ningún rol U5 o `tst_u5_*`
  debe existir. Se conservan los propietarios reales; no se presupone `postgres`.
- Se exige `public` sin CREATE para PUBLIC ni otros roles no confiables; las ACL
  previas incompatibles se informan, no se corrigen. La guarda conservadora admite
  como creadores existentes al propietario de esquema/base, `pg_database_owner`
  y superusuarios; cualquier otro creador obliga a revisión humana. También se
  rechaza CREATE para PUBLIC en otros esquemas, para no concederlo indirectamente
  a los propietarios NOLOGIN (§2.1).
- No deben existir entradas previas en `pg_default_acl`: §6 espera exactamente las
  dos entradas nuevas. Si `reportes` existe, debe pertenecer al instalador y no
  tener concesiones adicionales. No se adopta silenciosamente un esquema ajeno.
- Conservar inventario VP y las huellas F0 de SEC-15 **antes** de modificar ACL;
  las pruebas compararán F1. El inventario no reemplaza la comparación completa.

## Orden de instalación (aplicado en la validación integral)

Desde la raíz, con `u5_base_objetivo` definido por quien autorice la base (no contiene
una contraseña). Seleccionar host/puerto/usuario instalador de esa instancia fuera
del repositorio; no confiar en una conexión implícita a otra instancia.

```sh
psql -X -v ON_ERROR_STOP=1 -v u5_base_objetivo="$u5_base_objetivo" -d "$u5_base_objetivo" -f unidades/unidad-5/sql/00_precondiciones.sql
psql -X -v ON_ERROR_STOP=1 -v u5_base_objetivo="$u5_base_objetivo" -d "$u5_base_objetivo" -f unidades/unidad-5/sql/roles.sql
psql -X -v ON_ERROR_STOP=1 -v u5_base_objetivo="$u5_base_objetivo" -d "$u5_base_objetivo" -f unidades/unidad-5/sql/funciones_seguridad.sql
```

Estos comandos son instrucciones para una etapa autorizada posterior, no permiso
para ejecutarlos ahora. El nombre se compara usando interpolación literal segura
`:'u5_base_objetivo'`; una variable ausente, vacía o distinta provoca
`RAISE EXCEPTION` bajo `ON_ERROR_STOP`, nunca una salida con `\quit` ni un default.
Las pruebas usan exactamente la misma variable y comparación de destino real.

| Orden | Archivo | Transacción / `-1` |
|---|---|---|
| 1 | `00_precondiciones.sql` | `BEGIN READ ONLY`/`COMMIT`; **sin `-1`**. Solo inventario/guardas VP-00..VP-12. |
| 2 | `roles.sql` | Repite precondiciones antes de escribir; luego una transacción para todos los roles/ACL/ADP. **Sin `-1`**. |
| 3 | `funciones_seguridad.sql` | Requiere roles instalados; una transacción para las tres funciones, OWNER, REVOKE y GRANT. **Sin `-1`**. |
| 4 | Scripts de verificación en `pruebas/` | Otro responsable los implementa. Seguir su README para orden, variables y transacciones; no inventar `-1` ni ejecutarlos aquí. |

`ON_ERROR_STOP` está activado también dentro de los SQL. Un error interrumpe el
proceso; cerrar la conexión revierte la transacción abierta. No continuar en otra
sesión como si la etapa hubiese terminado. Los dos archivos de instalación son
atómicos **por archivo**, no una transacción conjunta. Si falla el tercero después
del segundo, los roles y las ACL del segundo permanecen; revisar el diagnóstico.

Se usa `CREATE ROLE`/`CREATE FUNCTION`, no actualización silenciosa ni
`CREATE OR REPLACE`. Repetir la instalación falla. Solo `CREATE SCHEMA IF NOT EXISTS
reportes` sigue §4.1, con comprobación previa estricta de propietario/ACL.
No se proporciona limpieza destructiva ni se crean identidades efímeras aquí.

## Asignación segura de contraseñas (fuera del repositorio)

Los LOGIN se crean sin cláusula `PASSWORD`. No son cuentas habilitadas con una
contraseña por estos scripts; otras rutas de autenticación dependen de `pg_hba.conf`.
No introducir contraseñas, verificadores, cadenas de conexión sensibles ni hashes
reales en archivos, argumentos de shell, evidencias o historial Git.

En una sesión interactiva futura de psql moderno, conectada por un canal seguro a
la instancia autorizada, confirmar `password_encryption = scram-sha-256`; establecer
ese valor en la sesión si corresponde. Luego usar exclusivamente los prompts de:

```text
\password app_web
\password admin_datos
```

Con SCRAM configurado, psql calcula el verificador en el cliente y envía ese
verificador, no la contraseña en texto plano. El verificador sigue siendo sensible;
no capturar ni publicar esta sesión ni sus logs. No usar `ALTER ROLE ... PASSWORD`
con valores literales ni sustituir variables de contraseñas dentro de SQL.
Esto configura credenciales del motor, no los hashes bcrypt de `public.usuario`.

Antes de **cualquier prueba de credenciales de negocio**, verificar §7/SEC-16:
`log_parameter_max_length = 0`, `log_parameter_max_length_on_error = 0`,
`log_statement = mod` (no `all`), `log_file_mode = 0600` y
`password_encryption = scram-sha-256`; usar valores sintéticos generados fuera del
texto SQL, en el shell, importados con `\getenv` y enviados con `\bind`.
Seguir [M02](pruebas/README.md#m02--sec-16nr-revisión-de-logs-no-protección) para
buscar los valores exactos mediante `grep -F` y limpiar el entorno; nunca
concatenar/interpolar credenciales en SQL ni guardarlas en archivos. La configuración de servidor y las
pruebas de logs corresponden a otra etapa; estos archivos no las cambian.

## Matriz implementada

S = SELECT, I = INSERT, U = UPDATE, X = EXECUTE. Paréntesis = columnas exactas;
sin paréntesis = objeto completo. Todo objeto de tabla/rutina está en `public`,
salvo la materializada que conserva su ubicación real. No se conceden opciones de
concesión, privilegios de secuencias ni DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN.

| Rol | Objeto | Privilegio |
|---|---|---|
| `rol_app_lectura` | `v_productos_vigentes` | S |
| `rol_app_escritura` | `pedido` | I(usuario_id, forma_pago); S(id) |
| `rol_app_escritura` | `api_registrar_detalle_pedido(bigint,bigint,integer)` | X |
| `rol_soporte` | `v_usuarios_publico`, `v_pedidos_resumen` | S |
| `rol_soporte` | `fn_resetear_password(bigint,text)` | X |
| `rol_reportes` | `<ubicación real>.mv_facturacion_categoria_mes` | S |
| `rol_propietario_ventas` | `pedido` | S(id, usuario_id, eliminado); U(total) |
| `rol_propietario_ventas` | `usuario` | S(id, eliminado); U(celular) |
| `rol_propietario_ventas` | `producto` | S(id, precio, stock, disponible, eliminado); U(stock) |
| `rol_propietario_ventas` | `detalle_pedido` | S(pedido_id, producto_id, subtotal, eliminado); I(pedido_id, producto_id, cantidad, precio_unitario) |
| `rol_propietario_ventas` | `registrar_detalle_pedido(bigint,bigint,integer)`, `calcular_total_pedido(bigint)` | X |
| `rol_propietario_credenciales` | `usuario` | S(id, mail, contrasena, rol, eliminado); U(contrasena) |
| `rol_propietario_credenciales` | `crypt(text,text)`, `gen_salt(text)` | X heredado de PUBLIC, no GRANT adicional |
| `rol_app_autenticacion` | `fn_autenticar(text,text)` | X |
| `admin_datos` | `categoria`, `producto`, `pedido`, `detalle_pedido` | S |
| `admin_datos` | `usuario` | S(id, rol, eliminado, created_at) |
| `admin_datos` | `<ubicación real>.mv_facturacion_categoria_mes` | S |
| Todos los grupos salvo excepción siguiente, más `admin_datos` | esquema `public` | USAGE explícito |
| `rol_reportes` | esquema `public` | USAGE explícito solo si la materializada reside allí |
| `rol_reportes` | esquema `reportes` | USAGE |
| `admin_datos` | esquema `reportes` | USAGE, CREATE |
| `rol_reportes` | futuras tablas/vistas/materializadas de `admin_datos` en `reportes` | S por ADP |
| PUBLIC | futuras funciones de `admin_datos` (global) | EXECUTE revocado por ADP |
| PUBLIC | siete rutinas canónicas y tres interfaces nuevas | EXECUTE revocado |

Los propietarios conservan sus privilegios de propiedad. Ningún GRANT a las cinco
funciones trigger: EXECUTE se comprueba al crear el trigger, no al dispararlo.
`app_web` no recibe privilegios de objeto directos: hereda exactamente
`rol_app_lectura`, `rol_app_escritura` y `rol_app_autenticacion`, sin ADMIN OPTION
(`admin_option=false`, `inherit_option=true`, `set_option=false`, explícitos).
Hereda capacidades sin asumir la identidad de sus grupos ni delegar membresías;
los SET ROLE desde el superusuario de pruebas no dependen de estas opciones.
Las identidades efímeras de soporte/reportes usan las mismas tres opciones
(design §3.4). `admin_datos` no tiene
membresías. Los dos propietarios son NOLOGIN, NOINHERIT, sin miembros ni membresías.
Los demás grupos son NOLOGIN INHERIT; los LOGIN son INHERIT. Los nueve roles tienen
NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOREPLICATION/NOBYPASSRLS.

Las tres funciones se crean con `SECURITY DEFINER`,
`SET search_path = public, pg_temp`, propietario NOLOGIN y ACL cerrada antes del
COMMIT. `pg_catalog` queda implícitamente primero. Solo se llama a la API con
SELECT; el CALL canónico queda interno. No se cambia el propietario de ninguna
rutina TPI. RR-01 permanece: U(celular) habilita bloqueos pero permitiría escribir
esa columna a quien obtuviera SQL arbitrario como `rol_propietario_ventas`.

## Nombres exactos a crear (DDL, no instalación realizada)

- Grupos: `rol_app_lectura`, `rol_app_escritura`, `rol_soporte`, `rol_reportes`,
  `rol_app_autenticacion`, `rol_propietario_ventas`, `rol_propietario_credenciales`.
- LOGIN: `app_web`, `admin_datos`.
- Esquema: `reportes` (propietario: superusuario instalador; se conserva si ya es suyo).
- Función `public.api_registrar_detalle_pedido(bigint,bigint,integer) RETURNS void`,
  OWNER `rol_propietario_ventas`.
- Función `public.fn_autenticar(text,text) RETURNS TABLE(usuario_id bigint, rol public.rol)`,
  OWNER `rol_propietario_credenciales`.
- Función `public.fn_resetear_password(bigint,text) RETURNS void`,
  OWNER `rol_propietario_credenciales`.
- No se crean vistas, materializadas, extensiones, tablas, secuencias ni triggers.
  `v_resumen_ventas_rol_mes` es propuesta futura, fuera de la Parte A: ningún
  REQ-A aprobado obliga a implementarla. Las pruebas no toleran su presencia
  como excepción; informan cualquier relación inesperada en `reportes`.

## Trazabilidad de secciones (objetivos, no aceptación acreditada)

| Sección | Requisitos | Criterios relacionados |
|---|---|---|
| Precondiciones: identidad/VP-00..04, propietarios/secuencias, colisiones | REQ-A01/A06/A12 | SEC-15/17/20 |
| Precondiciones: VP-05..12, ACL, extensión y vistas | REQ-A04/A05/A06/A07/A08/A12 | SEC-04/10/11/12/15/17 |
| Roles §1–2: atributos/membresías | REQ-A01/A02/A06/A11 | SEC-01/02/06/07/10/20 |
| Roles §3: esquemas | REQ-A05/A08/A09 | SEC-04/06/17 |
| Roles §4: aplicación/soporte | REQ-A02/A03/A09 | SEC-04/05/08/09/14 |
| Roles §5–6: propietarios | REQ-A02/A03/A10 | SEC-03/05/17/18 |
| Roles §7–8: administración/materializada | REQ-A01/A02/A08/A09 | SEC-04/06 |
| Roles §9: D3 | REQ-A07/A12 | SEC-03/13/15 |
| Roles §10: ADP | REQ-A04/A08 | SEC-11/12 |
| Funciones §1: API | REQ-A02/A07/A10/A12 | SEC-03/05/13/15/17 |
| Funciones §2: autenticación | REQ-A10/A11 | SEC-16/17 |
| Funciones §3: reset | REQ-A10/A11 | SEC-16/17/18 |
| README: contraseñas y orden de verificación | REQ-A06/A11 | SEC-16/19/20 |

REQ-A06 (EXCEPT bidireccional), REQ-A11 (identidades efímeras), SEC-01..20 y las
regresiones requieren evidencia posterior de `pruebas/`; no se consideran
satisfechos por comentarios o inspección estática. SEC-19 y la limpieza de SEC-20
pertenecen al responsable de pruebas. REQ-A09 además requiere revisar cada objeto
analítico futuro: el ADP no valida su contenido ni impide reidentificación.

## Recuperación manual de ACL tras reinstalar el TPI (RR-07)

**Procedimiento documentado, no ejecutado ni autorizado por este cierre.** No es
una migración nueva ni vuelve idempotente `roles.sql`. Requiere autorización
separada y revisión humana de cada bloque antes de aplicarlo. Mantener la
aplicación detenida y sin otras sesiones de negocio desde antes de la
reinstalación autorizada hasta terminar la verificación: recrear rutinas puede
restaurar transitoriamente EXECUTE a PUBLIC.

### 1. Precondiciones e inventario, sin reparar roles

En la instancia/base autorizadas, usar superusuario, psql `-X`,
`ON_ERROR_STOP=1`, `-v u5_base_objetivo` explícito y sin `-1` si se administran
BEGIN/COMMIT manualmente. Incluir `pruebas/00_destino.sql` para comprobar el
mismo destino real, versión y guardas. **No** incluir `00_precondiciones.sql`
ni `roles.sql`: sus guardas exigen ausencia de roles U5 para una instalación nueva.

Verificar los nueve roles existentes contra design §3.4: LOGIN solo para
`app_web` y `admin_datos`; INHERIT salvo los dos propietarios; todos sin
SUPERUSER/CREATEDB/CREATEROLE/REPLICATION/BYPASSRLS. Verificar las tres membresías
de `app_web` (`admin_option=false`, `inherit_option=true`, `set_option=false`),
ninguna otra, sin miembros/membresías de propietarios y sin `tst_u5_*` previos.
Usar las consultas de `pruebas/10_catalogo.sql` (incluye estos controles).
Si falta un rol o difieren atributos/opciones, **detenerse**: nunca recrearlo ni
aplicar `ALTER ROLE` o GRANT de membresía silenciosos para hacerlo coincidir.

Inventariar tablas, columnas, vistas U3, materializada única, extensión pgcrypto,
esquemas, propietarios reales y ACL; revisar public sin CREATE no confiable y
los dos ADP de §6. La recuperación no instala dependencias ni corrige diferencias
ajenas. Conservar la huella SEC-15 de las siete rutinas/cinco triggers/tablas
**después de la reinstalación y antes de recuperar ACL**, además de la huella
previa a reinstalar si existe. No fabricar una huella histórica perdida.

### 2. Reaplicar D3: únicamente ACL de las siete rutinas canónicas

Con existencia, firmas, definiciones y propietarios canónicos confirmados,
reaplicar en una transacción manual el bloque siguiente. Los únicos beneficiarios
no propietarios permitidos son los de design §3.2; si hay otras concesiones,
detenerse para revisión en vez de revocar roles ajenos automáticamente.

```sql
BEGIN;
REVOKE EXECUTE ON PROCEDURE public.registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.calcular_total_pedido(BIGINT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_set_subtotal() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_validar_detalle_vigente() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_total_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_total_update() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_total_delete() FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    TO rol_propietario_ventas;
GRANT EXECUTE ON FUNCTION public.calcular_total_pedido(BIGINT) TO rol_propietario_ventas;
COMMIT;
```

No conceder EXECUTE sobre las funciones trigger. El propietario real conserva sus
privilegios; no se redefine ninguna rutina ni se cambia su propietario.

### 3. Solo si se recrearon tablas/vistas: restituir GRANT de relación/columna

Una reinstalación exclusivamente de rutinas no pierde estos permisos: omitir este
paso en ese caso. Si hubo recreación autorizada de tablas/vistas, verificar primero
sus definiciones canónicas y seleccionar solo los GRANT perdidos del bloque
siguiente, dentro de una transacción manual. No son autorización para recrearlas.

```sql
GRANT SELECT ON public.v_productos_vigentes TO rol_app_lectura;
GRANT INSERT (usuario_id, forma_pago) ON public.pedido TO rol_app_escritura;
GRANT SELECT (id) ON public.pedido TO rol_app_escritura;
GRANT SELECT ON public.v_usuarios_publico, public.v_pedidos_resumen TO rol_soporte;
GRANT SELECT (id, usuario_id, eliminado) ON public.pedido TO rol_propietario_ventas;
GRANT UPDATE (total) ON public.pedido TO rol_propietario_ventas;
GRANT SELECT (id, eliminado) ON public.usuario TO rol_propietario_ventas;
GRANT UPDATE (celular) ON public.usuario TO rol_propietario_ventas;
GRANT SELECT (id, precio, stock, disponible, eliminado) ON public.producto TO rol_propietario_ventas;
GRANT UPDATE (stock) ON public.producto TO rol_propietario_ventas;
GRANT SELECT (pedido_id, producto_id, subtotal, eliminado) ON public.detalle_pedido TO rol_propietario_ventas;
GRANT INSERT (pedido_id, producto_id, cantidad, precio_unitario) ON public.detalle_pedido TO rol_propietario_ventas;
GRANT SELECT (id, mail, contrasena, rol, eliminado) ON public.usuario TO rol_propietario_credenciales;
GRANT UPDATE (contrasena) ON public.usuario TO rol_propietario_credenciales;
GRANT SELECT ON public.categoria, public.producto, public.pedido, public.detalle_pedido TO admin_datos;
GRANT SELECT (id, rol, eliminado, created_at) ON public.usuario TO admin_datos;
```

Si también se recreó la materializada por autorización separada, seleccionar
**solo uno** de estos GRANT según su ubicación real verificada; nunca duplicarla:

```sql
-- Alternativa si reside en public:
GRANT SELECT ON public.mv_facturacion_categoria_mes TO rol_reportes, admin_datos;
-- Alternativa si reside en reportes:
GRANT SELECT ON reportes.mv_facturacion_categoria_mes TO rol_reportes, admin_datos;
```

Los permisos de esquema y ADP deben seguir coincidiendo con §3.3/§6: no se pierden
por recrear solo tablas/rutinas. Si difieren, detenerse; no ampliar el procedimiento.

### 4. Interfaces U5: conservar las existentes; si falta alguna, detenerse

Inventariar las tres firmas, sin asumir que una reinstalación TPI las elimina:

```sql
SELECT to_regprocedure('public.api_registrar_detalle_pedido(bigint,bigint,integer)'),
       to_regprocedure('public.fn_autenticar(text,text)'),
       to_regprocedure('public.fn_resetear_password(bigint,text)');
```

Si alguna firma está **ausente**, RR-07 se detiene en este punto y se informa.
RR-07 se limita a ACL: no crea funciones ni asigna propietarios. Crear una
interfaz U5 ausente es otro procedimiento, que exige autorización expresa y
separada, y se analiza aparte. No se resuelve ejecutando `funciones_seguridad.sql`
dentro de esta recuperación.

Si la interfaz ya existe, conservar definición y propietario; verificar SEC-17 y
reaplicar **solo** su REVOKE/GRANT si se perdió el ACL aprobado:

```sql
REVOKE ALL ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) TO rol_app_escritura;
REVOKE ALL ON FUNCTION public.fn_autenticar(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_autenticar(TEXT, TEXT) TO rol_app_autenticacion;
REVOKE ALL ON FUNCTION public.fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_resetear_password(BIGINT, TEXT) TO rol_soporte;
```

Seleccionar solo las firmas existentes verificadas y envolver sus ACL en una
transacción. Una definición, propietario o ACL adicional inesperados exige detenerse,
no `CREATE OR REPLACE`, ALTER OWNER de lo existente ni una reparación silenciosa.

### 5. Verificar antes de reabrir acceso

- **SEC-13:** catálogo de las diez rutinas sin PUBLIC; solo propietario y beneficiario
  previsto. Probar API autorizada y denegación de CALL/total directo (20/30).
- **SEC-15:** comparar huella anterior/posterior a recuperar ACL con EXCEPT
  bidireccional: solo pueden diferir ACL previstos; definiciones, propietarios y
  triggers deben coincidir. Comparar también con la huella previa a reinstalar,
  si está disponible. La captura F0 de instalación nueva (`01_f0.sql`) no se
  reejecuta sobre roles existentes; conservar/comparar el inventario manual sin
  desactivar su guarda. Repetir batería TPI por M01 cuando esté autorizada.
- **Matriz:** ejecutar 10 → 11 → 16 en una sesión de verificación nueva; luego
  12/20/30 y, con controles SEC-16 y entorno de M02, 40. Revisar SEC-17, permisos
  efectivos y limpieza final. Los procedimientos manuales siguen pendientes según
  su alcance; nada de esta guía acredita resultados.

**Nunca** DROP/CREATE de objetos canónicos, cambios de sus propietarios,
`CREATE OR REPLACE`, modificación de definiciones existentes, recreación/ALTER
silencioso de roles, D9 (CONNECT/TEMP) ni instalación de dependencias. No ejecutar
esta recuperación automáticamente después del TPI ni reejecutar `roles.sql`.

## REVISAR y decisiones que no se implementan

- **§5.2, D16 y RR-06:** equivalencia temporal de bcrypt **no acreditada**.
  REVISAR: medición autorizada pendiente, sin garantía contra inferencias temporales.
  Se conserva la lógica aprobada: hashes válidos pagan
  `crypt` con su costo almacenado (04..31); inexistentes/inválidos pagan el costo
  por defecto de `gen_salt('bf')`. Hay trabajo bcrypt en ambas rutas, pero no una
  garantía de costo/tiempo idéntico para cualquier hash; entradas nulas/vacías
  abortan antes. Resolver esa diferencia exige cambiar el contrato, no inventar
  otra política. No se ha medido ni validado la ejecución de credenciales.
- **§14 VP-07:** formato/costo real de `gen_salt('bf')` y funcionamiento de pgcrypto
  pendientes de ejecución autorizada. Las precondiciones inspeccionan solo sus
  catálogos/ACL y pertenencia a la extensión, sin generar sales ni hashes.
- **§4.2 frente a §3.3:** la ubicación arbitraria de la materializada requeriría
  USAGE adicional no especificado. Opción conservadora: abortar si no está en
  `public`/`reportes`. No moverla ni conceder acceso a otro esquema.
- **§5.4 RR-07:** seguir la recuperación manual de ACL documentada arriba, con
  autorización separada. `roles.sql` sigue siendo una instalación no repetible.
  SEC-01 en una «base limpia» también necesita ausencia de esos roles en el
  clúster, no solo otra base.
- **Coherencia de las specs (alineada el 2026-11-02):** REQ-A07 remite a la
  recuperación manual de ACL en lugar de reaplicar `roles.sql`. REQ-A10 y design
  §5.2 presentan la equivalencia de costo como intención de D16, no acreditada
  (RR-06). La regla invariante de design §7.3 usa generación externa, `\getenv`,
  `\bind` y búsqueda de valores exactos, igual que M02/SEC-16.N.
- **§14 VP-00/01/02/05/06/08/10/11/12 y §7/SEC-16:** versión cliente >=16 para
  las pruebas con `\bind`, autorización/aislamiento de instancia, propietarios,
  ACL efectivos, definiciones U3 canónicas, configuración y logs no se han
  verificado en una base real. Conservar salida VP; revisar confianza de los
  propietarios de base/esquemas y F0/F1. Una guarda no certifica estos supuestos.
- **D4 pendiente:** no UPDATE de `pedido.estado`.
- **D8 parcial:** solo se rechazan contraseñas nulas/vacías y resets de ADMIN;
  longitud mínima, historial, notificaciones y ruta ADMIN siguen pendientes.
- **D9 pendiente:** no REVOKE CONNECT/TEMP de PUBLIC, ni CONNECT explícito adicional.
  Se conserva su estado real y se inventaría. No se garantiza autenticación ni
  límites de conexión; `CONNECTION LIMIT` (§2.2) no se define en esta etapa.

## Validación de esta etapa

TDD estricto **desactivado por autorización humana explícita**: escritura/revisión
sin ejecución SQL; RED/GREEN no activos. Revisión estática contra requisitos,
diseño y POC; comandos autorizados: `git diff --check`, `git status --short`
y grep de espacios finales sobre los archivos no rastreados tocados.
`bash -n` no valida SQL y no se usa. No se ejecutan clientes PostgreSQL, Docker,
instaladores, pruebas ni commits. No se modifica `odd/` ni los archivos de otro
responsable.
