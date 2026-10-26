# Design — Unidad 5: Administración y Seguridad de Food Store

**Trabajo Práctico — Unidad 5 / Semana 9**
Base de Datos II — Tecnicatura Universitaria en Programación — UTN
**Integrantes:** Avalos Pablo, Blangetti Sofia, Suarez Ismael
**Motor objetivo:** PostgreSQL 17.11
> Ningún objeto de U5 ha sido ejecutado en la base de laboratorio todavía.
> Los contratos de este documento son propuestas pendientes de revisión humana y prueba.

> Este documento describe el diseño propuesto. Ningún SQL de este archivo ha sido ejecutado en
> PostgreSQL. La implementación real queda pendiente de revisión humana y autorización explícita.

---

## 1. Arquitectura del esquema de roles

### 1.1. Principio organizador

Se aplica el modelo de **roles de grupo + roles de login** descrito en la Clase 1:

- **Roles de grupo** (NOLOGIN): definen qué se puede hacer. Se revisan y estabilizan
  de forma independiente de quién se conecta.
- **Roles de login** (LOGIN + PASSWORD): representan conexiones reales. Adquieren
  capacidades mediante membresía en roles de grupo. Cambiar la responsabilidad de un
  servicio o persona es un ajuste de membresía, no una reescritura de privilegios.

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
                   │ GRANT (membresía)
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
Su único propósito es ser OWNER de las rutinas SECURITY DEFINER correspondientes, de modo que
esas funciones corran con el mínimo privilegio necesario y no con los privilegios amplios de
`admin_datos`.

---

## 2. Especificación de roles

### 2.1. Roles de grupo

#### `rol_app_lectura` — NOLOGIN, NOINHERIT opcional

**Justificación:** Sirve el catálogo público del sitio. Solo necesita leer productos vigentes
a través de la vista `v_productos_vigentes`, que ya proyecta `categoria_nombre`. No necesita
ver pedidos ni usuarios.

| Objeto | Privilegio | Esquema |
|---|---|---|
| `v_productos_vigentes` | SELECT | public |
| SCHEMA public | USAGE | — |

**Excluido deliberadamente:** SELECT directo sobre la tabla `categoria`. La vista
`v_productos_vigentes` (U3) ya expone `categoria_id` y `categoria_nombre` junto con los
productos, filtrando por `eliminado = FALSE` en ambas tablas. Si se necesita consultar
categorías de forma independiente de los productos (por ejemplo, para poblar un selector
en la UI), el equipo debe crear una vista específica `v_categorias_vigentes` y otorgar
SELECT sobre ella a `rol_app_lectura`. Esta vista no existe en el modelo oficial actual
y no se crea en U5 sin autorización explícita.

> Si la cátedra exige demostrar acceso directo a una tabla de catálogo, documentarlo
> en BITACORA.md y crear `v_categorias_vigentes` en ese momento.

---

#### `rol_app_escritura` — NOLOGIN

**Justificación:** Crea pedidos y accede a la interfaz de venta autorizada. No puede leer ni
modificar `detalle_pedido` directamente — esa tabla se gestiona exclusivamente a través de
`api_registrar_detalle_pedido`. No puede modificar `estado`, `total` ni `eliminado` en `pedido`.

| Objeto | Privilegio | Esquema | Nota |
|---|---|---|---|
| `pedido` | INSERT (columnas: `fecha`, `forma_pago`, `usuario_id`) | public | Permiso por columna — práctica REQ-A03 |
| `pedido` | SELECT | public | Para consultar sus propios pedidos creados |
| `api_registrar_detalle_pedido(bigint,bigint,integer)` | EXECUTE | public | Única interfaz de venta autorizada (D1) |
| SCHEMA public | USAGE | — | — |

**Excluido deliberadamente:**
- DELETE, TRUNCATE, UPDATE sobre `pedido`
- Todo privilegio sobre `detalle_pedido` (tabla base)
- EXECUTE directo sobre `registrar_detalle_pedido` (el procedimiento canónico del TPI)
- EXECUTE sobre `calcular_total_pedido` (función interna; el total lo mantienen los triggers)

**Nota:** El INSERT por columna sobre `pedido` es el permiso por columna requerido por REQ-A03.
El campo `total` lo calcula el trigger; `estado` inicia siempre en PENDIENTE por default del schema;
`eliminado` inicia en FALSE. Ninguno de estos campos necesita ser otorgado al rol operativo.

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

> Si la cátedra exige demostrar permisos por columna específicamente sobre `usuario`, puede
> documentarse como ejemplo complementario sin incluirlo en `roles.sql` operativo.

---

#### `rol_reportes` — NOLOGIN

**Justificación:** Panel gerencial de solo lectura. Accede a objetos analíticos agregados.
No accede a datos individuales identificables.

| Objeto | Privilegio | Esquema |
|---|---|---|
| `mv_facturacion_categoria_mes` | SELECT | reportes (ver §4) |
| Vistas analíticas futuras | SELECT | reportes |
| SCHEMA reportes | USAGE | — |

> La vista materializada `mv_facturacion_categoria_mes` fue creada en U3 sobre el esquema
> `public` de la base de laboratorio de esa unidad. En la base de U5, si se reinstala,
> se ubica en el esquema `reportes` conforme a D10.

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

#### `rol_propietario_ventas` — NOLOGIN, sin miembros (D6)

**Justificación:** Propietario de `api_registrar_detalle_pedido`. Como esa función es
SECURITY DEFINER, corre con los privilegios de este rol. Dado que `registrar_detalle_pedido`
es SECURITY INVOKER, hereda el usuario efectivo del caller — es decir, también corre bajo
`rol_propietario_ventas`. Este rol necesita todos los privilegios que el procedimiento
canónico usa internamente.

El propietario de `registrar_detalle_pedido` y demás rutinas del TPI no cambia (D2).

Este rol no tiene miembros. Nadie se conecta como él ni lo hereda.

**Privilegios requeridos sobre tablas (sujetos a verificación empírica — D11):**

