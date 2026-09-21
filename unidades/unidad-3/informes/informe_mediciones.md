# TP5 — Índices, vistas y vistas materializadas
## Food Store — Modelo oficial

**Informe vigente.** Los tres índices se aceptan para el TP con mejoras de
lectura observadas y costos de escritura explícitos. Las cuatro vistas y la
materializada resultaron equivalentes a sus consultas manuales; la seguridad
y el refresh concurrente se probaron realmente.

Fuente exclusiva de resultados: [evidencia técnica del Bloque 2](evidencia_modelo_oficial.md).
Allí se conservan las corridas, los buffers, los 30 planes completos de
ejecuciones válidas y el bootstrap de laboratorio. Este resumen no reproduce
esos planes ni reutiliza cifras de iteraciones anteriores.

### Entorno

- PostgreSQL **17.11**, Windows x86_64; base descartable `foodstore_tp5_oficial`.
- Ejecución: **20/09/2026**, aproximadamente 21:01–21:03,
  zona `America/Buenos_Aires`.
- Datos sintéticos generados para una copia conforme al modelo oficial.

| Tabla | Filas |
|---|---:|
| `categoria` | 8 |
| `producto` | 50.000 |
| `usuario` | 20.000 |
| `pedido` | 200.000 |
| `detalle_pedido` | 500.000 |

Los resultados son específicos de este dataset y esta máquina; **no son
valores universales**. El esquema raíz y su dataset no reconstruyen esta
copia de laboratorio. El bootstrap temporal no es una migración entregable.

### Protocolo y línea base

Cada caso utilizó `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` tres veces:
calentamiento descartado y media de corridas 2 y 3. Se ejecutó `ANALYZE`
antes y después de cada candidato. Los tiempos son `Execution Time`, en ms.

Antes de los candidatos existían PK/UNIQUE y los índices de cátedra
`idx_producto_categoria`, `idx_pedido_usuario` e `idx_producto_nombre_vig`.
El inventario completo está en la sección 2 de la evidencia. No se retiraron
índices base. Dos corridas válidas no son una estimación estadística robusta.

### 1. Índice stock bajo

```sql
SELECT id, nombre, stock, precio
FROM producto
WHERE eliminado = FALSE AND stock <= 5
ORDER BY stock ASC, nombre ASC;
```

`idx_producto_stock_bajo`: claves `(stock ASC, nombre ASC)`,
`INCLUDE (id, precio)`, parcial `WHERE eliminado = FALSE`.

| Antes | Después | Mejora observada | Plan final |
|---:|---:|---:|---|
| 9.4390 ms | 0.2975 ms | 31.73x | `Index Only Scan` |

El plan anterior fue `Seq Scan` más `Sort`. Se conservaron 1.477 filas;
los buffers shared hit bajaron de 869 a 14 y desapareció el `Sort`.
El plan final informó `Heap Fetches: 0`.

**No se filtra `disponible`:** un producto no disponible puede necesitar
reposición. Disponibilidad comercial y eliminación lógica son reglas
distintas. En los resultados hubo 74 productos no disponibles con stock bajo.

### 2. Índice pedidos recientes

```sql
SELECT id, usuario_id, fecha, estado, forma_pago, total
FROM pedido
WHERE eliminado = FALSE AND fecha >= CURRENT_DATE - 30
ORDER BY fecha DESC;
```

`idx_pedido_fecha_reciente`: clave `(fecha DESC)`,
`INCLUDE (id, usuario_id, estado, forma_pago, total)`,
parcial `WHERE eliminado = FALSE`.

| Antes | Después | Mejora observada | Plan final |
|---:|---:|---:|---|
| 264.3715 ms | 1.2250 ms | 215.81x | `Index Only Scan` |

`fecha` es `DATE`; el límite inclusivo fue `2026-08-21`.
Se obtuvieron 8.525 filas. El plan anterior fue `Gather Merge` con lectura
secuencial paralela y ordenamiento; shared hit pasó de 4.001 a 72.
El plan final no tuvo `Sort` e informó `Heap Fetches: 0`.

La cobertura de `INCLUDE` se observó en la ejecución, no se asumió como
garantía ni como diseño óptimo para cualquier carga. No se atribuye el
tiempo elevado anterior a una causa aislada no medida. Esta variante usa
la ventana móvil autorizada, no el literal `DATE '2026-04-11'` de
[`queries.sql`](../sql/queries.sql).

### 3. Índice usuario mail

```sql
SELECT id, nombre, apellido, mail, rol
FROM usuario
WHERE eliminado = FALSE
  AND lower(mail) = lower('usuario8452@foodstore.test');
```

`idx_usuario_mail_lower`: expresión `lower(mail)`, parcial
`WHERE eliminado = FALSE`, **sin UNIQUE**.

| Antes | Después | Mejora observada | Plan final |
|---:|---:|---:|---|
| 10.8865 ms | 0.1360 ms | 80.05x | `Bitmap Heap Scan` + `Bitmap Index Scan` |

Se obtuvo una fila; shared hit bajó de 344 a 3 frente al `Seq Scan` inicial.
El literal medido existe en la carga y reemplaza solo en este ensayo a
`ANA.GOMEZ@FOODSTORE.TEST` del archivo de consultas estático.

`usuario.mail` ya tiene unicidad exacta, pero `lower(mail)` es otra
expresión. Declararla UNIQUE introduciría una regla de negocio de unicidad
case-insensitive no establecida.

### 4. Propuesta descartada

**RECHAZADO: `idx_usuario_mail_lower_covering`.** La alternativa incluía
`id, nombre, apellido, mail, rol` además de la expresión y el predicado.

