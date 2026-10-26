# Requirements — Unidad 5: Administración y Seguridad de Food Store

**Trabajo Práctico — Unidad 5 / Semana 9**
Base de Datos II — Tecnicatura Universitaria en Programación — UTN
**Integrantes:** Avalos Pablo, Blangetti Sofia, Suarez Ismael
**Motor objetivo:** PostgreSQL 17.11
> Ningún objeto de U5 ha sido ejecutado en la base de laboratorio todavía.
> Los contratos de este documento son propuestas pendientes de prueba.

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
Unidades 1 a 4 y opera con un único rol dueño de los objetos. El esquema canónico comprende:

- **Cinco tablas:** `categoria`, `usuario`, `producto`, `pedido`, `detalle_pedido`
- **Tres ENUM:** `forma_pago`, `rol`, `estado_pedido`
- **Siete rutinas** y **cinco triggers** del TPI (ver `objetos_programables.sql`)
- **Cuatro vistas convencionales** y **una materializada** (Unidad 3, instaladas en base separada)
- Un campo `usuario.contrasena VARCHAR(255)` que almacena el hash de la credencial
- Un campo `usuario.rol ENUM('ADMIN','USUARIO')` de dominio de negocio (distinto de los roles del motor)

Todo el trabajo de esta unidad se ejecuta sobre una copia de laboratorio explícitamente autorizada.
No se modifica el esquema canónico ni los objetos programables existentes.

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
| `rol_app_escritura` | grupo (NOLOGIN) | Flujo operativo de compra; habilita la creación de pedidos (INSERT con columnas restringidas) y el EXECUTE sobre la única interfaz de venta autorizada, porque el backend necesita registrar órdenes sin poder leer datos de detalle arbitrarios ni modificar stock o totales directamente |
| `rol_soporte` | grupo (NOLOGIN) | Atención al cliente; habilita lectura de identidad pública y resumen de pedidos porque soporte no debe ver contraseñas ni modificar datos de negocio |
| `rol_reportes` | grupo (NOLOGIN) | Panel gerencial; habilita solo SELECT sobre objetos analíticos agregados porque reportes no debe modificar datos ni acceder a información individual identificable |

**Roles de grupo adicionales propuestos (D6):**

| Rol | Tipo | Justificación |
|---|---|---|
| `rol_app_autenticacion` | grupo (NOLOGIN) | Agrupa el EXECUTE sobre `fn_autenticar` para separar la capacidad de autenticarse de la capacidad de leer catálogo o escribir pedidos; `app_web` necesita ambas y se las otorga como membresías independientes |
| `rol_propietario_ventas` | grupo (NOLOGIN) | Propietario lógico únicamente de `api_registrar_detalle_pedido`; no tiene miembros. El propietario de las siete rutinas canónicas del TPI no cambia (D2) |
| `rol_propietario_credenciales` | grupo (NOLOGIN) | Es el propietario lógico de `fn_autenticar` y `fn_resetear_password`; no tiene miembros — análogo a `rol_propietario_ventas` para las rutinas de credenciales |

Los roles propietarios NOLOGIN son NOINHERIT y no tienen miembros. Su único propósito es ser el
OWNER de las rutinas SECURITY DEFINER para que esas funciones operen con el privilegio mínimo
necesario, sin depender de los privilegios de `admin_datos`.

**Roles de login obligatorios:**

| Rol | Tipo | Membresías |
|---|---|---|
| `app_web` | login | `rol_app_lectura`, `rol_app_escritura`, `rol_app_autenticacion` |
| `admin_datos` | login | Ninguna de los grupos de aplicación (D13) |

`admin_datos` no hereda los grupos de la aplicación; su acceso es el de dueño del esquema,
no el de un consumidor de la API de negocio.

**Verificación de soporte y reportes (D12):**
`rol_soporte` y `rol_reportes` se verifican con identidades efímeras de prueba durante la
implementación de la Parte A. No se crean cuentas de login permanentes para ellos.

### REQ-A02 — Principio de mínimo privilegio