| Objeto | Privilegio | Por qué |
|---|---|---|
| `pedido` | SELECT, UPDATE | `FOR UPDATE` para bloquear el pedido antes de modificar |
| `usuario` | SELECT | `FOR SHARE` para verificar baja lógica del usuario |
| `usuario` | UPDATE (col: `celular`)⁷ | `FOR SHARE` puede requerir UPDATE sobre ≥1 columna en PG17 |
| `producto` | SELECT, UPDATE | `FOR UPDATE` para leer precio/stock; UPDATE para descontar stock |
| `detalle_pedido` | INSERT, SELECT | INSERT de la línea; PERFORM para detectar duplicado |
| SCHEMA public | USAGE | resolución de nombres |
| `registrar_detalle_pedido(bigint,bigint,integer)` | EXECUTE | CALL desde la función wrapper |

⁷ Riesgo residual documentado: un atacante con acceso a `rol_propietario_ventas` podría
ejecutar `UPDATE usuario SET celular = ...`. Se acepta porque `celular` es nullable y sin
lógica de negocio; el equipo puede elegir otra columna igualmente inocua si lo prefiere.

**Lo que este rol no necesita** (los triggers AFTER corren bajo el OWNER de la función trigger,
que es el OWNER canónico, no el usuario efectivo de la cadena):
- EXECUTE sobre `calcular_total_pedido`
- EXECUTE sobre las cinco funciones trigger

---

#### `rol_propietario_credenciales` — NOLOGIN, sin miembros (D6)

**Justificación:** Propietario de `fn_autenticar` y `fn_resetear_password`. Al ser OWNER,
estas funciones SECURITY DEFINER corren con el mínimo privilegio (SELECT sobre `usuario`
incluyendo `contrasena`; UPDATE sobre `usuario.contrasena`) sin exponer esos privilegios a
`app_web` ni a `rol_soporte`.

Este rol no tiene miembros.

**Privilegios requeridos:**

| Objeto | Privilegio | Para qué |
|---|---|---|
| `usuario` | SELECT | `fn_autenticar` necesita leer `contrasena` y `mail` |
| `usuario.contrasena` | UPDATE (columna) | `fn_resetear_password` necesita actualizar solo esa columna |
| SCHEMA public | USAGE | — |

---

### 2.2. Roles de login

#### `app_web` — LOGIN, PASSWORD (marcador académico, no credencial real)

**Justificación:** Es la identidad que usa el backend de la aplicación web para conectarse.
Acumula los privilegios necesarios para servir el catálogo, gestionar el flujo de compra
y autenticar usuarios.

```sql
CREATE ROLE app_web WITH LOGIN PASSWORD 'PLACEHOLDER_NO_USAR_EN_PRODUCCION';
GRANT rol_app_lectura        TO app_web;
GRANT rol_app_escritura      TO app_web;
GRANT rol_app_autenticacion  TO app_web;
```

**Atributos:** Sin SUPERUSER, sin CREATEDB, sin CREATEROLE, sin BYPASSRLS.
`CONNECTION LIMIT` a definir según criterio operativo del equipo (la Clase 1 sugiere 50).

---

#### `admin_datos` — LOGIN, PASSWORD (marcador académico)

**Justificación:** Administrador de la base y rol de la cátedra. Es el propietario del esquema.
Gestiona la instalación y mantenimiento de los objetos.

**Decisión D13 — sin CREATEROLE ni CREATEDB:**
La Clase 1 mostraba `admin_datos WITH LOGIN PASSWORD ... CREATEDB CREATEROLE`.
La decisión D13 revierte esos atributos. Justificación: CREATEROLE permite crear roles con
cualquier privilegio que `admin_datos` tenga, lo cual podría usarse para escalar privilegios
de forma indirecta. CREATEDB no es necesario para administrar una base existente.

```sql
CREATE ROLE admin_datos WITH LOGIN PASSWORD 'PLACEHOLDER_NO_USAR_EN_PRODUCCION';
-- Sin CREATEDB, sin CREATEROLE
```

> Si la cátedra requiere que `admin_datos` pueda crear objetos en el esquema, el privilegio
> correcto es `GRANT CREATE ON SCHEMA public TO admin_datos`, no el atributo global CREATEDB.

---

## 3. Mapa consolidado de privilegios

### 3.1. Sobre tablas y vistas (esquema public)

| Objeto | rol_app_lectura | rol_app_escritura | rol_soporte | rol_reportes | rol_prop_ventas¹ | rol_prop_cred² |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| `categoria` | — | — | — | — | — | — |
| `usuario` | — | — | — | — | SELECT, UPD(celular)⁴ | SELECT, UPD(contrasena)⁵ |
| `producto` | — | — | — | — | SELECT, UPDATE | — |
| `pedido` | — | SELECT⁶, INS(col)³ | — | — | SELECT, UPDATE | — |
| `detalle_pedido` | — | — | — | — | INSERT, SELECT | — |
| `v_productos_vigentes` | SELECT | — | — | — | — | — |
| `v_usuarios_publico` | — | — | SELECT | — | — | — |
| `v_pedidos_resumen` | — | — | SELECT | — | — | — |
| `v_pedido_detalle` | — | — | — | — | — | — |

¹ `rol_propietario_ventas` — OWNER de `api_registrar_detalle_pedido`; hereda estos privilegios como
  usuario efectivo cuando `registrar_detalle_pedido` (SECURITY INVOKER) se ejecuta dentro de la cadena.
  **Sujeto a verificación empírica en PG 17.11** — ver D11 §9.
² `rol_propietario_credenciales` — OWNER de `fn_autenticar` y `fn_resetear_password`.
³ INSERT restringido a columnas `fecha`, `forma_pago`, `usuario_id` — práctica REQ-A03.
⁴ `SELECT` requerido por `FOR SHARE`; `UPDATE(celular)` requerido en PG17 por `FOR SHARE` sobre ≥1 col.
  Riesgo residual documentado en §2.1.
⁵ `UPDATE(contrasena)` columna única; `SELECT` completo para comparar hash en `fn_autenticar`.
⁶ SELECT sobre `pedido` para `rol_app_escritura` no implica visibilidad restringida a pedidos propios —
  sin RLS activo, este SELECT ve todos los pedidos. Si se requiere aislamiento, es necesario implementar
  Row-Level Security, que está fuera del alcance de U5 sin autorización explícita.

### 3.2. Sobre rutinas (esquema public)

