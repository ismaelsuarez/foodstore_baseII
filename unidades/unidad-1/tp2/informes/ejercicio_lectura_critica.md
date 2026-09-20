# Ejercicio de lectura crítica — Parte 3

## Script 1 — Baja de funciones de películas retiradas de cartel

### Script original

```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE;
```

### Qué haría realmente

El `UPDATE` no contiene ninguna cláusula `WHERE`.

Por lo tanto, PostgreSQL actualizaría **todas las filas de la tabla `funcion`**, estableciendo:

```text
activa = FALSE
```

para cada una de ellas.

No importa si una función corresponde a una película retirada de cartel o a una película que todavía se encuentra disponible.

El efecto real sería desactivar todas las funciones registradas en la tabla.

### Por qué no coincide con la consigna

La intención indicada en el comentario es:

> dar de baja las funciones de películas retiradas de cartel

Sin embargo, el script no contiene ninguna condición que permita distinguir las funciones correspondientes a películas retiradas de las demás.

El problema no es de sintaxis: el SQL es válido y PostgreSQL podría ejecutarlo correctamente.

El problema es lógico y potencialmente destructivo, porque una sentencia `UPDATE` sin `WHERE` afecta todas las filas de la tabla.

### Versión corregida

La corrección debe incluir una cláusula `WHERE` que limite la actualización exclusivamente a las funciones de las películas identificadas como retiradas.

Por ejemplo, si el esquema genérico dispone de una tabla `pelicula` y de un atributo booleano `retirada`, una posible versión sería:

```sql
UPDATE funcion
SET activa = FALSE
WHERE pelicula_id IN (
    SELECT id
    FROM pelicula
    WHERE retirada = TRUE
);
```

Esta versión únicamente modifica las funciones cuya película asociada está marcada como retirada.

### Aclaración sobre el esquema

La guía entregada no especifica en este ejercicio el nombre exacto del atributo utilizado por el esquema genérico para representar que una película fue retirada de cartel.

Por ese motivo, `retirada` se utiliza aquí como nombre ilustrativo de la condición de negocio.

En una aplicación real, antes de ejecutar el script se debe revisar el esquema concreto y sustituir esa condición por la columna o criterio real correspondiente.

### Riesgo identificado

El riesgo principal del script original es ejecutar una operación masiva válida sintácticamente pero incorrecta desde el punto de vista del negocio.

Antes de ejecutar un `UPDATE`, especialmente uno generado por IA, debe comprobarse siempre:

- qué tabla se modifica;
- qué columnas se actualizan;
- si existe una cláusula `WHERE`;
- qué filas cumplen esa condición;
- y si el conjunto afectado coincide realmente con la intención declarada.

Una verificación previa segura podría hacerse primero con un `SELECT` utilizando exactamente la misma condición:

```sql
SELECT *
FROM funcion
WHERE pelicula_id IN (
    SELECT id
    FROM pelicula
    WHERE retirada = TRUE
);
```

Solo después de revisar las filas resultantes tendría sentido considerar el `UPDATE`.


## Script 2 — Limpieza de categorías sin productos asociados

### Script original

```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (
    SELECT categoria_id
    FROM producto
);
```

### Qué haría realmente

La intención aparente es eliminar las categorías que no estén siendo utilizadas por ningún producto.

Sin embargo, el uso de `NOT IN` puede producir un resultado inesperado si la subconsulta devuelve algún valor `NULL`.

En SQL, una comparación contra `NULL` no devuelve `TRUE` ni `FALSE`, sino `UNKNOWN`.

Por ejemplo, si la subconsulta devuelve:

```text
1
2
NULL
```

entonces una condición como:

```sql
3 NOT IN (1, 2, NULL)
```

no se evalúa como verdadera.

La presencia de al menos un `NULL` en el resultado de la subconsulta puede hacer que la condición `NOT IN` evalúe como `UNKNOWN` para categorías que no coinciden con ninguno de los valores no nulos. Como un `DELETE` solo afecta filas cuya condición `WHERE` evalúa como `TRUE`, categorías que deberían identificarse como no asociadas pueden no ser eliminadas.

### Por qué no coincide de forma segura con la consigna

La consigna pretende identificar categorías sin productos asociados.

El problema del script original es que depende de que `producto.categoria_id` nunca contenga `NULL`.

Si esa condición no está garantizada por el esquema, el comportamiento de `NOT IN` puede no coincidir con la intención declarada.

Por lo tanto, aunque el SQL sea sintácticamente correcto, su resultado puede ser incorrecto desde el punto de vista lógico.

### Versión corregida recomendada

Una forma más segura es utilizar `NOT EXISTS`:

```sql
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto p
    WHERE p.categoria_id = c.id
);
```

Esta versión evalúa cada categoría y elimina únicamente aquellas para las que no existe ningún producto relacionado.

El comportamiento no queda afectado por la presencia de valores `NULL` en otras filas de `producto.categoria_id`.

### Alternativa manteniendo NOT IN

Si se quisiera conservar `NOT IN`, sería necesario excluir explícitamente los valores `NULL`:

```sql
DELETE FROM categoria
WHERE id NOT IN (
    SELECT categoria_id
    FROM producto
    WHERE categoria_id IS NOT NULL
);
```

Esta versión evita que un `NULL` dentro de la subconsulta vuelva indeterminada toda la comparación.

Sin embargo, `NOT EXISTS` expresa de forma más directa la intención de buscar categorías sin productos asociados.

### Verificación previa antes de eliminar

Antes de ejecutar el `DELETE`, conviene verificar qué categorías serían afectadas utilizando primero un `SELECT` con la misma condición:

```sql
SELECT c.*
FROM categoria c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto p
    WHERE p.categoria_id = c.id
);
```

Esto permite inspeccionar las filas candidatas antes de realizar una operación destructiva.

### Relación con el proyecto Food Store

En nuestro esquema actual de Food Store, `producto.categoria_id` está definido como:

```sql
categoria_id BIGINT NOT NULL
```

Por lo tanto, en nuestro esquema particular la subconsulta no debería producir `NULL` en esa columna.

Sin embargo, el ejercicio de la guía utiliza un esquema genérico y pide analizar específicamente el riesgo del manejo de `NULL`.

Por ese motivo, la corrección con `NOT EXISTS` sigue siendo la alternativa más robusta y defendible para este ejercicio.

### Riesgo identificado

El riesgo del script original no está en la sintaxis sino en la semántica de tres valores de SQL:

- `TRUE`
- `FALSE`
- `UNKNOWN`

Cuando interviene `NULL`, una condición con `NOT IN` puede producir `UNKNOWN` y evitar que se eliminen filas que conceptualmente deberían cumplir la condición.

La lectura crítica del script debe considerar no solo si una sentencia es válida, sino también cómo se comporta frente a valores nulos y casos límite.

