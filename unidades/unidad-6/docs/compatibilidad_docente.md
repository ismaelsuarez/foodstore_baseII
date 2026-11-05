# Compatibilidad docente — Unidad 6

Análisis consolidado de compatibilidad entre la consigna oficial (PDF), los scripts
del docente (ZIP `scripts_mantenimiento.zip`) y el esquema vigente de Food Store
(`schema.sql`). No se declaran erratas confirmadas, compatibilidad demostrada ni
aprobaciones docentes que no consten en las fuentes.

---

## Referencias por fuente

### PDF (consigna oficial)

Documento: `TPUnidad_6_Mantenimiento_FoodStore.pdf` — «Trabajo Práctico —
Unidad 6: Mantenimiento, respaldo y recuperación». Material de la cátedra,
actividad de laboratorio de la Semana 10, no incorporado al repositorio.
Identificar el documento no resuelve las decisiones docentes pendientes.

| Aspecto | Referencia del PDF |
|---|---|
| Base principal | `foodstore` |
| Base de restauración | `foodstore_restore_test` |
| Tabla de usuarios en validación | `cliente` |
| Flags de restauración sugeridas | `--no-owner --no-privileges` |

### ZIP (scripts del docente)

| Aspecto | Referencia del ZIP |
|---|---|
| Base principal | `food_store` (en `backup_food_store.sh`, `backup_food_store.ps1`) |
| Base de restauración | `food_store_prueba_restauracion` (en `prueba_restauracion.sh`) |
| Tabla de usuarios | `usuario` (en `prueba_restauracion.sh`) |
| Flags de restauración usadas | `--exit-on-error -j 4` con TOC filtrado; sin `--no-owner` ni `--no-privileges` |
| `dropdb` automático | `dropdb --if-exists food_store_prueba_restauracion` |

### Esquema vigente (schema.sql)

| Aspecto | Referencia del schema |
|---|---|
| Tabla de usuarios | `usuario` (no existe `cliente`) |
| Otras tablas | `categoria`, `producto`, `pedido`, `detalle_pedido` |
| Función de total | `calcular_total_pedido(bigint)` — SECURITY INVOKER, sin `SECURITY` clause |

---

## Decisiones que requieren precisar la comprobación docente

### CD-1 — Nombre de la base

El PDF dice `foodstore`; los scripts del ZIP dicen `food_store`. No se pueden modificar
los scripts originales. Si se usa `foodstore`, los scripts del docente fallan; si se usa
`food_store`, contradice el PDF. **Pendiente: confirmar con el docente.**

**Decisión del equipo (2026-11-05):** se usan los nombres del PDF, `foodstore` y
`foodstore_restore_test`. Es una decisión del equipo, no una confirmación docente,
y los scripts del ZIP siguen esperando `food_store`.

### CD-2 — Tabla en la validación

El PDF usa `cliente` (no existe en el schema). El script `prueba_restauracion.sh` del ZIP
usa `usuario` (correcto para el schema). **Pendiente: confirmar si la comprobación docente
usa el PDF literal o el script del ZIP.**

**Decisión del equipo (2026-11-05):** se usa `usuario`, la tabla del schema
vigente; no se crean `cliente` ni aliases. La diferencia con el PDF se mantiene
visible.

### CD-3 — `00_roles_unidad5_base.sql` del ZIP

El script es una simplificación de U5 que otorga `SELECT, INSERT, UPDATE ON pedido,
detalle_pedido` a `rol_app_escritura` y referencia `v_categorias_vigentes` (inexistente).
Una base nueva dentro del mismo clúster no aísla roles: los roles son objetos del
clúster, no de una base individual. Si se ejecuta en una base nueva del mismo clúster
que ya tiene los roles reales de U5, `CREATE ROLE` falla por conflicto de nombres. La
alternativa de aislamiento es un clúster separado (contenedor distinto), no una base
nueva en el mismo. **Pendiente: decidir estrategia de aislamiento con el docente.**

### CD-4 — `calcular_total_pedido` y permisos del ejecutor

Después de U5 D3, EXECUTE sobre `calcular_total_pedido` fue revocada a PUBLIC y concedida
solo a `rol_propietario_ventas`. El script `04_verificar_integridad.sql` del ZIP invoca
`public.calcular_total_pedido(p.id)`. El ejecutor necesita EXECUTE o ser superusuario.
**Pendiente: verificar quién es el propietario real de la función (VP-02 de U5) y qué
identidad usa el docente al ejecutar.**

### CD-5 — `pg_read_all_data` y EXECUTE

`pg_read_all_data` por sí solo no concede EXECUTE sobre funciones. Concede SELECT sobre
tablas, vistas y secuencias, y USAGE sobre esquemas. La disponibilidad de EXECUTE sobre
`calcular_total_pedido` después de U5 D3 depende de los permisos efectivos del ejecutor:
si es superusuario funciona; si es un rol sin EXECUTE explícito ni condición de
propietario, falla con 42501. No presentar `pg_read_all_data` como solución para el
acceso a `calcular_total_pedido`.

---

## Decisiones del equipo

### EA-1 — RPO 24 h y RTO 20 min

Metas de laboratorio propuestas por el equipo. No son exigencias del docente ni
resultados obtenidos. **Adoptadas por el equipo el 2026-11-05**, antes de la
corrida de evaluación; no están confirmadas por el docente.

### EA-2 — Scripts que instalan objetos vs consultas de solo lectura