| Rutina | Tipo | OWNER (no cambia) | PUBLIC tras D3 | GRANT explícito |
|---|---|---|---|---|
| `registrar_detalle_pedido(bigint,bigint,integer)` | procedimiento (TPI) | `admin_datos` (D2) | REVOKE | GRANT EXECUTE → `rol_propietario_ventas`⁶ |
| `calcular_total_pedido(bigint)` | función SQL (TPI) | `admin_datos` | REVOKE | — (solo triggers y `admin_datos`) |
| `fn_set_subtotal()` | fn trigger (TPI) | `admin_datos` | REVOKE | — (solo triggers) |
| `fn_validar_detalle_vigente()` | fn trigger (TPI) | `admin_datos` | REVOKE | — (solo triggers) |
| `fn_recalcular_total_insert()` | fn trigger (TPI) | `admin_datos` | REVOKE | — (solo triggers) |
| `fn_recalcular_total_update()` | fn trigger (TPI) | `admin_datos` | REVOKE | — (solo triggers) |
| `fn_recalcular_total_delete()` | fn trigger (TPI) | `admin_datos` | REVOKE | — (solo triggers) |
| `api_registrar_detalle_pedido(bigint,bigint,integer)` | función (nueva) | `rol_propietario_ventas` | REVOKE | GRANT EXECUTE → `rol_app_escritura` |
| `fn_autenticar(text,text)` | función (nueva) | `rol_propietario_credenciales` | REVOKE | GRANT EXECUTE → `rol_app_autenticacion` |
| `fn_resetear_password(bigint,text)` | función (nueva) | `rol_propietario_credenciales` | REVOKE | GRANT EXECUTE → `rol_soporte` |

⁶ `rol_propietario_ventas` necesita EXECUTE sobre `registrar_detalle_pedido` para que la función
  wrapper pueda invocarlo. Este GRANT no cambia el OWNER del procedimiento (D2).

**Nota sobre `calcular_total_pedido`:** Esta función es invocada por los triggers AFTER de
`detalle_pedido`. Los triggers corren bajo el OWNER de la función trigger, que es `admin_datos`.
Ningún rol de aplicación necesita EXECUTE sobre ella.

**Verificación de proacl NULL:**
Antes de cualquier REVOKE, consultar `pg_proc.proacl` para las siete rutinas del TPI.
Si el valor es NULL, PUBLIC tiene EXECUTE implícito (comportamiento de PG 14 y anteriores;
en PG 15+ las funciones nuevas no lo otorgan por defecto, pero las instaladas previamente
pueden tenerlo). Verificar con el rol efímero (D12) antes de concluir que el REVOKE es efectivo.

---

## 4. Esquema `reportes` (decisión D10)

### 4.1. Creación

```sql
CREATE SCHEMA IF NOT EXISTS reportes;
GRANT USAGE ON SCHEMA reportes TO rol_reportes;
```

### 4.2. Objetos a instalar en `reportes`

Los objetos analíticos que no deben exponer datos personales (REQ-A09):

| Objeto propuesto | Tipo | Política de ubicación | Expone datos personales |
|---|---|---|---|
| `mv_facturacion_categoria_mes` | materializada | Ver nota abajo | No — agrega por categoría/mes |
| `v_resumen_ventas_rol_mes` | vista | Nueva en U5, en `reportes` | No — agrega por rol y mes, sin ID de usuario |

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

> **Nota sobre REFRESH CONCURRENTLY:** `admin_datos` puede ejecutar el REFRESH directamente
> como propietario del objeto. Si se delega a otro rol, requiere definición separada.

---

## 5. Rutinas SECURITY DEFINER (decisión D1)

Las tres rutinas nuevas tienen SECURITY DEFINER, `search_path` fijo y propietario NOLOGIN
propio. Ninguna duplica la lógica de los objetos canónicos.

### 5.1. `api_registrar_detalle_pedido` — interfaz de venta (D1)

**Propósito:** Único punto de entrada para `rol_app_escritura` hacia las operaciones de venta.
Invoca el procedimiento canónico sin duplicar su lógica. La función es SECURITY DEFINER con
propietario `rol_propietario_ventas`.

**Propietario:** `rol_propietario_ventas`
**Operación atómica:** CREATE + ALTER OWNER + REVOKE + GRANT en la misma transacción.

**Análisis de la cadena de ejecución — CORRECCIÓN CRÍTICA:**
En PostgreSQL, una rutina SECURITY INVOKER llamada desde una función SECURITY DEFINER
**hereda el usuario efectivo de la función invocadora**, no el OWNER de la rutina llamada.

```
CALL api_registrar_detalle_pedido(...)
  → corre como: rol_propietario_ventas   (SECURITY DEFINER)
    → CALL registrar_detalle_pedido(...) (SECURITY INVOKER por defecto)
       → corre como: rol_propietario_ventas  ← mismo usuario efectivo
```

**Consecuencia:** `rol_propietario_ventas` necesita todos los privilegios que
`registrar_detalle_pedido` requiere internamente para ejecutarse. Esto incluye:

| Objeto | Privilegio | Por qué lo necesita `registrar_detalle_pedido` |
|---|---|---|
| `pedido` | SELECT, UPDATE | `SELECT ... FOR UPDATE` para bloquear el pedido |
| `usuario` | SELECT | `SELECT ... FOR SHARE` para verificar baja lógica |
| `usuario` | UPDATE (columna) | `FOR SHARE` puede exigir UPDATE sobre ≥1 columna⁷ |
| `producto` | SELECT, UPDATE | `SELECT ... FOR UPDATE` para stock; `UPDATE stock` |
| `detalle_pedido` | INSERT, SELECT | INSERT de la línea + `PERFORM` de duplicado |
| SCHEMA public | USAGE | resolución de nombres |
| `registrar_detalle_pedido(bigint,bigint,integer)` | EXECUTE | CALL desde la función wrapper |

⁷ `FOR SHARE` en PostgreSQL 17 requiere SELECT (confirmado). El requerimiento adicional
de UPDATE sobre al menos una columna está documentado en la fuente. La columna propuesta
es `celular` (nullable, sin lógica de negocio). **Riesgo residual:** si `rol_propietario_ventas`
es comprometido, un atacante podría ejecutar `UPDATE usuario SET celular = ...`. Se acepta
como el costo mínimo del diseño; el equipo puede elegir otra columna igualmente inocua.

