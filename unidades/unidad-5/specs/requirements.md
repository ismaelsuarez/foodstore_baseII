# Requirements — Unidad 5: Administración y Seguridad de Food Store

**Trabajo Práctico — Unidad 5 / Semana 9**
Base de Datos II — Tecnicatura Universitaria en Programación — UTN
**Integrantes:** Avalos Pablo, Blangetti Sofia, Suarez Ismael
**Motor objetivo:** PostgreSQL 17.11
> **Estado de la Parte A (2026-11-02).** Los scripts de `unidades/unidad-5/sql/` se instalaron y
> validaron en instancias PostgreSQL 17.11 descartables y aisladas, ya destruidas (`design.md`
> §15; evidencia en `unidades/unidad-5/validacion_parte_a/`). SEC-01 a SEC-20 tienen PASS, salvo
> SEC-16, cuyo PASS vale para el intervalo ensayado, y SEC-04, pendiente de aceptación formal del
> equipo. P8.membresias se repitió con la aserción corregida y dio PASS. La POC previa está en
> `design.md` §13.7 (evidencia en `unidades/unidad-5/poc_permisos/`).

> **Revisión técnica final de la Parte A (2026-10-26, Claude Code).** Corrige la
> interpretación de la cadena SECURITY DEFINER → SECURITY INVOKER, el conjunto mínimo
> de privilegios, la verificación de privilegios por defecto, las suposiciones sobre
> propietarios, la validación bcrypt, los ejemplos con contraseñas literales, la lectura
> de `pedido`, las pruebas de escalamiento y la trazabilidad REQ ↔ SEC. La numeración
> REQ-A01…A12 y SEC-01…SEC-20 se conserva.

---

## Fuentes declaradas

| Fuente | Disponibilidad | Observación |
|---|---|---|
| Consigna oficial TP U5 (PDF) | Disponible — extraída con Ghostscript | 7 páginas, texto completo leído |
| Material Clase 1 (PDF: DBA, Roles, Permisos, Auditoría) | Disponible — extraída con Ghostscript | 16 páginas, texto completo leído |
| Material Clase 2 (PDF: Complemento U5) | Disponible — extraída con Ghostscript | 8 páginas, texto completo leído |
| AGENTS.md del repositorio | Disponible | Leído y aplicado |
| schema.sql (raíz) | Disponible | Leído, modelo oficial |
| objetos_programables.sql (TPI) | Disponible | Leído, 7 rutinas + 5 triggers |
| Informe de análisis de brechas (Claude Opus) | **NO DISPONIBLE** | No existe como archivo en el repositorio |
| Diseño técnico v1 (Claude Opus) | **NO DISPONIBLE** | No existe como archivo en el repositorio |
| Diseño técnico v2 / correcciones (Claude Opus) | **NO DISPONIBLE** | No existe como archivo en el repositorio |

Los tres documentos de trabajo previo con Claude Opus no se encuentran en el repositorio ni en el
directorio de Unidad 5. Este requirements.md y el design.md se construyen a partir de las demás
fuentes obligatorias disponibles, incorporando las decisiones aceptadas (D1–D13) declaradas en el
prompt de especificación, y las omiten donde hubieran aportado criterios que solo ellos contienen.

---

## Contexto del sistema

Food Store es una base PostgreSQL que modela un comercio de comidas. Fue construida durante las
Unidades 1 a 4. El esquema canónico comprende:

- **Cinco tablas:** `categoria`, `usuario`, `producto`, `pedido`, `detalle_pedido`
- **Tres ENUM:** `forma_pago`, `rol`, `estado_pedido`
- **Siete rutinas** y **cinco triggers** del TPI (ver `objetos_programables.sql`), todas
  SECURITY INVOKER y sin `SET search_path`