| Alternativa | Tamaño real |
|---|---:|
| Índice simple | 999.424 bytes |
| Índice covering | 2.621.440 bytes |

El covering ocupó **2.62x** el tamaño del simple. Para una consulta que
obtiene una fila, sin beneficio temporal adicional medido, no se justifica
cargar permanentemente esas columnas en cada entrada. Se creó únicamente
para medir tamaño dentro de `BEGIN`/`ROLLBACK`; su ausencia final fue
verificada. No es un rechazo general de `INCLUDE`.

### 5. Costo de escritura y decisión

Cada corrida insertó 1.000 filas en la tabla indexada dentro de una
transacción revertida. Para obtener el BEFORE se retiraron únicamente los
tres candidatos; luego se recrearon exactamente. Se aplicó el mismo
protocolo de un calentamiento y dos corridas válidas, con `VACUUM ANALYZE`
previo fuera del tiempo medido.

| Tabla | Antes, ms | Después, ms | Incremento observado |
|---|---:|---:|---:|
| `producto` | 16.9725 | 19.5120 | +14.96 % |
| `pedido` | 9.5240 | 10.4330 | +9.54 % |
| `usuario` | 7.6655 | 14.7085 | +91.88 % |

Los índices aceleraron lecturas a costa de mantenimiento adicional durante
escrituras. El ensayo no aísla todos los efectos del entorno. `ROLLBACK`
preservó los conteos, pero no revierte el avance de secuencias identity ni
garantiza un estado físico idéntico.

La penalización relativa en altas de usuario es importante. **La decisión
humana del TP es conservar el índice simple** por la mejora medida, el
carácter interactivo de la búsqueda y su menor tamaño frente al covering.
Se asume que las altas son mucho menos frecuentes que las búsquedas por
mail: esa frecuencia **no fue medida**. La decisión depende de esa carga
de trabajo supuesta y debe revisarse si cambia; no justifica el índice
automáticamente para cualquier sistema.

### 6. Vistas y equivalencia

| Vista | Filas | manual_minus_view | view_minus_manual |
|---|---:|---:|---:|
| `v_productos_vigentes` | 43.299 | 0 | 0 |
| `v_pedidos_resumen` | 198.059 | 0 | 0 |
| `v_pedido_detalle` | 495.327 | 0 | 0 |
| `v_usuarios_publico` | 19.802 | 0 | 0 |

- Productos: producto y categoría no eliminados; no filtra disponibilidad.
- Pedidos: no excluye historial por baja posterior del usuario.
- Detalle: utiliza `dp.subtotal` físico y no oculta historial por baja del producto.
- Seguridad: expone `id, nombre, apellido, mail, rol`; omite `contrasena` y `celular`.

Se comparó cada vista con su consulta manual mediante `EXCEPT`
bidireccional. Esto acredita igualdad de conjuntos para esta carga, no una
demostración universal. Las consultas y controles adicionales están en la
sección 7 de la evidencia.

### 7. Seguridad real

El inventario inicial no contenía `rol_soporte`; se creó temporalmente
`NOLOGIN` sin alterar roles preexistentes. Tras aplicar
[`seguridad.sql`](../sql/seguridad.sql), `SET ROLE rol_soporte` permitió
leer `v_usuarios_publico`. Las lecturas directas de `usuario.contrasena`
y `usuario.celular` fallaron con **SQLSTATE 42501**.

Se registraron dos denegaciones esperadas y cero errores SQL inesperados.
Al terminar se revocó la concesión y se eliminó ese rol; su ausencia fue
verificada. **No quedaron roles temporales instalados.** La prueba no
garantiza seguridad para roles futuros con privilegios heredados o acceso
directo: deberán verificarse al desplegar.

### 8. Vista materializada

`mv_facturacion_categoria_mes` suma **`SUM(dp.subtotal)`**, filtra
`ped.eliminado = FALSE` y `dp.eliminado = FALSE`, y no filtra el estado actual
de producto/categoría ni disponibilidad para no borrar historia contable.

| Lectura | Promedio estable |
|---|---:|
| Consulta original | 1188.4945 ms |
| Materializada: mismo orden `mes ASC, facturacion_total DESC` | 0.2230 ms |
| Materializada: orden solicitado `categoria_id, mes` | 0.1220 ms |

La comparación homogénea es **1188.4945 → 0.2230 ms**. El valor 0.1220 ms
corresponde a otro ordenamiento y no se usa para esa comparación.
La materializada devolvió **192 filas**, con `EXCEPT` **0 / 0** antes y
después del refresh. El índice `idx_mv_facturacion_categoria_mes_unique`,
UNIQUE sobre `(categoria_id, mes)` sin predicado, permitió ejecutar
`REFRESH MATERIALIZED VIEW CONCURRENTLY`: **PASS**.

**Ejecución de prueba:** un refresh concurrente manual exitoso. No se
midieron su duración ni bloqueos entre sesiones; la lectura no incluye
costos de construcción o refresh.

**Propuesta de política:** se conserva como propuesta heredada refrescar
cada 60 minutos, pendiente de ratificación del equipo antes de un
despliegue. No fue automatizada ni validada como frecuencia operativa.
La vista admite staleness: el atraso real depende también de duración y
fallos de refresh, por lo que no se garantiza un máximo de una hora.

### Alcance documental

Este informe y la evidencia son la autoridad de resultados del modelo
oficial. SQL/specs conservan los estados previos a ejecución del Bloque 1;
las pruebas posteriores están aquí. El [informe histórico](informe_mediciones_historico.md)
se conserva sin editar, exclusivamente por trazabilidad. Las referencias
temporales de la evidencia al informe anterior corresponden a ese archivo
histórico, no a este nuevo informe.
