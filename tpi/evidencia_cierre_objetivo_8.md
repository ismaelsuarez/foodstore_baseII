# TPI-B — Evidencia de transacciones y aislamiento

**OBJECTIVE_8_STATUS = PASS**, en el alcance académico explícito de este
documento. Se ejecutaron dos veces SAVEPOINT, REPEATABLE READ y SERIALIZABLE
sobre el modelo canónico. La atomicidad del CALL y los tres casos READ COMMITTED
conservan su evidencia previa: no se repitieron ni se reemplazaron con U4.

## 1. Entorno y fuentes

| Dato | Valor observado |
|---|---|
| Fecha local | 2026-09-23, America/Buenos_Aires |
| Repositorio | `C:\Users\facu\Documents\UTN\Base_datos_II\foodStore` |
| Rama | `fix/tpi-cierre-primera-entrega` |
| HEAD base | `7c585837e72b1e66258ae1d2072da0394de6f2a2` |
| Motor | PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit |
| Cliente | psql 17.11; PowerShell 7.6.6 |
| Base exclusiva | `foodstore_tpi_cierre_b` |
| Estado final | `PRESERVED`, datos lógicos iniciales restaurados |

Se comprobó `COUNT(*) = 0` en `pg_database` para ese nombre antes de crearla.
Instalación desde archivos actuales, sin dumps ni datos de otra base:

1. [schema.sql](../schema.sql), `ON_ERROR_STOP=1`, `-1`: exit 0.
2. [datos_iniciales.sql](../datos_iniciales.sql), `ON_ERROR_STOP=1`, sin `-1`
   porque administra BEGIN/COMMIT: exit 0.
3. [objetos_programables.sql](sql/objetos_programables.sql), `ON_ERROR_STOP=1`,
   `-1`: exit 0. Siete rutinas y cinco triggers habilitados.

SHA-256 de las fuentes instaladas, conservadas sin modificación:

| Fuente | SHA-256 |
|---|---|
| schema.sql | `6EB8E9FC39B0E3E86894B80CE3E2549CF222BE5F8C49E448B07C32C68C069614` |
| datos_iniciales.sql | `3948AD5A54D50B3EFDABBABE378C0FD45CB8573C6C4C24CA91B495788911882B` |
| objetos_programables.sql | `CFF4FC5E3E3F5EA904EBFE8B7289E6233D1737D81017E4A2A09B57C127D73B18` |

Inventario inicial y final: categoria 2, usuario 3, producto 3, pedido 5,
detalle_pedido 7. Cinco tablas, cinco PK, cuatro FK, seis CHECK, tres UNIQUE;
cero constraints sin validar. No se instaló U3 ni U4.

## 2. Atomicidad y control transaccional previamente acreditados

La [batería canónica](pruebas/pruebas_objetos_programables.sql), grupo
`ATOMICIDAD`, ejecuta CALL, comprueba sus efectos y genera `P0099` dentro de un
subbloque. Al capturarlo verifica la reversión conjunta de detalle, subtotal,
total y stock. La [evidencia oficial](evidencia_modelo_oficial.md), Bloque 6,
registra ese PASS, el ROLLBACK final, cero fixtures y seed intacto.

`P0099` pertenece exclusivamente a aquel test, no al producto. El rollback
implícito de ese subbloque no se presenta como SAVEPOINT SQL explícito.
BEGIN/COMMIT del seed y los COMMIT de sesiones del Bloque 7 tienen evidencia
previa. En TPI-B también se ejecutaron BEGIN, COMMIT y ROLLBACK reales.

## 3. Arnés y coordinación

Archivos versionados en [pruebas/transacciones](pruebas/transacciones/README.md):
[ejecutar.ps1](pruebas/transacciones/ejecutar.ps1),
[guard.sql](pruebas/transacciones/guard.sql),
[auditoria.sql](pruebas/transacciones/auditoria.sql) y los cinco SQL de casos
enlazados a continuación. No se crean objetos auxiliares permanentes.