- **Cuatro vistas convencionales** y **una materializada** (Unidad 3, instaladas en base separada)
- Un campo `usuario.contrasena VARCHAR(255)` que almacena el hash de la credencial
- Un campo `usuario.rol ENUM('ADMIN','USUARIO')` de dominio de negocio (distinto de los roles del motor)

**Propietarios reales: no verificados.** Las evidencias registradas instalan los objetos con
`-U postgres`, lo que sugiere que su propietario es `postgres`, pero el diseño no lo asume:
el propietario real de cada objeto canónico se inventaría antes de implementar (VP-02 en
`design.md` §14) y se conserva sin cambios (D2). Ningún requisito depende de que
`admin_datos` sea propietario de los objetos canónicos.

Todo el trabajo de esta unidad se ejecuta sobre una copia de laboratorio explícitamente autorizada.
No se modifica el esquema canónico ni las definiciones de los objetos programables existentes.

---

## Alcance de la especificación

Este documento cubre la **Parte A** del TP: diseño e implementación del esquema de roles y
permisos de mínimo privilegio. Se documentan además las dependencias con las Partes B, C y D,
que condicionan algunas decisiones de diseño.

Las Partes B, C, D y E no se especifican aquí en detalle; sus requisitos son los de la consigna.

---

## Requisitos de la Parte A

### REQ-A01 — Roles del esquema de seguridad

El esquema de seguridad de Food Store comprende los siguientes roles. Los cuatro primeros son
obligatorios según la consigna. Los tres adicionales son decisiones propias del equipo (D6).

**Roles de grupo obligatorios (Clase 1):**

| Rol | Tipo | Función declarada |
|---|---|---|
| `rol_app_lectura` | grupo (NOLOGIN) | Lectura del catálogo público; habilita SELECT sobre `v_productos_vigentes` (que ya incluye `categoria_nombre`) porque es el acceso mínimo para servir el sitio sin exponer tablas base ni datos de pedidos o usuarios |
| `rol_app_escritura` | grupo (NOLOGIN) | Flujo operativo de compra; habilita la creación de pedidos (INSERT con columnas restringidas y lectura de `pedido.id` para `RETURNING`) y el EXECUTE sobre la única interfaz de venta autorizada, porque el backend necesita registrar órdenes sin poder leer datos de pedidos o detalles ni modificar stock o totales directamente |
| `rol_soporte` | grupo (NOLOGIN) | Atención al cliente; habilita lectura de identidad pública y resumen de pedidos porque soporte no debe ver contraseñas ni modificar datos de negocio |
| `rol_reportes` | grupo (NOLOGIN) | Panel gerencial; habilita solo SELECT sobre objetos analíticos agregados porque reportes no debe modificar datos ni acceder a información individual identificable |

**Roles de grupo adicionales propuestos (D6):**

| Rol | Tipo | Justificación |
|---|---|---|
| `rol_app_autenticacion` | grupo (NOLOGIN) | Agrupa el EXECUTE sobre `fn_autenticar` para separar la capacidad de autenticarse de la capacidad de leer catálogo o escribir pedidos; `app_web` necesita ambas y se las otorga como membresías independientes |
| `rol_propietario_ventas` | grupo (NOLOGIN) | Propietario únicamente de `api_registrar_detalle_pedido`; no tiene miembros. Es el **usuario efectivo** de toda la cadena de venta (ver REQ-A10). El propietario de las siete rutinas canónicas del TPI no cambia (D2) |
| `rol_propietario_credenciales` | grupo (NOLOGIN) | Es el propietario de `fn_autenticar` y `fn_resetear_password`; no tiene miembros — análogo a `rol_propietario_ventas` para las rutinas de credenciales |

Los roles propietarios NOLOGIN son NOINHERIT, no tienen miembros, no tienen `CREATE` sobre
ningún esquema y no tienen atributos (SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS).
Su único propósito es ser el OWNER de las rutinas SECURITY DEFINER, de modo que esas rutinas
—y todo lo que ejecutan— operen con el privilegio mínimo necesario.

