# TPI-A — Cierre de ventana canónica y defensa de normalización

**Objetivo 5: PASS. Objetivo 3: PASS académico en el alcance declarado.**
La ventana se ejecutó realmente; la defensa de normalización es un análisis
formal del modelo FoodStore, no una afirmación de FNBC física universal.
No se modificaron schema, seed, objetos programables ni unidades históricas.
Objetivo 8 y el cierre integral del informe permanecen fuera de esta fase.

## Procedencia y límites

| Dato | Valor registrado |
|---|---|
| Fecha PostgreSQL | 2026-09-23 |
| Captura de validación | 2026-09-23T23:07:59.025414-03:00 |
| Repositorio | `C:\Users\facu\Documents\UTN\Base_datos_II\foodStore` |
| Rama | `fix/tpi-cierre-primera-entrega` |
| HEAD base | `841efbab9db27c06351b9008af3f4282b5d54cdf` |
| Motor y cliente psql | PostgreSQL 17.11 |
| Base nueva | `foodstore_tpi_cierre_a` |
| Fuentes | [schema.sql](../schema.sql) y [datos_iniciales.sql](../datos_iniciales.sql) del HEAD base |

SHA-256 de los archivos utilizados, sin cambios:

- Schema: `6EB8E9FC39B0E3E86894B80CE3E2549CF222BE5F8C49E448B07C32C68C069614`.
- Seed: `3948AD5A54D50B3EFDABBABE378C0FD45CB8573C6C4C24CA91B495788911882B`.

La base no existía: `SELECT count(*) FROM pg_database WHERE
datname='foodstore_tpi_cierre_a'` devolvió **0** antes de crearla.
Se creó desde cero; no se restauró ningún dump ni se reutilizó otra base.
Se aplicó schema transaccionalmente y seed con su propio BEGIN/COMMIT.
Cada comando terminó con **exit code 0** y se usó `ON_ERROR_STOP=1` en psql.

Comandos ejecutados desde la raíz, con autenticación local ya configurada:

```powershell
createdb -w -h 127.0.0.1 -p 5432 -U postgres foodstore_tpi_cierre_a
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_cierre_a -v ON_ERROR_STOP=1 -1 -f .\schema.sql
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_cierre_a -v ON_ERROR_STOP=1 -f .\datos_iniciales.sql
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_cierre_a -v ON_ERROR_STOP=1 -f .\tpi\sql\consultas_cobertura_tpi.sql
```

Estos comandos documentan la ejecución: no repetir creación/carga sobre la base
ya existente. No hay borrado ni recreación automática. No se instalaron objetos
programables TPI, U3 o U4; la consulta solo necesita el modelo y el seed coherente.
La base quedó disponible con esos datos, sin fixtures adicionales.

## A. OBJETIVO 5 — FUNCIÓN DE VENTANA

### Consulta exacta ejecutada

Fuente: [consultas_cobertura_tpi.sql](sql/consultas_cobertura_tpi.sql), sección
«Función de ventana — ranking de usuarios por gasto». La consulta HAVING
preexistente se conservó sin cambios.

```sql
WITH gasto_usuario AS (
    SELECT
        u.id,
        u.nombre,
        u.apellido,
        SUM(p.total) AS gasto_total
    FROM usuario u
    JOIN pedido p ON p.usuario_id = u.id
    WHERE p.eliminado = FALSE
    GROUP BY u.id, u.nombre, u.apellido
)
SELECT
    id,
    nombre,
    apellido,
    gasto_total,
    RANK() OVER (ORDER BY gasto_total DESC) AS ranking
FROM gasto_usuario
ORDER BY ranking, id;
```

La CTE produce una fila por usuario con pedidos elegibles. RANK se aplica
después de la agregación, sin reducir nuevamente el conjunto. El ranking es
global: no requiere PARTITION BY. `id` solo desempata el orden de presentación,
no el gasto dentro de OVER.

### Semántica de historia y baja lógica

Se rankea el importe acumulado de pedidos no eliminados, sin filtro de fecha
ni estado. Se usa `pedido.total` físico, conciliado en el seed; no se unen sus
líneas para evitar multiplicar el importe de cada pedido.

