# Informe de concurrencia — Food Store

## Escenario 1 — Lectura no repetible

### Escenario

Se reprodujo una lectura no repetible sobre la tabla `producto`, utilizando el precio del producto `Muzzarella`.

El objetivo fue comprobar el comportamiento de una misma consulta ejecutada dos veces dentro de una misma transacción bajo `READ COMMITTED`, mientras otra sesión modificaba y confirmaba el valor leído.

Luego se repitió el mismo experimento usando `REPEATABLE READ` para verificar si el fenómeno quedaba evitado.

### Cómo se reprodujo

#### Prueba con READ COMMITTED

**Sesión A**

```sql
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella';
```

Resultado inicial observado:

```text
id = 10
nombre = Muzzarella
precio = 1050.00
```

**Sesión B**

```sql
BEGIN;

UPDATE producto
SET precio = 1200.00
WHERE nombre = 'Muzzarella';

COMMIT;
```

La sentencia `UPDATE` afectó una fila y el cambio fue confirmado con `COMMIT`.

**Sesión A**

Dentro de la misma transacción se repitió exactamente la misma consulta:

```sql
SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella';
```

Resultado observado después del `COMMIT` de la Sesión B:

```text
id = 10
nombre = Muzzarella
precio = 1200.00
```

#### Verificación con REPEATABLE READ

Antes de repetir el experimento, el precio de `Muzzarella` fue restaurado a `1050.00`.

**Sesión A**

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella';
```

Resultado inicial observado:

```text
id = 10
nombre = Muzzarella
precio = 1050.00
```

**Sesión B**

```sql
BEGIN;

UPDATE producto
SET precio = 1200.00
WHERE nombre = 'Muzzarella';

COMMIT;
```

La modificación fue confirmada correctamente.

**Sesión A**

Dentro de la misma transacción `REPEATABLE READ` se repitió la consulta:

```sql
SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella';
```

Resultado observado:

```text
id = 10
nombre = Muzzarella
precio = 1050.00
```

Aunque la Sesión B confirmó el cambio a `1200.00`, la Sesión A continuó viendo `1050.00` durante toda su transacción.

### Qué se observó

Con `READ COMMITTED`, la Sesión A realizó dos veces la misma consulta dentro de una única transacción y obtuvo resultados distintos:

- Primera lectura: `1050.00`
- Segunda lectura, después del `COMMIT` de la Sesión B: `1200.00`

Esto demuestra una lectura no repetible: el valor leído inicialmente cambió dentro de la misma transacción porque otra sesión modificó y confirmó la fila entre ambas consultas.

Con `REPEATABLE READ`, la Sesión A volvió a realizar dos veces la misma consulta dentro de la misma transacción, pero en ambas oportunidades observó `1050.00`, aun cuando la Sesión B había actualizado el precio a `1200.00` y confirmado el cambio.

Por lo tanto, `REPEATABLE READ` evitó la lectura no repetible en este experimento.

### Explicación de la IA

Herramienta: OpenCode  
Modelo: `MiMo V2.5 Free`

> Explicación del experimento
>
> 1. Fenómeno en READ COMMITTED: lectura no repetible
>
> Ocurrió una lectura no repetible (non-repeatable read). La Sesión A leyó la misma fila dos veces dentro de una misma transacción y obtuvo valores distintos. La segunda lectura reflejó un cambio confirmado por otra transacción (Sesión B) que cometió entre ambas lecturas.
>
> 2. Por qué la segunda lectura vio 1050 → 1200 en READ COMMITTED
>
> READ COMMITTED garantiza que cada sentencia solo ve datos committeados al momento de iniciarse la sentencia. No bloquea la fila durante toda la transacción. Cuando la Sesión A ejecuta el segundo SELECT, la sentencia toma un snapshot nuevo. La Sesión B ya hizo COMMIT con precio = 1200.00, así que el snapshot de esa sentencia incluye el cambio. Cada sentencia within READ COMMITTED es una "mini-transacción" con su propio snapshot.
>
> 3. Por qué REPEATABLE READ mantuvo 1050.00
>
> REPEATABLE READ en PostgreSQL toma un snapshot una sola vez: en la primera sentencia de datos (el primer SELECT). Todas las sentencias subsiguientes de la misma transacción leen el mismo snapshot. La Sesión B modificó y cometió la fila después de ese snapshot, pero la Sesión A nunca lo ve porque su snapshot quedó congelado en el estado anterior al UPDATE. La fila modificada por B es invisible para A hasta que A termine.
>
> 4. Qué nivel evita el problema
>
> SERIALIZABLE es el nivel más alto en PostgreSQL. Evita lecturas no repetibles y phantom reads, garantizando que el resultado final equivale a ejecutar las transacciones en algún orden secuencial determinista. Usa predicate locking (SIREAD locks) para detectar dependencias de lectura-escritura y abortar transacciones que comprometerían la serializabilidad.
>
> En la práctica, para este escenario específico, REPEATABLE READ ya resuelve la lectura no repetible. SERIALIZABLE protege además contra anomalias más sutiles (write skew, phantom reads).
>
> 5. Papel de MVCC
>
> MVCC (Multi-Version Concurrency Control) es el mecanismo subyacente. Cada transacción en PostgreSQL trabaja con versiones de las filas, no con bloqueos de lectura. Cuando la Sesión B actualiza precio, PostgreSQL no sobreescribe la fila original: crea una nueva versión de la fila con el valor 1200.00, marcando la versión anterior como obsoleta (su xmax se setea con el ID de la transacción de B).
>
> - En READ COMMITTED, cada sentencia de A consulta el catálogo de versiones y toma la versión más reciente que esté committeada. Al ser un snapshot por sentencia, ve la nueva versión de B.
> - En REPEATABLE READ, el snapshot se toma una vez y se reutiliza. La nueva versión de B tiene un xmin (transacción creadora) posterior al snapshot de A, por lo que A siempre ve la versión anterior.
>
> MVCC permite lecturas sin bloquear escrituras y viceversa. El nivel de aislamiento controla cuánto tiempo vive el snapshot: una sentencia (READ COMMITTED) o toda la transacción (REPEATABLE READ).

### Verificación en el motor

La explicación de la IA fue contrastada directamente en PostgreSQL 17.11.

Con `READ COMMITTED`, la Sesión A leyó inicialmente:

`precio = 1050.00`

Después de que la Sesión B ejecutó:

```sql
UPDATE producto
SET precio = 1200.00
WHERE nombre = 'Muzzarella';