Los triggers AFTER (`fn_recalcular_total_*`) se disparan sobre `detalle_pedido` bajo el
OWNER de la **función trigger** (`admin_datos`), no bajo el usuario efectivo de la cadena.
Por eso `rol_propietario_ventas` **no necesita** EXECUTE sobre `calcular_total_pedido`
ni privilegios sobre las tablas que solo usan esos triggers.

> **Todos los privilegios de la tabla anterior están sujetos a verificación empírica en
> PG 17.11 antes de considerarlos definitivos.** Ver D11 §9.

**Contrato propuesto:**
```sql
BEGIN;

CREATE OR REPLACE FUNCTION public.api_registrar_detalle_pedido(
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
    -- Referencias calificadas con esquema para evitar resolución ambigua
    CALL public.registrar_detalle_pedido(p_pedido_id, p_producto_id, p_cantidad);
END;
$$;

-- Asignar propietario explícitamente: nunca debe quedar en manos de postgres u otro superusuario
ALTER FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    OWNER TO rol_propietario_ventas;

-- Revocar antes de que finalice la transacción, sin ventana de exposición
REVOKE ALL ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    TO rol_app_escritura;

COMMIT;
```

**Garantías:**
- `rol_app_escritura` no necesita EXECUTE sobre el procedimiento canónico del TPI.
- La lógica de validación, locks y descuento de stock permanece íntegra en el procedimiento
  canónico; esta función no la duplica.
- `search_path` fijo y referencias calificadas impiden la suplantación de esquema.
- El `ALTER FUNCTION ... OWNER TO` dentro de la misma transacción garantiza que en ningún
  instante la función quede bajo propiedad de `postgres` u otro superusuario.
- El REVOKE dentro de la misma transacción elimina la ventana en que PUBLIC tendría EXECUTE.

**Riesgo residual (D2):** El procedimiento canónico conserva `admin_datos` como OWNER.
`rol_propietario_ventas` recibe GRANT EXECUTE sobre él, sin transferir propiedad.

---

### 5.2. `fn_autenticar` — autenticación de usuarios

**Propósito:** Permite que `app_web` valide credenciales sin tener SELECT directo sobre
`usuario.contrasena`. Rechaza credenciales nulas, marcadores académicos y hashes inválidos
sin revelar la causa específica del fallo.

**Propietario:** `rol_propietario_credenciales`
**Operación atómica:** CREATE + ALTER OWNER + REVOKE + GRANT en la misma transacción.

**Contrato propuesto:**
```sql
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_autenticar(
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

    -- Recuperar el hash almacenado sin exponer su valor al caller
    SELECT u.contrasena INTO v_hash
    FROM public.usuario u
    WHERE u.mail = p_mail AND u.eliminado = FALSE;

    -- Si no existe el usuario: respuesta opaca, sin revelar la causa
    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Verificar formato válido de hash bcrypt antes de invocar crypt()
    -- Un hash bcrypt válido comienza con $2a$, $2b$ o $2y$ y tiene exactitud de 60 chars.
    -- SEED_NO_AUTH, hash_no_valido y cadenas cortas devolverán FOUND=false sin lanzar error.
    IF v_hash IS NULL
       OR length(v_hash) <> 60
       OR v_hash NOT LIKE '$2%$%' THEN
        -- Hash inválido o marcador académico: no autenticar, no revelar por qué
        RETURN;
    END IF;

    -- Invocar crypt() solo con un hash bien formado para evitar excepciones inesperadas
    RETURN QUERY
    SELECT u.id, u.rol
    FROM public.usuario u
    WHERE u.mail = p_mail
      AND u.eliminado = FALSE
      AND u.contrasena = public.crypt(p_contrasena, v_hash);
END;
$$;

-- Asignar propietario explícitamente: nunca debe quedar en manos de postgres u otro superusuario
ALTER FUNCTION public.fn_autenticar(TEXT, TEXT)
    OWNER TO rol_propietario_credenciales;

REVOKE ALL ON FUNCTION public.fn_autenticar(TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_autenticar(TEXT, TEXT) TO rol_app_autenticacion;

COMMIT;
```

**Garantías:**
- `app_web` (miembro de `rol_app_autenticacion`) nunca lee `usuario.contrasena` directamente.
- `search_path` fijo y referencias calificadas impiden la suplantación de esquema.
- Los marcadores académicos (`SEED_NO_AUTH`, `hash_no_valido`) y hashes con formato incorrecto
  devuelven cero filas sin lanzar excepciones desde `crypt()`.
- Los intentos fallidos retornan cero filas de forma opaca (mismo comportamiento para mail
  inexistente, contraseña incorrecta o hash inválido), sin revelar la causa del fallo.
- La contraseña no aparece en el log cuando el caller usa parámetros enlazados reales.

**Diferencia con intentos de login a PostgreSQL:**
Un intento de login fallido a la base (contraseña incorrecta de `app_web` al conectarse)
aparece en el log como `connection failure` con `log_connections = on`. Una autenticación
de negocio fallida a través de `fn_autenticar` devuelve cero filas; no es un error de conexión
ni aparece en el log como tal. El simulacro de la Parte C distingue estos dos eventos.

**Requiere `pgcrypto`:** `crypt()` pertenece a esa extensión. Debe instalarse antes:
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

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