**Roles de login obligatorios:**

| Rol | Tipo | Membresías |
|---|---|---|
| `app_web` | login | `rol_app_lectura`, `rol_app_escritura`, `rol_app_autenticacion` (todas sin ADMIN OPTION) |
| `admin_datos` | login | Ninguna de los grupos de aplicación (D13) |

`admin_datos` no hereda los grupos de la aplicación ni es propietario de los objetos canónicos.
Es un rol de administración de datos con privilegios explícitos de lectura y creación de objetos
analíticos en `reportes` (detalle en `design.md` §2.2 y §3). La instalación de roles y permisos la
ejecuta un superusuario durante una etapa de instalación autorizada, no `admin_datos`.

**Verificación de soporte y reportes (D12):**
`rol_soporte` y `rol_reportes` se verifican con identidades efímeras de prueba (`tst_u5_*`) durante
la implementación de la Parte A. No se crean cuentas de login permanentes para ellos.

### REQ-A02 — Principio de mínimo privilegio

Cada rol recibe exactamente los privilegios necesarios para cumplir su función, sin permisos
adicionales. En particular:

- `rol_app_escritura` no recibe ningún privilegio sobre `detalle_pedido`.
  El acceso a esa tabla se canaliza exclusivamente a través de `api_registrar_detalle_pedido`.
- `rol_app_escritura` no recibe UPDATE sobre ninguna columna de `pedido` y su lectura de `pedido`
  se limita a la columna `id`, necesaria para `INSERT ... RETURNING id`.
- Ningún rol de aplicación puede modificar directamente `producto.stock`.
- `app_web` no recibe DELETE ni TRUNCATE sobre ninguna tabla de dominio.
- `admin_datos` no recibe SUPERUSER, CREATEROLE ni CREATEDB (decisión D13).
- Ningún rol de aplicación recibe SUPERUSER, CREATEDB ni CREATEROLE.
- Ningún rol de U5 tiene ADMIN OPTION sobre ningún otro rol.
- Los roles de grupo no tienen atributo LOGIN.
- Los propietarios NOLOGIN reciben privilegios **por columna** limitados a lo que la cadena
  de ejecución realmente lee, bloquea o escribe (`design.md` §3).
- La lectura del catálogo se limita a vistas que filtran registros eliminados (`v_productos_vigentes`),
  no a las tablas base directamente.

### REQ-A03 — Permiso a nivel de columna

El script `roles.sql` debe incluir al menos un caso de permiso a nivel de columna, como práctica
explícita requerida por la consigna.

La forma elegida es `INSERT` restringido a las columnas necesarias de `pedido` para
`rol_app_escritura`: `usuario_id` y `forma_pago`, más `SELECT (id)` para obtener el
identificador generado mediante `RETURNING id`. Esto demuestra el mecanismo de permiso por
columna sin otorgar acceso a `fecha`, `estado`, `total`, `eliminado` ni a los datos de otros
pedidos. `fecha` toma siempre el default `CURRENT_DATE` del schema (D15, aprobada).

Los propietarios NOLOGIN (`rol_propietario_ventas`, `rol_propietario_credenciales`) también
reciben privilegios por columna; son casos adicionales del mismo mecanismo.

El permiso redundante de `rol_soporte` sobre columnas de `usuario` (SELECT de id, nombre, etc.)
se elimina de este diseño: `v_usuarios_publico` ya cumple esa función de forma más segura y
mantenible, y duplicar el acceso vía columnas aumentaría la superficie de ataque sin beneficio.

### REQ-A04 — Permisos por defecto (ALTER DEFAULT PRIVILEGES)

El script debe incluir sentencias `ALTER DEFAULT PRIVILEGES` acotadas a los contextos donde
son necesarias:

1. **Esquema `reportes`**: los objetos analíticos futuros creados por `admin_datos` en `reportes`
   otorgan SELECT automáticamente a `rol_reportes`.