COMMIT;
```
la Sesión A repitió la misma consulta dentro de la misma transacción y obtuvo:

precio = 1200.00

Esto confirmó la lectura no repetible.

Luego se restauró el precio a 1050.00 y se repitió el experimento utilizando:

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

En este caso, aunque la Sesión B volvió a actualizar el precio a 1200.00 y ejecutó COMMIT, la Sesión A continuó observando:

precio = 1050.00

Por lo tanto, el comportamiento observado en PostgreSQL confirmó que REPEATABLE READ evita la lectura no repetible en este escenario.

### Conclusión

El experimento confirmó que bajo `READ COMMITTED` puede ocurrir una lectura no repetible, porque cada sentencia obtiene un snapshot actualizado de los datos confirmados y una segunda lectura dentro de la misma transacción puede devolver un valor diferente.

En cambio, `REPEATABLE READ` mantuvo estable el valor observado por la Sesión A durante toda la transacción, aun cuando otra sesión confirmó una modificación sobre la misma fila.

La explicación de OpenCode quedó confirmada por el comportamiento real de PostgreSQL para este escenario.

Por lo tanto, `REPEATABLE READ` resulta suficiente para evitar la lectura no repetible reproducida en este laboratorio.

## Escenario 2 — Lectura fantasma

### Escenario

Se reprodujo una lectura fantasma utilizando la tabla `pedido`.

La consulta utilizada contó la cantidad de pedidos asociados a la cliente Ana Gómez mediante su correo electrónico `ana.gomez@foodstore.test`.

El objetivo fue comprobar qué ocurre cuando una transacción repite el mismo `COUNT(*)` mientras otra sesión inserta y confirma una nueva fila que cumple exactamente la misma condición del `WHERE`.

Primero se realizó el experimento bajo `READ COMMITTED` y luego se repitió utilizando `REPEATABLE READ`.

---

### Cómo se reprodujo

#### Prueba con READ COMMITTED

**Sesión A**

Se abrió una transacción con nivel de aislamiento `READ COMMITTED`:

```sql
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