El orquestador abre procesos psql independientes y conserva las conexiones
entre bloques delimitados por `-- BARRIER --`. Un marcador único en stdout
confirma que cada bloque terminó antes de enviar el siguiente. Para SERIALIZABLE
se exige además evidencia de espera real en `pg_stat_activity`,
`pg_blocking_pids` y `pg_locks`, antes de permitir el COMMIT de A.

No se usa `pg_sleep`. El sondeo de 50 ms del monitor solo limita la frecuencia
de consultas: el intercalado se acredita con resultados y locks, no con demora.
Se registra el nivel efectivo mediante `current_setting('transaction_isolation')`.

Seguridad: base literal, host local, puerto 5432, `-X -w`, ON_ERROR_STOP, guardas
antes de DML, comprobación de exclusividad inicial, timeouts y fail-fast si falta
psql. No hay credenciales versionadas ni cambios de autenticación. Los procesos
propios se cierran ante fallo; no se mata otra sesión ni se restaura ciegamente
un stock inesperado. Requiere laboratorio sin escritores externos.

## 4. SAVEPOINT explícito

Archivo exacto ejecutado: [savepoint.sql](pruebas/transacciones/savepoint.sql).
Después de la guarda de base/seed, ejecuta literalmente:

```sql
SELECT 'BEFORE=' || stock FROM public.producto WHERE id = 1;
BEGIN;
UPDATE public.producto SET stock = stock - 1 WHERE id = 1;
SELECT 'AFTER_FIRST_CHANGE=' || stock FROM public.producto WHERE id = 1;
SAVEPOINT sp_tpi;
UPDATE public.producto SET stock = stock - 2 WHERE id = 1;
SELECT 'AFTER_SECOND_CHANGE=' || stock FROM public.producto WHERE id = 1;
ROLLBACK TO SAVEPOINT sp_tpi;
SELECT 'AFTER_ROLLBACK_TO_SAVEPOINT=' || stock FROM public.producto WHERE id = 1;
ROLLBACK;
SELECT 'FINAL=' || stock FROM public.producto WHERE id = 1;
```

| Paso | Resultado real, ambas ejecuciones |
|---|---:|
| BEFORE | 50 |
| AFTER_FIRST_CHANGE | 49 |
| AFTER_SECOND_CHANGE | 47 |
| AFTER_ROLLBACK_TO_SAVEPOINT | 49 |
| FINAL | 50 |

**PASS:** la primera modificación permanece dentro de la transacción después
del rollback parcial; la segunda desaparece. El rollback final deshace también
la primera. No se indujo un error para simularlo.

## 5. READ COMMITTED preservado

La [evidencia oficial, Bloque 7](evidencia_modelo_oficial.md) acredita:

| Ensayo previo | Resultado registrado |
|---|---|
| Mismo producto / pedidos distintos | B espera a A; 23514; stock final 1, sin sobreventa |
| Mismo pedido / productos distintos | Ambos confirman; total 1300; stocks 8 y 7 |
| Mismo pedido / mismo producto | B espera; 23505; una línea, stock 8, sin segundo descuento |

En los tres casos se observó `Lock / transactionid`. Se conserva también la
incidencia histórica del helper de cleanup `42601`, que no fue fallo productivo.
**READ_COMMITTED_STATUS = PASS_PREVIOUS_CANONICAL_EVIDENCE**.
Estos tres scripts temporales no se reconstruyen ni se presentan como parte
del nuevo arnés. Su falta de versionado íntegro permanece como límite de
reproducción de aquellos intercalados específicos; el arnés nuevo sí versiona
completamente los casos que ejecuta.

## 6. REPEATABLE READ

Scripts: [rr_a.sql](pruebas/transacciones/rr_a.sql) y
[rr_b.sql](pruebas/transacciones/rr_b.sql).

1. A inicia `BEGIN ISOLATION LEVEL REPEATABLE READ` y lee stock 50.
2. Manteniendo A abierta, B inicia READ COMMITTED, lee 50, incrementa a 51 y
   ejecuta COMMIT. El orquestador confirma que B observa 51 y termina sin error.