Cada rol recibe exactamente los privilegios necesarios para cumplir su función, sin permisos
adicionales. En particular:

- `rol_app_escritura` no recibe SELECT, INSERT ni UPDATE en bloque sobre `detalle_pedido`.
  El acceso a esa tabla se canaliza exclusivamente a través de `api_registrar_detalle_pedido`.
- `rol_app_escritura` no recibe UPDATE sobre `pedido.total`, `pedido.estado`, ni ningún campo
  que no sea necesario para la creación de pedidos nuevos.
- Ningún rol de aplicación puede modificar directamente `producto.stock`.
- `app_web` no recibe DELETE ni TRUNCATE sobre ninguna tabla de dominio.
- `admin_datos` no recibe SUPERUSER (decisión D13).
- Ningún rol de aplicación recibe SUPERUSER, CREATEDB ni CREATEROLE.
- Los roles de grupo no tienen atributo LOGIN.
- La lectura del catálogo se limita a vistas que filtran registros eliminados (`v_productos_vigentes`),
  no a las tablas base directamente.

### REQ-A03 — Permiso a nivel de columna

El script `roles.sql` debe incluir al menos un caso de permiso a nivel de columna, como práctica
explícita requerida por la consigna.

La forma elegida es `INSERT` restringido a las columnas necesarias de `pedido` para
`rol_app_escritura`: `fecha`, `forma_pago`, `usuario_id`. Esto demuestra el mecanismo de
permiso por columna sin otorgar UPDATE sobre `estado`, `total` ni `eliminado`.

El permiso redundante de `rol_soporte` sobre columnas de `usuario` (SELECT de id, nombre, etc.)
se elimina de este diseño: `v_usuarios_publico` ya cumple esa función de forma más segura y
mantenible, y duplicar el acceso vía columnas aumentaría la superficie de ataque sin beneficio.
Si la cátedra exige demostrar permisos por columna en `usuario`, se documenta pero no se otorga
en `roles.sql` operativo.

### REQ-A04 — Permisos por defecto (ALTER DEFAULT PRIVILEGES)

El script debe incluir sentencias `ALTER DEFAULT PRIVILEGES` acotadas a los contextos donde
son necesarias:

1. **Esquema `reportes`**: los objetos analíticos futuros creados por `admin_datos` en `reportes`
   otorgan SELECT automáticamente a `rol_reportes`.
2. **EXECUTE global**: las funciones futuras creadas por `admin_datos` en cualquier esquema
   revocan EXECUTE a PUBLIC por defecto, como defensa en profundidad.

No se aplica `ALTER DEFAULT PRIVILEGES` sobre todas las tablas de `public`: ese alcance es
demasiado amplio y otorgaría permisos de INSERT/UPDATE a nuevas tablas operativas que pueden
requerir un control diferente.

### REQ-A05 — USAGE sobre esquema

Todo rol que acceda a objetos del esquema `public` debe recibir `GRANT USAGE ON SCHEMA public`.
Sin este privilegio, ningún otro permiso sobre los objetos del esquema es efectivo.

### REQ-A06 — Verificación de privilegios

La salida de `\du` y de una consulta sobre `information_schema.role_table_grants` debe confirmar
que cada rol tiene exactamente los privilegios previstos en esta especificación: ni más, ni menos.
La verificación se adjunta como evidencia en la entrega.

### REQ-A07 — Restricción de EXECUTE sobre rutinas (decisión D3)

La decisión D3 aplica específicamente a `registrar_detalle_pedido` y `calcular_total_pedido`:
se revoca EXECUTE a PUBLIC sobre ambas y se otorga explícitamente solo a los roles autorizados.

Las cinco funciones trigger (`fn_set_subtotal`, `fn_validar_detalle_vigente`,
`fn_recalcular_total_insert`, `fn_recalcular_total_update`, `fn_recalcular_total_delete`)
son invocadas exclusivamente por sus triggers; ningún rol de aplicación necesita ni debe tener
EXECUTE sobre ellas. Se revoca PUBLIC como buena práctica, pero no se requiere GRANT de usuario.