Luego se contó la cantidad de pedidos de Ana Gómez:

```sql
SELECT COUNT(*) AS pedidos_ana
FROM pedido p
JOIN cliente c ON c.id = p.cliente_id
WHERE c.email = 'ana.gomez@foodstore.test';
```

Resultado inicial:

```text
pedidos_ana
-----------
2
```

**Sesión B**

Se abrió otra transacción:

```sql
BEGIN;
```

Luego se insertó un nuevo pedido para Ana Gómez:

```sql
INSERT INTO pedido (cliente_id, fecha, forma_pago)
VALUES (
    (
        SELECT id
        FROM cliente
        WHERE email = 'ana.gomez@foodstore.test'
    ),
    '2026-09-12 23:15:00-03',
    'EFECTIVO'
)
RETURNING id;
```

PostgreSQL generó:

```text
id = 21
```

Antes de ejecutar `COMMIT`, la Sesión A repitió el mismo `COUNT(*)` y continuó observando:

```text
pedidos_ana = 2
```

Esto confirmó que la fila todavía no era visible mientras la transacción de la Sesión B permanecía sin confirmar.

Luego, en la Sesión B, se ejecutó:

```sql
COMMIT;
```

**Sesión A**

Sin finalizar su transacción `READ COMMITTED`, la Sesión A volvió a ejecutar exactamente la misma consulta:

```sql
SELECT COUNT(*) AS pedidos_ana
FROM pedido p
JOIN cliente c ON c.id = p.cliente_id
WHERE c.email = 'ana.gomez@foodstore.test';
```

Resultado:

```text
pedidos_ana
-----------
3
```

La misma consulta pasó de devolver `2` filas a devolver `3` filas dentro de la misma transacción.

Finalmente, la Sesión A cerró su transacción mediante:

```sql
ROLLBACK;
```

Para restaurar los datos de laboratorio, en la Sesión B se eliminó el pedido utilizado en la prueba:

```sql
DELETE FROM pedido
WHERE id = 21;
```

Resultado:

```text
DELETE 1
```

---

#### Verificación con REPEATABLE READ

Una vez restaurados los datos originales, se repitió el mismo experimento utilizando `REPEATABLE READ`.

**Sesión A**

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

Luego se ejecutó nuevamente:

```sql
SELECT COUNT(*) AS pedidos_ana
FROM pedido p
JOIN cliente c ON c.id = p.cliente_id
WHERE c.email = 'ana.gomez@foodstore.test';
```

Resultado inicial:

```text
pedidos_ana
-----------
2
```

**Sesión B**

Se abrió una nueva transacción:

```sql
BEGIN;
```

Se insertó otro pedido para Ana Gómez:

```sql
INSERT INTO pedido (cliente_id, fecha, forma_pago)
VALUES (
    (
        SELECT id
        FROM cliente
        WHERE email = 'ana.gomez@foodstore.test'
    ),
    '2026-09-12 23:25:00-03',
    'EFECTIVO'
)
RETURNING id;
```

PostgreSQL generó:

```text
id = 22
```

Luego la Sesión B confirmó el cambio:

```sql
COMMIT;
```

**Sesión A**

Dentro de la misma transacción `REPEATABLE READ`, se repitió:

```sql
SELECT COUNT(*) AS pedidos_ana
FROM pedido p
JOIN cliente c ON c.id = p.cliente_id
WHERE c.email = 'ana.gomez@foodstore.test';
```

Resultado:

```text
pedidos_ana
-----------
2
```

Aunque la Sesión B había insertado y confirmado una tercera fila que cumplía el mismo `WHERE`, la Sesión A continuó observando únicamente los dos pedidos presentes en su snapshot inicial.

La transacción de la Sesión A se cerró mediante:

```sql
ROLLBACK;
```

Finalmente, para dejar nuevamente la base en su estado original, se eliminó el pedido utilizado en la segunda prueba:

```sql
DELETE FROM pedido
WHERE id = 22;
```

Resultado:

```text
DELETE 1
```

---

### Qué se observó