Se filtra **`p.eliminado = FALSE`**, pero no `u.eliminado`: una baja posterior
de usuario no debe borrar su historia de compras. INNER JOIN excluye usuarios
sin pedidos elegibles; no inventa una compra de importe cero. Esta es la misma
política histórica de la consulta HAVING, no una nueva política de cancelación.

### Resultado real

| id | nombre | apellido | gasto_total | ranking |
|---:|---|---|---:|---:|
| 3 | Marta | Ruiz | 6200.00 | 1 |
| 1 | Ana | Gómez | 5950.00 | 2 |
| 2 | Luis | Paz | 2550.00 | 3 |

**Tres filas, sin errores.** El archivo completo devolvió además el HAVING
conservado: Ana Gómez 2 y Luis Paz 2, dos filas.
La ventana se extrajo sin modificar su texto del archivo y se ejecutó dos veces
más con salida CSV; encabezados y filas fueron exactamente iguales entre ambas.
No fueron benchmarks ni se registraron tiempos de rendimiento.

### Validaciones ejecutadas

Los SELECT de validación utilizaron la misma CTE `gasto_usuario` y una segunda
CTE `ranking` con `RANK() OVER (ORDER BY gasto_total DESC) AS ranking`.
Se contrastó cada rango con la definición independiente:

```sql
SELECT COUNT(*) AS errores
FROM ranking r
WHERE r.ranking <> 1 + (
    SELECT COUNT(*)
    FROM gasto_usuario g
    WHERE g.gasto_total > r.gasto_total
);
```

El fragmento requiere las dos CTE descritas; no refiere tablas permanentes
llamadas ranking o gasto_usuario. También se contaron grupos de empate con
`GROUP BY gasto_total HAVING COUNT(*) > 1` y se verificaron los tres pares
id/importe/rango del resultado anterior.

| Comprobación | Resultado real |
|---|---|
| Filas de ranking | 3 |
| Columna `ranking` / tipo `pg_typeof` | Presente / bigint |
| MIN(ranking) | 1 |
| Grupos de empate en gasto_total | 0 |
| Diferencias contra `1 + COUNT(usuarios con gasto mayor)` | 0 |
| Diferencias contra resultado esperado del seed | 0 |
| Repeticiones CSV idénticas | TRUE |
| Usuarios eliminados / pedidos eliminados en el seed | 0 / 0 |
| Subtotales inconsistentes | 0 |
| Totales inconsistentes | 0 |

