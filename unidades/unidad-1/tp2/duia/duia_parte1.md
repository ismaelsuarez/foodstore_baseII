# DUIA — Parte 1: Integridad versionada

## Herramienta utilizada

OpenCode

Modelo configurado:

`MiMo V2.5 Free`

Uso realizado:

Se utilizó OpenCode primero en modo Plan para proponer una implementación de restricciones de integridad sobre `detalle_pedido`, y luego en modo Build únicamente después de revisar y corregir el plan propuesto.
## Spec o prompt utilizado

Antes de utilizar OpenCode se creó el archivo `spec_restricciones.md` con las siguientes reglas:

### Regla 1 — Cantidad válida en detalle de pedido

La columna `detalle_pedido.cantidad` debe aceptar únicamente valores mayores que cero.

No deben permitirse valores iguales a cero ni cantidades negativas.

### Regla 2 — Precio unitario válido en detalle de pedido

La columna `detalle_pedido.precio_unitario` debe aceptar únicamente valores mayores o iguales a cero.

No deben permitirse precios unitarios negativos.

El primer prompt enviado a OpenCode en modo Plan fue:

> Revisá `spec_restricciones.md` y `schema.sql`.
>
> Necesito implementar las dos reglas de negocio definidas en la spec sobre la tabla `detalle_pedido`:
>
> 1. `detalle_pedido.cantidad` debe ser mayor que cero.
> 2. `detalle_pedido.precio_unitario` debe ser mayor o igual que cero.
>
> Estamos en modo Plan.
>
> No modifiques ningún archivo todavía.  
> No ejecutes SQL.  
> No hagas commits.
>
> Quiero que propongas el plan mínimo y seguro para implementar estas reglas, indicando:
>
> - qué archivo modificarías o crearías;
> - qué restricciones usarías;
> - los nombres exactos que proponés para las constraints;
> - cómo probarías casos válidos e inválidos;
> - cómo aplicarías el cambio primero dentro de una transacción sobre la base de laboratorio `foodstore_tp2`;
> - cualquier riesgo o consideración que deba revisar antes de pasar a modo Build.
>
> Respetá las convenciones definidas en `AGENTS.md` y `.kiro/steering/`.

### Prompts de revisión del Plan y ejecución Build

#### Corrección 1 del Plan

> Antes de pasar a Build, corregí el plan.
>
> Detecté estos problemas:
>
> 1. Los datos de prueba que propusiste no existen en este proyecto.  
> No existen:
> - juan.perez@email.com
> - Milanesa con fritas
> - Empanada
> - Agua
>
> Revisá `datos_iniciales.sql` y utilizá exclusivamente clientes, productos y pedidos que realmente existan en Food Store.
>
> 2. El procedimiento de prueba con varios INSERT inválidos dentro de un único BEGIN no es correcto para PostgreSQL:  
> después del primer error la transacción queda abortada y las pruebas siguientes no pueden continuar normalmente.
>
> Replanteá las pruebas usando una estrategia segura, por ejemplo SAVEPOINT/ROLLBACK TO SAVEPOINT o transacciones independientes, para poder verificar individualmente:
> - cantidad válida > 0;
> - cantidad = 0 rechazada;
> - cantidad negativa rechazada;
> - precio_unitario = 0 aceptado;
> - precio_unitario negativo rechazado.
>
> 3. No propongas DROP ni recreación destructiva de la base `foodstore_tp2`.  
> Si necesitás verificar una creación desde cero, proponé una base descartable separada o explicá una alternativa no destructiva.
>
> 4. No dependas de `currval('pedido_id_seq')` si no es necesario. Preferí identificar registros existentes mediante los datos reales del proyecto o una estrategia explícita y verificable.
>
> Seguimos en modo Plan.  
> No modifiques archivos.  
> No ejecutes SQL.  
> No hagas commits.
>
> Devolveme el plan corregido completo.

#### Corrección 2 del Plan

> Corregí una última vez el plan antes de pasar a Build.
>
> 1. Si `schema.sql` ya fue modificado con las nuevas CHECK constraints y luego se crea una base temporal desde ese archivo, no corresponde volver a aplicar las mismas constraints con ALTER TABLE porque ya existirán.
>
> Separá claramente:
> - prueba de creación desde cero con el schema nuevo en una base temporal descartable;
> - migración de la base existente `foodstore_tp2` mediante ALTER TABLE.
>
> 2. En `foodstore_tp2`, después de probar el ALTER y las verificaciones dentro de una transacción con ROLLBACK, falta el paso definitivo:
> - abrir una nueva transacción;
> - aplicar nuevamente las constraints;
> - verificar;
> - hacer COMMIT únicamente si todo es correcto.
>
> 3. Evitá crear pedidos nuevos y evitá `currval()` en los tests si podemos usar registros existentes del proyecto.
> Revisá `datos_iniciales.sql` y elegí una combinación real de pedido y producto que no exista todavía en `detalle_pedido`, identificando el pedido mediante cliente + fecha + forma_pago y el producto mediante nombre.
>
> 4. Mantené SAVEPOINT/ROLLBACK TO SAVEPOINT para las pruebas inválidas.
>
> Seguimos en modo Plan.
> No modifiques archivos.
> No ejecutes SQL.
> No hagas commits.
>
> Devolveme únicamente el plan final corregido.