Bajo `READ COMMITTED`, la Sesión A ejecutó dos veces el mismo `COUNT(*)` dentro de una única transacción.

La primera ejecución devolvió:

```text
2
```

Después de que la Sesión B insertó una nueva fila que cumplía la condición y ejecutó `COMMIT`, la misma consulta en la Sesión A devolvió:

```text
3
```

Por lo tanto, apareció dentro del conjunto consultado una nueva fila confirmada por otra transacción.

Esto constituye el escenario de lectura fantasma reproducido en el laboratorio.

En cambio, al repetir el experimento con `REPEATABLE READ`, la Sesión A obtuvo:

```text
2
```

tanto antes como después del `INSERT` y `COMMIT` realizado por la Sesión B.

El conjunto visible para la Sesión A permaneció estable durante toda su transacción.

---

### Explicación de la IA

Herramienta: OpenCode  
Modelo: `MiMo V2.5 Free`

> Explicación del experimento
>
> 1. Fenómeno en READ COMMITTED: lectura fantasma
>
> Ocurrió una lectura fantasma (phantom read). La Sesión A ejecutó dos veces la misma consulta de rango (WHERE email = 'ana.gomez@foodstore.test') y obtuvo distinto conteo. La segunda ejecución devolvió una fila nueva (fantasma) que fue insertada y commiteada por la Sesión B entre ambas consultas. La fila no existía en el primer snapshot, pero sí en el segundo.
>
> 2. Por qué el COUNT cambió de 2 a 3
>
> READ COMMITTED asigna un snapshot nuevo por sentencia. La primera consulta de A ve solo los 2 pedidos que existían al momento de esa sentencia. Luego la Sesión B inserta un tercer pedido y hace COMMIT. Cuando A ejecuta la segunda consulta, esta toma un snapshot nuevo que incluye la fila commiteada de B. El COUNT(*) ahora encuentra 3 filas que cumplen el WHERE, incluyendo el fantasma.
>
> 3. Por qué REPEATABLE READ mantuvo COUNT = 2
>
> REPEATABLE READ congela el snapshot al inicio de la primera sentencia de datos. La segunda consulta de A reutiliza el mismo snapshot, que solo contiene los 2 pedidos originales. La fila insertada por B tiene un xmin posterior al snapshot de A, por lo que es invisible. PostgreSQL no la cuenta en el resultado del COUNT(*).
>
> A diferencia de lo que ocurre con UPDATE/DELETE (que causan error serialization_failure si另一事务 modifica filas que A ya leyó), con INSERT no hay conflicto: la fila simplemente no existe en el snapshot de A, así que no se reporta error, solo se omite.
>
> 4. Qué nivel evita el problema
>
> SERIALIZABLE. Es el único nivel en PostgreSQL que protege contra lecturas fantasma. Usa predicate locks (SIREAD locks) sobre rangos de índices. Cuando la Sesión B intenta insertar una fila que cae dentro del rango que la Sesión A tiene bloqueado por predicado, PostgreSQL detecta la dependencia y aborta la transacción de B (ERROR: could not serialize access due to read/write dependencies). Esto garantiza que el resultado sea serializable.
>
> En la práctica, REPEATABLE READ ya resuelve phantom reads en PostgreSQL para la mayoría de los casos prácticos porque el snapshot congelado los excluye. Pero no ofrece la garantía formal de serializabilidad — existen casos borde (write skew) donde REPEATABLE READ permite resultados no serializables que SERIALIZABLE sí previene.
>
> 5. Papel de MVCC
>
> MVCC maneja esto mediante la visibilidad de versiones de filas:
>
> - Cada fila en PostgreSQL tiene campos ocultos xmin (transacción que la creó) y xmax (transacción que la eliminó/modificó, o 0 si está viva).
> - La中新 INSERT de B crea una fila con xmin = ID de la transacción de B.
> - READ COMMITTED: la segunda consulta de A evalúa el snapshot y ve esa fila porque xmin de B ya está commiteado. La cuenta.
> - REPEATABLE READ: el snapshot de A tiene un xmax virtual — solo ve filas cuyo xmin sea ≤ al ID de la transacción de A y que no estén marcadas como obsoletas. El xmin de la INSERT de B es mayor, así que la fila es invisible.
>
> MVCC no usa bloqueos para lecturas. Cada transacción simplemente filtra filas según la regla de visibilidad de su snapshot. El nivel de aislamiento define cuándo se toma ese snapshot y cuánto dura.