2. **EXECUTE global**: las funciones futuras creadas por `admin_datos` en cualquier esquema
   revocan EXECUTE a PUBLIC por defecto, como defensa en profundidad.

No se aplica `ALTER DEFAULT PRIVILEGES` sobre `public`: ese alcance es demasiado amplio y
otorgaría permisos automáticos sobre nuevas tablas operativas que pueden requerir un control
diferente.

La verificación se realiza sobre `pg_default_acl` (o con `\ddp` en psql). La vista
`information_schema.default_privileges` no existe en PostgreSQL y no debe usarse.

### REQ-A05 — USAGE sobre esquema

Todo rol que acceda a objetos del esquema `public` debe recibir `GRANT USAGE ON SCHEMA public`.
Sin este privilegio, ningún otro permiso sobre los objetos del esquema es efectivo. Esto incluye
a los propietarios NOLOGIN, porque el código que ejecutan resuelve nombres de `public` con su
identidad. Ningún rol de U5 recibe `CREATE` sobre `public`.

### REQ-A06 — Verificación de privilegios

La salida de `\du` y de las consultas de catálogo debe confirmar que cada rol tiene exactamente
los privilegios previstos en esta especificación: ni más, ni menos. Como
`information_schema.role_table_grants` no incluye privilegios por columna, sobre rutinas, sobre
esquemas, privilegios por defecto ni membresías, la verificación combina:

- `information_schema.role_table_grants` y `information_schema.role_column_grants`
- `information_schema.role_routine_grants` o `aclexplode(pg_proc.proacl)`
- `has_schema_privilege` / `pg_namespace.nspacl`
- `pg_default_acl` (o `\ddp`)
- `pg_auth_members` (incluidas `admin_option`, `inherit_option` y `set_option`)

La comparación contra la matriz de `design.md` §3 se hace con EXCEPT bidireccional y se adjunta
como evidencia en la entrega.

### REQ-A07 — Restricción de EXECUTE sobre rutinas (decisión D3)

La decisión D3 aplica específicamente a `registrar_detalle_pedido` y `calcular_total_pedido`:
se revoca EXECUTE a PUBLIC sobre ambas y se otorga explícitamente solo a
`rol_propietario_ventas`, que es el usuario efectivo de la cadena de venta. `calcular_total_pedido`
lo invocan las funciones trigger de total, que se ejecutan con ese mismo usuario efectivo; sin
ese GRANT la venta falla.

Las cinco funciones trigger (`fn_set_subtotal`, `fn_validar_detalle_vigente`,
`fn_recalcular_total_insert`, `fn_recalcular_total_update`, `fn_recalcular_total_delete`)
son invocadas exclusivamente por sus triggers. PostgreSQL verifica EXECUTE sobre la función
trigger al crear el trigger, no al dispararlo (comprobado en la POC: `design.md` §13.7, T08). Se revoca
PUBLIC como buena práctica y no se requiere GRANT a ningún rol.

En todas las versiones vigentes, incluida PostgreSQL 17, `pg_proc.proacl NULL` significa
privilegios por defecto: el propietario y **PUBLIC con EXECUTE**. Esto no cambió en PostgreSQL 15
(ese cambio afectó a `CREATE` sobre el esquema `public`, no a EXECUTE sobre funciones). La
verificación se realiza con `aclexplode(coalesce(proacl, acldefault('f', proowner)))` y con pruebas
de comportamiento. Una reinstalación desde cero de `objetos_programables.sql` vuelve a crear las
rutinas con el ACL por defecto. Esos ACL se recuperan con el procedimiento manual de
`unidades/unidad-5/sql/README.md` (RR-07), que se limita a ACL y preserva los objetos canónicos.
`roles.sql` no se reaplica: no es repetible y falla si los roles ya existen.

### REQ-A08 — Esquema dedicado `reportes`