#### Corrección 3 del Plan

> Hacé un último ajuste al plan para que el entregable de la Parte 1 quede explícitamente versionado.
>
> Además de actualizar `schema.sql` para que las instalaciones nuevas incluyan las dos CHECK constraints, creá un archivo dedicado:
>
> `restricciones_integridad.sql`
>
> Ese archivo debe contener solamente la migración necesaria para una base existente:
>
> ALTER TABLE detalle_pedido
>     ADD CONSTRAINT chk_detalle_pedido_cantidad CHECK (cantidad > 0),
>     ADD CONSTRAINT chk_detalle_pedido_precio_unitario CHECK (precio_unitario >= 0);
>
> No incluyas DROP.
> No ejecutes SQL.
> No hagas commits.
>
> La finalidad es que:
> - `schema.sql` represente el esquema definitivo desde cero;
> - `restricciones_integridad.sql` sea el script de restricciones entregable de esta Parte 1;
> - luego podamos revisar ambos con `git diff` y aplicar el segundo sobre `foodstore_tp2` dentro de una transacción.
>
> Seguimos en modo Plan.
> Devolveme únicamente el plan final ajustado.

#### Prompt de ejecución en modo Build

> Implementá únicamente los cambios aprobados en el Plan.
>
> 1. Modificá `schema.sql` para agregar dentro de `detalle_pedido`:
>
> - `chk_detalle_pedido_cantidad` con `CHECK (cantidad > 0)`
> - `chk_detalle_pedido_precio_unitario` con `CHECK (precio_unitario >= 0)`
>
> 2. Creá `restricciones_integridad.sql` con únicamente:
>
> ALTER TABLE detalle_pedido
>     ADD CONSTRAINT chk_detalle_pedido_cantidad CHECK (cantidad > 0),
>     ADD CONSTRAINT chk_detalle_pedido_precio_unitario CHECK (precio_unitario >= 0);
>
> Restricciones de esta ejecución:
>
> - No ejecutes SQL.
> - No te conectes a PostgreSQL.
> - No crees ni elimines bases de datos.
> - No hagas DROP.
> - No modifiques `datos_iniciales.sql`.
> - No modifiques `spec_restricciones.md`.
> - No hagas git add.
> - No hagas commits.
> - No modifiques ningún otro archivo.
>
> Solamente realizá esos dos cambios de archivos y al terminar informame qué modificaste.



## Qué generó la IA

OpenCode propuso inicialmente agregar dos restricciones `CHECK` sobre la tabla `detalle_pedido`:

- `chk_detalle_pedido_cantidad` con `CHECK (cantidad > 0)`.
- `chk_detalle_pedido_precio_unitario` con `CHECK (precio_unitario >= 0)`.

Durante la revisión del modo Plan se detectaron y corrigieron varias propuestas antes de permitir modificaciones:

- Se descartaron datos de prueba inventados que no existían en el proyecto.
- Se corrigió la estrategia de pruebas porque un error dentro de una transacción PostgreSQL deja la transacción abortada.
- Se adoptó el uso de `SAVEPOINT` y `ROLLBACK TO SAVEPOINT` para aislar pruebas válidas e inválidas.
- Se evitó depender de `currval()` y de IDs fijos cuando podía utilizarse una combinación real de pedido y producto existente en el proyecto.
- Se separó la verificación desde cero del esquema de la migración de la base existente.
- Se eliminó del plan cualquier recreación destructiva de `foodstore_tp2`.
- Se agregó un script dedicado, `restricciones_integridad.sql`, para que la migración de la Parte 1 quedara explícitamente versionada.

Finalmente, en modo Build, OpenCode realizó únicamente estos cambios:

1. Modificó `schema.sql` para incluir las dos restricciones `CHECK` dentro de `CREATE TABLE detalle_pedido`.
2. Creó `restricciones_integridad.sql` con el `ALTER TABLE` necesario para aplicar las mismas restricciones sobre una base ya existente.

OpenCode no ejecutó SQL, no se conectó a PostgreSQL y no realizó commits durante la fase Build.

## Qué se aceptó

