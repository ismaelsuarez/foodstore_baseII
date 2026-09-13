# DUIA — Parte 2: Laboratorio de concurrencia

## Herramienta utilizada

OpenCode

Modelo configurado:

`MiMo V2.5 Free`

Motor utilizado para la verificación:

`PostgreSQL 17.11`

Base de laboratorio:

`foodstore_tp2`

## Objetivo del uso de IA

OpenCode fue utilizado para explicar técnicamente los fenómenos de concurrencia reproducidos previamente en PostgreSQL.

La IA no ejecutó los experimentos, no modificó archivos, no se conectó a PostgreSQL y no realizó commits.

Los experimentos fueron realizados manualmente mediante dos sesiones simultáneas de `psql`.

Para cada escenario se siguió el mismo criterio:

1. reproducir primero el fenómeno en PostgreSQL;
2. registrar los comandos y resultados reales;
3. pedir a OpenCode una explicación técnica;
4. conservar la explicación entregada por la IA;
5. contrastarla contra el comportamiento real observado en PostgreSQL;
6. documentar coincidencias, imprecisiones o discrepancias.

---

## Escenario 1 — Lectura no repetible

### Prompt utilizado

El prompt enviado a OpenCode fue:

> Explicá el siguiente experimento de concurrencia realizado sobre PostgreSQL 17.11 y la base `foodstore_tp2`.
>
> Escenario: lectura no repetible sobre `producto.precio`.
>
> Prueba 1 — READ COMMITTED
>
> Sesión A:
>
> BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
>
> SELECT id, nombre, precio
> FROM producto
> WHERE nombre = 'Muzzarella';
>
> Resultado inicial:
> precio = 1050.00
>
> Sesión B:
>
> BEGIN;
>
> UPDATE producto
> SET precio = 1200.00
> WHERE nombre = 'Muzzarella';
>
> COMMIT;
>
> Sesión A, dentro de la misma transacción:
>
> SELECT id, nombre, precio
> FROM producto
> WHERE nombre = 'Muzzarella';
>
> Resultado:
> precio = 1200.00
>
> Prueba 2 — REPEATABLE READ
>
> Se restauró previamente el precio a 1050.00.
>
> Sesión A:
>
> BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
>
> SELECT id, nombre, precio
> FROM producto
> WHERE nombre = 'Muzzarella';
>
> Resultado inicial:
> precio = 1050.00
>
> Sesión B:
>
> BEGIN;
>
> UPDATE producto
> SET precio = 1200.00
> WHERE nombre = 'Muzzarella';
>
> COMMIT;
>
> Sesión A, dentro de la misma transacción:
>
> SELECT id, nombre, precio
> FROM producto
> WHERE nombre = 'Muzzarella';
>
> Resultado:
> precio = 1050.00
>
> Necesito que expliques:
>
> 1. Qué fenómeno de concurrencia ocurrió en READ COMMITTED.
> 2. Por qué la segunda lectura de la Sesión A cambió de 1050.00 a 1200.00.
> 3. Por qué con REPEATABLE READ la Sesión A continuó viendo 1050.00.
> 4. Qué nivel de aislamiento evita este problema en PostgreSQL.
> 5. Qué papel cumple MVCC en este comportamiento.
>
> No modifiques archivos.
> No ejecutes SQL.
> No te conectes a PostgreSQL.
> No hagas commits.
>
> Respondé únicamente con la explicación técnica del fenómeno.

### Qué generó la IA

OpenCode identificó correctamente el fenómeno como una lectura no repetible.

Explicó que bajo `READ COMMITTED` PostgreSQL utiliza un snapshot por sentencia, por lo que la segunda consulta de la Sesión A pudo observar el valor `1200.00` confirmado por la Sesión B.

También explicó que `REPEATABLE READ` mantiene un snapshot estable durante la transacción y que por ese motivo la Sesión A continuó observando `1050.00`.

La explicación relacionó este comportamiento con MVCC y con la visibilidad de diferentes versiones de las filas.

### Verificación realizada

La explicación fue verificada directamente en PostgreSQL.

Bajo `READ COMMITTED`:

- primera lectura: `1050.00`;
- la Sesión B modificó el precio a `1200.00`;
- la Sesión B ejecutó `COMMIT`;
- segunda lectura en la misma transacción de la Sesión A: `1200.00`.

Bajo `REPEATABLE READ`:

- primera lectura: `1050.00`;
- la Sesión B modificó el precio a `1200.00`;
- la Sesión B ejecutó `COMMIT`;
- segunda lectura en la misma transacción de la Sesión A: `1050.00`.

La explicación principal de OpenCode quedó confirmada por el motor.

---

## Escenario 2 — Lectura fantasma

### Prompt utilizado

El prompt enviado a OpenCode fue:

> Explicá el siguiente experimento de concurrencia realizado sobre PostgreSQL 17.11 y la base `foodstore_tp2`.
>
> Escenario: lectura fantasma sobre la tabla `pedido`.
>
> Prueba 1 — READ COMMITTED
>
> Sesión A:
>
> BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
>
> SELECT COUNT(*) AS pedidos_ana
> FROM pedido p
> JOIN cliente c ON c.id = p.cliente_id
> WHERE c.email = 'ana.gomez@foodstore.test';
>
> Resultado inicial:
> COUNT(*) = 2
>
> Sesión B:
>
> BEGIN;
>
> INSERT INTO pedido (cliente_id, fecha, forma_pago)
> VALUES (
>     (SELECT id FROM cliente WHERE email = 'ana.gomez@foodstore.test'),
>     '2026-09-12 23:15:00-03',
>     'EFECTIVO'
> );
>
> COMMIT;
>
> Sesión A, dentro de la misma transacción:
>
> SELECT COUNT(*) AS pedidos_ana
> FROM pedido p
> JOIN cliente c ON c.id = p.cliente_id
> WHERE c.email = 'ana.gomez@foodstore.test';
>
> Resultado:
> COUNT(*) = 3
>
> Prueba 2 — REPEATABLE READ
>
> Se restauraron previamente los datos originales.
>
> Sesión A:
>
> BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
>
> SELECT COUNT(*) AS pedidos_ana
> FROM pedido p
> JOIN cliente c ON c.id = p.cliente_id
> WHERE c.email = 'ana.gomez@foodstore.test';
>
> Resultado inicial:
> COUNT(*) = 2
>
> Sesión B:
>
> BEGIN;
>
> INSERT INTO pedido (cliente_id, fecha, forma_pago)
> VALUES (
>     (SELECT id FROM cliente WHERE email = 'ana.gomez@foodstore.test'),
>     '2026-09-12 23:25:00-03',
>     'EFECTIVO'
> );
>
> COMMIT;
>
> Sesión A, dentro de la misma transacción:
>
> SELECT COUNT(*) AS pedidos_ana
> FROM pedido p
> JOIN cliente c ON c.id = p.cliente_id
> WHERE c.email = 'ana.gomez@foodstore.test';
>
> Resultado:
> COUNT(*) = 2
>
> Necesito que expliques:
>
> 1. Qué fenómeno de concurrencia ocurrió en READ COMMITTED.
> 2. Por qué el COUNT cambió de 2 a 3.
> 3. Por qué con REPEATABLE READ el COUNT se mantuvo en 2.
> 4. Qué nivel de aislamiento evita este problema en PostgreSQL.
> 5. Qué papel cumple MVCC en este comportamiento.
>
> No modifiques archivos.
> No ejecutes SQL.
> No te conectes a PostgreSQL.
> No hagas commits.
>
> Respondé únicamente con la explicación técnica del fenómeno.

### Qué generó la IA

OpenCode identificó el escenario como una lectura fantasma.

Explicó que bajo `READ COMMITTED` cada sentencia obtiene un snapshot nuevo, por lo que el segundo `COUNT(*)` pudo observar el nuevo pedido confirmado por la Sesión B.

También indicó que bajo `REPEATABLE READ` el snapshot se mantiene estable y la fila insertada posteriormente por la Sesión B no resulta visible dentro de la transacción de la Sesión A.

La explicación relacionó el comportamiento con MVCC y los identificadores internos de las versiones de fila.

### Qué se modificó o cuestionó

Se detectó una imprecisión en la explicación de OpenCode.

La IA afirmó que `SERIALIZABLE` era el único nivel de PostgreSQL que protege contra lecturas fantasma.

Sin embargo, el experimento realizado directamente en PostgreSQL 17.11 mostró que bajo `REPEATABLE READ` el segundo `COUNT(*)` permaneció en `2`, aun después de que la Sesión B insertó y confirmó una tercera fila.

Por lo tanto, para el escenario reproducido, `REPEATABLE READ` también evitó que apareciera la fila fantasma debido al snapshot estable de la transacción.

`SERIALIZABLE` proporciona garantías adicionales de serializabilidad y protege frente a otras anomalías que todavía pueden existir bajo `REPEATABLE READ`, pero la afirmación original de la IA fue considerada demasiado absoluta.

También aparecieron en la respuesta de OpenCode dos fragmentos de texto extraños (`另一事务` y `新增`). Se conservaron literalmente en `informe_concurrencia.md`, tal como exige la consigna, y se interpretaron como artefactos de generación del modelo.

### Verificación realizada

Bajo `READ COMMITTED`:

- primer `COUNT(*)`: `2`;
- la Sesión B insertó un nuevo pedido;
- la Sesión B ejecutó `COMMIT`;
- segundo `COUNT(*)` en la misma transacción de la Sesión A: `3`.

Bajo `REPEATABLE READ`:

- primer `COUNT(*)`: `2`;
- la Sesión B insertó un nuevo pedido;
- la Sesión B ejecutó `COMMIT`;
- segundo `COUNT(*)`: `2`.

Los pedidos creados específicamente para los experimentos (`id = 21` e `id = 22`) fueron eliminados al finalizar cada prueba.

La base quedó restaurada a su estado original.

---

## Escenario 3 — Espera por bloqueo con SELECT FOR UPDATE