#### Observaciones sobre la explicación de la IA

La explicación de OpenCode coincidió con el motor en los puntos principales:

- bajo `READ COMMITTED`, el `COUNT(*)` cambió de `2` a `3`;
- bajo `REPEATABLE READ`, el `COUNT(*)` se mantuvo en `2`;
- el comportamiento se explica por el uso de snapshots y MVCC.

Sin embargo, se detectó una imprecisión en la afirmación de que `SERIALIZABLE` sería el único nivel de PostgreSQL que protege contra lecturas fantasma.

El experimento realizado demostró que `REPEATABLE READ` también evitó que la nueva fila apareciera en la segunda consulta de la misma transacción, debido al snapshot estable utilizado por PostgreSQL.

La diferencia es que `SERIALIZABLE` ofrece garantías adicionales de serializabilidad y puede detectar otras anomalías que `REPEATABLE READ` todavía permite, como determinados casos de `write skew`.

También se conservaron literalmente dos fragmentos extraños generados por el modelo (`另一事务` y `新增`) porque la consigna exige registrar la explicación de la IA tal como fue entregada. Se interpretaron como artefactos de generación de texto y no como parte de la explicación técnica.

---

### Verificación en el motor

La explicación de la IA fue contrastada con los resultados obtenidos directamente en PostgreSQL 17.11.

La prueba real permitió comprobar los siguientes hechos:

#### READ COMMITTED

Primera ejecución:

```text
COUNT(*) = 2
```

La Sesión B insertó un nuevo pedido para Ana Gómez y ejecutó:

```sql
COMMIT;
```

Segunda ejecución de la misma consulta en la Sesión A:

```text
COUNT(*) = 3
```

Esto confirmó la aparición de una fila adicional que cumplía la misma condición de búsqueda.

#### REPEATABLE READ

Primera ejecución:

```text
COUNT(*) = 2
```

La Sesión B insertó otro pedido que cumplía la misma condición y ejecutó:

```sql
COMMIT;
```

Segunda ejecución en la Sesión A:

```text
COUNT(*) = 2
```

Por lo tanto, bajo `REPEATABLE READ`, PostgreSQL mantuvo estable el conjunto de filas visible para la transacción y la nueva fila confirmada por la otra sesión no apareció en la segunda lectura.

---

### Conclusión

El experimento demostró que bajo `READ COMMITTED` una consulta de conjunto puede devolver resultados diferentes dentro de una misma transacción cuando otra sesión inserta y confirma nuevas filas que cumplen la condición consultada.

En este caso, el `COUNT(*)` de pedidos de Ana Gómez cambió de `2` a `3`.

Al repetir el experimento bajo `REPEATABLE READ`, el resultado permaneció en `2`, incluso después de que la otra sesión insertó y confirmó un nuevo pedido.

Por lo tanto, para el escenario reproducido en PostgreSQL 17.11, `REPEATABLE READ` mantuvo estable el snapshot de la transacción y evitó la lectura fantasma observada bajo `READ COMMITTED`.

Los pedidos creados exclusivamente para las pruebas (`id = 21` e `id = 22`) fueron eliminados al finalizar cada experimento, dejando la base de laboratorio nuevamente en su estado original.

## Escenario 3 — Espera por bloqueo con SELECT FOR UPDATE

### Escenario

Se reprodujo una espera por bloqueo sobre una fila de la tabla `producto`.

Se utilizó el producto `Muzzarella`, cuyo `id` era `10` y cuyo precio al momento del experimento era `1050.00`.

El objetivo fue comprobar qué sucede cuando dos transacciones intentan obtener simultáneamente un bloqueo exclusivo sobre la misma fila mediante `SELECT ... FOR UPDATE`.

---

### Cómo se reprodujo

#### Sesión A

Se abrió una transacción:

```sql
BEGIN;
```

Luego se consultó y bloqueó la fila correspondiente al producto `Muzzarella`:

```sql
SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella'
FOR UPDATE;
```

Resultado:

```text
 id |   nombre   | precio
----+------------+---------
 10 | Muzzarella | 1050.00
(1 fila)
```

