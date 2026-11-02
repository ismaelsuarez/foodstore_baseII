# Design — Unidad 5: Administración y Seguridad de Food Store

**Trabajo Práctico — Unidad 5 / Semana 9**
Base de Datos II — Tecnicatura Universitaria en Programación — UTN
**Integrantes:** Avalos Pablo, Blangetti Sofia, Suarez Ismael
**Motor objetivo:** PostgreSQL 17.11
> **Estado de la Parte A (2026-11-02).** Los scripts de `unidades/unidad-5/sql/` se instalaron y
> validaron en instancias PostgreSQL 17.11 descartables y aisladas, ya destruidas (§15). No se
> instalaron en ninguna base compartida ni en bases de unidades anteriores. SEC-04 sigue pendiente
> de aceptación formal del equipo y SEC-16 vale para el intervalo ensayado. D4, D8 (resto) y D9
> siguen sin implementar.

> **Estado de evidencia.** POC de permisos (§13.7, evidencia en `../poc_permisos/`) y validación
> integral de la Parte A (§15, evidencia en `../validacion_parte_a/`). Cada evidencia vale para
> su entorno de laboratorio y para lo que efectivamente se ejecutó.

> **Revisión técnica final de la Parte A (2026-10-26, Claude Code).** Cambios principales:
> contexto de ejecución SECURITY DEFINER → INVOKER y triggers (§5.0), privilegios mínimos por
> columna derivados de la cadena completa (§3, §5.0), propietarios reales no asumidos (§3.2, §14),
> verificación de privilegios por defecto con `pg_default_acl` (§6), validación bcrypt exacta
> (§5.2), eliminación de contraseñas literales (§2.2, §7.3, §8), lectura de `pedido` limitada a
> `id` (§2.1), escalamiento con ADMIN OPTION (SEC-10), plan de POC (§13) e inventario de
> verificaciones previas (§14).

> **Consolidación de la POC (2026-11-02, Claude Code).** Resultados observados en §13.7;
> evidencia en [`../poc_permisos/`](../poc_permisos/README.md). Las afirmaciones que decían «a
> confirmar en la POC» indican ahora el caso que las comprobó o que siguen sin comprobar.
> Correcciones del plan: T03 (diez sentencias), T11 (tabla temporal con columnas explícitas),
> T12 (entre P4 y P5) y T14 (diferencias esperadas). D11 documentada con evidencia (§9).

---

## 1. Arquitectura del esquema de roles

### 1.1. Principio organizador

Se aplica el modelo de **roles de grupo + roles de login** descrito en la Clase 1:

- **Roles de grupo** (NOLOGIN): definen qué se puede hacer. Se revisan y estabilizan
  de forma independiente de quién se conecta.
- **Roles de login** (LOGIN): representan conexiones reales. Adquieren capacidades mediante
  membresía en roles de grupo. Cambiar la responsabilidad de un servicio o persona es un
  ajuste de membresía, no una reescritura de privilegios.

### 1.2. Jerarquía de roles

```
┌─────────────────────────────────────────────────────────────┐
│             ROLES DE GRUPO — NOLOGIN                        │
├─────────────────────────────────────────────────────────────┤
│  Obligatorios (consigna)     │  Adicionales (D6)            │
│  ─────────────────────────── │  ──────────────────────────  │
│  rol_app_lectura             │  rol_app_autenticacion       │
│  rol_app_escritura           │  rol_propietario_ventas      │
│  rol_soporte                 │  rol_propietario_credenciales│
│  rol_reportes                │  (sin miembros — solo OWNER) │
└──────────────────┬──────────────────────────────────────────┘
                   │ GRANT (membresía, sin ADMIN OPTION)
      ┌────────────▼──────────────────┐
      │     ROLES DE LOGIN            │
      ├───────────────────────────────┤
      │  app_web                      │
      │   ├─ rol_app_lectura          │
      │   ├─ rol_app_escritura        │
      │   └─ rol_app_autenticacion    │
      │                               │
      │  admin_datos                  │
      │   └─ (sin membresías de app)  │
      └───────────────────────────────┘
```

Los roles `rol_propietario_ventas` y `rol_propietario_credenciales` son NOLOGIN sin miembros.
Su único propósito es ser OWNER de las rutinas SECURITY DEFINER correspondientes. Como esas
rutinas se ejecutan con la identidad de su propietario, el propietario define el techo de
privilegios de todo lo que la rutina ejecuta (§5.0).

---

## 2. Especificación de roles

### 2.1. Roles de grupo

#### `rol_app_lectura` — NOLOGIN

**Justificación:** Sirve el catálogo público del sitio. Solo necesita leer productos vigentes
a través de la vista `v_productos_vigentes`, que ya proyecta `categoria_nombre`. No necesita
ver pedidos ni usuarios.

| Objeto | Privilegio | Esquema |
|---|---|---|
| `v_productos_vigentes` | SELECT | public |
| SCHEMA public | USAGE | — |

La vista no usa `security_invoker`: accede a las tablas base con los privilegios de su propietario,
por lo que `rol_app_lectura` no necesita privilegios sobre `producto` ni `categoria`. Las vistas de
U3 deben estar instaladas en la base de U5 (VP-11); si no lo están, su instalación requiere
autorización separada.

**Excluido deliberadamente:** SELECT directo sobre la tabla `categoria`. Si se necesita consultar
categorías de forma independiente de los productos, el equipo debe crear una vista específica
`v_categorias_vigentes` y otorgar SELECT sobre ella a `rol_app_lectura`. Esta vista no existe en
el modelo oficial actual y no se crea en U5 sin autorización explícita.

> Si la cátedra exige demostrar acceso directo a una tabla de catálogo, documentarlo
> en BITACORA.md y crear `v_categorias_vigentes` en ese momento.

---

#### `rol_app_escritura` — NOLOGIN

**Justificación:** Crea pedidos y accede a la interfaz de venta autorizada. No puede leer ni
modificar `detalle_pedido` directamente — esa tabla se gestiona exclusivamente a través de
`api_registrar_detalle_pedido`. No puede leer ni modificar `estado`, `total` ni `eliminado` en `pedido`.

| Objeto | Privilegio | Esquema | Nota |
|---|---|---|---|
| `pedido` | INSERT (`usuario_id`, `forma_pago`) | public | Permiso por columna — REQ-A03; sin `fecha` (D15) |
| `pedido` | SELECT (`id`) | public | Solo para `INSERT ... RETURNING id` |
| `api_registrar_detalle_pedido(bigint,bigint,integer)` | EXECUTE | public | Única interfaz de venta autorizada (D1) |
| SCHEMA public | USAGE | — | — |

**Excluido deliberadamente:**
- SELECT sobre las demás columnas de `pedido`. La versión inicial otorgaba SELECT sobre toda la
  tabla «para consultar sus propios pedidos», pero sin RLS ese privilegio expone todos los pedidos
  de todos los usuarios. Si la aplicación necesita consultar pedidos, debe hacerlo mediante una
  vista o rutina específica que se diseñe aparte.
- DELETE, TRUNCATE, UPDATE sobre `pedido`
- Todo privilegio sobre `detalle_pedido` (tabla base)
- EXECUTE directo sobre `registrar_detalle_pedido` (el procedimiento canónico del TPI)
- EXECUTE sobre `calcular_total_pedido` (función interna; el total lo mantienen los triggers)

**Nota:** La FK `fk_pedido_usuario` se verifica con la identidad del propietario de `usuario`
(mecanismo interno del motor), por lo que el INSERT no requiere SELECT sobre `usuario`.
**Comprobado en la POC (T04.1):** `app_web`, sin ningún privilegio sobre `usuario`, insertó un
pedido de U1. `fecha` inicia en `CURRENT_DATE` (D15: la aplicación no puede registrar pedidos
con otra fecha), `estado` en PENDIENTE, `total` en 0 y `eliminado` en FALSE por default del schema.

---

#### `rol_soporte` — NOLOGIN

**Justificación:** Atención al cliente. Necesita ver el estado y el resumen de pedidos,
y la identidad pública de usuarios (sin contraseña ni celular). No escribe datos de dominio.

| Objeto | Privilegio | Esquema |
|---|---|---|
| `v_usuarios_publico` | SELECT | public |
| `v_pedidos_resumen` | SELECT | public |
| `fn_resetear_password(bigint, text)` | EXECUTE | public |
| SCHEMA public | USAGE | — |

**Permisos excluidos deliberadamente:**
- SELECT sobre columnas de la tabla base `usuario`: `v_usuarios_publico` ya garantiza la
  proyección segura sin exponer `contrasena` ni `celular`, y es más mantenible que un GRANT
  por columna que habría que mantener sincronizado con la vista.
- Cualquier privilegio sobre `producto`, `pedido` o `detalle_pedido`.

---

#### `rol_reportes` — NOLOGIN

**Justificación:** Panel gerencial de solo lectura. Accede a objetos analíticos agregados.
No accede a datos individuales identificables.

| Objeto | Privilegio | Esquema |
|---|---|---|
| `mv_facturacion_categoria_mes` | SELECT | ubicación real (ver §4) |
| Objetos analíticos futuros de `admin_datos` | SELECT (por ADP) | reportes |
| SCHEMA reportes | USAGE | — |
| SCHEMA public | USAGE | solo si la materializada permanece en `public` |

---

#### `rol_app_autenticacion` — NOLOGIN (D6)

**Justificación:** Agrupa el EXECUTE sobre `fn_autenticar`. Separar esta capacidad de
`rol_app_escritura` permite otorgar autenticación sin escritura o viceversa, y facilita
la rotación o restricción futura de la identidad de login de la aplicación.

| Objeto | Privilegio | Esquema |
|---|---|---|
| `fn_autenticar(text,text)` | EXECUTE | public |
| SCHEMA public | USAGE | — |

---

#### `rol_propietario_ventas` — NOLOGIN, NOINHERIT, sin miembros (D6)

**Justificación:** Propietario de `api_registrar_detalle_pedido`. Como esa función es
SECURITY DEFINER, se ejecuta con la identidad de este rol, y todo lo que invoca sin SECURITY
DEFINER —el procedimiento canónico, sus triggers y `calcular_total_pedido`— también se ejecuta
con esta identidad (§5.0). Por eso este rol necesita exactamente los privilegios de la cadena
completa. El propietario original de las rutinas canónicas no aporta privilegios a esa ejecución.

El propietario de `registrar_detalle_pedido` y demás rutinas del TPI no cambia (D2).
Este rol no tiene miembros. Nadie se conecta como él ni lo hereda.

**Privilegios mínimos (derivados en §5.0; necesidad comprobada por ablación en la POC, T07 —
23/23 —, salvo USAGE sobre `public`, que no se ablacionó; ver §13.7):**

| Objeto | Privilegio | Por qué |
|---|---|---|
| SCHEMA public | USAGE | Resolución de nombres con su identidad |
| `pedido` | SELECT (`id`, `usuario_id`, `eliminado`) | Bloqueo y lectura del pedido; validación del trigger de vigencia |
| `pedido` | UPDATE (`total`) | Recalculo de total; además habilita `FOR UPDATE` / `FOR SHARE` |
| `usuario` | SELECT (`id`, `eliminado`) | Baja lógica del usuario del pedido |
| `usuario` | UPDATE (`celular`) — D11 | Solo para habilitar `FOR SHARE`; la cadena nunca escribe esa columna |
| `producto` | SELECT (`id`, `precio`, `stock`, `disponible`, `eliminado`) | Bloqueo, validación y precio histórico |
| `producto` | UPDATE (`stock`) | Descuento de stock; además habilita `FOR UPDATE` / `FOR SHARE` |
| `detalle_pedido` | SELECT (`pedido_id`, `producto_id`, `subtotal`, `eliminado`) | Detección de duplicado y agregado de `calcular_total_pedido` |
| `detalle_pedido` | INSERT (`pedido_id`, `producto_id`, `cantidad`, `precio_unitario`) | Alta de la línea |
| `registrar_detalle_pedido(bigint,bigint,integer)` | EXECUTE | CALL desde la función |
| `calcular_total_pedido(bigint)` | EXECUTE | Invocada por los triggers de total con esta identidad |

**No necesita (comprobado en la POC):** EXECUTE sobre las cinco funciones trigger (EXECUTE se
verifica al crear el trigger, no al dispararlo; T08), privilegios sobre las secuencias de
identidad (el valor generado por `GENERATED ALWAYS AS IDENTITY` no exige USAGE sobre la
secuencia; T09) ni privilegios adicionales para las FK (la venta de T01 funciona sin REFERENCES
ni otro GRANT fuera de la matriz).

---

#### `rol_propietario_credenciales` — NOLOGIN, NOINHERIT, sin miembros (D6)

**Justificación:** Propietario de `fn_autenticar` y `fn_resetear_password`. Al ser OWNER,
estas funciones SECURITY DEFINER se ejecutan con su identidad, sin exponer esos privilegios a
`app_web` ni a `rol_soporte`.

Este rol no tiene miembros.

**Privilegios mínimos:**

| Objeto | Privilegio | Para qué |
|---|---|---|
| SCHEMA public | USAGE | Resolución de `usuario`, `crypt` y `gen_salt` |
| `usuario` | SELECT (`id`, `mail`, `contrasena`, `rol`, `eliminado`) | Búsqueda por mail y comparación de hash; validación del destino del reset |
| `usuario` | UPDATE (`contrasena`) | Reset; además habilita `FOR UPDATE` en `fn_resetear_password` |
| `public.crypt(text,text)`, `public.gen_salt(text)` | EXECUTE | Heredado de PUBLIC según el ACL de `pgcrypto` (VP-07) |

---

### 2.2. Roles de login

#### `app_web` — LOGIN

**Justificación:** Es la identidad que usa el backend de la aplicación web para conectarse.
Acumula los privilegios necesarios para servir el catálogo, gestionar el flujo de compra
y autenticar usuarios.

```sql
-- Sin contraseña en el texto SQL. Si el rol necesita autenticarse por contraseña,
-- se asigna después y fuera del script con el metacomando de psql: \password app_web
CREATE ROLE app_web LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT rol_app_lectura        TO app_web WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT rol_app_escritura      TO app_web WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT rol_app_autenticacion  TO app_web WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
```

`\password` calcula el verificador SCRAM en el cliente y envía solo el verificador, de modo que la
contraseña no queda en el script, en el historial del repositorio ni en el log del servidor. El
verificador igualmente se trata como dato sensible.
`CONNECTION LIMIT` a definir según criterio operativo del equipo (la Clase 1 sugiere 50).

---

#### `admin_datos` — LOGIN

**Justificación:** Rol de administración de datos de la cátedra: consulta los datos de dominio y
crea objetos analíticos en `reportes`. **No es propietario de los objetos canónicos** (D2: se
conservan los propietarios reales inventariados en VP-02) y no instala roles ni permisos: esa
etapa la ejecuta un superusuario con autorización explícita.

**Decisión D13 — sin CREATEROLE ni CREATEDB:**
La Clase 1 mostraba `admin_datos WITH LOGIN PASSWORD ... CREATEDB CREATEROLE`.
La decisión D13 revierte esos atributos. En PostgreSQL 16+ un rol con CREATEROLE administra los
roles que crea (recibe ADMIN OPTION sobre ellos); en la operación normal no se crean roles, y la
incorporación de identidades es un procedimiento administrativo separado. CREATEDB no es necesario
para administrar una base existente.