La verificación de qué tiene PUBLIC sobre las rutinas se realiza mediante ACL
(`\df+` en psql o consultando `pg_proc.proacl`). El comportamiento de `proacl NULL`
varía entre versiones de PostgreSQL; se prueba con roles reales (D12) antes de
considerar el requisito cumplido.

### REQ-A08 — Esquema dedicado `reportes`

Se crea un esquema dedicado `reportes` para los objetos analíticos (decisión D10).
`rol_reportes` recibe USAGE sobre ese esquema y SELECT sobre los objetos analíticos allí instalados.
Los demás roles no reciben acceso a `reportes` salvo indicación explícita.

### REQ-A09 — Protección de datos personales en objetos analíticos

Los nuevos objetos analíticos instalados en el esquema `reportes` no exponen:
- Datos de identificación directa: `nombre`, `apellido`, `mail`, `celular`, `contrasena`
- Identificadores que permitan reidentificación indirecta de usuarios individuales en conjuntos pequeños

Los objetos analíticos operan sobre agregaciones (totales, conteos, promedios por categoría/mes)
o sobre versiones anonimizadas de los datos. Este requisito conecta con la Parte D del TP.

### REQ-A10 — Interfaces controladas SECURITY DEFINER (decisión D1)

El diseño contempla tres rutinas nuevas con SECURITY DEFINER, cada una con un propietario
NOLOGIN distinto y `search_path` fijo. Ninguna duplica la lógica de negocio de los objetos
canónicos.

**`api_registrar_detalle_pedido` (D1 — interfaz de venta):**
Wrapper SECURITY DEFINER que invoca el procedimiento canónico `registrar_detalle_pedido`.
Es la única ruta autorizada para `rol_app_escritura` hacia las operaciones de venta.
El propietario es `rol_propietario_ventas` (no el propietario del procedimiento canónico, que
conserva su propietario original conforme a D2).

**`fn_autenticar` (nueva — autenticación):**
Valida credenciales mediante hash (`pgcrypto`) sin exponer `usuario.contrasena` a `app_web`.
Rechaza parámetros nulos, marcadores académicos y hashes inválidos sin revelar información
sensible. El propietario es `rol_propietario_credenciales`. Solo `rol_app_autenticacion` tiene EXECUTE.

**`fn_resetear_password` (nueva — reset de soporte):**
Permite a `rol_soporte` forzar un cambio de contraseña sin UPDATE directo sobre `usuario`.
Bloquea la fila con FOR UPDATE entre la validación del rol y la actualización para evitar
condiciones de carrera concurrentes. El propietario es `rol_propietario_credenciales`.
Solo `rol_soporte` tiene EXECUTE.

Las tres rutinas se crean con:
- `SECURITY DEFINER`
- `SET search_path = public, pg_temp`
- `REVOKE ALL ... FROM PUBLIC` antes del GRANT al rol específico

El permiso PUBLIC de ejecución se revoca en todos los casos.

### REQ-A11 — Identidades temporales para pruebas

Para verificar permisos se crean roles temporales de prueba con LOGIN y sin privilegios adicionales
(decisión D12). Estos roles se eliminan al finalizar las pruebas. No se usan credenciales de
producción para los ensayos, y no se registran contraseñas reales en la bitácora ni en el código.

### REQ-A12 — Compatibilidad con objetos existentes

El script `roles.sql` no modifica:
- Las cinco tablas canónicas del schema raíz
- Las siete rutinas ni los cinco triggers del TPI
- Los objetos de U3 (índices, vistas, materializada) instalados en su base separada

Los GRANT sobre rutinas existentes amplían el control de acceso sin alterar las definiciones.

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

La verificación de permisos de lectura del archivo de log se documenta según el sistema operativo
(Linux o Windows) donde se ejecute la prueba (ajuste 4 de la especificación).

### Dependencia A → C (Simulacro de incidente)