La Sesión A mantuvo la transacción abierta, por lo que el bloqueo sobre esa fila permaneció activo.

#### Sesión B

En una segunda conexión simultánea se abrió otra transacción:

```sql
BEGIN;
```

Luego se intentó obtener un bloqueo `FOR UPDATE` sobre exactamente la misma fila:

```sql
SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella'
FOR UPDATE;
```

En este punto la Sesión B no devolvió inmediatamente ningún resultado.

La consulta quedó esperando porque la fila ya se encontraba bloqueada por la transacción de la Sesión A.

#### Liberación del bloqueo

Mientras la Sesión B continuaba esperando, en la Sesión A se ejecutó:

```sql
COMMIT;
```

Resultado en la Sesión A:

```text
COMMIT
```

Inmediatamente después del `COMMIT` de la Sesión A, la consulta que estaba esperando en la Sesión B se destrabó y devolvió:

```text
 id |   nombre   | precio
----+------------+---------
 10 | Muzzarella | 1050.00
(1 fila)
```

Finalmente, la transacción de la Sesión B se cerró mediante:

```sql
ROLLBACK;
```

Resultado:

```text
ROLLBACK
```

No se modificó ningún dato durante el experimento.

---

### Qué se observó

La Sesión A obtuvo primero un bloqueo sobre la fila correspondiente a `Muzzarella` utilizando `SELECT ... FOR UPDATE`.

Cuando la Sesión B intentó ejecutar otro `SELECT ... FOR UPDATE` sobre la misma fila, PostgreSQL no devolvió un error ni permitió inmediatamente el acceso exclusivo.

En cambio, la Sesión B quedó esperando.

La espera continuó mientras la transacción de la Sesión A permaneció abierta.

Cuando la Sesión A ejecutó `COMMIT`, el bloqueo fue liberado y la Sesión B pudo obtener inmediatamente el bloqueo solicitado y devolver la fila.

Esto demostró que dos transacciones no pueden mantener simultáneamente un bloqueo `FOR UPDATE` incompatible sobre la misma fila.

---

### Explicación de la IA

Herramienta: OpenCode  
Modelo: `MiMo V2.5 Free`

> Explicación del experimento
>
> 1. Tipo de bloqueo de SELECT ... FOR UPDATE
>
> Obtiene un bloqueo de exclusión a nivel de fila (ROW EXCLUSIVE / FOR UPDATE). Marca la fila con un bit de bloqueo en la estructura de control de locks de PostgreSQL. Otros procesos pueden seguir leyendo la fila (sin FOR UPDATE), pero cualquier intento de modificar o bloquear la misma fila para escritura quedará en espera hasta que el titular libere el bloqueo.
>
> 2. Por qué la Sesión B quedó esperando
>
> Ambas sesiones intentaron adquirir FOR UPDATE sobre la misma fila (nombre = 'Muzzarella'). La Sesión A ya tenía el bloqueo otorgado y su transacción estaba abierta (sin COMMIT ni ROLLBACK). La Sesión B solicitó el mismo bloqueo de exclusión sobre esa fila. Como dos bloqueos FOR UPDATE son incompatibles entre sí, PostgreSQL puso a la Sesión B en estado de espera (wait) hasta que el bloqueo fuera liberado.
>
> 3. Por qué la espera terminó con COMMIT
>
> COMMIT finaliza la transacción de la Sesión A y libera todos los bloqueos que esa transacción poseía. Inmediatamente, el gestor de bloqueos de PostgreSQL otorga el bloqueo solicitado a la Sesión B, que estaba en la cola de espera. La Sesión B se desbloquea y obtiene la fila.
>
> 4. Qué habría ocurrido con ROLLBACK
>
> El mismo efecto: liberación del bloqueo. ROLLBACK también finaliza la transacción y libera todos sus bloqueos. La Sesión B se habría desbloqueado de la misma forma. No hay diferencia en el resultado de la espera entre COMMIT y ROLLBACK — ambos terminan la transacción propietaria y sueltan los locks.
>
> 5. Mecanismo subyacente
>
> El gestor de bloqueos de PostgreSQL (Lock Manager). Cada bloqueo se registra en una tabla hash en memoria compartida (LOCKTAG). Cuando un proceso solicita un bloqueo incompatible, el Lock Manager verifica si el bloqueo ya está otorgado a otro BackendId. Si es incompatible, el proceso se duerme (WaitOnLock) y se agrega a una cola de espera associada al LOCKTAG. Cuando el propietario libera el bloqueo (por COMMIT o ROLLBACK), el Lock Manager despierta al siguiente proceso en la cola y le otorga el bloqueo.
>
> Este mecanismo es independiente de MVCC. MVCC maneja la visibilidad de versiones de filas para lecturas. FOR UPDATE actúa sobre la misma versión de la fila, bloqueando la fila física para escritura. Coexisten: MVCC permite lecturas sin bloquear, y el Lock Manager coordina escrituras concurrentes sobre la misma fila.