```sql
-- Sin contraseña en el texto SQL (ver app_web).
CREATE ROLE admin_datos LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
```

**Privilegios operativos (D18, aprobada):**

| Objeto | Privilegio |
|---|---|
| Base de datos | CONNECT (explícito si se aprueba D9) |
| SCHEMA public | USAGE (sin CREATE) |
| SCHEMA reportes | USAGE, CREATE |
| `categoria`, `producto`, `pedido`, `detalle_pedido` | SELECT |
| `usuario` | SELECT (`id`, `rol`, `eliminado`, `created_at`) |
| `mv_facturacion_categoria_mes` | SELECT |

Sin DML sobre tablas canónicas. Como `admin_datos` no puede leer `nombre`, `apellido`, `mail`,
`celular` ni `contrasena`, tampoco puede construir en `reportes` un objeto que los exponga
(control preventivo de REQ-A09).

---

## 3. Matriz definitiva de privilegios propuestos

Las columnas `app_escritura` y `prop_ventas` fueron contrastadas en la POC (§13.7): la ruta de
venta funciona con ellas, y cada privilegio de `prop_ventas` es necesario (T07). La columna
elegida en D11 (`celular`) fue aprobada el 2026-11-02. Las demás columnas no tienen evidencia de
ejecución. Toda celda vacía significa «ningún privilegio». Abreviaturas: S = SELECT, I = INSERT, U = UPDATE, X = EXECUTE; la lista entre
paréntesis indica privilegio por columna.

### 3.1. Tablas y vistas (esquema public)

| Objeto | app_lectura | app_escritura | soporte | reportes | prop_ventas | prop_credenciales | admin_datos |
|---|---|---|---|---|---|---|---|
| `categoria` | | | | | | | S |
| `usuario` | | | | | S(id, eliminado); U(celular)¹ | S(id, mail, contrasena, rol, eliminado); U(contrasena) | S(id, rol, eliminado, created_at) |
| `producto` | | | | | S(id, precio, stock, disponible, eliminado); U(stock) | | S |
| `pedido` | | I(usuario_id, forma_pago)²; S(id) | | | S(id, usuario_id, eliminado); U(total) | | S |
| `detalle_pedido` | | | | | S(pedido_id, producto_id, subtotal, eliminado); I(pedido_id, producto_id, cantidad, precio_unitario) | | S |
| `v_productos_vigentes` | S | | | | | | |
| `v_usuarios_publico` | | | S | | | | |
| `v_pedidos_resumen` | | | S | | | | |
| `v_pedido_detalle` | | | | | | | |
| `mv_facturacion_categoria_mes` | | | | S | | | S |

¹ D11: privilegio nominal requerido por `FOR SHARE`; riesgo residual RR-01 (§5.4).
² D15 (aprobada): sin `fecha`; se usa el default `CURRENT_DATE`.

`app_web` no recibe privilegios directos: los obtiene solo por herencia de sus tres grupos.
Ningún rol recibe DELETE, TRUNCATE, REFERENCES, TRIGGER ni MAINTAIN sobre tablas de dominio.

### 3.2. Rutinas

| Rutina | Tipo | OWNER | PUBLIC | GRANT EXECUTE explícito |
|---|---|---|---|---|
| `registrar_detalle_pedido(bigint,bigint,integer)` | procedimiento TPI, INVOKER | real, sin cambio (VP-02, D2) | revocado (D3) | `rol_propietario_ventas` |
| `calcular_total_pedido(bigint)` | función SQL TPI, INVOKER | real, sin cambio | revocado (D3) | `rol_propietario_ventas` |
| `fn_set_subtotal()` | función trigger TPI | real, sin cambio | revocado | — |
| `fn_validar_detalle_vigente()` | función trigger TPI | real, sin cambio | revocado | — |
| `fn_recalcular_total_insert()` | función trigger TPI | real, sin cambio | revocado | — |
| `fn_recalcular_total_update()` | función trigger TPI | real, sin cambio | revocado | — |
| `fn_recalcular_total_delete()` | función trigger TPI | real, sin cambio | revocado | — |
| `api_registrar_detalle_pedido(bigint,bigint,integer)` | función nueva, DEFINER | `rol_propietario_ventas` | revocado | `rol_app_escritura` |
| `fn_autenticar(text,text)` | función nueva, DEFINER | `rol_propietario_credenciales` | revocado | `rol_app_autenticacion` |
| `fn_resetear_password(bigint,text)` | función nueva, DEFINER | `rol_propietario_credenciales` | revocado | `rol_soporte` |

El propietario real de las siete rutinas canónicas no se asume: la versión inicial lo daba por
`admin_datos`, pero las evidencias de instalación usan `-U postgres`. Se inventaría en VP-02 y se
conserva. El propietario conserva EXECUTE implícito por ser dueño; la POC y la implementación usan
al superusuario de instalación para las ejecuciones directas de comparación.

**ACL por defecto:** en PostgreSQL 17, como en versiones anteriores, `proacl NULL` significa
«propietario + PUBLIC con EXECUTE». La afirmación de la versión inicial de que PostgreSQL 15
dejó de otorgar EXECUTE a PUBLIC sobre funciones era incorrecta: el cambio de PostgreSQL 15 retiró
`CREATE` a PUBLIC sobre el esquema `public`. Consulta de verificación:

```sql
SELECT p.oid::regprocedure AS rutina,
       pg_get_userbyid(p.proowner) AS propietario,
       CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type
FROM pg_proc p
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
WHERE p.pronamespace = 'public'::regnamespace
ORDER BY 1, 3;
```

### 3.3. Esquemas, base de datos y privilegios por defecto

| Objeto | Privilegios |
|---|---|
| SCHEMA public | Propietario real (VP-05). USAGE: PUBLIC (default) y explícito a los roles de U5 que lo usan. CREATE: ningún rol de U5 ni PUBLIC |
| SCHEMA reportes | Propietario: superusuario de instalación. USAGE: `rol_reportes`, `admin_datos`. CREATE: solo `admin_datos` |
| Base de datos | CONNECT/TEMP de PUBLIC según D9; si se aprueba, CONNECT explícito a `app_web`, `admin_datos` y a las identidades `tst_u5_*` durante las pruebas |
| `pg_default_acl` | Exactamente dos entradas (§6) |

### 3.4. Atributos y membresías

| Rol | LOGIN | INHERIT | Atributos especiales | Miembro de | Miembros |
|---|---|---|---|---|---|
| `rol_app_lectura`, `rol_app_escritura`, `rol_app_autenticacion` | no | sí | ninguno | — | `app_web` |
| `rol_soporte` | no | sí | ninguno | — | `tst_u5_soporte` (solo pruebas) |
| `rol_reportes` | no | sí | ninguno | — | `tst_u5_reportes` (solo pruebas) |
| `rol_propietario_ventas`, `rol_propietario_credenciales` | no | no | ninguno | — | ninguno |
| `app_web` | sí | sí | ninguno | tres grupos de aplicación | — |
| `admin_datos` | sí | sí | ninguno | — | — |

Las tres membresías de `app_web` tienen exactamente `admin_option = false`,
`inherit_option = true`, `set_option = false`, concedidas explícitamente con
`WITH INHERIT TRUE, SET FALSE, ADMIN FALSE` (PostgreSQL 16+). Las membresías efímeras
`rol_soporte → tst_u5_soporte` y `rol_reportes → tst_u5_reportes` usan las mismas opciones;
`tst_u5_sin_privilegios` no tiene membresías.

Justificación frente a SEC-01..20: SEC-03/05/08/09/13/14/17 usan los privilegios
heredados por `app_web`, no un cambio al rol de grupo. SEC-04/18 y las conexiones
reales D12 necesitan herencia del grupo de la identidad efímera, no SET al grupo.
Los `SET ROLE app_web`, `SET ROLE tst_u5_*` y los `SET ROLE` a grupos parten del
superusuario de pruebas; no dependen de `set_option` de esas membresías.
SEC-07 fija las tres opciones; SEC-10 conserva la prohibición de delegación mediante
ADMIN FALSE. SEC-19 mantiene su identidad sin membresías y SEC-20 la limpieza.
SEC-01/02/06/11/12/15/16 no requieren asumir grupos desde esos miembros: atributos,
ADP, conservación canónica y controles de logs no cambian. Así SET FALSE no altera
los accesos positivos previstos y reduce la capacidad de asumir otra identidad.

Ninguna membresía tiene `admin_option = true`. «Atributos especiales» comprende SUPERUSER,
CREATEDB, CREATEROLE, REPLICATION y BYPASSRLS.

---

## 4. Esquema `reportes` (decisión D10)

### 4.1. Creación

```sql
-- Ejecutado por el superusuario de instalación, que queda como propietario del esquema.
CREATE SCHEMA IF NOT EXISTS reportes;
GRANT USAGE ON SCHEMA reportes TO rol_reportes;
GRANT USAGE, CREATE ON SCHEMA reportes TO admin_datos;
```

### 4.2. Objetos a instalar en `reportes`

Los objetos analíticos que no deben exponer datos personales (REQ-A09):

| Objeto propuesto | Tipo | Política de ubicación | Expone datos personales |
|---|---|---|---|
| `mv_facturacion_categoria_mes` | materializada | Ver nota abajo | No — agrega por categoría/mes |
| `v_resumen_ventas_rol_mes` | vista | Propuesta futura, fuera de la Parte A; sin requisito REQ-A aprobado que obligue a instalarla | No — intención de agregar por rol y mes, sin ID de usuario; definición pendiente |

**Política para `mv_facturacion_categoria_mes`:**
- Si la materializada **ya existe** en la base de U5 (por haber instalado U3 sobre ella),
  conservarla en su ubicación actual sin moverla ni duplicarla. Otorgar `GRANT SELECT` sobre
  ella a `rol_reportes` independientemente del esquema donde resida.
- Si **no existe**, crearla directamente en el esquema `reportes` conforme a D10, usando
  la definición de `unidades/unidad-3/sql/materializadas.sql` como referencia.
- En ningún caso se duplica el objeto en ambos esquemas.

**Regla de diseño para objetos en `reportes`:** Toda vista o materializada debe pasar el
test de reidentificación: ¿puede un analista determinar la identidad de un usuario individual
a partir de los datos expuestos? Si la respuesta es sí, el objeto no se instala sin
anonimización adicional.

> **Nota sobre REFRESH:** el refresco lo ejecuta el propietario real de la materializada. Si se
> delega, PostgreSQL 17 ofrece el privilegio MAINTAIN; su uso requiere una decisión separada.

---

## 5. Rutinas SECURITY DEFINER (decisión D1)

Las tres rutinas nuevas tienen SECURITY DEFINER, `search_path` fijo y propietario NOLOGIN
propio. Ninguna duplica la lógica de los objetos canónicos.

### 5.0. Contexto de ejecución y cadena de privilegios

**Regla.** Una rutina SECURITY DEFINER cambia el usuario efectivo (`current_user`) a su
propietario durante su ejecución. Una rutina SECURITY INVOKER —y una función trigger sin
SECURITY DEFINER— se ejecuta con el **usuario efectivo del momento**, no con los privilegios de
su propio propietario. `session_user` sigue siendo la identidad conectada (`app_web`).

**Corrección.** La versión inicial afirmaba que los triggers AFTER «corren bajo el OWNER de la
función trigger». Es incorrecto: las cinco funciones trigger del TPI son INVOKER y se ejecutan
como `rol_propietario_ventas` cuando la sentencia que las dispara se ejecuta dentro de la API.
Por eso `rol_propietario_ventas` sí necesita EXECUTE sobre `calcular_total_pedido` y privilegios
sobre las columnas que leen y escriben los triggers.

```
app_web (session_user)                              current_user
└─ SELECT public.api_registrar_detalle_pedido(...)  app_web → necesita X sobre la API
   └─ [SECURITY DEFINER]                            rol_propietario_ventas
      └─ CALL public.registrar_detalle_pedido(...)  rol_propietario_ventas (INVOKER)
         ├─ BEFORE trg_detalle_vigente              rol_propietario_ventas
         ├─ BEFORE trg_subtotal                     rol_propietario_ventas
         ├─ FK fk_detalle_pedido_*                  propietario de pedido/producto (interno)
         ├─ AFTER trg_total_detalle_insert          rol_propietario_ventas
         │  └─ calcular_total_pedido(...)           rol_propietario_ventas (INVOKER)
         └─ UPDATE producto                         rol_propietario_ventas
```

**Cadena completa, sentencia por sentencia** (líneas de `tpi/sql/objetos_programables.sql`):

| # | Origen | Sentencia | Privilegios exigidos al usuario efectivo |
|---|---|---|---|
| 1 | API | `CALL public.registrar_detalle_pedido(...)` | USAGE public; X sobre el procedimiento |
| 2 | proc. L257 | `SELECT usuario_id FROM pedido WHERE id = ... AND eliminado = FALSE FOR UPDATE` | S(id, usuario_id, eliminado) + U sobre ≥1 columna de `pedido` |
| 3 | proc. L262 | `PERFORM 1 FROM pedido WHERE id = ...` (solo ruta de error) | S(id) |
| 4 | proc. L272 | `SELECT eliminado FROM usuario WHERE id = ... FOR SHARE` | S(id, eliminado) + U sobre ≥1 columna de `usuario` (D11) |
| 5 | proc. L285 | `SELECT precio, stock, disponible, eliminado FROM producto ... FOR UPDATE` | S(id, precio, stock, disponible, eliminado) + U sobre ≥1 columna |
| 6 | proc. L307 | `PERFORM 1 FROM detalle_pedido WHERE pedido_id = ... AND producto_id = ...` | S(pedido_id, producto_id) |
| 7 | proc. L317 | `INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)` | I sobre esas cuatro columnas. `subtotal` lo asigna el trigger y no exige INSERT; `id`, `eliminado` y `created_at` toman default |
| 8 | `fn_validar_detalle_vigente` L88/L101/L114 | `FOR SHARE` sobre `pedido`, `usuario`, `producto` | Cubierto por 2, 4 y 5 |
| 9 | `fn_set_subtotal` L41 | Búsqueda de precio solo si `precio_unitario` es NULL; el procedimiento siempre lo envía | Ninguno en esta ruta (si ocurriera: S(id, precio) + U sobre `producto`, ya cubiertos) |
| 10 | FK | `fk_detalle_pedido_pedido`, `fk_detalle_pedido_producto` | Ninguno adicional para el usuario efectivo (comprobado: T01) |
| 11 | `fn_recalcular_total_insert` L156 | Lectura de la transition table `nuevos` | Ninguno |
| 12 | `fn_recalcular_total_insert` L158 | `UPDATE pedido p SET total = calcular_total_pedido(p.id) WHERE p.id = ...` | U(total), S(id); X sobre `calcular_total_pedido` |
| 13 | `calcular_total_pedido` L17 | `SELECT COALESCE(SUM(subtotal), 0) FROM detalle_pedido WHERE pedido_id = ... AND eliminado = FALSE` | S(pedido_id, subtotal, eliminado) |
| 14 | proc. L320 | `UPDATE producto SET stock = stock - ... WHERE id = ...` | U(stock), S(id, stock) |
| 15 | — | Ejecución de funciones trigger y secuencias de identidad | Ninguno (comprobado: T08, T09) |