Se crea un esquema dedicado `reportes` para los objetos analíticos (decisión D10).
`rol_reportes` recibe USAGE sobre ese esquema y SELECT sobre los objetos analíticos allí instalados.
`admin_datos` recibe USAGE y CREATE sobre `reportes`. Los demás roles no reciben acceso a
`reportes` salvo indicación explícita.

### REQ-A09 — Protección de datos personales en objetos analíticos

Los nuevos objetos analíticos instalados en el esquema `reportes` no exponen:
- Datos de identificación directa: `nombre`, `apellido`, `mail`, `celular`, `contrasena`
- Identificadores que permitan reidentificación indirecta de usuarios individuales en conjuntos pequeños

Los objetos analíticos operan sobre agregaciones (totales, conteos, promedios por categoría/mes)
o sobre versiones anonimizadas de los datos. Este requisito conecta con la Parte D del TP.

### REQ-A10 — Interfaces controladas SECURITY DEFINER (decisión D1)

El diseño contempla tres rutinas nuevas con SECURITY DEFINER, cada una con un propietario
NOLOGIN y `search_path` fijo. Ninguna duplica la lógica de negocio de los objetos canónicos.

**Contexto de ejecución (corrección de interpretación).** Una rutina SECURITY DEFINER se ejecuta
con la identidad de su propietario. Una rutina SECURITY INVOKER se ejecuta con el **usuario
efectivo del momento** (`current_user`), no con los privilegios de su propio propietario. Las
funciones trigger sin SECURITY DEFINER se comportan igual: usan el usuario efectivo de la
sentencia que las dispara. Por lo tanto, cuando `app_web` invoca `api_registrar_detalle_pedido`:

1. El usuario efectivo pasa a ser `rol_propietario_ventas`.
2. `registrar_detalle_pedido` (INVOKER) se ejecuta como `rol_propietario_ventas`.
3. Los triggers de `detalle_pedido` y `calcular_total_pedido` también se ejecutan como
   `rol_propietario_ventas`.
4. Solo las verificaciones de claves foráneas se ejecutan con la identidad del propietario
   de la tabla referenciada (mecanismo interno del motor).

En consecuencia, `rol_propietario_ventas` necesita todos los privilegios que usa la cadena
completa, y ninguno más. El propietario original de las rutinas canónicas no aporta privilegios
a esa ejecución.

**`api_registrar_detalle_pedido` (D1 — interfaz de venta):**
Función SECURITY DEFINER que invoca el procedimiento canónico `registrar_detalle_pedido`.
Es la única ruta autorizada para `rol_app_escritura` hacia las operaciones de venta.
El propietario es `rol_propietario_ventas` (no el propietario del procedimiento canónico, que
conserva su propietario original conforme a D2).

**`fn_autenticar` (nueva — autenticación):**
Valida credenciales mediante hash (`pgcrypto`) sin exponer `usuario.contrasena` a `app_web`.
Solo compara contra el hash almacenado cuando este tiene el formato bcrypt exacto que produce
`gen_salt('bf')` (`$2a$`, costo de dos dígitos, 53 caracteres del alfabeto bcrypt; 60 caracteres
en total); `$2b$` y `$2y$` se rechazan (D16). Los marcadores académicos (`SEED_NO_AUTH`,
`hash_no_valido`) y cualquier otro valor devuelven cero filas sin revelar la causa. Las ramas de
mail inexistente y hash inválido ejecutan igualmente un cálculo bcrypt de costo equivalente, para
que el tiempo de respuesta no revele si el mail existe (D16). Esa es la intención del diseño: la
equivalencia temporal no está acreditada (RR-06). El propietario es `rol_propietario_credenciales`.
Solo `rol_app_autenticacion` tiene EXECUTE.