**No se observó empate en el seed.** Si existe uno, RANK comparte el puesto
entre pares y deja saltos posteriores; el id externo no cambia ese cálculo.
Es semántica documentada en [PostgreSQL 17, funciones de ventana](https://www.postgresql.org/docs/17/functions-window.html),
no un caso de empate ejecutado en esta carga. Tampoco se simularon bajas:
la política de soft delete se justifica por el SQL y el contrato, no por una
prueba de mutación que no se realizó.

### Estado del laboratorio después de consultar

| Tabla | Filas |
|---|---:|
| categoria | 2 |
| usuario | 3 |
| producto | 3 |
| pedido | 5 |
| detalle_pedido | 7 |

Catálogo observado: **40 columnas, 5 PK, 4 FK, 6 CHECK y 3 UNIQUE adicionales**.
Rutinas de usuario en public: **0**; triggers no internos: **0**.
Las conciliaciones compararon subtotal con cantidad por precio unitario y total
con la suma de detalles no eliminados, incluyendo pedidos sin líneas mediante
subconsulta correlacionada y COALESCE. No hubo DML después de cargar el seed.

## B. OBJETIVO 3 — NORMALIZACIÓN

Fuente principal: [normalizacion.md](modelo/normalizacion.md), contrastada con
[modelo relacional](modelo/modelo_relacional.md), schema y objetos TPI.
Este cierre no utiliza el ejercicio aislado de Unidad 4 como evidencia principal.

### Claves, dependencias y alcance por relación

| Relación | Claves candidatas y DF respaldadas | Estado |
|---|---|---|
| usuario | id y mail determinan el resto | 1FN/2FN/3FN/FNBC con las DF identificadas |
| categoria | id y nombre determinan el resto | 1FN/2FN/3FN/FNBC con las DF identificadas |
| producto | id determina el resto | 1FN/2FN/3FN/FNBC con las DF identificadas |
| pedido | id determina el resto | 1FN/2FN/3FN/FNBC para sus DF internas identificadas |
| detalle_pedido | id y (pedido_id, producto_id) determinan el resto; (cantidad, precio_unitario) determina subtotal | 1FN/2FN; no 3FN/FNBC física estricta |

No se infieren claves por coincidencias del seed. El modelo lógico separa los
hechos y analiza todas las claves candidatas declaradas; la PK simple del
detalle no permite ignorar su clave alternativa compuesta al analizar 2FN.

### Excepción física consciente

`{cantidad, precio_unitario} → subtotal` no tiene determinante superclave y
subtotal no es primo. Se reconoce formalmente la violación de 3FN/FNBC.
El subtotal se conserva como **REDUNDANCIA DERIVADA CONTROLADA**, deliberada
y exigida por el contrato oficial, no por error de modelado inadvertido.

La persistencia del importe de la línea favorece trazabilidad y reportes;
la capa del motor evita depender de un recálculo externo y mantiene la igualdad
en la misma sentencia/transacción. Esa justificación no demuestra una mejora
de rendimiento ni vuelve normalizada estrictamente la tabla física.

Mecanismo existente: **`fn_set_subtotal` + `trg_subtotal`**, BEFORE por fila
en INSERT y UPDATE de cantidad, precio unitario, producto o subtotal.
La función sobrescribe subtotal con cantidad por precio histórico. Código:
[objetos_programables.sql](sql/objetos_programables.sql), sección 2.
Las pruebas N/O/P y su ejecución previa se conservan en la
[batería](pruebas/pruebas_objetos_programables.sql) y en la
[evidencia oficial](evidencia_modelo_oficial.md).

No se modificaron ni reinstalaron esos objetos en TPI-A. La base de ventana
solo tiene schema/seed y no adquiere automáticamente sus garantías para futuras
escrituras. `pedido.total` es otro agregado controlado, entre relaciones;
por sí solo no demuestra una DF interna que viole FNBC de pedido.

### Alcance lossless, sin migración artificial

Las otras cuatro relaciones no requieren nueva descomposición bajo las DF
internas identificadas. Para detalle D, la demostración teórica considera:

```text
D1(cantidad, precio_unitario, subtotal)
D2(id, cantidad, precio_unitario, pedido_id, producto_id, eliminado, created_at)
X = D1 ∩ D2 = {cantidad, precio_unitario}
X → D1
```

Por el criterio binario de unión sin pérdida, las proyecciones de una instancia
de D que cumple la DF reconstruyen exactamente D. Se usan proyecciones sin
duplicados, no copias SQL arbitrarias. La igualdad aritmética es más fuerte que
la DF y seguiría necesitando control; la prueba no afirma una clasificación
exhaustiva de otras DF aritméticas.

No se implementa D1 como un catálogo artificial de multiplicaciones ni se crean
tablas nuevas. La alternativa lógica sin subtotal almacenado se distingue de
la decisión física oficial: **schema.sql permanece intacto**. El cumplimiento
académico aquí significa análisis formal y excepción justificada, nunca
«todas las tablas físicas están estrictamente en 3FN/FNBC».

## Resultado del cierre acotado

- Objetivo 5: ventana canónica implementada y ejecutada, resultado conservado.
- Objetivo 3: defensa académica explícita, con redundancia y alcance real reconocidos.
- Modelo relacional: revisado, sin afirmación de FNBC física universal; no modificado.
- Informe técnico: correcciones directas de objetivos 3/5, sin cierre integral.
- No se implementaron SAVEPOINT ni pruebas de aislamiento; TPI-B queda pendiente.
- No se alteró la evidencia histórica ni se utilizaron resultados U4 para cubrir estos objetivos.