**Regla de bloqueo de filas.** PostgreSQL exige, para `FOR UPDATE`, `FOR NO KEY UPDATE`,
`FOR SHARE` y `FOR KEY SHARE`, privilegio UPDATE sobre al menos una columna de cada tabla
bloqueada, además de SELECT sobre las columnas leídas. Para `pedido` lo satisface `U(total)` y para
`producto` `U(stock)`, que la cadena ya necesita. Para `usuario` ninguna escritura es necesaria:
el privilegio UPDATE es puramente habilitante y su elección es la decisión D11.

El conjunto resultante es el de §2.1 y §3.1. La POC lo validó por ablación: retirar cualquiera
de los 23 privilegios individuales hizo fallar la venta con 42501 (T07, §13.7). Se confirmó
también la regla de bloqueo para `usuario` y `pedido` (T10).

### 5.1. `api_registrar_detalle_pedido` — interfaz de venta (D1)

**Propósito:** Único punto de entrada para `rol_app_escritura` hacia las operaciones de venta.
Invoca el procedimiento canónico sin duplicar su lógica. Se invoca con `SELECT`, no con `CALL`,
porque es una función.

**Propietario:** `rol_propietario_ventas`
**Operación atómica:** CREATE + ALTER OWNER + REVOKE + GRANT en la misma transacción, ejecutada
por el superusuario de instalación.

**Contrato propuesto:**
```sql
BEGIN;

CREATE FUNCTION public.api_registrar_detalle_pedido(
    p_pedido_id   BIGINT,
    p_producto_id BIGINT,
    p_cantidad    INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Referencia calificada; el procedimiento canónico hereda este search_path
    CALL public.registrar_detalle_pedido(p_pedido_id, p_producto_id, p_cantidad);
END;
$$;

ALTER FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    OWNER TO rol_propietario_ventas;

REVOKE ALL ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    TO rol_app_escritura;

COMMIT;
```

Se usa `CREATE FUNCTION` y no `CREATE OR REPLACE`: si la función ya existiera, el script debe
fallar en lugar de conservar en silencio un propietario o ACL anteriores.

**Garantías:**
- `rol_app_escritura` no necesita EXECUTE sobre el procedimiento canónico del TPI.
- La lógica de validación, bloqueos y descuento de stock permanece íntegra en el procedimiento
  canónico; esta función no la duplica.
- El procedimiento canónico, los triggers y `calcular_total_pedido` usan nombres sin calificar
  y heredan `search_path = public, pg_temp`. `pg_catalog` se busca implícitamente primero y
  `pg_temp` queda explícitamente al final; las funciones y operadores nunca se buscan en
  `pg_temp`. La protección depende además de que ningún rol no confiable tenga CREATE en
  `public` (SEC-17, VP-05).
- Como la creación ocurre en una sola transacción, ningún otro rol observa la función con
  ACL por defecto (PUBLIC con EXECUTE) ni con propietario superusuario.
- La transacción pertenece al llamante, igual que en el procedimiento canónico.

### 5.2. `fn_autenticar` — autenticación de usuarios

**Propósito:** Permite que `app_web` valide credenciales sin tener SELECT directo sobre
`usuario.contrasena`. Rechaza credenciales nulas, marcadores académicos y hashes inválidos
sin revelar la causa específica del fallo.

**Propietario:** `rol_propietario_credenciales`
**Operación atómica:** CREATE + ALTER OWNER + REVOKE + GRANT en la misma transacción.

**Validación bcrypt para `pgcrypto`.** La versión inicial aceptaba cualquier valor de 60
caracteres que coincidiera con `LIKE '$2%$%'`. Ese patrón acepta prefijos que `pgcrypto` no
implementa (por ejemplo `$2$`), para los cuales `crypt()` falla con error en lugar de devolver
un hash. Además, `pgcrypto` interpreta cualquier sal sin prefijo reconocido como sal DES, por lo
que no puede confiarse en `crypt()` para rechazar valores mal formados. El diseño valida
exactamente el formato que genera `crypt(p, gen_salt('bf'))`: `$2a$`, costo de dos dígitos entre
04 y 31, `$` y 53 caracteres del alfabeto bcrypt (`./A-Za-z0-9`), 60 caracteres en total.
Por D16 (aprobada) no se aceptan `$2b$` ni `$2y$`: la base solo contiene hashes generados por
`gen_salt('bf')`.

**Tiempo de respuesta (D16, RR-06).** Cuando el mail no existe o el hash almacenado no es válido,
la función ejecuta igualmente un `crypt()` con una sal bcrypt nueva de costo por defecto (el mismo
que usa `fn_resetear_password`), y descarta el resultado. Así todas las ramas pagan un cálculo
bcrypt. La intención es que el tiempo no revele si el mail existe, pero esa equivalencia **no
está acreditada** (RR-06): el costo por defecto puede diferir del costo de los hashes almacenados. No se usa un hash ficticio literal: aparecería en
el texto DDL registrado por `log_statement = mod` y haría fallar la verificación de SEC-16.

**Contrato propuesto:**
```sql
BEGIN;

CREATE FUNCTION public.fn_autenticar(
    p_mail       TEXT,
    p_contrasena TEXT
)
RETURNS TABLE(usuario_id BIGINT, rol public.rol)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_hash TEXT;
BEGIN
    -- Validaciones defensivas: rechazar antes de consultar
    IF p_mail IS NULL OR trim(p_mail) = '' THEN
        RAISE EXCEPTION 'Credenciales inválidas' USING ERRCODE = '28P01';
    END IF;
    IF p_contrasena IS NULL OR trim(p_contrasena) = '' THEN
        RAISE EXCEPTION 'Credenciales inválidas' USING ERRCODE = '28P01';
    END IF;

    SELECT u.contrasena INTO v_hash
    FROM public.usuario u
    WHERE u.mail = p_mail AND u.eliminado = FALSE;

    -- Usuario inexistente o eliminado, o hash fuera del formato exacto de gen_salt('bf')
    -- (incluye SEED_NO_AUTH y hash_no_valido): cero filas, sin revelar la causa.
    -- D16: se paga un cálculo bcrypt para no revelar la causa por tiempo (equivalencia no acreditada, RR-06).
    IF NOT FOUND
       OR v_hash IS NULL
       OR v_hash !~ '^\$2a\$(0[4-9]|[12][0-9]|3[01])\$[./A-Za-z0-9]{53}$' THEN
        PERFORM public.crypt(p_contrasena, public.gen_salt('bf'));
        RETURN;
    END IF;

    RETURN QUERY
    SELECT u.id, u.rol
    FROM public.usuario u
    WHERE u.mail = p_mail
      AND u.eliminado = FALSE
      AND u.contrasena = public.crypt(p_contrasena, v_hash);
END;
$$;

ALTER FUNCTION public.fn_autenticar(TEXT, TEXT)
    OWNER TO rol_propietario_credenciales;

REVOKE ALL ON FUNCTION public.fn_autenticar(TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_autenticar(TEXT, TEXT) TO rol_app_autenticacion;

COMMIT;
```

**Garantías:**
- `app_web` (miembro de `rol_app_autenticacion`) nunca lee `usuario.contrasena` directamente.
- `search_path` fijo y referencias calificadas impiden la suplantación de esquema.
- Los valores que no tienen el formato bcrypt exacto nunca se usan como sal de `crypt()`.
- Mail inexistente, contraseña incorrecta y hash inválido devuelven cero filas, y las tres ramas
  ejecutan un cálculo bcrypt (D16), con costos potencialmente distintos. La equivalencia de tiempos **no está
  acreditada**: la rama ficticia usa el costo por defecto de `gen_salt('bf')` y los hashes
  almacenados pueden tener otro costo (04–31). Solo una medición autorizada podría acreditarla.
  Riesgo residual RR-06.
- La contraseña no aparece en el texto de la sentencia cuando el llamante usa parámetros
  enlazados, y no aparece en el log **solo si** `log_parameter_max_length = 0` y
  `log_parameter_max_length_on_error = 0` (§7). Los mensajes de error no incluyen parámetros.

**Diferencia con intentos de login a PostgreSQL:**
Un intento de login fallido a la base (contraseña incorrecta de `app_web` al conectarse)
aparece en el log como error de autenticación. Una autenticación de negocio fallida a través de
`fn_autenticar` devuelve cero filas; no es un error de conexión ni aparece en el log como tal.
El simulacro de la Parte C distingue estos dos eventos.

**Requiere `pgcrypto`:** `crypt()` y `gen_salt()` pertenecen a esa extensión, que se instala en
`public` (VP-07). Su instalación en la base de U5 requiere autorización.

---

### 5.3. `fn_resetear_password` — reset por soporte (D8 parcial)

**Propósito:** Permite a `rol_soporte` forzar un cambio de contraseña sin UPDATE directo
sobre `usuario`. Bloquea la fila con FOR UPDATE entre la validación del rol del usuario y
la actualización para evitar condiciones de carrera concurrentes.

**Propietario:** `rol_propietario_credenciales`
**Operación atómica:** CREATE + ALTER OWNER + REVOKE + GRANT en la misma transacción.

**Contrato propuesto:**
```sql
BEGIN;

CREATE FUNCTION public.fn_resetear_password(
    p_usuario_id BIGINT,
    p_nueva      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol_usuario public.usuario.rol%TYPE;
BEGIN
    -- D8: contraseña nueva no nula ni vacía
    IF p_nueva IS NULL OR trim(p_nueva) = '' THEN
        RAISE EXCEPTION 'La contraseña nueva no puede ser nula ni vacía'
            USING ERRCODE = '22023';
    END IF;

    -- FOR UPDATE serializa la validación del rol y la actualización
    SELECT u.rol INTO v_rol_usuario
    FROM public.usuario u
    WHERE u.id = p_usuario_id AND u.eliminado = FALSE
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % no existe o está eliminado', p_usuario_id
            USING ERRCODE = '23503';
    END IF;

    -- D8: soporte no puede resetear cuentas ADMIN
    IF v_rol_usuario = 'ADMIN' THEN
        RAISE EXCEPTION 'Soporte no puede resetear contraseñas de cuentas ADMIN'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.usuario
    SET contrasena = public.crypt(p_nueva, public.gen_salt('bf'))
    WHERE id = p_usuario_id
      AND eliminado = FALSE;
END;
$$;

ALTER FUNCTION public.fn_resetear_password(BIGINT, TEXT)
    OWNER TO rol_propietario_credenciales;

REVOKE ALL ON FUNCTION public.fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_resetear_password(BIGINT, TEXT) TO rol_soporte;

COMMIT;
```

**Garantías:**
- `rol_soporte` no tiene UPDATE directo sobre `usuario`.
- El bloqueo FOR UPDATE entre la validación y el UPDATE elimina la ventana de tiempo en
  que un cambio concurrente de `usuario.rol` (ADMIN ↔ USUARIO) podría invalidar la validación.
  El bloqueo es posible porque el propietario tiene `U(contrasena)`.
- Las referencias a `public.crypt` y `public.gen_salt` son calificadas.
- Ningún mensaje de error incluye la contraseña nueva.
- La transacción pertenece al caller; si falla, la contraseña no cambia.

**Restricciones de D8 no aprobadas aún:**
Las políticas adicionales (longitud mínima, historial de contraseñas, notificación al usuario)
no están definidas. No se implementan hasta que el equipo las especifique.

### 5.4. Riesgos residuales del diseño