**`fn_resetear_password` (nueva — reset de soporte):**
Permite a `rol_soporte` forzar un cambio de contraseña sin UPDATE directo sobre `usuario`.
Bloquea la fila con FOR UPDATE entre la validación del rol y la actualización para evitar
condiciones de carrera concurrentes. El propietario es `rol_propietario_credenciales`.
Solo `rol_soporte` tiene EXECUTE.

Las tres rutinas se crean, en una única transacción ejecutada por el superusuario de instalación, con:
- `SECURITY DEFINER`
- `SET search_path = public, pg_temp` (`pg_catalog` se busca implícitamente primero y `pg_temp`
  queda explícitamente al final)
- Referencias calificadas con esquema dentro de la rutina nueva
- `ALTER ... OWNER TO` al propietario NOLOGIN, `REVOKE ALL ... FROM PUBLIC` y `GRANT EXECUTE`
  al grupo autorizado antes del `COMMIT`

El permiso PUBLIC de ejecución se revoca en todos los casos.

### REQ-A11 — Identidades temporales para pruebas

Para verificar permisos se crean roles temporales de prueba con prefijo `tst_u5_` y sin
privilegios adicionales a los de sus grupos (decisión D12). Estos roles se eliminan al finalizar
las pruebas. No se usan credenciales de producción para los ensayos.

Ningún script, ejemplo ni evidencia contiene contraseñas literales. Las contraseñas sintéticas de
prueba se generan en tiempo de ejecución, se transmiten como parámetros enlazados y se descartan.
Los roles de login se crean sin `PASSWORD` en el texto SQL; si necesitan contraseña, se asigna con
`\password` de psql, que envía el verificador SCRAM calculado en el cliente.

### REQ-A12 — Compatibilidad con objetos existentes

El script `roles.sql` no modifica:
- Las cinco tablas canónicas del schema raíz
- Las definiciones ni los propietarios de las siete rutinas y los cinco triggers del TPI
- Los objetos de U3 (índices, vistas, materializada) instalados en su base separada

Los GRANT y REVOKE sobre rutinas existentes cambian su ACL sin alterar sus definiciones. La
conservación se verifica comparando huellas de catálogo (definición, propietario, triggers)
tomadas antes y después de aplicar `roles.sql`: solo pueden diferir los ACL previstos por D3.

---

## Dependencias con las demás partes del TP

### Dependencia A → B (Auditoría)

La Parte B activa `log_connections`, `log_disconnections` y `log_statement` en el servidor.
La estrategia de auditoría del simulacro (decisión ajuste 2) debe:
- Registrar intentos de login fallidos y exitosos contra `fn_autenticar`
- Registrar lecturas masivas de `usuario`
- Registrar intentos de escalamiento de privilegios
- **No registrar contraseñas en texto plano** — ni en el log nativo ni en el log del simulacro
- El log producido en B alimenta directamente el simulacro de C

Los parámetros enlazados solo protegen las contraseñas si el servidor no registra sus valores:
`log_parameter_max_length = 0` y `log_parameter_max_length_on_error = 0` son condición previa de
cualquier prueba que invoque `fn_autenticar` o `fn_resetear_password` (`design.md` §7).

La verificación de permisos de lectura del archivo de log se documenta según el sistema operativo
(Linux o Windows) donde se ejecute la prueba (ajuste 4 de la especificación).

### Dependencia A → C (Simulacro de incidente)

El esquema de permisos diseñado en A es el que el simulacro de C pone a prueba. En particular:
- El intento de otorgar membresía en `admin_datos` a un rol de bajo privilegio debe **fallar**
  si el diseño de A es correcto. En PostgreSQL 16+ ese GRANT exige ADMIN OPTION sobre
  `admin_datos` (o SUPERUSER); ningún rol de U5 la tiene.
- Si no falla, se trata de un hallazgo de defecto de seguridad que debe corregirse antes de continuar.
- Los datos del log del simulacro se anonimizan antes de entregarse a la IA (mails, nombres,
  identificadores se reemplazan por tokens sintéticos).

### Dependencia A → D (Protección de datos)