CREATE OR REPLACE FUNCTION public.fn_resetear_password(
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

    -- Bloquear la fila primero (FOR UPDATE) para serializar la validación y la actualización
    -- Evita que un cambio concurrente de rol entre SELECT y UPDATE deje el estado inconsistente
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

-- Asignar propietario explícitamente: nunca debe quedar en manos de postgres u otro superusuario
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
- Las referencias a `public.crypt` y `public.gen_salt` son calificadas para evitar resolución
  ambigua si existiera otro esquema en `search_path`.
- La transacción pertenece al caller; si falla, la contraseña no cambia.

**Restricciones de D8 no aprobadas aún:**
Las políticas adicionales (longitud mínima, historial de contraseñas, notificación al usuario)
no están definidas. No se implementan hasta que el equipo las especifique.

---

## 6. `ALTER DEFAULT PRIVILEGES` (REQ-A04)

Solo se aplican `ALTER DEFAULT PRIVILEGES` donde hay beneficio claro y alcance acotado.
No se aplica sobre todas las tablas de `public` porque otorgaría INSERT/UPDATE automático
a nuevas tablas operativas que pueden requerir un control más restrictivo.

```sql
-- 1. Objetos analíticos futuros en reportes: accesibles por rol_reportes automáticamente
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA reportes
    GRANT SELECT ON TABLES TO rol_reportes;

-- 2. Funciones futuras creadas por admin_datos: revocar EXECUTE a PUBLIC por defecto
--    PostgreSQL 17 concede EXECUTE a PUBLIC sobre funciones por defecto; esta sentencia
--    revierte ese comportamiento para todas las funciones futuras de admin_datos.
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
```

**Qué no se incluye y por qué:**
- `ALTER DEFAULT PRIVILEGES ... GRANT SELECT ON TABLES TO rol_app_lectura IN SCHEMA public`:
  nuevas tablas en `public` pueden ser operativas o de staging; el acceso de lectura general
  no es automáticamente correcto para `rol_app_lectura`.
- `ALTER DEFAULT PRIVILEGES ... GRANT INSERT, UPDATE ON TABLES TO rol_app_escritura IN SCHEMA public`:
  prohibido por la corrección del prompt; INSERT/UPDATE sobre tablas futuras de `public`
  se otorgará caso por caso.

---

## 7. Estrategia de auditoría del simulacro (ajuste 2)

### 7.1. Qué registra la auditoría nativa (Parte B)

Parámetros a activar (sobre la instancia de desarrollo):
- `log_connections = on`
- `log_disconnections = on`
- `log_statement = 'mod'` (DDL y DML de modificación; no todas las consultas)

### 7.2. Qué registra `log_statement = mod` y qué no

`log_statement = 'mod'` registra sentencias DDL y DML de modificación (INSERT, UPDATE, DELETE,
TRUNCATE), pero **no registra SELECT**. Esto es relevante para el diseño del simulacro de la
Parte C:

| Evento del simulacro | `log_statement = mod` | Mecanismo complementario requerido |
|---|---|---|
| Intentos fallidos de login | Sí — vía `log_connections` | Ninguno |
| Login exitoso | Sí — vía `log_connections` | Ninguno |
| Lectura masiva `SELECT * FROM usuario` | **No registrado** | Ver §7.3 |
| `CALL api_registrar_detalle_pedido(...)` | Sí (la llamada aparece, no los parámetros) | Ninguno |
| Intento de GRANT a rol de bajo privilegio | Sí (DDL) | Ninguno |

La lectura masiva de `usuario` es el evento central del simulacro de la Parte C. Con `mod` solo
no queda rastro de ese SELECT en el log. Se necesita un mecanismo complementario.

### 7.3. Mecanismo complementario para el simulacro (Parte C)

Para que el simulacro permita reconstruir la secuencia completa incluyendo la lectura masiva,
se propone una de las siguientes opciones. El equipo elige una antes de implementar:

**Opción A — `log_statement = 'all'` temporalmente:**
Activar `all` solo durante la ejecución del simulacro, sobre la instancia de laboratorio
descartable. Riesgo: si el dataset contiene datos reales, el log captura las filas.
Mitigación obligatoria: el dataset del simulacro usa exclusivamente datos sintéticos.

**Opción B — función de auditoría en la misma sesión:**
Antes del SELECT masivo, el script de simulacro registra un evento en una tabla de auditoría
de sesión (creada para el simulacro). Esto no requiere cambiar `log_statement`.

**Opción C — `log_min_duration_statement = 0` sobre la conexión del simulacro:**
Activa el log de duración para todas las sentencias de esa conexión, incluyendo SELECT,
sin cambiar la configuración global. Require `ALTER ROLE rol_prueba_simulacro SET ...`.

La opción elegida debe documentarse en la bitácora (Parte E) antes de ejecutar el simulacro.

**Regla invariante:** En ninguna opción se registran contraseñas en texto plano.
El script de simulacro llama a `fn_autenticar` usando parámetros enlazados reales:

- **Con psql 16+ y el metacomando `\bind`:**
  ```sql
  SELECT * FROM fn_autenticar($1, $2) \bind 'usuario@test.com' 'contrasena_prueba' \g
  ```
- **Con cualquier driver de aplicación** (libpq, JDBC, psycopg2, etc.): usar parámetros
  posicionales (`$1`, `$2`) nunca concatenación de strings.

`\set` en psql realiza sustitución textual en el buffer de la consulta antes de enviarla —
no es enlace de parámetros y puede exponer el valor si el log captura la sentencia.
No usar `\set` con credenciales en los scripts de prueba del simulacro.

### 7.4. Verificación de permisos del archivo de log (ajuste 4)

**En Linux (sistema del entorno validado):**
El archivo de log de PostgreSQL se ubica típicamente en:
- `/var/lib/postgresql/<versión>/main/log/` (instalación APT)
- o en la ruta definida por `log_directory` en `postgresql.conf`

Los permisos esperados:
```
-rw------- 1 postgres postgres ... postgresql-<fecha>.log
```
Solo el usuario del sistema operativo `postgres` y los miembros del grupo `postgres` deben
poder leerlo. El archivo no debe ser legible por `world` (bit `o+r` debe estar ausente).

Verificación:
```bash
ls -la $(psql -U postgres -t -c "SHOW log_directory;")
# Confirmar owner=postgres, group=postgres, permisos 600 o 640 máximo
```

**En Windows:** El archivo de log se ubica en `%PGDATA%\log\`. Los permisos se verifican
con `icacls` o desde las propiedades de seguridad del archivo. Solo la cuenta de servicio
de PostgreSQL y los administradores del sistema deben tener acceso.

---

## 8. Criterios de aceptación (SEC-01 a SEC-20)

Cada criterio define una prueba positiva (P), negativa (N) y de regresión (R).
La numeración original se conserva. Los criterios cuyo significado cambió se marcan con ⟳.

### Existencia y atributos de roles

**SEC-01** — Los siete roles de grupo existen y tienen NOLOGIN.
- P: `\du` muestra los cuatro roles obligatorios y los tres adicionales (D6) sin atributo LOGIN.
- N: `psql -U rol_app_lectura` falla con error de autenticación.
- R: Reejecutar `roles.sql` en una base limpia; los siete roles existen con atributos correctos.

**SEC-02** — Ningún rol de grupo tiene SUPERUSER, CREATEDB ni CREATEROLE.
- P: `SELECT rolname, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname LIKE 'rol_%'` devuelve todo `false`.
- N: N/A.
- R: Verificar después de cualquier `ALTER ROLE`.

**SEC-03** ⟳ — `api_registrar_detalle_pedido` y `registrar_detalle_pedido` producen resultados equivalentes.
- P: Con los mismos parámetros de entrada válidos, invocar `api_registrar_detalle_pedido` y el procedimiento canónico directamente (como `admin_datos`) produce el mismo estado final en `detalle_pedido`, `producto.stock` y `pedido.total`.
- N: Con `SET ROLE rol_app_escritura`, `CALL registrar_detalle_pedido(...)` falla con 42501 (acceso denegado al procedimiento directo).
- R: Verificar la equivalencia después de cualquier cambio en `api_registrar_detalle_pedido` o en `registrar_detalle_pedido`.

**SEC-04** — `rol_reportes` tiene USAGE sobre `reportes` y SELECT sobre objetos en él.
- P: Con `SET ROLE rol_reportes`, `SELECT * FROM reportes.mv_facturacion_categoria_mes LIMIT 1` funciona.
- N: Con `SET ROLE rol_reportes`, `SELECT * FROM usuario` falla con 42501.
- R: Verificar después de cada instalación de un nuevo objeto en `reportes`.

### Membresías y accesos de login

**SEC-05** ⟳ — INSERT directo sobre `detalle_pedido` falla por permisos para `rol_app_escritura`.
- P: Con `SET ROLE rol_app_escritura`, `SELECT api_registrar_detalle_pedido(...)` funciona (datos válidos, transacción revertida).
- N: Con `SET ROLE rol_app_escritura`, `INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (...)` falla con 42501.
- R: Verificar con `information_schema.role_table_grants` que `rol_app_escritura` no tiene ningún privilegio sobre `detalle_pedido`.

**SEC-06** — `admin_datos` tiene LOGIN y no tiene SUPERUSER, CREATEDB ni CREATEROLE (D13).
- P: `SELECT rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = 'admin_datos'` devuelve todo `false`.
- N: N/A.
- R: Verificar después de cualquier `ALTER ROLE admin_datos`.

**SEC-07** — `app_web` es miembro exactamente de `rol_app_lectura`, `rol_app_escritura` y `rol_app_autenticacion`. No es miembro de `rol_soporte` ni `rol_reportes`.
- P: `SELECT roleid::regrole FROM pg_auth_members WHERE member = 'app_web'::regrole` devuelve exactamente los tres roles esperados.
- N: `rol_soporte` y `rol_reportes` no aparecen en esa consulta para `app_web`.
- R: Verificar después de cualquier GRANT/REVOKE de membresía.

### GRANT sobre tablas y vistas

**SEC-08** — `rol_app_escritura` tiene INSERT (columnas restringidas) y SELECT sobre `pedido`. No tiene ningún privilegio sobre `detalle_pedido`.
- P: Con `SET ROLE rol_app_escritura`, `INSERT INTO pedido (fecha, forma_pago, usuario_id) VALUES (CURRENT_DATE, 'EFECTIVO', 1)` funciona (transacción revertida).
- N: Con `SET ROLE rol_app_escritura`, `UPDATE pedido SET estado = 'CANCELADO' WHERE id = 1` falla con 42501. `SELECT * FROM detalle_pedido` falla con 42501.
- R: Verificar con `information_schema.role_table_grants` y `information_schema.column_privileges`.

**SEC-09** — `rol_app_escritura` no tiene DELETE ni TRUNCATE sobre ninguna tabla de dominio.
- P: `information_schema.role_table_grants` no devuelve DELETE ni TRUNCATE para `rol_app_escritura`.
- N: Con `SET ROLE rol_app_escritura`, `DELETE FROM pedido WHERE id = -1` falla con 42501.
- R: Verificar después de cualquier GRANT sobre tablas de dominio.

**SEC-10** ⟳ — El intento de escalamiento de privilegios del simulacro falla.
- P: El diseño de roles de A es correcto si el intento de otorgar membresía en `admin_datos` a un rol de bajo privilegio produce error de permisos en la Parte C.
- N: Si ese GRANT no falla, es un defecto de seguridad que debe corregirse antes de continuar con el TP.
- R: Verificar que ningún rol de aplicación tiene CREATEROLE (único atributo que habilitaría crear ese GRANT).

### GRANT sobre rutinas (EXECUTE)

**SEC-11** ⟳ — Verificación de privilegios futuros en `reportes`: `ALTER DEFAULT PRIVILEGES` produce el efecto esperado.
- P: Crear un objeto de prueba como `admin_datos` en el esquema `reportes` y verificar que `rol_reportes` hereda SELECT automáticamente; luego eliminar el objeto de prueba.
- N: Crear un objeto de prueba como `admin_datos` en `public` y verificar que `rol_app_escritura` NO hereda INSERT automáticamente (la corrección eliminó ese ALTER DEFAULT PRIVILEGES).
- R: Verificar `information_schema.default_privileges` después de aplicar `roles.sql`.

> **Verificación de proacl NULL (D3):** Antes de REVOKE, confirmar `pg_proc.proacl` para las siete
> rutinas del TPI. Un valor NULL implica que PUBLIC tiene EXECUTE implícito. Ejecutar la prueba
> negativa con el rol efímero (D12) para verificar el efecto real del REVOKE, no solo el ACL.

**SEC-12** ⟳ — `ALTER DEFAULT PRIVILEGES` revoca EXECUTE a PUBLIC sobre funciones futuras de `admin_datos`.
- P: Crear una función de prueba como `admin_datos` y verificar que un rol efímero sin membresías no puede ejecutarla (42501).
- N: Antes de aplicar el `ALTER DEFAULT PRIVILEGES`, el mismo rol efímero sí puede ejecutar funciones recién creadas.
- R: Verificar `information_schema.default_privileges` para confirmar que la sentencia sigue activa.

**SEC-13** — `rol_app_escritura` tiene EXECUTE sobre `api_registrar_detalle_pedido`. No tiene EXECUTE sobre `registrar_detalle_pedido` ni `calcular_total_pedido`.
- P: Con `SET ROLE app_web`, `SELECT api_registrar_detalle_pedido(...)` funciona con datos válidos de prueba (transacción revertida).
- N: Con `SET ROLE app_web`, `CALL registrar_detalle_pedido(...)` falla con 42501. `SELECT calcular_total_pedido(1)` falla con 42501.
- R: Verificar con `\df+` después de cualquier cambio en las rutinas.

### Permisos por columna, rutinas de soporte y ALTER DEFAULT PRIVILEGES

**SEC-14** — `rol_app_escritura` puede INSERT en `pedido` solo sobre las columnas autorizadas (`fecha`, `forma_pago`, `usuario_id`). No puede INSERT/UPDATE sobre otras columnas de `pedido`.
- P: Con `SET ROLE rol_app_escritura`, `INSERT INTO pedido (fecha, forma_pago, usuario_id) VALUES (CURRENT_DATE, 'EFECTIVO', 1)` funciona (transacción revertida).
- N: Con `SET ROLE rol_app_escritura`, `INSERT INTO pedido (fecha, forma_pago, usuario_id, total) VALUES (...)` falla con 42501.
- R: Verificar `information_schema.column_privileges` para `rol_app_escritura` sobre `pedido`.

**SEC-15** ⟳ — Las siete rutinas y cinco triggers canónicos del TPI siguen funcionando después de aplicar todos los REVOKE/GRANT de U5. Los propietarios originales no cambiaron.
- P: Los cinco triggers se disparan en INSERT/UPDATE/DELETE sobre `detalle_pedido` cuando lo ejecuta `admin_datos`. `calcular_total_pedido` devuelve el total correcto. Las cuatro vistas de U3 devuelven filas.
- N: `SELECT proname, rolname AS owner FROM pg_proc JOIN pg_roles ON pg_roles.oid = pg_proc.proowner WHERE proname IN ('calcular_total_pedido','fn_set_subtotal','fn_validar_detalle_vigente','registrar_detalle_pedido','fn_recalcular_total_insert','fn_recalcular_total_update','fn_recalcular_total_delete')` confirma que todos tienen `admin_datos` como owner, no `rol_propietario_ventas`.
- R: Ejecutar esta batería después de `roles.sql` y después de cualquier REVOKE adicional.

### Esquema `reportes` y privacidad

**SEC-16** ⟳ — El simulacro de la Parte C no registra contraseñas en logs. El log distingue intentos de login a PostgreSQL de autenticaciones vía `fn_autenticar`.
- P: Ejecutar el script del simulacro con parámetros enlazados reales (`\bind` en psql 16+ o driver de aplicación con `$1/$2`). Revisar el log resultante: no debe contener la cadena de la contraseña de prueba ni ningún hash de contraseña.
- N: N/A — no se ejecuta intencionalmente una prueba que filtre contraseñas al log.
- R: Revisar el log completo antes de entregarlo a la IA en la Parte C para confirmar la ausencia de credenciales. El mecanismo de auditoría elegido (§7.3) se documenta en BITACORA.md.

**SEC-17** ⟳ — Las tres funciones SECURITY DEFINER tienen `prosecdef = true`, `search_path` fijo y referencias calificadas.
- P: `SELECT proname, prosecdef, proconfig FROM pg_proc WHERE proname IN ('api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password')` muestra `prosecdef = true` y `proconfig` con `search_path=public,pg_temp` para las tres.
- N: Con `SET ROLE app_web`, `SELECT contrasena FROM public.usuario LIMIT 1` falla con 42501.
- R: Verificar `prosecdef` y `proowner` después de cualquier `CREATE OR REPLACE` de esas funciones. Confirmar que el OWNER no cambió.

### Identidades efímeras

**SEC-18** ⟳ — `rol_soporte` tiene EXECUTE sobre `fn_resetear_password` exclusivamente; no puede resetear cuentas ADMIN.
- P: Con `SET ROLE rol_soporte`, `SELECT fn_resetear_password(<id_usuario_no_admin>, 'nueva_valida')` funciona (transacción revertida).
- N: Con `SET ROLE rol_soporte`, `SELECT fn_resetear_password(<id_usuario_admin>, 'nueva')` falla con 42501. `SELECT calcular_total_pedido(1)` falla con 42501.
- R: Verificar con `\df+` que el OWNER es `rol_propietario_credenciales`.

**SEC-19** — Las pruebas negativas se ejecutan con un rol efímero sin membresías.
- P: El rol efímero puede conectarse a la base.
- N: El rol efímero no puede ejecutar ninguna rutina del TPI ni acceder a tablas de dominio.
- R: Al finalizar las pruebas, el rol efímero fue eliminado: `SELECT rolname FROM pg_roles WHERE rolname = 'rol_prueba_efimero'` devuelve cero filas.

### Ausencia de SUPERUSER

**SEC-20** ⟳ — Ningún rol creado por `roles.sql` tiene SUPERUSER. Todas las identidades efímeras de prueba fueron eliminadas al finalizar las verificaciones.
- P: `SELECT rolname FROM pg_roles WHERE rolsuper = TRUE` no incluye ninguno de los nueve roles del esquema de U5.
- N: N/A.
- R: Verificar como último paso del script de permisos. Verificar que `SELECT rolname FROM pg_roles WHERE rolname LIKE '%efimero%' OR rolname LIKE '%temp%' OR rolname LIKE '%prueba%'` devuelve cero filas después de las pruebas.

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
**Estado: incorporado como propuesta en el design; aprobación del equipo requerida antes de implementar.**

### D8 — Restricciones sobre `fn_resetear_password`

**Restricciones aprobadas (incorporadas en §5.3):**
- La contraseña nueva no puede ser nula ni vacía.
- `rol_soporte` no puede resetear contraseñas de cuentas con `usuario.rol = 'ADMIN'`.

**Restricciones pendientes de definición:**
- Longitud mínima de la contraseña nueva.
- Historial de contraseñas (no reutilizar las N anteriores).
- Notificación al usuario tras el reset.
- Otras políticas de seguridad de credenciales.

**Estado: restricciones aprobadas incorporadas; las demás pendientes de definición por el equipo.**

### D9 — Revocar CONNECT y TEMP a PUBLIC

**Propuesta:** `REVOKE CONNECT ON DATABASE <nombre_base> FROM PUBLIC` y
`REVOKE TEMP ON DATABASE <nombre_base> FROM PUBLIC`. Esto impide que cualquier rol sin
privilegio explícito se conecte a la base o cree tablas temporales.

**Riesgo:** Afecta toda la instancia de la base, no solo el esquema de Food Store. Si existen
otras aplicaciones o usuarios en la misma base que no tienen CONNECT otorgado explícitamente,
dejarían de poder conectarse.

**Condición:** Requiere autorización explícita sobre la instancia aislada de laboratorio
de U5, donde se confirme que no hay otras conexiones que se rompan.
**Estado: pendiente de autorización — no aprobada.**

### D11 — Privilegio para `SELECT ... FOR SHARE` sobre `usuario` desde `registrar_detalle_pedido`

**Contexto:** El procedimiento canónico `registrar_detalle_pedido` ejecuta:
```sql
SELECT eliminado INTO v_usuario_eliminado
FROM usuario
WHERE id = v_usuario_id
FOR SHARE;
```
Si `rol_propietario_ventas` es el OWNER del procedimiento (para que `api_registrar_detalle_pedido`
corra como SECURITY DEFINER con ese rol), entonces `rol_propietario_ventas` necesita los
privilegios que ese SELECT FOR SHARE requiere sobre `usuario`.

**Comportamiento esperado en PostgreSQL 17:**
`SELECT ... FOR SHARE` requiere SELECT sobre la tabla (confirmado por la documentación).
En algunas versiones, el motor también exige UPDATE sobre al menos una columna al tomar
locks de fila con `FOR SHARE`. Este requisito adicional está documentado pero necesita
verificación empírica en PG 17.11.

**Alternativa propuesta:**
Otorgar `GRANT UPDATE (celular) ON usuario TO rol_propietario_ventas`. La columna `celular`
es opcional (nullable) y no participa en ninguna regla de negocio de las ventas. Usarla
como columna de UPDATE nominal permite satisfacer el requerimiento del motor sin exponer
columnas funcionales como `contrasena`, `rol` o `eliminado`.

**Riesgo residual:** Aunque `celular` no tiene lógica de negocio, el privilegio UPDATE
sobre ella existe formalmente. Un rol que comprometa a `rol_propietario_ventas` tendría
UPDATE sobre `celular`. Se documenta como riesgo aceptado si el equipo aprueba la alternativa.

**Estado: alternativa propuesta — no aprobada hasta prueba real en PG 17.11.**
La prueba de D11 es independiente de SEC-11 (que verifica ALTER DEFAULT PRIVILEGES futuros
en `reportes`). El resultado de D11 se documenta como evidencia separada en `docs/` y
actualiza la matriz §3.1 cuando esté disponible.

---

## 10. Pruebas de regresión globales

Estas pruebas verifican que los cambios de U5 no rompieron el comportamiento de las unidades
anteriores:

| Prueba | Qué verifica |
|---|---|
| REG-01 | Las siete rutinas y cinco triggers del TPI responden correctamente después de aplicar los REVOKE/GRANT de D3 |
| REG-02 | `api_registrar_detalle_pedido` funciona cuando la invoca un rol miembro de `rol_app_escritura`; `registrar_detalle_pedido` sigue funcionando cuando lo invoca `admin_datos` directamente |
| REG-03 | Los triggers de subtotal y total siguen disparándose correctamente (no dependen de privilegios de usuario) |
| REG-04 | Las cuatro vistas de U3 siguen siendo consultables con `admin_datos` |
| REG-05 | Los propietarios canónicos no cambiaron: las siete rutinas del TPI tienen `admin_datos` como OWNER; `api_registrar_detalle_pedido` tiene `rol_propietario_ventas`; `fn_autenticar` y `fn_resetear_password` tienen `rol_propietario_credenciales` |

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

**Paso previo obligatorio — inventario de propietarios:**
Antes de aplicar cualquier REVOKE o GRANT sobre las rutinas del TPI, ejecutar en la base
de laboratorio de U5:
```sql
SELECT proname, rolname AS owner
FROM pg_proc
JOIN pg_roles ON pg_roles.oid = pg_proc.proowner
WHERE pronamespace = 'public'::regnamespace
  AND proname IN (
    'registrar_detalle_pedido','calcular_total_pedido',
    'fn_set_subtotal','fn_validar_detalle_vigente',
    'fn_recalcular_total_insert','fn_recalcular_total_update','fn_recalcular_total_delete'
  );
```
Este resultado documenta quién es el OWNER real de cada rutina canónica. Si el OWNER no es
`admin_datos`, D2 no puede aplicarse sin intervención humana adicional. No asumir el resultado:
verificar antes de proceder. Conservar la salida como evidencia en `docs/`.

1. **Aprobar D6** — confirmar que el equipo acepta los tres roles adicionales y sus contratos.
2. **Resolver D11 (prueba de cadena SECURITY DEFINER → INVOKER)** — ejecutar en PG 17.11
   y confirmar si `rol_propietario_ventas` necesita o no privilegios sobre tablas cuando
   `registrar_detalle_pedido` es invocado desde `api_registrar_detalle_pedido`. Esta prueba
   es independiente de SEC-11 (que verifica ALTER DEFAULT PRIVILEGES).
3. **Aprobar D8 completa** — definir las políticas adicionales de contraseña no especificadas.
4. **Autorizar D9** — confirmar instancia aislada antes de REVOKE de CONNECT/TEMP a PUBLIC.
5. **Definir D4** — especificar qué rol puede cambiar `pedido.estado` y bajo qué condición.
6. **Verificar `pgcrypto`** — confirmar instalación en la base de U5.
7. **Elegir mecanismo complementario de auditoría (§7.3)** — Opción A, B o C.
8. **Recibir revisión humana de este design.md** antes de escribir ningún SQL de implementación.

**Contradicción pendiente de resolución humana (D11):**
Si la prueba de la cadena SECURITY DEFINER → INVOKER confirma que `rol_propietario_ventas`
necesita privilegios sobre tablas, la columna de esa fila en §3.1 se actualiza con esos
privilegios y se decide si `UPDATE(celular)` es aceptable como riesgo residual.
Si confirma que no los necesita, la columna queda vacía y el diseño es más limpio.