| ID | Riesgo | Mitigación / estado |
|---|---|---|
| RR-01 | `rol_propietario_ventas` tiene `U(celular)` sobre `usuario` solo para poder bloquear con `FOR SHARE`. La necesidad de algún UPDATE está comprobada (T07.09, T10.2); el privilegio permitiría escribir `celular` de cualquier usuario a quien ejecute SQL arbitrario con esa identidad | Rol NOLOGIN sin miembros (T13); solo código fijo se ejecuta con su identidad; ninguna sentencia de la cadena escribe `celular`. Decisión D11 |
| RR-02 | `rol_propietario_ventas` puede escribir `pedido.total` y `producto.stock` de cualquier fila | Solo a través del código canónico. El riesgo se traslada a quien pueda modificar las rutinas o crear triggers en esas tablas: propietarios reales (VP-02); ningún rol de U5 tiene TRIGGER ni es propietario |
| RR-03 | La API no verifica que el pedido pertenezca al usuario final autenticado; `rol_app_escritura` puede crear pedidos para cualquier `usuario_id` | Igual que el procedimiento canónico: la base no conoce al usuario final. Responsabilidad de la aplicación; RLS fuera de alcance |
| RR-04 | `S(id)` sobre `pedido` permite enumerar identificadores de pedidos | Solo identificadores, sin datos asociados |
| RR-05 | El código canónico usa nombres sin calificar | `search_path` fijo, `pg_temp` al final, sin CREATE no confiable en `public` (SEC-17); D9 retira TEMP. Comprobado en la POC con TEMP permitido: una `pg_temp.producto` homónima no fue usada por la API (T11) |
| RR-06 | Diferencia de tiempo en `fn_autenticar` permite inferir si un mail existe | Equivalencia temporal de bcrypt **no acreditada**: no hay mediciones. D16 conserva trabajo bcrypt en las ramas de búsqueda, pero el costo por defecto y los hashes de costo 04..31 pueden diferir; nulos/vacíos abortan antes. Las afirmaciones temporales de §5.2 son intención, no una garantía probada. No se modifica la lógica de autenticación; REVISAR: medición autorizada pendiente |
| RR-07 | Una reinstalación desde cero de `objetos_programables.sql` restaura el EXECUTE de PUBLIC | Seguir [Recuperación manual de ACL tras reinstalar el TPI](../sql/README.md#recuperación-manual-de-acl-tras-reinstalar-el-tpi-rr-07), con autorización separada: verificar roles existentes, reaplicar solo ACL y repetir SEC-13, huella SEC-15 y matriz. No reejecutar `roles.sql`, recrear objetos canónicos ni cambiar sus propietarios |
| RR-08 | El superusuario evita todos los controles | Uso limitado a la etapa de instalación autorizada |

---

## 6. `ALTER DEFAULT PRIVILEGES` (REQ-A04)

Solo se aplican `ALTER DEFAULT PRIVILEGES` donde hay beneficio claro y alcance acotado.
No se aplica sobre `public` porque otorgaría privilegios automáticos a nuevas tablas operativas
que pueden requerir un control más restrictivo.

```sql
-- 1. Objetos analíticos futuros de admin_datos en reportes: SELECT para rol_reportes.
--    "TABLES" incluye tablas, vistas y vistas materializadas.
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA reportes
    GRANT SELECT ON TABLES TO rol_reportes;

-- 2. Funciones futuras de admin_datos en cualquier esquema: sin EXECUTE para PUBLIC.
--    PostgreSQL 17 otorga EXECUTE a PUBLIC sobre funciones nuevas por defecto.
--    Un REVOKE de este tipo solo es efectivo sin IN SCHEMA.
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
```

**Verificación.** La vista `information_schema.default_privileges` que citaba la versión inicial
no existe en PostgreSQL. Se usa `\ddp` en psql o la consulta:

```sql
SELECT pg_get_userbyid(d.defaclrole)     AS rol_creador,
       coalesce(n.nspname, '(global)')   AS esquema,
       d.defaclobjtype                   AS tipo,      -- r = tablas, f = funciones
       d.defaclacl                       AS acl
FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY 1, 2, 3;
```

Resultado esperado tras `roles.sql`: exactamente dos filas, ambas con `rol_creador = admin_datos`.
1. `esquema = reportes`, `tipo = r`, ACL con una entrada `rol_reportes=r/admin_datos`.
2. `esquema = (global)`, `tipo = f`, ACL sin entrada para PUBLIC (ninguna entrada con la forma `=X/…`).

**Qué no se incluye y por qué:**
- `ALTER DEFAULT PRIVILEGES ... IN SCHEMA public GRANT SELECT ON TABLES TO rol_app_lectura`:
  nuevas tablas en `public` pueden ser operativas o de staging.
- `ALTER DEFAULT PRIVILEGES ... IN SCHEMA public GRANT INSERT, UPDATE ON TABLES TO rol_app_escritura`:
  INSERT/UPDATE sobre tablas futuras de `public` se otorga caso por caso.

---

## 7. Estrategia de auditoría del simulacro (ajuste 2)

### 7.1. Qué registra la auditoría nativa (Parte B)

Parámetros a activar (sobre la instancia de desarrollo):
- `log_connections = on`
- `log_disconnections = on`
- `log_statement = 'mod'` (DDL y DML de modificación de nivel superior; no todas las consultas)

Parámetros preventivos obligatorios antes de cualquier prueba con credenciales:
- `log_parameter_max_length = 0` (por defecto `-1`: los valores de los parámetros enlazados se
  registran completos junto a las sentencias registradas)
- `log_parameter_max_length_on_error = 0`
- `password_encryption = 'scram-sha-256'`
- `log_file_mode = 0600`

Todos requieren superusuario y se aplican en la Parte B. El estado actual se inventaría en VP-09.

### 7.2. Qué registra `log_statement = mod` y qué no

`log_statement` registra sentencias de **nivel superior**. Con `mod` registra DDL e INSERT, UPDATE,
DELETE, TRUNCATE; no registra SELECT ni CALL, y nunca registra las sentencias que se ejecutan
dentro de funciones o procedimientos.

| Evento del simulacro | `log_statement = mod` | Mecanismo complementario requerido |
|---|---|---|
| Intentos fallidos de login | Sí — error de autenticación (con `log_connections` también los intentos) | Ninguno |
| Login exitoso | Sí — vía `log_connections` | Ninguno |
| Lectura masiva `SELECT * FROM usuario` | **No registrado** | Ver §7.3 |
| `SELECT api_registrar_detalle_pedido(...)` | **No registrado** (es un SELECT; el INSERT y el UPDATE internos tampoco) | Ver §7.3 si el simulacro lo requiere |
| Intento de GRANT a rol de bajo privilegio | Sí (DDL); si falla, también como error | Ninguno |

### 7.3. Mecanismo complementario para el simulacro (Parte C)

Para que el simulacro permita reconstruir la secuencia completa incluyendo la lectura masiva,
se propone una de las siguientes opciones. El equipo elige una antes de implementar:

**Opción A — `log_statement = 'all'` temporalmente:**
Activar `all` solo durante la ejecución del simulacro, sobre la instancia de laboratorio
descartable. El log registra el texto de las sentencias y, salvo que `log_parameter_max_length = 0`,
los valores de los parámetros enlazados. El dataset del simulacro usa exclusivamente datos sintéticos.

**Opción B — función de auditoría en la misma sesión:**
Antes del SELECT masivo, el script de simulacro registra un evento en una tabla de auditoría
de sesión (creada para el simulacro). Esto no requiere cambiar `log_statement`.

**Opción C — `log_min_duration_statement = 0` para el rol del simulacro:**
Registra todas las sentencias de ese rol, incluidas las SELECT, sin cambiar la configuración
global. Requiere `ALTER ROLE ... SET` ejecutado por superusuario. Con la misma condición sobre
`log_parameter_max_length` que la opción A.

La opción elegida debe documentarse en la bitácora (Parte E) antes de ejecutar el simulacro.

**Regla invariante:** En ninguna opción se registran contraseñas en texto plano, y ningún script
contiene contraseñas literales. Las credenciales sintéticas se generan en el shell, **fuera del
SQL**, viajan solo por el entorno del cliente, se leen con `\getenv` (psql 15+) y se envían como
parámetros enlazados con `\bind` (psql 16+). Así ni el texto de las sentencias ni los scripts
contienen el valor o la expresión que lo genera (procedimiento completo: `sql/pruebas/README.md`, M02):

```text
# Shell: generar y exportar; nunca en archivos del repositorio ni en argumentos -v.
U5_SYN_PWD="u5syn_$(openssl rand -hex 16)"; export U5_SYN_PWD

-- psql: leer del entorno; el texto enviado al servidor no contiene el valor.
\getenv u5_pwd U5_SYN_PWD

-- Fixture (superusuario de prueba): el valor viaja como parámetro, no como literal.
UPDATE public.usuario SET contrasena = public.crypt($1, public.gen_salt('bf'))
WHERE id = $2 \bind :'u5_pwd' :'u5_uid' \g

-- Prueba: el texto enviado contiene solo $1 y $2.
SELECT * FROM public.fn_autenticar($1, $2) \bind :'u5_mail' :'u5_pwd' \g
```

- Con cualquier driver de aplicación (libpq, JDBC, psycopg, etc.): parámetros posicionales,
  nunca concatenación de strings.
- `\set` con un valor literal deja la contraseña escrita en el script, y su interpolación en una
  consulta sin `\bind` la incluye en el texto enviado al servidor. No se usa con credenciales.
- Prohibido imprimir esas variables (`\echo`, `\set` sin argumentos) o activar opciones de eco que
  muestren resultados del `\gset`.
- La verificación del log (SEC-16.N) busca con `grep -F` los **valores sintéticos exactos**
  todavía presentes en el entorno, además de `$2a$` y `PASSWORD '`. No basta con buscar el prefijo
  `u5syn_`: con `log_statement = 'all'`, una sentencia generadora lo registraría sin haber filtrado
  ningún valor. Al terminar se hace `unset` de las variables de entorno, también ante un fallo.

### 7.4. Verificación de permisos del archivo de log (ajuste 4)

**En Linux (sistema del entorno validado):**
El archivo de log de PostgreSQL se ubica típicamente en:
- `/var/lib/postgresql/<versión>/main/log/` (instalación APT)
- o en la ruta definida por `log_directory` en `postgresql.conf`

Los permisos esperados:
```
-rw------- 1 postgres postgres ... postgresql-<fecha>.log
```
Solo el usuario del sistema operativo `postgres` debe poder leerlo (`log_file_mode = 0600`).
El archivo no debe ser legible por otros usuarios (bit `o+r` ausente).

Verificación:
```bash
ls -la "$(psql -U postgres -At -c 'SHOW data_directory;')/$(psql -U postgres -At -c 'SHOW log_directory;')"
# Confirmar owner=postgres y permisos 600 (640 solo si el grupo está justificado)
```

**En Windows:** El archivo de log se ubica en `%PGDATA%\log\`. Los permisos se verifican
con `icacls` o desde las propiedades de seguridad del archivo. Solo la cuenta de servicio
de PostgreSQL y los administradores del sistema deben tener acceso.

---

## 8. Criterios de aceptación (SEC-01 a SEC-20)

Cada criterio define una prueba positiva (P), negativa (N) y de regresión (R).
La numeración original se conserva. ⟳ = cambió en la revisión del 2026-10-26.
Convenciones: las pruebas de comportamiento se ejecutan desde una sesión del superusuario de
pruebas con `SET ROLE`, dentro de `BEGIN … ROLLBACK`; «42501» significa `insufficient_privilege`.
Las identidades efímeras usan el prefijo `tst_u5_`. Ningún criterio usa contraseñas literales.

### Existencia y atributos de roles

**SEC-01** ⟳ — Los siete roles de grupo existen y tienen NOLOGIN.
- P: `SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname IN (<los siete>)` devuelve siete filas con `rolcanlogin = false`; `\du` se adjunta como evidencia.
- N: Un intento de conexión como `rol_app_lectura` falla porque el rol no puede iniciar sesión (solo si se ejecuta la prueba de conexión; la verificación principal es el catálogo).
- R: Reejecutar `roles.sql` en una base limpia; los siete roles existen con atributos correctos.

**SEC-02** ⟳ — Ningún rol de grupo tiene SUPERUSER, CREATEDB, CREATEROLE, REPLICATION ni BYPASSRLS; los propietarios son NOINHERIT.
- P: `SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolinherit FROM pg_roles WHERE rolname IN (<los siete>)` devuelve `false` en los cinco atributos, y `rolinherit = false` para los dos propietarios. Se usa lista explícita, no `LIKE 'rol_%'` (`_` es comodín).
- N: N/A.
- R: Verificar después de cualquier `ALTER ROLE`.

**SEC-03** ⟳ — `api_registrar_detalle_pedido` y `registrar_detalle_pedido` producen resultados equivalentes.
- P: Partiendo del mismo estado de fixture, en dos transacciones separadas con ROLLBACK: (a) el superusuario de pruebas ejecuta `CALL registrar_detalle_pedido(...)`; (b) con `SET ROLE app_web` se ejecuta `SELECT api_registrar_detalle_pedido(...)` con los mismos argumentos. Ambas producen la misma línea (`cantidad`, `precio_unitario`, `subtotal`), el mismo `producto.stock` y el mismo `pedido.total`. (La versión inicial usaba `admin_datos`, que no tiene EXECUTE sobre el procedimiento ni privilegios de escritura.)
- N: Con `SET ROLE app_web`, `CALL registrar_detalle_pedido(...)` falla con 42501. Los errores de negocio (22023, 23503, 23505, 23514) llegan intactos a través de la API.
- R: Verificar la equivalencia después de cualquier cambio en la API o en el procedimiento.

**SEC-04** ⟳ — `rol_reportes` tiene USAGE sobre `reportes` y SELECT solo sobre objetos analíticos.
- P: Con `SET ROLE rol_reportes` (y por conexión real como `tst_u5_reportes`, D12), `SELECT * FROM <esquema real>.mv_facturacion_categoria_mes LIMIT 1` funciona.
- N: Con el mismo rol, `SELECT * FROM public.usuario` y `SELECT * FROM public.pedido` fallan con 42501.
- R: Verificar después de cada instalación de un nuevo objeto en `reportes`.

### Membresías y accesos de login

**SEC-05** ⟳ — La venta solo es posible a través de la API; el DML directo sobre `detalle_pedido` falla.
- P: Con `SET ROLE app_web`, `SELECT api_registrar_detalle_pedido(...)` con datos válidos de fixture funciona (transacción revertida).
- N: Con `SET ROLE app_web`: `INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario) VALUES (...)`, `UPDATE detalle_pedido SET cantidad = ...`, `DELETE FROM detalle_pedido WHERE id = -1` y `SELECT * FROM detalle_pedido` fallan con 42501.
- R: `information_schema.role_table_grants` y `information_schema.role_column_grants` no devuelven filas de `rol_app_escritura` ni de `app_web` sobre `detalle_pedido`.

**SEC-06** ⟳ — `admin_datos` tiene LOGIN, no tiene SUPERUSER, CREATEDB ni CREATEROLE (D13) y tiene exactamente sus privilegios operativos.
- P: `SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = 'admin_datos'` devuelve `true, false, false, false`. Con `SET ROLE admin_datos`, `SELECT count(*) FROM categoria` funciona y `CREATE TABLE reportes.tst_u5_tmp (x int)` funciona (revertido).
- N: Con `SET ROLE admin_datos`: `CREATE ROLE tst_u5_x` falla con 42501; `INSERT INTO categoria ...`, `SELECT contrasena FROM usuario` y `CREATE TABLE public.tst_u5_tmp (x int)` fallan con 42501.
- R: Verificar después de cualquier `ALTER ROLE admin_datos`.

**SEC-07** ⟳ — `app_web` es miembro exactamente de `rol_app_lectura`, `rol_app_escritura` y `rol_app_autenticacion`, sin ADMIN OPTION.
- P: `SELECT roleid::regrole, admin_option, inherit_option, set_option FROM pg_auth_members WHERE member = 'app_web'::regrole` devuelve exactamente los tres roles, con `admin_option = false`, `inherit_option = true` y `set_option = false` (§3.4).
- N: `rol_soporte`, `rol_reportes` y los propietarios no aparecen en esa consulta; `pg_has_role('app_web', 'rol_propietario_ventas', 'MEMBER')` es `false`.
- R: Verificar después de cualquier GRANT/REVOKE de membresía.

### GRANT sobre tablas y vistas

**SEC-08** ⟳ — `rol_app_escritura` tiene INSERT por columnas y `SELECT (id)` sobre `pedido`; no tiene ningún privilegio sobre `detalle_pedido`.
- P: Con `SET ROLE app_web`, `INSERT INTO pedido (forma_pago, usuario_id) VALUES ('EFECTIVO', <usuario de fixture>) RETURNING id` funciona (transacción revertida) y el pedido queda con `fecha = CURRENT_DATE`.
- N: Con `SET ROLE app_web`: `SELECT * FROM pedido`, `SELECT total FROM pedido`, `UPDATE pedido SET estado = 'CANCELADO' WHERE id = <id>` y `SELECT * FROM detalle_pedido` fallan con 42501.
- R: `information_schema.role_column_grants` para `rol_app_escritura` sobre `pedido` devuelve exactamente INSERT en (`usuario_id`, `forma_pago`) y SELECT en (`id`) (D15).

**SEC-09** — `rol_app_escritura` no tiene DELETE ni TRUNCATE sobre ninguna tabla de dominio.
- P: `information_schema.role_table_grants` no devuelve DELETE ni TRUNCATE para ningún rol de U5.
- N: Con `SET ROLE app_web`, `DELETE FROM pedido WHERE id = -1` y `TRUNCATE detalle_pedido` fallan con 42501.
- R: Verificar después de cualquier GRANT sobre tablas de dominio.

**SEC-10** ⟳ — El intento de escalamiento de privilegios por membresía falla.
- P: `SELECT member::regrole, admin_option FROM pg_auth_members WHERE roleid = 'admin_datos'::regrole` devuelve cero filas, y ninguna membresía de roles de U5 tiene `admin_option = true`. En PostgreSQL 16+ conceder la membresía de un rol exige ADMIN OPTION sobre ese rol (o SUPERUSER); CREATEROLE por sí solo ya no alcanza, y un rol no tiene ADMIN OPTION implícita sobre sí mismo.
- N: Con `SET ROLE` sucesivo a `tst_u5_soporte`, `rol_soporte`, `app_web` y `admin_datos`, `GRANT admin_datos TO tst_u5_soporte` falla con error de permiso (SQLSTATE esperado 42501, a confirmar). Con `SET ROLE app_web`, `GRANT rol_app_escritura TO tst_u5_soporte` también falla. Si alguno no falla, es un defecto de seguridad que debe corregirse antes de continuar con el TP.
- R: Ningún rol de U5 tiene CREATEROLE ni SUPERUSER, y ninguna membresía tiene ADMIN OPTION.

### GRANT sobre rutinas (EXECUTE) y privilegios por defecto

**SEC-11** ⟳ — `ALTER DEFAULT PRIVILEGES` en `reportes` produce el efecto esperado y no existe ninguno sobre `public`.
- P: Con `SET ROLE admin_datos`, `CREATE TABLE reportes.tst_u5_adp (x int)` (revertido); `has_table_privilege('rol_reportes', 'reportes.tst_u5_adp', 'SELECT')` es `true`.
- N: Una tabla creada en `public` por el superusuario de pruebas (revertido) no otorga privilegios a ningún grupo: `has_table_privilege(<grupo>, 'public.tst_u5_adp', <privilegio>)` es `false` para los cuatro grupos de aplicación. `admin_datos` no puede crear en `public` (42501).
- R: La consulta de §6 sobre `pg_default_acl` (o `\ddp`) devuelve exactamente las dos filas esperadas.

**SEC-12** ⟳ — `ALTER DEFAULT PRIVILEGES` revoca EXECUTE a PUBLIC sobre funciones futuras de `admin_datos`.
- P: Con `SET ROLE admin_datos`, `CREATE FUNCTION reportes.tst_u5_fn() RETURNS int LANGUAGE sql AS 'SELECT 1'` (revertido); `aclexplode(proacl)` no contiene beneficiario 0 (PUBLIC) y `has_function_privilege('tst_u5_sin_privilegios', 'reportes.tst_u5_fn()', 'EXECUTE')` es `false`. Se usa la función de catálogo porque una llamada real fallaría antes por falta de USAGE sobre `reportes` y ocultaría el resultado.
- N (control): la misma función creada por el superusuario de pruebas (sin ADP para ese rol) devuelve `true` en la misma consulta.
- R: La fila global de tipo `f` de `pg_default_acl` sigue presente y sin PUBLIC.

**SEC-13** ⟳ — `rol_app_escritura` tiene EXECUTE sobre `api_registrar_detalle_pedido` y no sobre `registrar_detalle_pedido` ni `calcular_total_pedido`.
- P: Con `SET ROLE app_web`, `SELECT api_registrar_detalle_pedido(...)` funciona con datos de fixture (transacción revertida).
- N: Con `SET ROLE app_web`, `CALL registrar_detalle_pedido(...)` y `SELECT calcular_total_pedido(<id>)` fallan con 42501.
- R: La consulta `aclexplode` de §3.2 muestra, para las dos rutinas canónicas de D3, solo al propietario real y a `rol_propietario_ventas`, y ninguna entrada PUBLIC en las diez rutinas de §3.2.

### Permisos por columna y conservación de objetos canónicos

**SEC-14** — `rol_app_escritura` puede hacer INSERT en `pedido` solo sobre las columnas autorizadas.
- P: Con `SET ROLE app_web`, `INSERT INTO pedido (forma_pago, usuario_id) VALUES ('EFECTIVO', <usuario de fixture>)` funciona (transacción revertida).
- N: Con `SET ROLE app_web`, el mismo INSERT agregando `fecha`, `total`, `estado` o `eliminado` falla con 42501.
- R: Verificar `information_schema.column_privileges` para `rol_app_escritura` sobre `pedido`.

**SEC-15** ⟳ — Las siete rutinas y cinco triggers canónicos siguen intactos y funcionando; los propietarios reales no cambiaron.
- P: La batería TPI (`tpi/pruebas/pruebas_objetos_programables.sql`) mantiene 29 grupos / 37 variantes / 30 NOTICE PASS con exit 0, ejecutada por el superusuario en una base autorizada con el nombre que exige su guarda.
- N: Las huellas de catálogo tomadas antes (F0) y después (F1) de `roles.sql` coinciden: `md5(pg_get_functiondef(oid))`, `proowner`, `prosecdef` y `proconfig` de las siete rutinas; `pg_get_triggerdef` y `tgenabled` de los cinco triggers; `relowner` y definición de columnas de las cinco tablas. Solo difieren los `proacl` previstos por D3 y las funciones trigger. Los propietarios se comparan contra el inventario VP-02, no contra un valor supuesto.
- R: Ejecutar después de `roles.sql` y después de cualquier REVOKE adicional.

### Contraseñas, SECURITY DEFINER y reset

**SEC-16** ⟳ — Las pruebas y el simulacro no registran contraseñas en logs.
- P: Configuración preventiva verificada en `pg_settings` antes de la prueba: `log_parameter_max_length = 0`, `log_parameter_max_length_on_error = 0`, `log_file_mode = 0600`. Las llamadas a `fn_autenticar` y `fn_resetear_password` usan valores sintéticos generados en tiempo de ejecución (`u5syn_…`) enviados con `\bind` o con un driver.
- N: Como **verificación** del control, no como protección: el log capturado no contiene los valores sintéticos exactos, ni cadenas con formato bcrypt (`$2a$`), ni `PASSWORD '`. Si aparece alguna, la prueba falla y el log no se entrega a la IA.
- R: Revisar el log completo antes de entregarlo a la IA en la Parte C. El mecanismo de auditoría elegido (§7.3) se documenta en BITACORA.md.

