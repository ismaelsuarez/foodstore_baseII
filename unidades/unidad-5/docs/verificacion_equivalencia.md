# Verificación de equivalencia — Unidad 5, Parte D

Cubre la Parte D: construcción de `usuario_anon` con datos sintéticos y comprobación de que una
agregación da el mismo resultado sobre la tabla anonimizada y sobre `usuario`.

Archivo: [`../sql/usuario_anon.sql`](../sql/usuario_anon.sql) (construcción, ambas consultas y
comprobaciones).

## 1. Método de anonimización

`usuario_anon` se crea con `CREATE TABLE ... (LIKE usuario)`: mismas columnas, tipos y `NOT NULL`,
con `id` como clave primaria y sin identidad ni `UNIQUE`. Se carga con un `INSERT ... SELECT`
desde `usuario`, que no se modifica.

| Columna | Tratamiento | Valor en `usuario_anon` |
|---|---|---|
| `nombre` | Reemplazo sintético derivado del `id` | `Usuario <id>` |
| `apellido` | Valor fijo | `Anonimo` |
| `mail` | Reemplazo sintético derivado del `id` | `usuario<id>@anon.test` |
| `celular` | Reemplazo sintético; se conserva el `NULL` si no había celular | `id` con ceros a la izquierda, 10 dígitos |
| `contrasena` | Valor fijo, no es una credencial | `ANON_NO_AUTH` |
| `rol`, `eliminado`, `created_at` | Se conservan | Igual que en `usuario` |
| `id` | Se conserva | Igual que en `usuario` |

Los tokens son **deterministas**: el mismo usuario recibe siempre el mismo valor, y dos usuarios
distintos nunca comparten mail. Se conservan `rol`, `eliminado` y `created_at` porque sostienen
la equivalencia estadística.

`id` es una clave técnica, no un dato personal, y permite relacionar `usuario_anon` con `pedido`.
Quien tenga acceso a `usuario` puede reidentificar a cada persona por ese `id`. Por eso solo se
comparte `usuario_anon`, nunca las dos tablas juntas.

**Alcance académico.** El procedimiento es un ejercicio sobre el seed sintético de Food Store.
Con datos reales, conservar `id` y la fecha de alta exacta (`created_at`) puede permitir la
reidentificación, por cruce con otras tablas o con información externa. En ese caso habría que
evaluar, como mínimo, reemplazar `id` por un identificador sin relación con el original y reducir
`created_at` al mes.

## 2. Consultas

Las dos consultas usan los mismos criterios: agrupan por `rol` y por mes de alta
(`to_char(created_at, 'YYYY-MM')`) y cuentan las filas con `count(*)`, incluidos los usuarios
dados de baja. El script fija `TimeZone = 'America/Argentina/Buenos_Aires'` para que el mes de
alta no dependa de la sesión.

Sobre `usuario_anon`:

```sql
SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
FROM usuario_anon
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;
```

Sobre `usuario`:

```sql
SELECT rol, to_char(created_at, 'YYYY-MM') AS mes_alta, count(*) AS cantidad
FROM usuario
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;
```

## 3. Ejecución

El 2026-11-03 a las 22:09 (UTC−3), en un contenedor descartable `postgres:17` sin red
(PostgreSQL 17.11), eliminado al terminar. Orden: `schema.sql` (con `-1`), `datos_iniciales.sql`
y `usuario_anon.sql`, todos con `ON_ERROR_STOP=1`. Los tres terminaron con exit 0.

| Archivo | sha256 |
|---|---|
| `schema.sql` | `d5cbb990c76ecc085c44736e877d3fc9d993a734ecc137120679ff3706e8a108` |
| `datos_iniciales.sql` | `ab983fbe7547793bc9fa5483c6254cee0d7c4b1363ba12f8b67ad3577327565f` |
| `unidades/unidad-5/sql/usuario_anon.sql` | `c4983af3f5b9a6428fbd2548e8272b44cc49c6af42b4b1ff5d256fb471898f78` |

Contenido de `usuario_anon` después de la carga:

```text
 id |  nombre   | apellido |        mail        |  celular   |  contrasena  |   rol   | eliminado |          created_at
----+-----------+----------+--------------------+------------+--------------+---------+-----------+-------------------------------
  1 | Usuario 1 | Anonimo  | usuario1@anon.test | 0000000001 | ANON_NO_AUTH | USUARIO | f         | 2026-11-03 22:09:44.290865-03
  2 | Usuario 2 | Anonimo  | usuario2@anon.test | 0000000002 | ANON_NO_AUTH | USUARIO | f         | 2026-11-03 22:09:44.290865-03
  3 | Usuario 3 | Anonimo  | usuario3@anon.test | 0000000003 | ANON_NO_AUTH | USUARIO | f         | 2026-11-03 22:09:44.290865-03
(3 rows)
```

## 4. Resultados

Sobre `usuario_anon`:

```text
   rol   | mes_alta | cantidad
---------+----------+----------
 USUARIO | 2026-11  |        3
(1 row)
```

Sobre `usuario`:

```text
   rol   | mes_alta | cantidad
---------+----------+----------
 USUARIO | 2026-11  |        3
(1 row)
```

## 5. Verificación de equivalencia