La tabla `usuario_anon` construida en D reproduce la estructura de `usuario` con datos sintéticos
deterministas. Los objetos analíticos en el esquema `reportes` pueden operar sobre esta tabla
o sobre agregaciones que no reidentifiquen individuos (requisito REQ-A09).

---

## Criterios de aceptación generales (SEC-01 a SEC-20)

Los criterios detallados —con su prueba positiva, negativa y de regresión— se definen en
`design.md` §8. La numeración se conserva. Trazabilidad entre requisitos y criterios:

| Criterio | Tema | Requisitos que verifica |
|---|---|---|
| SEC-01 | Siete roles de grupo NOLOGIN | REQ-A01 |
| SEC-02 | Grupos sin SUPERUSER, CREATEDB, CREATEROLE | REQ-A02 |
| SEC-03 | Equivalencia API ↔ procedimiento canónico; CALL directo denegado | REQ-A07, REQ-A10, REQ-A12 |
| SEC-04 | `rol_reportes`: USAGE en `reportes` y solo objetos analíticos | REQ-A08, REQ-A09 |
| SEC-05 | Venta solo por la API; DML directo sobre `detalle_pedido` denegado | REQ-A02, REQ-A10 |
| SEC-06 | `admin_datos`: LOGIN sin SUPERUSER, CREATEDB, CREATEROLE; privilegios exactos | REQ-A01, REQ-A02 |
| SEC-07 | Membresías exactas de `app_web`, sin ADMIN OPTION | REQ-A01, REQ-A06 |
| SEC-08 | `pedido`: INSERT por columna y SELECT (id); sin acceso a `detalle_pedido` | REQ-A02, REQ-A03 |
| SEC-09 | Sin DELETE ni TRUNCATE para la aplicación | REQ-A02 |
| SEC-10 | Escalamiento por membresía denegado (ADMIN OPTION) | REQ-A02, dependencia A → C |
| SEC-11 | ADP en `reportes`; nada automático en `public` | REQ-A04, REQ-A08 |
| SEC-12 | ADP global: funciones futuras sin EXECUTE para PUBLIC | REQ-A04 |
| SEC-13 | EXECUTE de rutinas: API sí; canónicas no | REQ-A07, REQ-A10 |
| SEC-14 | Permisos por columna de `pedido` | REQ-A03 |
| SEC-15 | Objetos canónicos intactos y funcionando | REQ-A12 |
| SEC-16 | Contraseñas fuera de los logs | REQ-A11, dependencia A → B |
| SEC-17 | Endurecimiento SECURITY DEFINER | REQ-A10 |
| SEC-18 | Reset de soporte: alcance y prohibición sobre ADMIN | REQ-A10 |
| SEC-19 | Pruebas negativas con identidad efímera sin membresías | REQ-A06, REQ-A11 |
| SEC-20 | Sin SUPERUSER y sin residuos de identidades efímeras | REQ-A02, REQ-A11 |
| — | Matriz exacta (EXCEPT bidireccional) | REQ-A05, REQ-A06 — verificación transversal de `design.md` §8 |

---

## Decisiones aceptadas (referencia)