**SEC-17** ⟳ — Las tres funciones SECURITY DEFINER están endurecidas.
- P: `SELECT proname, prosecdef, proconfig, pg_get_userbyid(proowner) FROM pg_proc WHERE proname IN ('api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password')` muestra `prosecdef = true`, `array_to_string(proconfig, ';')` = `search_path=public, pg_temp` (valor observado en la POC, T13) y el propietario NOLOGIN previsto; `aclexplode` no muestra PUBLIC. Los propietarios no tienen miembros, no pueden iniciar sesión y `has_schema_privilege(<propietario>, <esquema>, 'CREATE')` es `false` para `public` y `reportes`. Ningún rol de U5 ni PUBLIC tiene CREATE sobre `public`.
- N: Con `SET ROLE app_web`, `SELECT contrasena FROM public.usuario LIMIT 1` falla con 42501. Si `app_web` puede crear tablas temporales (D9 no aprobada), una tabla `pg_temp.producto` creada por `app_web` no es usada por la API: el stock se descuenta en `public.producto` (POC T11).
- R: Verificar `prosecdef`, `proconfig`, `proowner` y ACL después de cualquier recreación. La creación ocurre en una sola transacción: si se interrumpe antes del COMMIT, la función no existe (POC T12).

**SEC-18** ⟳ — `rol_soporte` tiene EXECUTE sobre `fn_resetear_password` y no puede resetear cuentas ADMIN.
- P: Con `SET ROLE tst_u5_soporte`, `SELECT public.fn_resetear_password($1, $2) \bind :'u5_uid' :'u5_pwd' \g` sobre un usuario USUARIO de fixture funciona (transacción revertida); el nuevo `contrasena` cumple el formato bcrypt de §5.2.
- N: Con el mismo rol: destino ADMIN → 42501; contraseña vacía → 22023; usuario eliminado o inexistente → 23503; `UPDATE usuario SET contrasena = ...` directo → 42501; `SELECT calcular_total_pedido(<id>)` → 42501.
- R: Verificar que el OWNER es `rol_propietario_credenciales` y que el ACL no cambió.

### Identidades efímeras y ausencia de SUPERUSER

**SEC-19** ⟳ — Las pruebas negativas se ejecutan con una identidad efímera sin membresías (`tst_u5_sin_privilegios`).
- P: La identidad existe, no tiene membresías ni atributos especiales, y se puede asumir con `SET ROLE` (o conectarse, si se otorga CONNECT para la prueba).
- N: Con esa identidad, cualquier CALL o SELECT sobre las rutinas de §3.2 y sobre tablas y vistas de dominio falla con 42501.
- R: Al finalizar, `SELECT rolname FROM pg_roles WHERE rolname LIKE 'tst\_u5\_%'` devuelve cero filas.

**SEC-20** ⟳ — Ningún rol creado por `roles.sql` tiene SUPERUSER y no quedan identidades efímeras.
- P: `SELECT rolname FROM pg_roles WHERE rolsuper` no incluye ninguno de los nueve roles de U5.
- N: N/A.
- R: Como último paso, `pg_roles` coincide con el inventario esperado (roles previos de VP-01 + nueve roles de U5) y no hay roles `tst_u5_*`.

### Verificación transversal de la matriz

Además de los criterios numerados, la unión de `role_table_grants`, `role_column_grants`,
`aclexplode(proacl)`, `has_schema_privilege`, `pg_default_acl` y `pg_auth_members` se compara con
la matriz de §3 mediante EXCEPT bidireccional. Resultado esperado: 0 filas en ambos sentidos.

---

## 9. Decisiones pendientes de confirmación

### D4 — No otorgar UPDATE sobre `pedido.estado` hasta definir su caso de uso

**Recomendación:** El campo `pedido.estado` controla el ciclo de vida del pedido
(PENDIENTE → CONFIRMADO → TERMINADO / CANCELADO). Ningún rol de aplicación recibe UPDATE
sobre él hasta que el equipo defina qué rol, bajo qué condición y con qué validaciones
puede cambiar el estado de un pedido.
**Estado: recomendación documentada — no aprobada como decisión de implementación.**
El equipo debe definir el caso de uso antes de incluir UPDATE de `pedido.estado` en `roles.sql`.

### D6 — Tres roles adicionales

Los roles `rol_app_autenticacion`, `rol_propietario_ventas` y `rol_propietario_credenciales`
están incorporados en el diseño (secciones 2.1 y 5). Su creación depende de la aprobación
del equipo sobre los contratos SECURITY DEFINER de §5.
**Estado: aprobada (2026-11-02)**, en el prompt «Food Store — Unidad 5 — Implementación
controlada de la Parte A»: los propietarios son NOLOGIN, NOINHERIT y no tienen miembros.
Implementación en `unidades/unidad-5/sql/`, validada en laboratorio (§15).

### D8 — Restricciones sobre `fn_resetear_password`

**Restricciones aprobadas (incorporadas en §5.3):**
- La contraseña nueva no puede ser nula ni vacía.
- `rol_soporte` no puede resetear contraseñas de cuentas con `usuario.rol = 'ADMIN'`.

**Restricciones pendientes de definición:**
- Longitud mínima de la contraseña nueva.
- Historial de contraseñas (no reutilizar las N anteriores).
- Notificación al usuario tras el reset.
- Ruta de reset para cuentas ADMIN.

**Estado: restricciones aprobadas incorporadas; las demás pendientes de definición por el equipo.**

### D9 — Revocar CONNECT y TEMP a PUBLIC

**Propuesta:** `REVOKE CONNECT ON DATABASE <nombre_base> FROM PUBLIC` y
`REVOKE TEMP ON DATABASE <nombre_base> FROM PUBLIC`, con CONNECT explícito a `app_web`,
`admin_datos` y a las identidades `tst_u5_*` durante las pruebas. Retirar TEMP elimina además el
vector de tablas temporales de RR-05.

**Riesgo:** Si existen otros roles que se conectan a la misma base sin CONNECT explícito,
dejarían de poder conectarse.

**Condición:** Requiere autorización explícita sobre la instancia aislada de laboratorio
de U5, donde se confirme que no hay otras conexiones que se rompan.
**Estado: pendiente de autorización — no aprobada.**

### D11 — Privilegio UPDATE habilitante para `FOR SHARE` sobre `usuario`

**Contexto corregido:** `rol_propietario_ventas` **no** es propietario del procedimiento canónico
(D2); es el propietario de la API y, por lo tanto, el usuario efectivo con el que se ejecutan el
procedimiento y su `SELECT eliminado FROM usuario WHERE id = ... FOR SHARE` (L272), y también el
mismo bloqueo en `fn_validar_detalle_vigente` (L101).

**Requisito del motor:** documentado por PostgreSQL —`FOR SHARE` exige UPDATE sobre al menos una
columna de la tabla bloqueada, además de SELECT sobre las columnas leídas—. La duda ya no es si
hace falta, sino qué columna se otorga.

**Evidencia de la POC (2026-11-02, §13.7):**

| Caso | Condición | Observado |
|---|---|---|
| T10.1 | `rol_propietario_ventas` con la matriz completa: `SELECT eliminado FROM usuario WHERE id = U1 FOR SHARE` | Sin error |
| T10.2 | Igual, tras `REVOKE UPDATE (celular) ON usuario` | 42501 |
| T10.3 | Tras `REVOKE UPDATE (total) ON pedido`: `SELECT usuario_id FROM pedido WHERE id = O1 FOR UPDATE` | 42501 |
| T07.09 | Venta completa por la API sin `UPDATE (celular)` | 42501 en `SELECT eliminado FROM usuario … FOR SHARE` de `registrar_detalle_pedido` (línea 34 del cuerpo) |
| T07.07, T07.08 | Venta sin `SELECT (id)` o sin `SELECT (eliminado)` de `usuario` | 42501 en la misma sentencia |

**Permisos requeridos sobre `usuario`, comprobados:** `SELECT (id, eliminado)` y UPDATE sobre
alguna columna. Con la matriz actual, ese UPDATE es `UPDATE (celular)`.

**Alcance de la validación.** La POC demuestra que el bloqueo exige UPDATE y que, en la matriz
propuesta, `UPDATE (celular)` es el privilegio que lo satisface. No demuestra que `celular` sea
la mejor columna: no se probaron alternativas. Tampoco cubre el `FOR SHARE` sobre `usuario` de
`fn_validar_detalle_vigente`. La ablación se detiene en el primer fallo, y ese primer fallo fue
el del procedimiento; el trigger usa la misma identidad y la misma tabla. La evidencia vale para
la ruta de venta, no para DML directo ni para concurrencia.

**Alternativa propuesta:** `GRANT UPDATE (celular) ON usuario TO rol_propietario_ventas`.
`celular` es nullable y no participa en reglas de venta, autenticación ni en las agregaciones de
las Partes C y D. Alternativas descartadas: `created_at` (lo usan las cargas de U4, la Parte D y el
análisis forense), `id` (identidad; `SET id = DEFAULT` renumeraría usuarios sin pedidos), y
`contrasena`, `rol`, `eliminado` (funcionales).

**Riesgo residual:** RR-01 (§5.4). Quien ejecute SQL arbitrario con la identidad de
`rol_propietario_ventas` podría escribir `celular` de cualquier usuario. El rol es NOLOGIN y no
tiene miembros (T13). Solo lo alcanza el código fijo de la API y de la cadena canónica, que nunca
escribe esa columna. El riesgo crece si alguien obtiene permiso para modificar esas rutinas
(RR-02).
**Estado: requisito comprobado empíricamente (T07.09, T10). Elección de `celular` aprobada
(2026-11-02) para la implementación de laboratorio:
`GRANT UPDATE (celular) ON public.usuario TO rol_propietario_ventas;`, nunca UPDATE completo
sobre `usuario`. El riesgo residual RR-01 sigue vigente.**

