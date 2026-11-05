# Tasks — Unidad 6: Implementación con Claude

Lista ordenada para Claude. Cada tarea indica resultado esperado y dependencias.
Los scripts del procedimiento están implementados. Primer ensayo funcional del
núcleo canónico satisfactorio, según las evidencias de la corrida; véase el
[ensayo funcional](../docs/ensayo_funcional.md). No completa el TP6: faltan la
comprobación docente, la seguridad de U5 y la entrega. La versión y las
herramientas del laboratorio se comprobaron antes, en la prueba de
infraestructura del [laboratorio](../docs/laboratorio.md).

---

## T1 — Resolver decisiones necesarias

**Resultado esperado:** confirmar con el docente o el equipo las decisiones
pendientes registradas en [compatibilidad_docente.md](../docs/compatibilidad_docente.md):
nombre de base (CD-1), tabla de validación (CD-2), estrategia de aislamiento de
roles (CD-3), y metas RPO/RTO (EA-1).

**Dependencias:** ninguna.

## T2 — Preparar el laboratorio cuando se autorice

**Resultado esperado:** contenedor descartable con `postgres:17` corriendo, base
creada con `schema.sql` + `datos_iniciales.sql` + objetos TPI + roles de U5 + vistas
de U3 + `pgcrypto`. Línea base registrada.

**Dependencias:** T1 (nombres de base confirmados); autorización explícita del
equipo para crear contenedores y bases.

**Estado parcial:** infraestructura creada el 2026-11-04: contenedor
`foodstore-u6-lab`, volumen `foodstore_u6_lab_data` y autenticación SCRAM.
EP-1 resuelto: imagen local `postgres:17`, id
`sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`;
servidor y clientes 17.11 (Debian 17.11-1.pgdg13+2). EP-2 parcial: contenedor y
volumen creados; bases y roles Food Store pendientes.

**Ensayo 2026-11-05:** con autorización se cargaron schema, seed y objetos TPI
en la base exclusiva `u6_ensayo_origen` y se registró su línea base (conteos 2,
3, 3, 5 y 7; controles en 0).

**Pendiente:** nombres de bases definitivos (CD-1). Roles U5, vistas U3 y
`pgcrypto` no cargados. `pg_cron` no comprobado (EP-6/VE-2); propietario real de las
rutinas canónicas (VE-1) e identidades por tarea (EP-4) pendientes.

## T3 — Implementar el respaldo

**Resultado esperado:** `backup_foodstore.sh` escrito y revisado línea por línea.
`pg_dump -Fc` con fecha en nombre, log con marca de inicio y fin, exit code
distinto de cero si falla. Sin contraseñas en el script. Autenticación con archivo
de formato pgpass (`~/.pgpass` en la SPEC, `PGPASSFILE` en el laboratorio).

**Dependencias:** T2 (laboratorio disponible para prueba manual).

**Estado:** implementado y ensayado con el núcleo canónico. La versión actual
(SHA-256 `3b8e39c8…`) captura la línea base con `validaciones.sql` antes de
`pg_dump` y la publica como `BASE_AAAAMMDD_HHMMSS.baseline`, asociada al respaldo
por nombre, SHA-256 y `pg_dump_inicio`. En el
[ensayo funcional](../docs/ensayo_funcional.md) terminó con exit 0: dump de 26546 B,
`.baseline` con 12 claves y controles en 0. Requiere una ventana sin escrituras
que el script no garantiza. La versión anterior tuvo
una primera prueba técnica de infraestructura en `postgres`: respaldo y
`pg_restore --list` con exit 0; base inexistente con exit 1 y sin archivos finales
ni temporales residuales. Clientes
por TCP/SCRAM mediante `PGHOST` y `PGPASSFILE` del contenedor, sin modificar el
script. Validación con datos Food Store y restauración pendientes; legibilidad no
equivale a restauración. El rol `postgres` no queda aprobado como rol definitivo
de respaldo.

## T4 — Implementar salud y mantenimiento

