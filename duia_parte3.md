# DUIA — Parte 3: Lectura crítica de scripts peligrosos

## Herramienta utilizada

ChatGPT

## Objetivo del uso de IA

La IA fue utilizada como apoyo para analizar críticamente dos scripts SQL entregados en la consigna de la Parte 3.

El objetivo no fue ejecutar los scripts, sino identificar:

- qué efecto real produciría cada sentencia;
- qué riesgo lógico contenía;
- por qué el comportamiento no coincidía de forma segura con la intención declarada;
- y cómo podría corregirse el script.

Ninguno de los dos scripts originales fue ejecutado sobre la base de datos.

---

## Script 1 — UPDATE sin WHERE

### Script analizado

```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE;
```

### Prompt / consulta utilizada

Se solicitó analizar el script antes de ejecutarlo, explicando:

- qué filas afectaría realmente;
- por qué no cumple correctamente la intención declarada;
- qué riesgo representa un `UPDATE` sin `WHERE`;
- y cómo podría reescribirse de forma segura.

### Qué generó la IA

La IA identificó que el script es sintácticamente válido, pero que al no contener una cláusula `WHERE` modifica todas las filas de la tabla `funcion`.

Por lo tanto, todas las funciones quedarían con:

```text
activa = FALSE
```

sin distinguir si corresponden a películas retiradas de cartel o a películas todavía disponibles.

La IA propuso que la corrección debe incorporar una condición explícita que limite las filas afectadas.

Como la consigna no proporciona el nombre exacto de la columna que representa que una película fue retirada de cartel, se utilizó una condición ilustrativa basada en un atributo `retirada`.

Ejemplo propuesto:

```sql
UPDATE funcion
SET activa = FALSE
WHERE pelicula_id IN (
    SELECT id
    FROM pelicula
    WHERE retirada = TRUE
);
```

### Qué se aceptó

Se aceptó el análisis principal:

- el problema no es de sintaxis;
- el problema es que el `UPDATE` sin `WHERE` afecta todas las filas;
- antes de ejecutar una sentencia de actualización masiva debe verificarse qué filas serán afectadas;
- la corrección necesita una condición que represente realmente la regla de negocio.

### Qué se aclaró o modificó

Se dejó explícito que `retirada` es solamente un nombre ilustrativo.

La guía no especifica qué columna o criterio utiliza el esquema genérico para representar una película retirada de cartel.

Por lo tanto, la versión definitiva de un sistema real debería adaptarse al esquema concreto antes de ejecutarse.

También se agregó como práctica segura realizar primero un `SELECT` con la misma condición que se utilizaría posteriormente en el `UPDATE`.

---

## Script 2 — NOT IN y valores NULL

### Script analizado

```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (
    SELECT categoria_id
    FROM producto
);
```

### Prompt / consulta utilizada

Se solicitó analizar:

- qué efecto podría producir realmente el script;
- qué problema existe cuando `NOT IN` recibe valores `NULL`;
- por qué ese comportamiento puede no coincidir con la intención declarada;
- y cuál sería una alternativa más robusta.

### Qué generó la IA

La IA explicó que SQL utiliza lógica de tres valores:

- `TRUE`;
- `FALSE`;
- `UNKNOWN`.

Si la subconsulta utilizada por `NOT IN` devuelve al menos un `NULL`, una expresión como:

```sql
3 NOT IN (1, 2, NULL)
```

puede evaluarse como `UNKNOWN`.

Como un `DELETE` solo afecta filas cuya condición `WHERE` resulta `TRUE`, categorías que conceptualmente no poseen productos asociados podrían no ser eliminadas.

La alternativa recomendada fue utilizar `NOT EXISTS`:

```sql
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto p
    WHERE p.categoria_id = c.id
);
```

También se analizó una alternativa conservando `NOT IN`, filtrando expresamente los valores nulos:

```sql
DELETE FROM categoria
WHERE id NOT IN (
    SELECT categoria_id
    FROM producto
    WHERE categoria_id IS NOT NULL
);
```

### Qué se aceptó

Se aceptó `NOT EXISTS` como la alternativa más clara y robusta para expresar la intención de eliminar categorías que no poseen productos relacionados.

También se aceptó la explicación sobre la lógica de tres valores y el riesgo asociado a `NULL`.

### Qué se aclaró o modificó

Se contrastó el caso genérico de la consigna con el esquema real de Food Store.

En el proyecto actual, la columna:

```sql
producto.categoria_id
```

está definida como:

```sql
BIGINT NOT NULL
```

Por lo tanto, en el esquema actual de Food Store esa columna no debería producir valores `NULL`.

Sin embargo, la consigna de la Parte 3 utiliza un esquema genérico y pide analizar específicamente el problema relacionado con `NULL`.

Por ese motivo, se conservó la corrección mediante `NOT EXISTS` como solución general y defendible.

---

## Verificación realizada

Los scripts peligrosos originales **no fueron ejecutados**.

La verificación fue realizada mediante lectura crítica del código SQL y contraste con las reglas semánticas de PostgreSQL utilizadas durante el proyecto.

Para el Script 1 se verificó que:

```sql
UPDATE funcion
SET activa = FALSE;
```

no contiene ninguna cláusula `WHERE`, por lo que afectaría todas las filas de la tabla.

Para el Script 2 se verificó conceptualmente el comportamiento de `NOT IN` ante valores `NULL` y se comparó con la alternativa basada en `NOT EXISTS`.

También se revisó el esquema real del proyecto Food Store para comprobar que `producto.categoria_id` está definido como `NOT NULL`, diferenciando así el caso concreto del proyecto del caso genérico planteado por la consigna.

---

## Criterio aplicado frente a la IA

La IA se utilizó para apoyar la lectura y explicación de los scripts, pero ninguna sentencia destructiva fue ejecutada automáticamente.

El criterio aplicado fue:

1. leer primero el script;
2. determinar qué filas afectaría realmente;
3. identificar supuestos y casos límite;
4. comprobar si el efecto coincide con la intención declarada;
5. proponer una corrección;
6. y solo considerar una ejecución después de verificar previamente el conjunto afectado.

Este procedimiento coincide con el principio utilizado durante todo el trabajo práctico: la IA puede asistir en la escritura y análisis, pero la decisión y la verificación permanecen bajo control humano.