### D14 — Entorno de la POC

Los roles de PostgreSQL son globales del clúster: crearlos en una instancia compartida modificaría
roles reales aunque la base fuera descartable. **Decisión:** una instancia PostgreSQL 17.11
dedicada y descartable (contenedor o clúster `initdb` propio, en un puerto distinto), con una
única base `foodstore_u5_poc`, destruida al terminar. Alternativa descartada: un clúster
compartido con prefijos `poc_u5_` en los roles, porque no prueba los nombres reales y deja
residuos globales.
**Estado: aprobada (2026-10-26).** Crear y destruir la instancia forma parte de la ejecución de la
POC, que se autoriza por separado.

**Autorizaciones registradas que justificaron ejecutar la POC.** Las fuentes son los prompts de
la sesión, guardados en el registro de prompts de Claude Code (Engram).

| Fecha | Texto literal | Alcance |
|---|---|---|
| 2026-10-26 13:32 | «Apruebo D14, D15, D16, D17 y D18» | Aprobación de las cinco decisiones de diseño; D14 no autoriza por sí sola la ejecución |
| 2026-10-26 13:36 | «Sí, autorizo la POC en la instancia descartable» | Autorización separada de la ejecución |
| 2026-11-02 | «Si por favor», en respuesta a «¿Querés que arranquemos por la POC?» | Inicio de la ejecución en esta sesión |
| 2026-11-02 | Opción elegida: «Carpeta hermana del repo» | Ubicación de las salidas fuera del repositorio hasta la revisión humana |
| 2026-11-02 | «La revisión humana acepta actualizar las especificaciones antes de realizar el siguiente commit» | Consolidación documental y copia de la evidencia a `unidades/unidad-5/poc_permisos/` |

Hasta la ejecución de la POC no había otras aprobaciones registradas. Después, el 2026-11-02,
el prompt «Food Store — Unidad 5 — Implementación controlada de la Parte A» aprobó D6 y la
columna de D11 (§9). D4, D8 (resto) y D9 siguen sin aprobar. El registro solo conserva la hora de los prompts del 2026-10-26.

### D15 — Sin `INSERT (fecha)` sobre `pedido`

Con `INSERT (fecha)`, la aplicación podría registrar pedidos con cualquier fecha. Sin esa columna,
el default `CURRENT_DATE` del schema la fija. No cambia reglas de negocio: solo qué columna puede
escribir la aplicación. **Decisión:** `rol_app_escritura` recibe `INSERT (usuario_id, forma_pago)`;
REQ-A03 sigue demostrando el permiso por columna.
**Estado: aprobada (2026-10-26).** Aplicada en §2.1, §3.1, SEC-08, SEC-14 y T04.

### D16 — Formato bcrypt aceptado y tiempo de respuesta de `fn_autenticar`

**Decisión:** aceptar solo `$2a$`, que es lo que genera `gen_salt('bf')`; `$2b$` y `$2y$` se
rechazan. Para RR-06, las ramas «mail inexistente» y «hash inválido» ejecutan un `crypt()` con sal
bcrypt nueva de costo por defecto y descartan el resultado (§5.2). No se usa un hash ficticio
literal porque quedaría en el log de DDL.
**Estado: aprobada (2026-10-26).** Aplicada en §5.2 y §5.4.

### D17 — Batería TPI fuera de la POC

La batería exige por guarda la base `foodstore_tpi_oficial`. **Decisión:** no se ejecuta en la POC;
la POC verifica la conservación con huellas de catálogo (T14) y la batería completa se ejecuta en
SEC-15 durante la implementación, en una base autorizada.
**Estado: aprobada (2026-10-26).**

### D18 — Privilegios operativos de `admin_datos`

El detalle de §2.2 (SELECT sobre cuatro tablas, SELECT por columna sobre `usuario`, USAGE/CREATE en
`reportes`, sin DML) concreta D13, que solo definía atributos.
**Estado: aprobada (2026-10-26).**

---

## 10. Pruebas de regresión globales

Estas pruebas verifican que los cambios de U5 no rompieron el comportamiento de las unidades
anteriores:

| Prueba | Qué verifica |
|---|---|
| REG-01 | Las siete rutinas y cinco triggers del TPI responden correctamente después de aplicar los REVOKE/GRANT de D3 (batería TPI, SEC-15) |
| REG-02 | `api_registrar_detalle_pedido` funciona cuando la invoca un miembro de `rol_app_escritura`; `registrar_detalle_pedido` sigue funcionando cuando lo invoca su propietario real o el superusuario |
| REG-03 | Los triggers de subtotal y total siguen disparándose correctamente dentro y fuera de la API |
| REG-04 | Las cuatro vistas de U3 siguen siendo consultables por sus roles beneficiarios y por el superusuario |
| REG-05 | Los propietarios canónicos coinciden con VP-02; `api_registrar_detalle_pedido` tiene `rol_propietario_ventas`; `fn_autenticar` y `fn_resetear_password` tienen `rol_propietario_credenciales` |

---

## 11. Estructura de archivos entregable (referencia consigna)

La consigna indica la siguiente estructura mínima. Las specs de Kiro deben exportarse
a `docs/kiro_roles_spec/` para cumplir con el entregable formal:

```
<raíz del repositorio>/
└── BITACORA.md                        ← obligatorio en la raíz, no en subcarpetas

unidades/unidad-5/
├── sql/
│   ├── roles.sql
│   ├── auditoria_test.sql
│   ├── simulacro_incidente.sql
│   └── usuario_anon.sql
├── specs/                             ← ubicación de trabajo de Kiro
│   ├── requirements.md
│   └── design.md
└── docs/
    ├── kiro_roles_spec/               ← exportación obligatoria para la entrega formal
    │   ├── requirements.md            ← copia de specs/requirements.md
    │   └── design.md                  ← copia de specs/design.md
    ├── informe_auditoria.md
    ├── log_auditoria_prueba.txt
    ├── log_simulacro_anonimizado.txt
    ├── informe_incidente.md
    └── verificacion_equivalencia.md
```

**BITACORA.md:** debe estar en la raíz del repositorio (`foodstore_baseII/BITACORA.md`),
no dentro de `unidades/unidad-5/`. Registra todos los prompts relevantes, respuestas de IA
y validaciones humanas de las Partes A–D, incluyendo al menos un caso de error o imprecisión
detectado.

**Exportación de specs:** los archivos `requirements.md` y `design.md` se mantienen bajo
`specs/` durante el desarrollo y se copian a `docs/kiro_roles_spec/` para la entrega.
No eliminar los originales de `specs/`.

---

## 12. Lo que queda pendiente antes de implementar

1. ~~Ejecutar las verificaciones previas (§14)~~ — **hecho en las instancias de validación**
   (§15), con `00_precondiciones.sql`. En cualquier otra instancia hay que repetirlas.
2. ~~Autorizar y ejecutar la POC (§13)~~ — **hecho el 2026-11-02**; resultados en §13.7. Queda
   abierta la limitación A-3 (§13.7.5).
3. ~~Aprobar la columna de D11~~ — **aprobada el 2026-11-02** (`celular`).
4. ~~Aprobar D6~~ — **aprobada el 2026-11-02**. (D14–D18 aprobadas el 2026-10-26.)
5. **Aprobar D8 completa** — definir las políticas adicionales de contraseña.
6. **Autorizar D9** — confirmar instancia aislada antes de REVOKE de CONNECT/TEMP a PUBLIC.
7. **Definir D4** — especificar qué rol puede cambiar `pedido.estado` y bajo qué condición.
8. **Elegir mecanismo complementario de auditoría (§7.3)** — Opción A, B o C.
9. ~~Recibir revisión humana de este design.md antes de escribir SQL de implementación~~ —
   hecho; la implementación se escribió y validó después (§15).
10. **Aceptación formal de SEC-04 por el equipo** (§15.4).

---

## 13. Plan técnico de la POC de permisos

Las secciones 13.1 a 13.6 son el plan: hipótesis, pasos, resultados esperados y criterios
PASS/FAIL. Los valores esperados se derivaron de los fixtures sintéticos, no de ejecuciones.
La POC se ejecutó una vez, el 2026-11-02, y sus resultados observados están en §13.7. Cuatro
puntos del plan se corrigieron después de la ejecución porque no coincidían con lo que se podía
probar o ejecutar. Esos puntos señalan su versión anterior (D-1 a D-4, §13.7.4).

### 13.1. Objetivo e hipótesis

Comprobar, antes de escribir `roles.sql` definitivo, que la cadena de venta funciona con la
matriz mínima de `rol_propietario_ventas` y que cada privilegio de esa matriz es necesario.

| Hipótesis | Enunciado | Pruebas |
|---|---|---|
| H1 | La API ejecutada por un rol limitado registra la venta correctamente | T01, T02 |
| H2 | El acceso directo a `detalle_pedido`, al procedimiento y a `calcular_total_pedido` está denegado | T03 |
| H3 | Los errores de negocio del procedimiento llegan intactos a través de la API | T05 |
| H4 | `FOR SHARE` y `FOR UPDATE` exigen UPDATE sobre al menos una columna | T07, T10 |
| H5 | Cada privilegio de la matriz es necesario (minimalidad) | T07 |
| H6 | Triggers y `calcular_total_pedido` se ejecutan con el usuario efectivo de la API; las funciones trigger y las secuencias de identidad no requieren GRANT | T01, T07, T08, T09 |
| H7 | Un error en la cadena no deja efectos parciales | T06 |
| H8 | `search_path` fijo impide usar tablas temporales homónimas | T11 |
| H9 | La creación atómica no deja ventana con ACL por defecto | T12, T13 |
| H10 | Propietarios y definiciones canónicos se conservan | T14 |

### 13.2. Aislamiento y guardas

- Instancia PostgreSQL 17.11 dedicada y descartable (D14); base única `foodstore_u5_poc`.
  No se usan `foodstore_tpi_oficial`, `foodstore_tpi_cierre_b` ni bases de U3/U4.
- Guardas al inicio de cada script (si alguna falla, el script se detiene con `ON_ERROR_STOP=1`):
  - `current_database() = 'foodstore_u5_poc'`
  - `current_setting('server_version_num')::int` entre 170000 y 179999 (y `server_version = '17.11'`
    registrado como evidencia)
  - `pg_database` contiene solo `postgres`, `template0`, `template1` y `foodstore_u5_poc`
  - Ningún rol de U5 ni `tst_u5_*` existe antes del paso P3
- Ejecución con `psql -X -v ON_ERROR_STOP=1`; cada caso negativo se aísla en `SAVEPOINT` o en su
  propia transacción, y se verifica el SQLSTATE exacto (no basta con «hubo error»).
- Sin contraseñas: los roles de la POC no tienen contraseña; las pruebas usan `SET ROLE` desde la
  sesión del superusuario de la instancia descartable. Las pruebas de conexión real quedan para la
  implementación (D12).
- Logs y salidas de la POC se guardan fuera del repositorio hasta su revisión humana. Tras esa
  revisión (2026-11-02) se incorporaron, sin editar, en
  [`unidades/unidad-5/poc_permisos/`](../poc_permisos/README.md).

### 13.3. Pasos

| Paso | Acción | Ejecutor |
|---|---|---|
| P0 | Guardas e inventario VP-01…VP-12 sobre la instancia vacía | superusuario |
| P1 | `schema.sql` (`-1`) y `tpi/sql/objetos_programables.sql` (`-1`) sin modificaciones; sin seed | superusuario |
| P2 | Huella F0 (VP-02, VP-03, VP-04) y fixtures sintéticos (§13.4); IDs capturados con `\gset` | superusuario |
| P3 | Roles de la POC: `rol_app_escritura`, `rol_propietario_ventas`, `app_web` (LOGIN sin contraseña, miembro de `rol_app_escritura`), `tst_u5_sin_privilegios` | superusuario |
| P4 | GRANT de la matriz §3 para esos roles; REVOKE de D3 y de las funciones trigger | superusuario |
| P4b | T12: creación revertida de la API. Va antes de P5, porque después la función ya existe y `CREATE FUNCTION` fallaría por duplicado (corregido, D-3) | superusuario |
| P5 | Creación atómica de la API (§5.1) | superusuario |
| P6 | Pruebas T01–T11 y T13 (§13.5); T14 se evalúa en P7 | `SET ROLE` según el caso |
| P7 | Huella F1 y comparación con F0 | superusuario |
| P8 | Limpieza: `DROP OWNED` / `DROP ROLE` de los roles de la POC, verificación sin residuos y destrucción de la instancia | superusuario |

### 13.4. Fixtures sintéticos

| Ref. | Tabla | Datos |
|---|---|---|
| C1 | `categoria` | nombre `POC categoría` |
| U1 | `usuario` | `POC Uno`, mail `poc.u1@ejemplo.test`, rol USUARIO, vigente, `contrasena = 'POC_SIN_CREDENCIAL'` (marcador, no hash) |
| U2 | `usuario` | `POC Dos`, mail `poc.u2@ejemplo.test`, rol USUARIO, `eliminado = TRUE` |
| P1 | `producto` | precio 1250.50, stock 10, disponible, vigente, categoría C1 |
| P2 | `producto` | precio 300.00, stock 2, disponible, vigente |
| P3 | `producto` | precio 100.00, stock 5, `disponible = FALSE` |
| P4 | `producto` | precio 100.00, stock 5, `eliminado = TRUE` |
| O1 | `pedido` | usuario U1, EFECTIVO, vigente, total 0 |
| O2 | `pedido` | usuario U2 (eliminado), EFECTIVO, vigente |
| O3 | `pedido` | usuario U1, EFECTIVO, `eliminado = TRUE` |

### 13.5. Casos de prueba y resultados esperados

Salvo indicación, cada caso corre en `BEGIN … ROLLBACK` y las llamadas a la API se hacen con
`SET ROLE app_web`; las verificaciones de estado se hacen con `RESET ROLE`.