`04_verificar_integridad.sql` del ZIP instala o reemplaza una función
(`CREATE OR REPLACE FUNCTION`). `05_monitoreo_salud.sql` del ZIP instala o reemplaza
una vista y concede permisos (`CREATE OR REPLACE VIEW`, `GRANT`). No son archivos de
consulta de solo lectura. Separar la instalación de esos objetos de la consulta
posterior. **Documentado.**

### EA-3 — `07_config_monitoreo.sql` como cambio de configuración

El script del ZIP ejecuta `ALTER SYSTEM SET` en varios parámetros de logging. Es un
cambio de configuración del servidor, no una verificación ni un mantenimiento
rutinario. Requiere superusuario y `pg_reload_conf()`. **Documentado.**

### EA-4 — Opciones de restauración del ZIP vs PDF

`--no-owner --no-privileges` aparece en el ejemplo del PDF, no en
`prueba_restauracion.sh` del ZIP. El script del ZIP no usa esas flags: restaura con
`--exit-on-error -j 4` y filtra pg_cron del TOC. `--no-owner` no elimina SECURITY
DEFINER: reasigna el propietario de los objetos restaurados al usuario que ejecuta
`pg_restore`, cambiando los privilegios efectivos de las funciones SECURITY DEFINER.
Aceptable para validar datos; no para validar el esquema de seguridad. **Documentado.**

### EA-5 — Archivado físico y estado terminal

`03_archivado_pedidos.sql` del ZIP usa `estado = 'CANCELADO' OR eliminado = TRUE`.
Un `PENDIENTE` con `eliminado = TRUE` sería archivado, pero `PENDIENTE` no es un
estado terminal. No se programa automáticamente sin revisar la condición. **Documentado.**

### EA-6 — `dropdb` automático en `prueba_restauracion.sh`

El script del docente ejecuta `dropdb --if-exists` sobre la base de prueba. No se
autoriza `dropdb` automático de una base existente sin confirmar que no hay trabajo
en curso. Si la base de restauración ya existe, el procedimiento se detiene.
**Documentado.**

### EA-7 — Mejoras que exceden las exigencias literales del TP

SHA256, retención de respaldos y verificación con `pg_restore --list` son mejoras que
exceden las exigencias literales del TP. El TP pide respaldo con fecha, log y exit code.
No se agregan borrados automáticos como requisito. **Documentado.**

---

## Verificaciones pendientes del entorno

| # | Verificación | Por qué no se puede resolver sin ejecución |
|---|---|---|
| VE-1 | Propietario real de las siete rutinas canónicas (VP-02 de U5) | Las evidencias registran instalación con `-U postgres`; no se asume `admin_datos` |
| VE-2 | `pg_cron` instalado y `shared_preload_libraries` configurado | `06_tareas_programadas.sql` del ZIP lo requiere. Sin servidor accesible, no se comprueba |
| VE-3 | `pgcrypto` instalada en la base de U6 | Requerida por `fn_autenticar` y `fn_resetear_password` de U5 |
| VE-4 | Vistas de U3 y materializada instaladas en la base de U6 | `00_roles_unidad5_base.sql` del ZIP referencia vistas que pueden no existir |
| VE-5 | Herramientas cliente disponibles en el entorno de ejecución | No están en el PATH de esta máquina (Ubuntu 26.04), pero pueden existir en otro entorno. No encontrarlas aquí no prueba que no existan |
| VE-6 | Antecedente de U5: validación en contenedores descartables `postgres:17` (Docker) | La evidencia de `validacion_parte_a` registra PostgreSQL 17.11 en contenedores. Diferenciar ese antecedente del entorno actual de U6, todavía pendiente |
| VE-7 | Permisos efectivos del ejecutor de `04_verificar_integridad.sql` | `calcular_total_pedido` tiene EXECUTE restringido por D3. Verificar qué identidad usa el docente: si es superusuario funciona; si es un rol sin EXECUTE, falla con 42501 |

---

## Controles de integridad del ZIP (`04_verificar_integridad.sql`)

| Control | Qué verifica | Observación |
|---|---|---|
| C1 | `pedido.total <> calcular_total_pedido(p.id)` | No se garantiza cero por instalar triggers: una escritura directa de `pedido.total` queda fuera de los triggers del detalle. No se presenta como resultado observado |
| C2 | `subtotal <> cantidad * precio_unitario` | El trigger canónico `trg_subtotal` dispara en `BEFORE INSERT OR UPDATE OF cantidad, precio_unitario, producto_id, subtotal` y recalcula `NEW.subtotal` en esas operaciones cuando está instalado y habilitado. Aun con el trigger activo, los datos existentes deben validarse. No se presenta como resultado observado |
| C3 | Producto vigente en categoría dada de baja | Puede devolver filas: el modelo establece que bajas posteriores no destruyen historial. Se documenta, no se oculta |
| C4 | Pedido vigente de usuario dado de baja | Puede devolver filas: mismo principio. Se documenta, no se convierte en aprobación automática |
| C5 | Pedido confirmado/terminado sin detalle | `NOT EXISTS` sin filtro por `eliminado` detecta ausencia de cualquier fila de detalle. No detecta un pedido cuyos detalles siguen existiendo aunque todos tengan `elimado = TRUE`: en ese caso `NOT EXISTS` devuelve falso porque las filas existen. No se modifica el SQL original del docente |

Los resultados de los controles se conservan literalmente como los devuelve el motor.
No se cambian datos ni reglas para forzar controles en cero.