El esquema de permisos diseñado en A es el que el simulacro de C pone a prueba. En particular:
- El intento de otorgar membresía en `admin_datos` a un rol de bajo privilegio debe **fallar**
  si el diseño de A es correcto.
- Si no falla, se trata de un hallazgo de defecto de seguridad que debe corregirse antes de continuar.
- Los datos del log del simulacro se anonimizan antes de entregarse a la IA (mails, nombres,
  identificadores se reemplazan por tokens sintéticos).

### Dependencia A → D (Protección de datos)

La tabla `usuario_anon` construida en D reproduce la estructura de `usuario` con datos sintéticos
deterministas. Los objetos analíticos en el esquema `reportes` pueden operar sobre esta tabla
o sobre agregaciones que no reidentifiquen individuos (requisito REQ-A09).

---

## Criterios de aceptación generales (SEC-01 a SEC-20)

Los criterios SEC numerados se conservan y revisarán en el design.md para alinearlos con los
requisitos de esta especificación. Aquí se listan las categorías:

| Rango | Categoría |
|---|---|
| SEC-01 a SEC-04 | Existencia y atributos de los roles de grupo |
| SEC-05 a SEC-07 | Existencia y membresías de los roles de login |
| SEC-08 a SEC-10 | GRANT sobre tablas y vistas |
| SEC-11 a SEC-13 | GRANT sobre rutinas (EXECUTE) |
| SEC-14 a SEC-15 | Permisos por columna y ALTER DEFAULT PRIVILEGES |
| SEC-16 a SEC-17 | Esquema `reportes` y sus permisos |
| SEC-18 | SECURITY DEFINER con search_path fijo |
| SEC-19 | Verificación con rol temporal (prueba negativa) |
| SEC-20 | Ausencia de SUPERUSER en roles de aplicación |

Los criterios detallados —con su prueba positiva, negativa y de regresión— se definen en design.md.

---

## Decisiones aceptadas (referencia)

| ID | Decisión | Estado en este documento |
|---|---|---|
| D1 | `api_registrar_detalle_pedido` como interfaz SECURITY DEFINER que invoca el procedimiento canónico | Aplicada en REQ-A10 |
| D2 | Conservar propietarios y definiciones de los siete objetos canónicos del TPI; `rol_propietario_ventas` es OWNER solo de `api_registrar_detalle_pedido` | Aplicada en REQ-A10 y REQ-A12 |
| D3 | Revocar EXECUTE a PUBLIC sobre `registrar_detalle_pedido` y `calcular_total_pedido`; GRANT explícito solo a los roles que los necesitan; REVOKE de PUBLIC sobre funciones trigger | Aplicada en REQ-A07 |
| D4 | No otorgar UPDATE sobre `pedido.estado` hasta definir su caso de uso | Documentada como recomendación pendiente en design.md §9 |
| D6 | Tres roles adicionales: `rol_app_autenticacion`, `rol_propietario_ventas` (OWNER de `api_registrar_detalle_pedido`), `rol_propietario_credenciales` | Aplicada en REQ-A01 |
| D8 | Contraseña nueva no nula ni vacía; soporte no puede resetear cuentas ADMIN; otras políticas pendientes de definición | Documentada como recomendación en design.md §9 |
| D9 | Propuesta de revocar CONNECT y TEMP a PUBLIC; sujeta a autorización sobre la instancia aislada | Documentada como pendiente de aprobación en design.md §9 |
| D10 | Crear esquema dedicado `reportes` | Aplicada en REQ-A08 |
| D11 | Verificar privilegios requeridos para `SELECT ... FOR SHARE` sobre `usuario` desde `registrar_detalle_pedido`; alternativa propuesta: `UPDATE(celular)` para `rol_propietario_ventas`; requiere prueba empírica en PG 17.11 | Documentada como pendiente de prueba en design.md §9 |
| D12 | Identidades efímeras para verificar accesos de soporte y reportes; sin cuentas permanentes adicionales | Aplicada en REQ-A01 y REQ-A11 |
| D13 | `admin_datos` sin CREATEROLE ni CREATEDB | Aplicada en REQ-A02 |

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
