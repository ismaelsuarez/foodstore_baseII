# TPI-B — Transacciones e aislamiento reproducibles

Este arnés demuestra rollback parcial, snapshot REPEATABLE READ y un conflicto
SERIALIZABLE sobre `public.producto.stock`, sin cambiar lógica productiva.
Se ejecuta **solo en `foodstore_tpi_cierre_b`**, en un PostgreSQL local ya
autenticado. Requiere **PowerShell 7+**, `psql`, `createdb` y PostgreSQL 17.
No almacena contraseñas ni modifica autenticación.

## Preparar una base nueva

Desde la raíz del repositorio, comprobar primero que la base no existe:

```powershell
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d postgres -At -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) FROM pg_database WHERE datname='foodstore_tpi_cierre_b';"
```

Continuar únicamente si devuelve **0**, sin error. Si ya existe, detenerse:
no borrarla, recrearla ni reinstalar archivos sobre ella automáticamente.

```powershell
createdb -w -h 127.0.0.1 -p 5432 -U postgres foodstore_tpi_cierre_b
if ($LASTEXITCODE -ne 0) { throw 'Falló la creación; detenerse.' }
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_cierre_b -v ON_ERROR_STOP=1 -1 -f .\schema.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló schema; detenerse.' }
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_cierre_b -v ON_ERROR_STOP=1 -f .\datos_iniciales.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló seed; detenerse.' }
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_cierre_b -v ON_ERROR_STOP=1 -1 -f .\tpi\sql\objetos_programables.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló objetos; detenerse.' }
```

El seed administra su propia transacción; no se envuelve con `-1`. No usar dumps
ni instalar U3/U4. Preparar este ensayo no requiere repetir la batería funcional
canónica completa.

## Ejecutar

```powershell
pwsh -NoProfile -File .\tpi\pruebas\transacciones\ejecutar.ps1
if ($LASTEXITCODE -ne 0) { throw 'TPI-B falló; revisar logs y preservar la base.' }
```

Cerrar previamente otras conexiones al laboratorio. El arnés comprueba
conteos, producto 1 (`Muzzarella`, stock 50), objetos e integridad. No crea ni
elimina bases. Puede repetirse tras un PASS: cada corrida restaura el stock y
compara huellas de las cinco tablas, secuencias y catálogo con su estado inicial.

| Caso | Intercalado verificable | Resultado exigido |
|---|---|---|
| [SAVEPOINT](savepoint.sql) | BEGIN, primer cambio, SAVEPOINT, segundo cambio, ROLLBACK TO, ROLLBACK final | 50 → 49 → 47 → 49 → 50 |
| [RR A](rr_a.sql) / [RR B](rr_b.sql) | A fija snapshot; B confirma 51; A relee y termina; nueva transacción de A | 50 / 51 / 50 / 51; luego restauración controlada a 50 |
| [SERIAL A](serial_a.sql) / [SERIAL B](serial_b.sql) | Ambos leen 50; A escribe 52; B intenta escribir y el monitor verifica su espera; A confirma | A confirma 52; B termina con SQLSTATE 40001 y exit 3; luego restauración a 50 |

`-- BARRIER --` separa bloques que el [orquestador](ejecutar.ps1) envía por stdin
a conexiones psql persistentes e independientes. Cada respuesta termina en un
marcador único `\echo`: una confirmación, no un temporizador, autoriza el paso
siguiente. SERIALIZABLE añade una conexión de monitoreo de `pg_stat_activity`,
`pg_blocking_pids` y `pg_locks`; exige `Lock / transactionid` de B bloqueado por A.
El sondeo de 50 ms no constituye por sí solo evidencia del bloqueo.

El 40001 esperado no se ignora genéricamente: B debe finalizar con exit **3**,
exactamente un ERROR con código **40001**, sin 40P01, FATAL ni PANIC. Cualquier
otra sesión debe finalizar con exit **0**, sin errores SQL. Hay timeouts; ante
fallo se cierran únicamente los procesos creados por el arnés, se conserva el
laboratorio y no se restaura ciegamente un valor no previsto.

## Salidas y límites

- Los logs se crean en un directorio **nuevo bajo TEMP**, nunca dentro del repo.
  La consola informa `TPI_B_LOG_DIRECTORY`. `summary.json` conserva valores,
  PIDs, códigos de salida, SQLSTATE observado, locks y auditorías antes/después.
- [guard.sql](guard.sql) y [auditoria.sql](auditoria.sql) son parte del arnés;
  no crean objetos permanentes. No se insertan fixtures ni se consumen IDs.
- Un PASS preserva los datos lógicos y secuencias; los UPDATE/rollback pueden
  dejar versiones físicas de filas. No se promete igualdad física ni rendimiento.
- READ COMMITTED y atomicidad del CALL conservan la
  [evidencia canónica previa](../../evidencia_modelo_oficial.md). No se repiten
  sus tres escenarios. B de la prueba RR usa READ COMMITTED solo para confirmar
  el cambio concurrente; no sustituye aquellos ensayos de venta.
- El caso de misma fila que produce 40001 bajo SERIALIZABLE también puede
  producirlo bajo REPEATABLE READ: no demuestra un fenómeno exclusivo de SSI.
  Se demuestra el nivel realmente configurado y el rechazo de una escritura
  concurrente sobre una versión cambiada después del snapshot.
- Estas pruebas no acreditan ausencia universal de deadlocks, retry automático,
  garantías para DML arbitrario ni rendimiento concurrente. La fila de stock
  es un fixture del laboratorio, no una implementación de venta.

Los resultados de esta fase se conservan en
[evidencia del objetivo 8](../../evidencia_cierre_objetivo_8.md).