| Comprobación | Resultado | Esperado |
|---|---|---|
| Filas distintas entre ambas agregaciones (`EXCEPT ALL` en los dos sentidos) | 0 | 0 |
| Filas de `usuario_anon` con un nombre, apellido, mail, celular o contraseña de `usuario` | 0 | 0 |
| Huella de `usuario` antes y después del script (`count` y `md5` de todas las filas) | `3 filas, md5 3e49bb8e4a4189a46ede84fbd25ff127` en ambas | Igual |

**Conclusión.** Para el dataset canónico, la agregación por rol y mes de alta da el mismo
resultado sobre `usuario_anon` que sobre `usuario`. La tabla anonimizada no contiene
identificadores personales de la original, y `usuario` no cambió.

**Límite.** El seed canónico tiene 3 usuarios, todos con rol `USUARIO` y dados de alta en el mismo
instante, así que la agregación tiene un solo grupo. La equivalencia está demostrada para estos
datos. Se sostiene en general porque `rol` y `created_at` se copian sin cambios, pero este
ensayo no la pone a prueba con varios roles o meses.

## 6. Qué datos personales no compartir con una IA

No deben enviarse a una IA, sin anonimizar, datos que identifiquen a una persona o permitan
contactarla o suplantarla:

- **Identificadores directos:** nombre y apellido, mail y celular.
- **Credenciales:** contraseñas o sus hashes. Un hash se puede atacar sin conexión.
- **Combinaciones que reidentifican:** fecha de alta exacta, junto con pedidos, montos o
  direcciones, puede señalar a una persona aunque no figure su nombre.
- **Registros completos de `usuario`** y logs con parámetros o resultados de consultas.

Una IA externa conserva lo que recibe fuera del control del equipo. Por eso se comparten
agregados o tablas como `usuario_anon`, y se revisa que no tengan identificadores reales.

## 7. Registro del uso de IA

Insumo para incorporar a `BITACORA.md` cuando el equipo lo apruebe.

| Fecha | Herramienta | Prompt | Respuesta de la IA | Validación humana |
|---|---|---|---|---|
| 2026-11-03 | Pi con el arnés Gentle Shell, modelo Claude Opus 5.5 (`claude-opus-5-5`) | «Food Store — TP Unidad 5 — Parte D: Anonimización» (texto completo abajo) | `usuario_anon.sql`, las dos consultas, ejecución en un contenedor descartable y este documento | El equipo acepta los resultados observados y reconoce las limitaciones de la prueba |
| 2026-11-03 | (misma herramienta) | Decisión del equipo sobre el dataset | La IA señaló que el seed canónico produce un único grupo y ofreció agregar usuarios sintéticos solo en el laboratorio | El equipo decidió conservar el dataset canónico, sin usuarios adicionales ni nuevas pruebas |

Datos que vio la IA: la IA no leyó filas de `usuario`. Sobre esa tabla solo vio agregados (la
consulta del punto 2), conteos y la huella `md5`. Las filas que se muestran arriba son de
`usuario_anon`. El seed canónico es sintético y ya está en el repositorio.

Prompt enviado:

~~~~text
# Food Store — TP Unidad 5 — Parte D: Anonimización

Trabajá en la rama `feat/u5-seguridad`.

Objetivo: completar exclusivamente la Parte D de la consigna oficial de Bases de Datos II, con una implementación académica sencilla y verificable.

## Tareas

1. Crear `unidades/unidad-5/sql/usuario_anon.sql`.

2. Construir la tabla `usuario_anon` a partir de `usuario`, utilizando datos sintéticos deterministas para los identificadores personales. No copiar nombres, correos, teléfonos ni contraseñas reales.

3. Conservar los campos necesarios para mantener la equivalencia estadística, especialmente `rol` y `created_at`. No modificar la tabla `usuario` original.

4. Generar una consulta de agregación sobre `usuario_anon` que cuente usuarios por rol y mes de alta.

5. Generar la consulta equivalente sobre `usuario`, utilizando exactamente los mismos criterios de agrupación y conteo.

6. Ejecutar ambas consultas sobre un laboratorio PostgreSQL 17 descartable con el esquema y los datos canónicos de Food Store.

7. Comparar los resultados de ambas consultas. Demostrar la equivalencia con las salidas reales y una comprobación SQL sencilla, sin construir baterías extensas de pruebas.

8. Crear `unidades/unidad-5/docs/verificacion_equivalencia.md`, incluyendo:
   - Método de anonimización utilizado.
   - Ambas consultas.
   - Resultados obtenidos.
   - Verificación de equivalencia.
   - Breve explicación de qué datos personales no deben compartirse con una IA sin anonimizar.

9. Conservar el prompt enviado a la IA para generar las consultas, su respuesta y la validación humana, de modo que puedan incorporarse a BITACORA.md.

## Restricciones

- Nivel académico universitario; evitar sobreingeniería.
- No modificar las Partes A, B y C.
- No modificar el esquema canónico.
- No utilizar datos personales reales ni exponer registros originales a la IA.
- No agregar funciones ni mecanismos de seguridad que la consigna no solicita.
- No tocar `odd/`.
- No hacer commits ni push todavía.
- No trabajar sobre bases persistentes ni contenedores ajenos.

## Entrega

Presentar los archivos creados, las consultas, sus resultados reales y la conclusión sobre la equivalencia.

Detenerse al completar la Parte D para nuestra revisión antes de versionar.
~~~~