| Caso | Acción | Resultado esperado | PASS si | FAIL si |
|---|---|---|---|---|
| T01 | `SELECT api_registrar_detalle_pedido(O1, P1, 3)` | Una línea: cantidad 3, precio_unitario 1250.50, subtotal 3751.50; P1 stock 7; O1 total 3751.50 | Todos los valores coinciden | Cualquier error (en especial 42501) o valor distinto |
| T02 | Tras T01 en la misma transacción: `api(O1, P2, 2)` | Segunda línea subtotal 600.00; P2 stock 0; O1 total 4351.50. Tras ROLLBACK: estado igual a los fixtures | Coincide antes y después del ROLLBACK | Total o stock incorrectos, o estado residual |
| T03 | Como `app_web`: INSERT, UPDATE, DELETE y SELECT sobre `detalle_pedido`; `CALL registrar_detalle_pedido(O1, P1, 1)`; `SELECT calcular_total_pedido(O1)`; `UPDATE producto SET stock = 0`; `UPDATE pedido SET total = 0`; `SELECT total FROM pedido`; `SELECT * FROM usuario` | Todos 42501 | Las diez sentencias enumeradas devuelven 42501 (corregido, D-1: la versión anterior decía «los once casos», pero enumeraba diez) | Alguno tiene éxito u otro SQLSTATE |
| T04 | Como `app_web`: `INSERT INTO pedido (usuario_id, forma_pago) VALUES (U1, 'TARJETA') RETURNING id`; el mismo agregando `fecha`; el mismo agregando `total` | El primero devuelve un id y el pedido tiene `fecha = CURRENT_DATE`; los otros dos 42501 | Los tres resultados | El primero falla o alguno de los otros tiene éxito |
| T05 | API con: cantidad 0; cantidad NULL; pedido inexistente (-1); O3; O2; P3; P4; `(O1, P2, 3)`; `(O1, P1, 1)` dos veces | 22023; 22023; 23503; 23514; 23514; 23514; 23514; 23514; 23505 (segunda llamada) | Cada SQLSTATE coincide; tras `ROLLBACK TO SAVEPOINT` no hay efectos | Algún 42501 (falta privilegio) u otro SQLSTATE |
| T06 | (a) T01 OK, `SAVEPOINT s`, `api(O1, P2, 5)` → 23514, `ROLLBACK TO s`. (b) En otra transacción: `REVOKE EXECUTE ON FUNCTION calcular_total_pedido(bigint) FROM rol_propietario_ventas`, `SAVEPOINT s`, `api(O1, P1, 1)` → 42501 en el trigger AFTER, `ROLLBACK TO s` | (a) estado = T01 (1 línea, P1 7, P2 2, total 3751.50). (b) sin línea nueva, P1 10, O1 total 0: la fila insertada antes del fallo del trigger no persiste | Ambos estados coinciden | Cualquier efecto parcial |
| T07 | Ablación: para cada uno de los 23 privilegios individuales de `rol_propietario_ventas` (EXECUTE ×2; `pedido` S×3, U×1; `usuario` S×2, U×1; `producto` S×5, U×1; `detalle_pedido` S×4, I×4; USAGE se excluye porque PUBLIC lo conserva), en su propia transacción: REVOKE de ese privilegio y `api(O1, P1, 1)` | Cada ablación falla con 42501 | 23/23 fallan con 42501 | Una ablación tiene éxito → ese privilegio no es necesario: se retira de la matriz y se documenta el hallazgo |
| T08 | Catálogo: sin EXECUTE de `rol_propietario_ventas` ni de PUBLIC sobre las cinco funciones trigger; T01 PASS | Los triggers se disparan igual | Catálogo sin GRANT y T01 PASS | T01 falla con permiso denegado sobre una función trigger → hipótesis refutada, se revisa la matriz |
| T09 | Catálogo: ningún GRANT sobre las secuencias de identidad de `detalle_pedido`; T01 PASS | La línea recibe `id` | Catálogo sin GRANT y T01 PASS | Error de permiso sobre la secuencia |
| T10 | `SET ROLE rol_propietario_ventas`: `SELECT eliminado FROM usuario WHERE id = U1 FOR SHARE` con la matriz completa; luego `REVOKE UPDATE (celular)` y repetir; luego `REVOKE UPDATE (total) ON pedido` y `SELECT usuario_id FROM pedido WHERE id = O1 FOR UPDATE` | OK; 42501; 42501 | Las tres respuestas coinciden | Cualquier otra respuesta (resuelve D11 en sentido contrario) |
| T11 | Como `app_web`: `CREATE TEMP TABLE producto (id BIGINT, nombre VARCHAR(120), precio NUMERIC(12,2), stock INTEGER, disponible BOOLEAN, categoria_id BIGINT, eliminado BOOLEAN)` e inserción de una fila con el id de P1 y stock 999; luego `api(O1, P1, 1)`. Corregido, D-2: la versión anterior usaba `(LIKE public.producto)`, que exige SELECT sobre la tabla origen y falla con 42501 por esa causa, no por TEMP | Si TEMP está permitido: `public.producto` P1 pasa a 9 y la tabla temporal queda en 999. Si D9 retiró TEMP: el CREATE falla con 42501 | Una de las dos ramas, completa | La API lee o modifica la tabla temporal |
| T12 | En P4b, antes de P5 (corregido, D-3): `BEGIN; CREATE FUNCTION public.api_…; ALTER … OWNER …; ROLLBACK;` y luego `to_regprocedure('public.api_registrar_detalle_pedido(bigint,bigint,integer)')` | NULL | Función inexistente | La función existe |
| T13 | Tras P5: propietario, `prosecdef`, `proconfig`, `aclexplode` de la API; atributos y miembros de `rol_propietario_ventas`; `has_schema_privilege` CREATE sobre `public` para los roles de la POC y PUBLIC | Propietario `rol_propietario_ventas`; `prosecdef = true`; `search_path` con `public` y `pg_temp` al final; sin PUBLIC; rol NOLOGIN sin miembros; CREATE `false` en todos los casos | Todo coincide | Cualquier diferencia |
| T14 | Comparar F1 con F0 | Iguales salvo: `proacl` de las siete rutinas canónicas; las dos líneas nuevas de `api_registrar_detalle_pedido` (definición y ACL, creadas en P5); y el ACL del esquema `public`, que suma `USAGE` explícito para `rol_app_escritura` y `rol_propietario_ventas` (§3.3, P4), si la huella incluye `nspacl` | Solo esas diferencias | Cambia una definición, un propietario, un trigger o una tabla canónicos, o aparece otra diferencia (corregido, D-4: la versión anterior solo esperaba los `proacl`) |

**Resultado global:** la POC es PASS solo si T01–T14 son PASS y la limpieza (P8) no deja residuos.
Un éxito inesperado en una prueba negativa es FAIL de seguridad. Un 42501 en la ruta positiva es
FAIL de matriz (falta un privilegio): se documenta, se corrige la matriz y se repite la POC completa.
Los resultados se registran tal como se observan, con su SQLSTATE; no se reescriben para ajustarlos.

### 13.6. Fuera del alcance de la POC

`fn_autenticar` y `fn_resetear_password` (dependen de VP-07, D16 y de la configuración de logs),
`rol_app_lectura`, `rol_soporte`, `rol_reportes` y `admin_datos` (dependen de las vistas de U3 y de
D18), `reportes` y privilegios por defecto (SEC-11, SEC-12), conexiones reales con identidades
efímeras, concurrencia, la batería TPI completa (D17) y la Parte B. Se verifican durante la
implementación con los criterios SEC.

### 13.7. Resultados observados (2026-11-02)

Ejecución única en un contenedor PostgreSQL 17.11 sin red, con la base `foodstore_u5_poc`
(D14), destruido al terminar. `schema.sql` y `tpi/sql/objetos_programables.sql` se instalaron
sin modificaciones y sin seed. Herramienta: Claude Code. Evidencia sin editar en
[`unidades/unidad-5/poc_permisos/evidencia/`](../poc_permisos/README.md): `corrida_final/` para la
corrida aceptada e `intentos_arnes/` para los intentos con defectos del arnés. Cada resultado
se emitió como `NOTICE RESULT|<caso>|PASS/FAIL|esperado=… observado=…|<mensaje>`.

Los resultados valen para el entorno y la ruta probados: venta por la API con `SET ROLE`, sin
conexiones reales, sin concurrencia y sin D9. No sustituyen SEC-01 a SEC-20 ni la batería TPI
(D17).

#### 13.7.1. Hipótesis

| Hipótesis | Estado anterior | Resultado observado | Evidencia |
|---|---|---|---|
| H1 | Derivada de §5.0 | Comprobada | T01, T02 |
| H2 | Derivada | Comprobada | T03 (10/10 con 42501) |
| H3 | Derivada | Comprobada | T05 (SQLSTATE exactos) |
| H4 | Documentación del motor | Comprobada para `usuario` y `pedido`; para `producto`, por la ablación de `UPDATE (stock)` | T10, T07.06, T07.09, T07.15 |
| H5 | Derivada | Comprobada para los 23 privilegios de `rol_propietario_ventas`; no para USAGE ni para `rol_app_escritura` (§13.7.3) | T07 |
| H6 | Derivada | Comprobada | T01, T06b, T07.02, T07.18, T07.19, T08, T09 |
| H7 | Derivada | Comprobada | T06 (a) y (b), residuos tras cada grupo |
| H8 | Derivada | Comprobada con la variante de columnas explícitas (D-2) y TEMP permitido | T11 |
| H9 | Derivada | Comprobada | T12, T13 |
| H10 | Derivada | Comprobada | T14 |

#### 13.7.2. Resultado por caso

| Caso | Resultado | Observado | Archivo de `corrida_final/` |
|---|---|---|---|
| P0 | OK | Guardas OK; inventario VP (§13.7.6) | `01_p0_inventario.txt` |
| P1 | OK | Instalación con `-1` sin errores; VP-02, 03, 04, 11 y 12 | `02_p1_instalacion.txt` |
| P2 | OK (tras A-1) | F0 de 105 líneas; fixtures: 1 categoría, 2 usuarios, 4 productos, 3 pedidos | `f0_huella.txt`, `03_p2_fixtures.txt` |
| P3, P4 | OK | Cuatro roles sin atributos especiales; única membresía de la POC: `rol_app_escritura <- app_web`, sin ADMIN OPTION | `04_p3_p4_roles.txt` |
| T01 | PASS | Línea O1/P1 `3 × 1250.50 = 3751.50`; P1 stock 7; O1 total 3751.50 | `07_pruebas.txt` |
| T02 | PASS | Segunda línea O1/P2 `2 × 300.00 = 600.00`; P2 stock 0; total 4351.50; tras ROLLBACK, estado igual a los fixtures | `07_pruebas.txt` |
| T03 | PASS | Las 10 sentencias devuelven 42501 | `07_pruebas.txt` |
| T04 | PASS | INSERT `(usuario_id, forma_pago)` OK con `fecha = CURRENT_DATE`, PENDIENTE, total 0.00; con `fecha` y con `total`, 42501 | `07_pruebas.txt` |
| T05 | PASS | 22023, 22023, 23503, 23514 × 5 y 23505 en la segunda llamada; sin efectos tras cada error | `07_pruebas.txt` |
| T06 | PASS | (a) estado igual a T01. (b) 42501 en `UPDATE pedido … calcular_total_pedido` dentro de `fn_recalcular_total_insert()`, disparado por el INSERT de la línea; sin línea, P1 stock 10, total 0 | `07_pruebas.txt` |
| T07 | PASS | 23/23 con 42501 (§13.7.3) | `08_t07.txt` |
| T08 | PASS | 0 entradas EXECUTE de `rol_propietario_ventas` o PUBLIC sobre las cinco funciones trigger; `has_function_privilege` false × 5; T01 PASS | `07_pruebas.txt` |
| T09 | PASS | `relacl` NULL en la secuencia de identidad de `detalle_pedido`; T01 PASS | `07_pruebas.txt` |
| T10 | PASS | Sin error, 42501, 42501 | `07_pruebas.txt` |
| T11 | PASS (variante) | La sentencia literal anterior (`LIKE`) se registró sin veredicto: 42501 `permission denied for table producto`. Variante: `public.producto` P1 = 9; `pg_temp.producto` = 999; sin residuo | `07_pruebas.txt` |
| T12 | PASS | Antes y después de la transacción revertida, `to_regprocedure` = NULL | `05_t12.txt` |
| P5 | OK | API creada en una transacción | `06_p5_api.txt`, `acl_tablas_f1.txt` |
| T13 | PASS | Propietario `rol_propietario_ventas`; `prosecdef` true; `search_path=public, pg_temp`; ACL `rol_app_escritura:EXECUTE` y `rol_propietario_ventas:EXECUTE`, sin PUBLIC; rol NOLOGIN, NOINHERIT, sin atributos ni miembros; CREATE sobre `public` false para los cuatro roles y para PUBLIC; `tst_u5_sin_privilegios` sin EXECUTE | `07_pruebas.txt` |
| T14 | PASS (con criterio corregido, D-4) | Sin cambios en definiciones (md5), propietarios, triggers, tipos, columnas, restricciones, índices ni secuencias. Difieren el `proacl` de las 7 rutinas, la API nueva (2 líneas) y el ACL de `public` | `t14_diff.txt` |
| P8 | OK, con límite A-3 | Roles y API retirados; guarda sin roles de U5 OK; `P8.membresias` FAIL de arnés sin repetir | `09_p8_limpieza.txt` |

En la corrida aceptada, P6 dio 66/66 PASS y T07 23/23 PASS. El único FAIL registrado en la
corrida final es `P8.membresias` (A-3).

#### 13.7.3. Contrastación de la matriz de `rol_propietario_ventas` (T07)

Cada ablación revocó un solo privilegio en su propia transacción y ejecutó
`api(O1, P1, 1)` como `app_web`. La columna «Primera sentencia que falla» sale del
`CONTEXT` registrado.

| # | Privilegio revocado | SQLSTATE | Primera sentencia que falla |
|---|---|---|---|
| 01 | EXECUTE `registrar_detalle_pedido` | 42501 | `CALL` en la API |
| 02 | EXECUTE `calcular_total_pedido` | 42501 | `UPDATE pedido SET total = calcular_total_pedido(…)` en `fn_recalcular_total_insert()` |
| 03 | `pedido` SELECT (id) | 42501 | `SELECT usuario_id FROM pedido … FOR UPDATE` |
| 04 | `pedido` SELECT (usuario_id) | 42501 | ídem |
| 05 | `pedido` SELECT (eliminado) | 42501 | ídem |
| 06 | `pedido` UPDATE (total) | 42501 | ídem (bloqueo sin UPDATE) |
| 07 | `usuario` SELECT (id) | 42501 | `SELECT eliminado FROM usuario … FOR SHARE` |
| 08 | `usuario` SELECT (eliminado) | 42501 | ídem |
| 09 | `usuario` UPDATE (celular) | 42501 | ídem (bloqueo sin UPDATE; D11) |
| 10–14 | `producto` SELECT (id), (precio), (stock), (disponible), (eliminado) | 42501 | `SELECT precio, stock, disponible, eliminado FROM producto … FOR UPDATE` |
| 15 | `producto` UPDATE (stock) | 42501 | ídem (bloqueo sin UPDATE) |
| 16, 17 | `detalle_pedido` SELECT (pedido_id), (producto_id) | 42501 | `PERFORM 1 FROM detalle_pedido …` (detección de duplicado) |
| 18, 19 | `detalle_pedido` SELECT (subtotal), (eliminado) | 42501 | Sentencia de `calcular_total_pedido` |
| 20–23 | `detalle_pedido` INSERT (pedido_id), (producto_id), (cantidad), (precio_unitario) | 42501 | `INSERT INTO detalle_pedido …` |

**Necesidad comprobada:** los 23 privilegios. Cada ablación tiene su `RESULT` y su `CONTEXT`
en `08_t07.txt`.

**Alcance:** una ablación prueba la necesidad en la primera sentencia que falla. No prueba qué
exigirían las sentencias posteriores de la cadena. Por ejemplo, `UPDATE (stock)` falla en el
bloqueo y no llega a probarse en el descuento de stock.

**Sin evidencia de necesidad (no se consideran probados):**