3. A vuelve a leer: 50. Confirma su transacción de lectura.
4. A inicia otra transacción REPEATABLE READ: ahora ve 51.
5. Cerradas ambas sesiones, restauración controlada 51 → 50 con COMMIT.

| Marca | Ejecución 1 | Ejecución 2 |
|---|---:|---:|
| A_READ_1 | 50 | 50 |
| B_BEFORE | 50 | 50 |
| B_AFTER_COMMIT | 51 | 51 |
| A_READ_2 | 50 | 50 |
| AFTER_A_NEW_TRANSACTION | 51 | 51 |

**PASS:** snapshot estable de A y visibilidad posterior del COMMIT de B.
No se afirma que la fila quede bloqueada por un SELECT normal de A.

## 7. SERIALIZABLE y conflicto real

Scripts: [serial_a.sql](pruebas/transacciones/serial_a.sql) y
[serial_b.sql](pruebas/transacciones/serial_b.sql).

Ambas sesiones inician `BEGIN ISOLATION LEVEL SERIALIZABLE`, comprueban el
nivel efectivo y leen stock 50 antes de la escritura de A. A incrementa a 52
sin confirmar; B intenta incrementar en 3 la misma fila y queda bloqueada.
Solo tras observar ese bloqueo, el orquestador permite COMMIT de A.

En ambas ejecuciones:

- Ganadora: **A**, COMMIT correcto, exit 0, valor confirmado **52**.
- Abortada: **B**, exit **3**, exactamente un SQLSTATE **40001**.
- Estado leído desde control: **52**, no 53 ni 55.
- Restauración posterior controlada: **52 → 50**, con COMMIT.

Salida stderr real de B, idéntica en ambas ejecuciones:

```text
ERROR:  40001: no se pudo serializar el acceso debido a un update concurrente
LOCATION:  ExecUpdate, nodeModifyTable.c:2417
```

El arnés extrae ese SQLSTATE de la salida real y exige exit 3 más un único
40001; no lo genera como resultado supuesto ni acepta cualquier error.
ON_ERROR_STOP termina la conexión fallida, revirtiendo su transacción. No se
ejecuta un retry automático que oculte el conflicto original.