| ID | Decisión | Estado en este documento |
|---|---|---|
| D1 | `api_registrar_detalle_pedido` como interfaz SECURITY DEFINER que invoca el procedimiento canónico | Aplicada en REQ-A10 |
| D2 | Conservar propietarios reales y definiciones de los siete objetos canónicos del TPI; `rol_propietario_ventas` es OWNER solo de `api_registrar_detalle_pedido` | Aplicada en REQ-A10 y REQ-A12; propietarios reales a inventariar (VP-02) |
| D3 | Revocar EXECUTE a PUBLIC sobre `registrar_detalle_pedido` y `calcular_total_pedido`; GRANT explícito de ambos solo a `rol_propietario_ventas`; REVOKE de PUBLIC sobre funciones trigger | Aplicada en REQ-A07 |
| D4 | No otorgar UPDATE sobre `pedido.estado` hasta definir su caso de uso | Documentada como recomendación pendiente en design.md §9 |
| D6 | Tres roles adicionales: `rol_app_autenticacion`, `rol_propietario_ventas` (OWNER de `api_registrar_detalle_pedido`), `rol_propietario_credenciales` | Aprobada 2026-11-02; aplicada en REQ-A01 |
| D8 | Contraseña nueva no nula ni vacía; soporte no puede resetear cuentas ADMIN; otras políticas pendientes de definición | Documentada como recomendación en design.md §9 |
| D9 | Propuesta de revocar CONNECT y TEMP a PUBLIC; sujeta a autorización sobre la instancia aislada | Documentada como pendiente de aprobación en design.md §9 |
| D10 | Crear esquema dedicado `reportes` | Aplicada en REQ-A08 |
| D11 | `SELECT ... FOR SHARE` sobre `usuario` exige SELECT de las columnas leídas y UPDATE sobre al menos una columna; se propone `UPDATE (celular)` para `rol_propietario_ventas` | Requisito comprobado en la POC (T07.09, T10; design.md §9 y §13.7); elección de `celular` aprobada 2026-11-02 para la implementación de laboratorio; riesgo residual RR-01 vigente |
| D12 | Identidades efímeras `tst_u5_*` para verificar accesos de soporte y reportes; sin cuentas permanentes adicionales | Aplicada en REQ-A01 y REQ-A11 |
| D13 | `admin_datos` sin CREATEROLE ni CREATEDB, no propietario de objetos canónicos, con privilegios explícitos | Aplicada en REQ-A01 y REQ-A02 |
| D14 | POC en una instancia PostgreSQL 17.11 dedicada y descartable, con base única `foodstore_u5_poc` | Aprobada 2026-10-26; la ejecución de la POC se autoriza por separado (design.md §13) |
| D15 | `rol_app_escritura` sin `INSERT (fecha)` sobre `pedido`; rige el default `CURRENT_DATE` | Aprobada 2026-10-26; aplicada en REQ-A03 |
| D16 | `fn_autenticar` acepta solo `$2a$` y ejecuta un cálculo bcrypt en todas las ramas; la equivalencia temporal no está acreditada (RR-06) | Aprobada 2026-10-26; aplicada en REQ-A10 |
| D17 | La batería TPI no se ejecuta en la POC; se ejecuta en SEC-15 durante la implementación | Aprobada 2026-10-26 |
| D18 | Privilegios operativos de `admin_datos` (design.md §2.2) | Aprobada 2026-10-26; aplicada en REQ-A01 |

---

## Fuera de alcance de esta especificación

- Implementación SQL (no se escribe `roles.sql` en este documento)
- Ejecución de pruebas en PostgreSQL
- Partes B, C, D y E del TP (se mencionan solo como dependencias)
- Configuración de `pg_hba.conf` o `postgresql.conf`
- Row-Level Security (se menciona en la Clase 1 como ampliación optativa)
- Extensión `pgaudit` (nociones; instalación no requerida por la consigna)
- Credenciales reales de ningún entorno

## Entregables y ubicación

**BITACORA.md** debe crearse en la raíz del repositorio (`foodstore_baseII/BITACORA.md`),
no dentro de `unidades/`. Registra todos los prompts relevantes enviados a la IA, las
respuestas recibidas (resumidas) y las validaciones o correcciones humanas aplicadas,
incluyendo al menos un caso de error o imprecisión detectado.

**Especificaciones de Kiro:** los archivos `requirements.md` y `design.md` se mantienen bajo
`unidades/unidad-5/specs/` durante el desarrollo. Para la entrega formal se copian a
`unidades/unidad-5/docs/kiro_roles_spec/`, que es la carpeta que menciona la consigna.
No eliminar los originales de `specs/`.