| Rol | Privilegio | Situación |
|---|---|---|
| `rol_propietario_ventas` | USAGE sobre `public` | Excluido de T07 porque PUBLIC conserva USAGE: retirarlo no tendría efecto observable. Se mantiene por explícito, no por evidencia |
| `rol_app_escritura` | EXECUTE sobre la API | Suficiencia comprobada (T01). Sin ablación ni llamada negativa: T13 solo verifica en el catálogo que un rol sin ese GRANT (`tst_u5_sin_privilegios`) no tiene EXECUTE |
| `rol_app_escritura` | INSERT (`usuario_id`, `forma_pago`) y SELECT (`id`) sobre `pedido` | Suficiencia comprobada (T04.1). Sin ablación individual |
| `rol_app_escritura` | USAGE sobre `public` | Mismo caso que en `rol_propietario_ventas` |

Se comprobó la denegación de lo que la matriz excluye (T03, T04.2, T04.3). Se comprobó también
que no hacen falta privilegios para las funciones trigger, las secuencias ni las FK (T08, T09,
T01, T04.1).

#### 13.7.4. Correcciones del plan derivadas de la ejecución

| ID | Caso | Versión anterior | Problema observado | Corrección |
|---|---|---|---|---|
| D-1 | T03 | «Los once casos devuelven 42501» | Se enumeraban diez sentencias | Diez sentencias; no se agregó ninguna |
| D-2 | T11 | `CREATE TEMP TABLE producto (LIKE public.producto)` | `LIKE` exige SELECT sobre la tabla origen: 42501 por esa causa, no por TEMP | Tabla temporal con columnas explícitas; la sentencia literal quedó registrada como `OBSERVADO` |
| D-3 | T12 | Listado junto con las pruebas de P6, después de P5 | Después de P5, `CREATE FUNCTION` fallaría por duplicado | Paso P4b, entre P4 y P5 |
| D-4 | T14 | «Iguales salvo `proacl` de las siete rutinas» | La API nueva y el USAGE explícito de §3.3 también aparecen en la huella | Esas diferencias quedan como esperadas. El ACL del esquema no forma parte de VP-02/03/04; la huella de la POC lo relevó de más |

#### 13.7.5. Incidencias del arnés

No son fallos del producto. Los resultados originales se conservan en `evidencia/intentos_arnes/`.

| ID | Paso | Incidencia | Tratamiento |
|---|---|---|---|
| A-1 | P2 | `huella.sql` concatenaba columnas `"char"` sin cast (`operator is not unique: text \|\| "char"`). Abortó antes de cargar fixtures; era de solo lectura | Se agregó `::text` en dos expresiones y se repitió P2 |
| A-2 | P6 | Primer intento con 4 FAIL de aserción y valores observados correctos: booleanos impresos como `t`/`f` por `format('%s')`, `ORDER BY 1` constante dentro de `string_agg`, y membresías predefinidas de `pg_monitor` incluidas en la consulta | Se corrigieron solo esas 4 aserciones y se repitió P6, que no deja estado: **66/66 PASS** |
| A-3 | P8 | `P8.membresias`: esperado 0, observado 3. Mismo defecto que A-2: son las 3 membresías predefinidas de `pg_monitor` registradas en VP-10 | **Sin repetir**: la instancia ya estaba destruida. La ausencia de roles y de la API está comprobada (`P8.roles`, `P8.api`, guarda posterior al DROP); la ausencia de membresías residuales queda sin aserción corregida |

#### 13.7.6. Inventario VP en el entorno de la POC

Solo vale para la instancia descartable. En la instancia de implementación hay que repetirlo.

| ID | Observado |
|---|---|
| VP-00 | Servidor y `psql` 17.11 |
| VP-01 | Cuatro bases; roles: `postgres` y predefinidos; ninguno de U5 |
| VP-02 | Tablas, secuencias, rutinas, tipos y base: `postgres`; esquema `public`: `pg_database_owner` |
| VP-03 | Las 7 rutinas: `proacl` NULL (PUBLIC con EXECUTE), `prosecdef` false, `proconfig` NULL |
| VP-04 | 5 triggers, `tgenabled = O` |
| VP-05 | PUBLIC: solo USAGE sobre `public` |
| VP-06 | `datacl` NULL: PUBLIC con CONNECT y TEMPORARY |
| VP-07 | Parcial: `pgcrypto` 1.3 disponible, no instalada; `gen_salt('bf')` no probado |
| VP-08 | 0 entradas en `pg_default_acl` |
| VP-09 | `log_statement = none`, `log_parameter_max_length = -1`, `log_parameter_max_length_on_error = 0`, `log_min_error_statement = error`, `log_min_duration_statement = -1`, `log_file_mode = 0600`, `logging_collector = off`, `password_encryption = scram-sha-256` (valores por defecto de la imagen; §7 exige ajustarlos) |
| VP-10 | Solo las 3 membresías predefinidas de `pg_monitor`, sin ADMIN OPTION; `createrole_self_grant` vacío |
| VP-11 | Vistas y materializada de U3 ausentes: no están en la instalación mínima |
| VP-12 | Cinco secuencias de identidad, `relacl` NULL |

#### 13.7.7. Pendiente después de la POC

- ~~Aprobar la columna de D11~~ (aprobada el 2026-11-02).
- Repetir la aserción de membresías de P8 en una corrida futura autorizada (A-3).
- Comprobar por ablación los privilegios de `rol_app_escritura`, si el equipo lo requiere.
- Todo lo listado en §13.6, las verificaciones VP en la instancia de implementación y SEC-01 a
  SEC-20.

---

## 14. Inventario de verificaciones previas en PostgreSQL

Se ejecutan solo en una instancia autorizada, antes de la POC o de la implementación. Son consultas
de lectura; su salida se conserva como evidencia. VP-00 a VP-12 se ejecutaron en la instancia
descartable de la POC (P0 y tras P1; resultados en §13.7.6), y de nuevo, mediante
`00_precondiciones.sql`, en cada instancia de la validación integral (§15). Esos valores
describen esos laboratorios: en cualquier otra instancia hay que repetirlas antes de instalar.

| ID | Qué se verifica | Fuente de catálogo | Uso |
|---|---|---|---|
| VP-00 | Herramientas: servidor 17.11; cliente psql 16 o superior (para `\bind`). En la estación de trabajo de esta revisión `psql` no está instalado | `SHOW server_version`; `psql --version` | Todas |
| VP-01 | Inventario de bases y roles de la instancia; ausencia de colisiones con los nombres de U5 (los roles son globales del clúster) | `pg_database`, `pg_roles` | D14, SEC-20 |
| VP-02 | Propietarios reales: cinco tablas, siete rutinas, tres tipos, esquema `public`, base y secuencias de identidad | `pg_class.relowner`, `pg_proc.proowner`, `pg_type.typowner`, `pg_namespace.nspowner`, `pg_database.datdba` | D2, SEC-15, REG-05 |
| VP-03 | ACL y configuración de las siete rutinas: `proacl` (se espera NULL = PUBLIC con EXECUTE), `prosecdef = false`, `proconfig` NULL | `pg_proc`, `aclexplode` | D3, F0 |
| VP-04 | Cinco triggers, función asociada y `tgenabled` | `pg_trigger`, `pg_get_triggerdef` | F0, SEC-15 |
| VP-05 | ACL del esquema `public`: sin CREATE para PUBLIC; propietario | `pg_namespace.nspacl`, `aclexplode` | SEC-17, RR-05 |
| VP-06 | ACL de la base: CONNECT y TEMP de PUBLIC | `pg_database.datacl` | D9 |
| VP-07 | `pgcrypto`: disponibilidad, versión y esquema; formato y costo por defecto de `gen_salt('bf')` (debe producir `$2a$` y cumplir la expresión regular de §5.2); ACL de `crypt` y `gen_salt` | `pg_available_extensions`, `pg_extension`, pruebas con valores sintéticos | §5.2, D16 |
| VP-08 | Privilegios por defecto existentes (se espera ninguno) | `pg_default_acl`, `\ddp` | SEC-11, SEC-12 |
| VP-09 | Configuración de logs y contraseñas: `log_statement`, `log_parameter_max_length`, `log_parameter_max_length_on_error`, `log_min_error_statement`, `log_min_duration_statement`, `log_file_mode`, `logging_collector`, `password_encryption` | `pg_settings` | §7, SEC-16 |
| VP-10 | Membresías existentes con `admin_option`; valor de `createrole_self_grant` | `pg_auth_members`, `pg_settings` | SEC-10 |
| VP-11 | Presencia, propietario y opciones (`security_invoker`) de las vistas y la materializada de U3 | `pg_class`, `pg_class.reloptions` | §2.1, SEC-04 |
| VP-12 | Secuencias de identidad de las cinco tablas y su ACL | `pg_depend`, `pg_get_serial_sequence`, `pg_class.relacl` | T09 |

---

## 15. Validación integral de la Parte A (2026-11-02)

Resultados observados en laboratorio. La evidencia se conserva sin editar en
[`../validacion_parte_a/`](../validacion_parte_a/README.md), con una carpeta por corrida. Los
fuentes ejecutados (canon, U3 y `unidades/unidad-5/sql/**`) quedaron registrados por sha256 antes
y después de cada corrida, y no cambiaron. Herramienta: Claude Code. Nada se ejecutó sobre
instancias compartidas ni sobre bases de unidades anteriores.

### 15.1. Entorno

| Aspecto | Valor observado |
|---|---|
| Imagen | `postgres:17`, `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3` |
| Servidor y cliente | PostgreSQL y psql 17.11 (Debian 17.11-1.pgdg13+2) |
| Aislamiento | Un contenedor nuevo por corrida, `--network none`, sin puertos publicados, repositorio montado en solo lectura; destruido con su volumen al terminar |
| Base | `foodstore_tpi_oficial`, nombre que exige la guarda de la batería TPI (D17), creada solo dentro de cada contenedor |
| Instalación | `schema.sql` (`-1`), seed, `objetos_programables.sql` (`-1`), vistas y materializada de U3, `pgcrypto` en `public` y luego el orden de `sql/README.md` con `u5_base_objetivo` |
| Logging | Solo dentro del contenedor: `log_statement=mod`, `log_parameter_max_length=0`, `log_parameter_max_length_on_error=0`, `log_file_mode=0600`, `password_encryption=scram-sha-256` |

### 15.2. Corridas

| Corrida | Alcance | Resultado |
|---|---|---|
| `20261102T185421Z` | Primera validación integral | **BLOCKED** antes de ejecutar SQL, por un control defectuoso del arnés de captura. Se conserva sin cambios |
| `20261102T190345Z` | Validación integral con el arnés corregido (solo la detección de arranque) | 207 RESULT PASS / 0 FAIL. Batería TPI 29/37/30, exit 0, antes y después, con salidas idénticas. SEC-01, 04 y 17 quedaron parciales por M05, M03 y M04 |
| `20261102T191848Z` | Cierre experimental: M04, M05, SCRAM y revisión de SEC-04 | M04, M05 y SCRAM PASS. Hubo una incidencia del arnés antes de crear contenedores; se conserva con su corrección |

### 15.3. Pruebas complementarias

- **M04 — interrupción antes del COMMIT.** Se le pasó a psql el `funciones_seguridad.sql`
  original, sin modificar, reteniendo su `COMMIT` final. Con la transacción abierta, otra
  conexión no veía las funciones. `pg_terminate_backend` terminó la sesión: el log registra
  `FATAL: 57P01: terminating connection due to administrator command` y esa sesión no envió
  ROLLBACK. Después no existían las funciones ni sus ACL, y los permisos de `roles.sql` y los
  propietarios estaban intactos. Un control separado con `ROLLBACK` explícito quedó registrado
  como tal en otra sesión.
- **M05 — segunda instalación limpia.** Reinstalación completa desde cero: 207 RESULT PASS /
  0 FAIL, con los mismos casos y veredictos que la corrida `20261102T190345Z`. Las únicas
  diferencias son campos naturalmente variables (identidades de instancia, PID, tiempos) y el
  transporte de las salidas. La limpieza de roles y membresías se verificó de nuevo.
- **SCRAM-SHA-256.** Reglas `pg_hba.conf` explícitas para loopback (127.0.0.1 y ::1) con
  `scram-sha-256`, sin errores en `pg_hba_file_rules`. Rol temporal `tst_u5_scram` sin GRANT
  directos ni membresías: solo lo que hereda de PUBLIC. Su verificador se calculó del lado del
  cliente y se asignó con el registro de sentencias desactivado para esa sesión. Una conexión TCP
  con `require_auth=scram-sha-256` se registró como `connection authenticated: ...
  method=scram-sha-256`; una contraseña incorrecta dio `FATAL: 28P01`. El rol se eliminó. Las
  búsquedas exactas de la contraseña y el verificador no tuvieron coincidencias en logs ni en
  evidencias. Esta es la autenticación de conexión de PostgreSQL; la autenticación funcional de
  `fn_autenticar` (bcrypt sobre `usuario.contrasena`) es otra cosa y la cubre SEC-18.

### 15.4. SEC-04 — reidentificación

El único objeto analítico que `rol_reportes` puede leer es `mv_facturacion_categoria_mes`:
categoría, mes, cantidad de pedidos, unidades y facturación, sin columnas de usuario. Las cohortes
del seed son pequeñas (3 y 2 usuarios por categoría y mes), así que no se acredita la ausencia de
reidentificación con conocimiento auxiliar. La revisión humana del 2026-11-02 «acepta
provisionalmente el uso académico de datos sintéticos y agregados, pero no autoriza exposición de
datos personales reales». Las condiciones para la aceptación formal están en
`../validacion_parte_a/20261102T191848Z/sec04/README.md`. **Estado: aceptación provisional,
pendiente de aceptación formal del equipo.**

### 15.5. Estado de los criterios de aceptación

| Estado | Criterios |
|---|---|
| PASS | SEC-01 (con M05), SEC-02, SEC-03, SEC-05 a SEC-15, SEC-17 (con M04), SEC-18 a SEC-20 |
| PASS limitado al intervalo ensayado | SEC-16: valores sintéticos exactos ausentes del log capturado, más SCRAM; no es una garantía universal |
| Pendiente de aceptación formal | SEC-04 (§15.4) |

Regresión: batería TPI con 29 grupos, 37 variantes, 30 NOTICE PASS y exit 0, antes y después de
U5, en las dos instalaciones. F0/F1 solo difieren en los ACL que autoriza D3. P8.membresias, con
la aserción corregida, dio PASS también después del COMMIT de la limpieza.

### 15.6. Límites y riesgos que siguen vigentes

- No se midieron concurrencia, serialización multisesión, tiempos de bcrypt (RR-06) ni estrés.
- RR-01 (`UPDATE (celular)`), RR-03 (pertenencia del pedido al usuario final), RR-04 (enumeración
  de IDs) y RR-07 (recuperación manual de ACL) siguen como riesgos del diseño.
- D4, D8 (resto) y D9 siguen sin implementar. El mecanismo de auditoría de §7.3 (Parte C) sigue
  sin elegir.
- La evidencia vale para los laboratorios descriptos. En otra instancia hay que repetir las
  precondiciones y la validación.