Este caso también puede fallar bajo REPEATABLE READ. Acredita ejecución bajo
SERIALIZABLE y rechazo de la escritura sobre una versión cambiada después del
snapshot; **no** demuestra una anomalía exclusiva de SSI ni una prueba general
de todas las invariantes de negocio. La interpretación de snapshot y conflictos
corresponde a la [documentación de PostgreSQL 17](https://www.postgresql.org/docs/17/transaction-iso.html).

## 8. Bloqueos observados y códigos de salida

| Ejecución | PID A | PID B | Estado B | Espera | Bloqueador | XID de A |
|---|---:|---:|---|---|---:|---:|
| 1 | 11684 | 16376 | active | Lock / transactionid | 11684 | 1351 |
| 2 | 17868 | 14896 | active | Lock / transactionid | 17868 | 1358 |

En `pg_locks`, A tenía `ExclusiveLock` concedido sobre su XID; B esperaba
`ShareLock`, `granted = false`, sobre ese mismo XID. A estaba `idle in transaction`,
esperando la instrucción del orquestador. También se observaron `SIReadLock`;
no se confunden con el lock bloqueante `transactionid`.

| Proceso | PID ejecución 1 | PID ejecución 2 | Exit en ambas |
|---|---:|---:|---:|
| control | 20520 | 10060 | 0 |
| savepoint | 11996 | 3348 | 0 |
| rr_a | 22204 | 13740 | 0 |
| rr_b | 20572 | 21924 | 0 |
| serial_a | 11684 | 17868 | 0 |
| serial_b | 16376 | 14896 | 3, esperado 40001 |

Los PIDs/XID son circunstanciales, no valores requeridos para repetir el test.
No se observó `40P01` ni error SQL inesperado. Esto **no prueba ausencia universal
de deadlocks**, ni seguridad de DML arbitrario, CALL bajo cualquier aislamiento,
estrés o rendimiento. Las pruebas no son benchmarks.

## 9. Integridad y limpieza

Ambas auditorías finales registraron cero inconsistencias de subtotal, total,
FK, UNIQUE, CHECK y NULL obligatorios. Conteos **2 / 3 / 3 / 5 / 7**; stock
**50 / 40 / 100**; siete rutinas y cinco triggers permanecen instalados.

Huellas MD5 lógicas de `row_to_json`, ordenadas por id, iguales antes y después
de ambas ejecuciones (son verificadores de igualdad, no firmas de seguridad):

| Tabla | Huella |
|---|---|
| categoria | `20727bbb740f90dea57b5f057d24d36a` |
| usuario | `3e36c220fee9eebaf4186160d82d9c58` |
| producto | `d4a354c17becacfe28cbce4682e9588d` |
| pedido | `ba1811e0d9f95011ffc8bf15423b18b7` |
| detalle_pedido | `45a1ed44ec55a9e160e6265b44b07f37` |

Huella del catálogo contrastado: `a04522fd16fd616e3065615509bddd01`, sin cambios.
Secuencias: categoria 2, usuario 3, producto 3, pedido 5, detalle 7; todas
`is_called = true`, iguales antes/después. No hubo INSERT ni consumo de IDs.
Cero sesiones restantes, sin fixtures nuevos. La base queda **PRESERVED**.
No se promete igualdad física: UPDATE y rollback pueden dejar versiones de fila.

## 10. Reproducción y procedencia

Preparación exacta en el [README del arnés](pruebas/transacciones/README.md).
Sobre el laboratorio instalado, exclusivo y con stock inicial 50:

```powershell
pwsh -NoProfile -File .\tpi\pruebas\transacciones\ejecutar.ps1
if ($LASTEXITCODE -ne 0) { throw 'TPI-B falló; preservar laboratorio y revisar logs.' }
```

Se ejecutó dos veces, ambas con exit global **0** y `TPI_B_STATUS=PASS`:

| Ejecución | Inicio local | Final local | Directorio bajo TEMP |
|---|---|---|---|
| 1 | 23:26:16.571825 | 23:26:17.828792 | `foodstore-tpi-b-24b1bd7adf5744dcacec0085eb1ad8ec` |
| 2 | 23:26:23.928194 | 23:26:25.083482 | `foodstore-tpi-b-2e206faba2ae4313bc6b4d00688ebf74` |

Los directorios conservan `summary.json` y SQL/stdout/stderr de cada sesión.
Son procedencia temporal, no dependencias para comprender esta evidencia:
los valores, SQLSTATE, intercalados y locks relevantes quedan registrados aquí.
No se almacenan secretos ni logs dentro del repositorio.

## 11. Resultado y alcance

| Requisito | Evidencia | Estado |
|---|---|---|
| BEGIN / COMMIT / ROLLBACK | Seed, evidencia previa y ejecución TPI-B | PASS |
| Atomicidad de venta | Batería ATOMICIDAD y Bloque 6 previo | PASS previo preservado |
| SAVEPOINT explícito | savepoint.sql, rollback parcial observado | PASS nuevo |
| READ COMMITTED | Tres escenarios canónicos del Bloque 7 | PASS previo preservado |
| REPEATABLE READ | A/B y snapshot contrastado dos veces | PASS nuevo |
| SERIALIZABLE | A/B, bloqueo y 40001 observado dos veces | PASS nuevo |
| Reproducción multisesión | SQL, PowerShell, guardas y auditoría versionados | PASS |
| Integridad final | Datos, secuencias y catálogo sin cambio lógico | PASS |

**OBJECTIVE_8_STATUS = PASS.** No se modificó lógica productiva, schema, seed,
unidades ni evidencia previa. Retirar esta unidad documental/de pruebas no
requiere revertir una migración: no añade objetos productivos y las pruebas
restauran sus cambios lógicos. TPI-C, merge y push quedan fuera de esta fase.