Se aceptó la solución basada en restricciones declarativas `CHECK`, porque las dos reglas corresponden directamente a validaciones simples sobre valores de columnas y no requieren triggers.

Se aceptaron los siguientes nombres y expresiones:

- `chk_detalle_pedido_cantidad` → `CHECK (cantidad > 0)`
- `chk_detalle_pedido_precio_unitario` → `CHECK (precio_unitario >= 0)`

También se aceptó:

- actualizar `schema.sql` para que una instalación nueva incluya las restricciones desde el inicio;
- crear `restricciones_integridad.sql` para aplicar la migración sobre una base existente;
- utilizar `SAVEPOINT` y `ROLLBACK TO SAVEPOINT` para probar casos inválidos sin perder toda la transacción.

## Qué se modificó o descartó, y por qué

Durante la revisión del Plan se descartaron varias propuestas iniciales de OpenCode:

- Datos de prueba inexistentes como `juan.perez@email.com`, `Milanesa con fritas`, `Empanada` y `Agua`, porque no pertenecían al conjunto real de datos del proyecto.
- La ejecución de varios `INSERT` inválidos consecutivos dentro de una única transacción sin recuperación, porque PostgreSQL deja la transacción abortada después del primer error.
- El uso innecesario de `currval('pedido_id_seq')`, porque se podían identificar pedidos existentes mediante datos reales del proyecto.
- La propuesta de realizar recreaciones destructivas mediante `DROP` sobre la base de laboratorio, porque el protocolo de seguridad exige evitar operaciones destructivas innecesarias.
- La aplicación redundante de `ALTER TABLE` sobre una base temporal creada desde un `schema.sql` que ya contenía las restricciones.

Las pruebas fueron reformuladas usando registros reales y una combinación pedido-producto que no existía previamente: pedido de Ana Gómez del `2026-03-01`, forma de pago `EFECTIVO`, con el producto `Napolitana`.

## Verificación realizada

La implementación fue verificada sobre PostgreSQL 17.11 utilizando la base de laboratorio `foodstore_tp2`.

Primero se comprobó que los datos existentes no violaran las nuevas reglas mediante:

```sql
SELECT *
FROM detalle_pedido
WHERE cantidad <= 0
   OR precio_unitario < 0;
```

Resultado: `0 filas`.

Luego se aplicó `restricciones_integridad.sql` dentro de una transacción de prueba:

```sql
BEGIN;

\i restricciones_integridad.sql
```

Se verificó con `\d detalle_pedido` que las dos constraints estuvieran activas:

- `chk_detalle_pedido_cantidad`
- `chk_detalle_pedido_precio_unitario`

Después se realizaron pruebas usando `SAVEPOINT` y `ROLLBACK TO SAVEPOINT`:

- `cantidad = 2` → aceptada.
- `cantidad = 0` → rechazada por `chk_detalle_pedido_cantidad`.
- `cantidad = -1` → rechazada por `chk_detalle_pedido_cantidad`.
- `precio_unitario = 0.00` → aceptado.
- `precio_unitario = -10.00` → rechazado por `chk_detalle_pedido_precio_unitario`.

La primera ejecución completa terminó con:

```sql
ROLLBACK;
```

Esto permitió confirmar que todos los cambios podían deshacerse correctamente antes de aplicar la modificación definitiva.

Después se verificó el `schema.sql` modificado desde cero sobre una base temporal descartable llamada `foodstore_tp2_test`.

En esa base se ejecutaron correctamente:

- `schema.sql`
- `datos_iniciales.sql`

Los conteos obtenidos fueron:

- 2 categorías
- 3 clientes
- 3 productos
- 5 pedidos
- 7 detalles de pedido

También se verificó con `\d detalle_pedido` que las dos restricciones `CHECK` quedaran creadas correctamente desde el esquema nuevo.

Finalmente se volvió a aplicar `restricciones_integridad.sql` sobre `foodstore_tp2` dentro de una nueva transacción.

Antes de confirmar se repitieron verificaciones válidas e inválidas con `SAVEPOINT`:

- un `INSERT` válido con `cantidad = 2` fue aceptado;
- un `INSERT` con `cantidad = 0` fue rechazado por `chk_detalle_pedido_cantidad`;
- un `INSERT` con `precio_unitario = -10.00` fue rechazado por `chk_detalle_pedido_precio_unitario`.

Después de recuperar la transacción mediante `ROLLBACK TO SAVEPOINT` en los casos inválidos, y al comprobar que todo funcionaba como se esperaba, se ejecutó:

```sql
COMMIT;
```

Después del `COMMIT`, el comando:

```sql
\d detalle_pedido
```

confirmó que ambas restricciones quedaron persistidas en la base de laboratorio `foodstore_tp2`.