### Prompt utilizado

El prompt enviado a OpenCode fue:

> Explicá el siguiente experimento de concurrencia realizado sobre PostgreSQL 17.11 y la base `foodstore_tp2`.
>
> Escenario: espera por bloqueo usando SELECT ... FOR UPDATE sobre la tabla `producto`.
>
> Sesión A:
>
> BEGIN;
>
> SELECT id, nombre, precio
> FROM producto
> WHERE nombre = 'Muzzarella'
> FOR UPDATE;
>
> Resultado:
> id = 10
> nombre = Muzzarella
> precio = 1050.00
>
> La Sesión A mantuvo la transacción abierta.
>
> Sesión B:
>
> BEGIN;
>
> SELECT id, nombre, precio
> FROM producto
> WHERE nombre = 'Muzzarella'
> FOR UPDATE;
>
> La Sesión B quedó esperando y no devolvió resultados inmediatamente.
>
> Mientras la Sesión B seguía esperando, la Sesión A ejecutó:
>
> COMMIT;
>
> Inmediatamente después, la Sesión B se destrabó y devolvió la fila de Muzzarella.
>
> Luego la Sesión B finalizó con:
>
> ROLLBACK;
>
> Necesito que expliques:
>
> 1. Qué tipo de bloqueo obtiene SELECT ... FOR UPDATE.
> 2. Por qué la Sesión B quedó esperando.
> 3. Por qué la espera terminó cuando la Sesión A hizo COMMIT.
> 4. Qué habría ocurrido si la Sesión A hubiera hecho ROLLBACK en lugar de COMMIT.
> 5. Qué mecanismo de PostgreSQL está actuando en este caso y cómo se relaciona con la concurrencia.
>
> No modifiques archivos.
> No ejecutes SQL.
> No te conectes a PostgreSQL.
> No hagas commits.
>
> Respondé únicamente con la explicación técnica del fenómeno.

### Qué generó la IA

OpenCode explicó que `SELECT ... FOR UPDATE` obtiene un bloqueo sobre la fila seleccionada y que otro intento incompatible sobre la misma fila debe esperar mientras la primera transacción siga abierta.

También explicó que tanto `COMMIT` como `ROLLBACK` finalizan la transacción y liberan los bloqueos mantenidos por ella.

Relacionó el comportamiento con el gestor de bloqueos de PostgreSQL y distinguió ese mecanismo de la visibilidad de versiones proporcionada por MVCC.

### Qué se modificó o cuestionó

Se detectaron simplificaciones terminológicas en la respuesta de OpenCode.

La expresión:

`ROW EXCLUSIVE / FOR UPDATE`

puede generar confusión, ya que `ROW EXCLUSIVE` también es el nombre de un modo de bloqueo de tabla de PostgreSQL, mientras que `SELECT ... FOR UPDATE` establece bloqueo sobre las filas seleccionadas.

También se consideró una simplificación la afirmación de que el bloqueo de fila queda representado simplemente mediante un “bit” en una tabla de locks.

PostgreSQL utiliza mecanismos internos más complejos para representar bloqueos de tuplas y procesos en espera.

Estas imprecisiones no afectaron la explicación principal del fenómeno y fueron documentadas en `informe_concurrencia.md`.

### Verificación realizada

La prueba real se ejecutó con dos sesiones concurrentes.

Sesión A:

```sql
BEGIN;

SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella'
FOR UPDATE;
```

La fila fue devuelta inmediatamente y la transacción quedó abierta.

Sesión B:

```sql
BEGIN;

SELECT id, nombre, precio
FROM producto
WHERE nombre = 'Muzzarella'
FOR UPDATE;
```

La Sesión B quedó esperando sin devolver resultados.

Mientras la Sesión B permanecía bloqueada, la Sesión A ejecutó:

```sql
COMMIT;
```

Inmediatamente después:

- la Sesión B dejó de esperar;
- PostgreSQL devolvió la fila de `Muzzarella`;
- la Sesión B obtuvo el bloqueo solicitado.

Finalmente la Sesión B ejecutó:

```sql
ROLLBACK;
```

No se modificaron datos durante este escenario.

---

## Resultado general de la Parte 2

Los tres escenarios seleccionados para cumplir el mínimo exigido fueron reproducidos directamente en PostgreSQL 17.11:

1. Lectura no repetible.
2. Lectura fantasma.
3. Espera por bloqueo mediante `SELECT ... FOR UPDATE`.

Las explicaciones proporcionadas por OpenCode fueron utilizadas como hipótesis técnicas y posteriormente contrastadas con el comportamiento real del motor.

Cuando la explicación de la IA coincidió con PostgreSQL, se dejó constancia de esa confirmación.

Cuando se detectaron afirmaciones demasiado absolutas, simplificaciones terminológicas o artefactos de texto, se documentaron explícitamente en lugar de descartarlos u ocultarlos.

El criterio utilizado durante toda la práctica fue que la evidencia obtenida directamente de PostgreSQL prevalece sobre la explicación generada por la IA.