**Resultado esperado:** `health_check.sql` con cuatro controles (tamaño,
conexiones, estado de tablas, consultas activas con `state <> 'idle'`).
`maintenance.sql` con revisión previa de `pg_stat_user_tables` y acción segura
justificada (no `VACUUM FULL`). Revisión humana antes de ejecutar.

**Dependencias:** T2.

**Estado:** `health_check.sql` y `maintenance.sql` implementados y ensayados con
el núcleo canónico. `health_check.sql` terminó con exit 0 en el origen y en la
restauración. Antes había tenido una prueba de infraestructura en `postgres`, y
entre ambas solo cambió su comentario sobre READ ONLY. Registra
métricas sin semáforo: los colores no son requisito bloqueante y los umbrales
quedan como mejora pendiente. `READ ONLY` es protección complementaria a la
revisión del SQL, no garantía absoluta; `backend_xmin` es diagnóstico, no prueba
por sí solo. `maintenance.sql` siempre muestra el diagnóstico y solo ejecuta
`ANALYZE VERBOSE` con selección, autorización y justificación explícitas. En el
ensayo, sin variables hizo solo el diagnóstico, y con selección ejecutó `ANALYZE`
sobre `detalle_pedido` en la copia restaurada (exit 0, conteos preservados).

## T5 — Preparar restauración y validaciones

**Resultado esperado:** `restore_test.sh` (opcional) escrito y revisado. Detiene
si la base ya existe. RTO desde `createdb` hasta fin de validaciones. Compara
conteos con línea base; verifica productos y detalles inválidos en cero.

**Dependencias:** T3 (respaldo generado para restaurar).

**Estado:** `restore_test.sh` y `validaciones.sql` implementados y ensayados con
el núcleo canónico. La restauración `sin-propietarios` quedó validada (exit 0,
comparación vacía) y se rechazaron destino existente, destino igual al origen y
dump alterado (exit 2). El modo `conservar-propietarios` no se probó. El modo `-m` (`sin-propietarios` o `conservar-propietarios`)
se elige explícitamente y registra su alcance. `sin-propietarios` no recupera la
seguridad de U5, y ningún modo restaura roles globales.

## T6 — Ejecutar pruebas autorizadas y conservar evidencia

**Resultado esperado:** respaldo generado, restauración probada, RPO/RTO medidos
y registrados por separado del cumplimiento de metas. Resultados de controles
conservados literalmente. Problemas reales documentados si los hubo.

**Dependencias:** T3, T4, T5; autorización explícita del equipo.

**Estado parcial:** el 2026-11-05 se realizó un
[ensayo funcional con el núcleo canónico](../docs/ensayo_funcional.md):

- Respaldo con línea base: exit 0.
- Restauración `sin-propietarios` validada: exit 0 y comparación vacía.
- Pruebas negativas A, B y C rechazadas: exit 2.
- Salud en ambas bases y `ANALYZE` puntual en la copia restaurada.

Los tiempos observados (0,312 s y 26 s de antigüedad) corresponden al seed mínimo.

**Pendiente:** T6 no completada. El ensayo usa bases exclusivas, el rol
`postgres` y el modo `sin-propietarios`; no es la comprobación docente ni recupera
la seguridad de U5. La prueba de infraestructura de
[laboratorio](../docs/laboratorio.md) tampoco valida el TP6. Faltan:

- La comprobación con el procedimiento docente.
- El modo `conservar-propietarios`.
- Las mediciones con las identidades y los nombres definitivos.

RPO 24 h y RTO 20 min siguen como propuestas pendientes de aprobación (EA-1); no
se declaran metas cumplidas. También siguen pendientes:

- Los nombres de las bases y el procedimiento de comprobación docente (CD-1).
- Las identidades definitivas de cada tarea (EP-4).
- La decisión de propietarios y permisos de la restauración (CD-3, EA-4).

## T7 — Preparar el informe y revisar la entrega

**Resultado esperado:** `informe_u6.pdf` con fecha/hora del respaldo, RTO
observado, RPO observado, resultado de validaciones, problema real, mejora
propuesta, y verificación del trabajo asistido con IA. Revisión final de
entregables contra la consigna.

**Dependencias:** T6.