#### Observaciones sobre la explicación de la IA

La explicación de OpenCode coincidió con el comportamiento observado en PostgreSQL:

- la Sesión A obtuvo primero el bloqueo sobre la fila de `Muzzarella`;
- la Sesión B quedó esperando cuando intentó ejecutar otro `SELECT ... FOR UPDATE`;
- la espera terminó inmediatamente cuando la Sesión A ejecutó `COMMIT`;
- un `ROLLBACK` de la Sesión A también habría liberado el bloqueo.

Se detectó una simplificación terminológica en la frase `ROW EXCLUSIVE / FOR UPDATE`: `FOR UPDATE` representa un bloqueo de fila asociado a esa operación, mientras que `ROW EXCLUSIVE` es también el nombre de un modo de bloqueo de tabla en PostgreSQL. Para este laboratorio, lo importante y verificado en el motor es que la fila seleccionada quedó protegida frente a otro `FOR UPDATE` incompatible.

También se toma como una simplificación la descripción de que el bloqueo de fila se guarda simplemente como un “bit” en la tabla de locks. PostgreSQL representa los bloqueos de tuplas y las esperas mediante mecanismos internos más complejos; para este TP alcanza con verificar experimentalmente que el segundo `FOR UPDATE` quedó bloqueado hasta finalizar la primera transacción.

La explicación sobre la coordinación entre MVCC y los mecanismos de bloqueo también resultó consistente con lo observado: una lectura común podría continuar, pero otra operación que intentara bloquear la misma fila para actualización debía esperar.

---

### Verificación en el motor

El comportamiento fue comprobado directamente sobre PostgreSQL 17.11 utilizando dos sesiones concurrentes sobre `foodstore_tp2`.

La secuencia observada fue:

1. La Sesión A inició una transacción.
2. La Sesión A ejecutó `SELECT ... FOR UPDATE` sobre `Muzzarella`.
3. PostgreSQL devolvió la fila a la Sesión A y mantuvo el bloqueo mientras la transacción permanecía abierta.
4. La Sesión B inició otra transacción.
5. La Sesión B ejecutó el mismo `SELECT ... FOR UPDATE` sobre `Muzzarella`.
6. La Sesión B quedó esperando y no recibió inmediatamente ningún resultado.
7. La Sesión A ejecutó `COMMIT`.
8. Inmediatamente después, la Sesión B dejó de esperar y PostgreSQL devolvió la fila solicitada.
9. La Sesión B finalizó mediante `ROLLBACK`.

La espera observada en la Sesión B terminó exactamente cuando la Sesión A liberó su bloqueo mediante `COMMIT`.

---

### Conclusión

El experimento confirmó que `SELECT ... FOR UPDATE` obtiene un bloqueo de fila destinado a proteger registros que una transacción pretende actualizar o manipular de forma exclusiva.

Cuando otra transacción solicita un bloqueo incompatible sobre la misma fila, PostgreSQL la deja esperando en lugar de permitir que ambas transacciones obtengan simultáneamente el mismo tipo de bloqueo.

El bloqueo se mantiene hasta que la transacción propietaria finaliza mediante `COMMIT` o `ROLLBACK`.

En este caso, la Sesión B permaneció bloqueada mientras la Sesión A mantuvo abierta su transacción y pudo continuar inmediatamente después del `COMMIT` de la Sesión A.

El experimento no modificó datos y la Sesión B finalizó con `ROLLBACK`.
