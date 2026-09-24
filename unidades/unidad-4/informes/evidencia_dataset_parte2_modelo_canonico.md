# Unidad 4 — Dataset canónico reproducible para Parte 2

**Carga y validación del dataset: PASS.** Se obtuvieron exactamente 8 categorías,
20.000 usuarios, 50.000 productos, 200.000 pedidos y 500.000 detalles. El reporte
del día tiene ocho categorías con importes distintos; subtotal y total concilian.
Se realizó mantenimiento ordinario y se creó un dump nuevo verificable por TOC.

Esta es evidencia de preparación de datos, **no un benchmark ni una elección de
desnormalización**. No se instaló TPI, FNBC ni Parte 2. No se ejecutó EXPLAIN
ANALYZE, no se compararon tiempos y no se reutilizaron resultados históricos.
El commit local se comprueba posteriormente; este documento no presupone su creación.

## 1. Entorno y fuentes verificadas

| Dato | Valor |
|---|---|
| Fecha SQL observada | 2026-09-23 |
| Zona horaria | America/Buenos_Aires |
| Motor | PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit |
| Repositorio | C:\Users\facu\Documents\UTN\Base_datos_II\foodStore |
| Rama | fix/u4-revalidacion-canonica |
| HEAD de ejecución | 0bca23429a44d98cef01f7b7d7046c04b6c56461 |
| Base canónica del repositorio | e5282f68a4af6975fb953c4f4b74f2e13240a0a6 |
| Base descartable exclusiva | foodstore_u4_revalidacion |
| Estructura / seed | schema.sql / datos_iniciales.sql del commit canónico |
| TPI | EXCLUDED_FROM_PRIMARY_U4_BASELINE |
| FNBC | PASS en Fase 2, retirado mediante DOWN; no reinstalado |
| Parte 2 | NOT_INSTALLED_NOT_EXECUTED |

Fuentes: [schema](../../../schema.sql), [seed](../../../datos_iniciales.sql),
[índices TP5](../../unidad-3/sql/indices.sql),
[evidencia FNBC](evidencia_revalidacion_fnbc_modelo_canonico.md).
Los artefactos históricos permanecen intactos; sus mediciones no describen este dataset.

## 2. Script, guardas y ejecución

Script nuevo: [carga_laboratorio_parte2_modelo_canonico.sql](../sql/carga_laboratorio_parte2_modelo_canonico.sql).

Comando ejecutado desde la raíz:

```powershell
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_u4_revalidacion -v ON_ERROR_STOP=1 -f .\unidades\unidad-4\sql\carga_laboratorio_parte2_modelo_canonico.sql
```

Resultado real: **exit code 0, tres NOTICE PASS, cero errores SQL**. No se empleó
`-1`: la carga DML tiene BEGIN/COMMIT propios; la prueba identity usa ROLLBACK
y los cinco VACUUM se ejecutan fuera de transacción.

SHA-256 de los bytes del SQL ejecutado:
`CA512A0EB8A3983E97965D72665EF214ADAA141CF3FF946464ECEDA93112F767`.
Una conversión de saltos de línea de Git puede cambiar una huella binaria sin
cambiar el SQL. Esta identifica el archivo usado en esta ejecución.

Guardas anteriores a la primera inserción:

- Base exacta autorizada; solo cinco tablas canónicas, sin vistas/materializadas.
- Cero rutinas no sistema y cero triggers no internos; sin FNBC/TPI/Parte 2.
- Seed con COUNT/MIN/MAX y PK: rangos 1..2, 1..3, 1..3, 1..5 y 1..7 sin huecos.
- Cuarenta columnas con tipos, nulabilidad e identidad esperados; ninguna categoría
  redundante en detalle. Dieciocho restricciones comparadas por nombre y definición.
- Catorce índices; definiciones exactas de los seis índices explícitos raíz + TP5;
  índices válidos y preparados, triggers internos de integridad habilitados.
- Seed anterior a CURRENT_DATE; bloqueo SHARE ROW EXCLUSIVE de las cinco tablas
  para impedir escrituras concurrentes durante guardas y carga.

El script rechaza volver a cargarse sobre esta base ya poblada. **No reejecutarlo
como mantenimiento ni truncar datos para forzar su guarda.** Su reproducción
requiere otra preparación limpia autorizada del mismo contrato y una nueva fecha
de referencia documentada. No se utilizaron dumps antiguos ni datos de otras bases.

## 3. Diseño determinístico

Los IDs se proporcionan mediante OVERRIDING SYSTEM VALUE después de validar el
seed. Todas las fórmulas son enteras/NUMERIC; no se usa random() ni FLOAT monetario.
`created_at` sintético se fija a medianoche UTC de CURRENT_DATE para maestros y de
la fecha del pedido para pedidos/detalles. No se depende de now() para generarlos.

| Entidad | Regla de generación |
|---|---|
| Categorías | IDs 3..8, nombres `__U4_LAB_CATEGORIA_03__` hasta `08`, no eliminadas |
| Usuarios | IDs 4..20000; nombres sintéticos, mail `u4.lab.<id>@foodstore.invalid`, rol USUARIO, no eliminados |
| Productos | IDs 4..50000; categoría `1 + ((id-1) % 8)`; disponibilidad TRUE y eliminado FALSE |
| Precio de producto | `1000*categoria_id + ((id*17)%97) + ((id*13)%100)::numeric/100`, convertido a NUMERIC(12,2) |
| Stock | `100 + id%401`; fotografía inicial, sin descuento por ventas sintéticas |
| Pedidos | Ordinal i=1..199995; ID=i+5; usuario `1+((i*13)%20000)`; ciclos modulares de cuatro estados y tres formas de pago |
| Fecha | i<=20000: CURRENT_DATE; resto, j=i-20000: `CURRENT_DATE-(1+(j-1)%60)` |
| Líneas | Dos por pedido sintético; tercera si i<=20000 e i par, o si es histórico y j<=90003 |
| Producto de línea l | `1+((i*37+(l-1)*997)%50000)`; productos distintos dentro del pedido |
| Cantidad | `1+((i+l)%4)` |
| ID detalle | `7+row_number()` ordenado por i y número de línea |
| Precio/subtotal detalle | Precio del producto durante la generación; subtotal=cantidad*precio_unitario con NUMERIC exacto |
| Bajas lógicas | Pedido sintético: i%100=0; detalle sintético: id%100=0 |

El marcador `SEED_NO_AUTH` satisface el atributo obligatorio, pero **no es una
credencial real ni un mecanismo de autenticación**. No se generó información
personal real ni se modificaron los tres usuarios seed.

Staging TEMP ON COMMIT DROP calcula detalles y agrupa sus subtotales no eliminados
**antes de insertar pedidos**. `pedido.total` incluye todas sus líneas vigentes,
incluso si el pedido está eliminado: el filtro del reporte es una regla separada.
No hubo UPDATE masivo posterior de total ni instalación de triggers para calcularlo.
Las inserciones finales se ordenaron por ID; no quedaron auxiliares permanentes.

## 4. Conteos y distribución temporal reales

| Tabla | Inicial | Agregadas | Final |
|---|---:|---:|---:|
| categoria | 2 | 6 | 8 |
| usuario | 3 | 19997 | 20000 |
| producto | 3 | 49997 | 50000 |
| pedido | 5 | 199995 | 200000 |
| detalle_pedido | 7 | 499993 | 500000 |

Los 20.000 pedidos sintéticos del día recibieron 50.000 detalles. Los 179.995
pedidos sintéticos históricos recibieron 449.993 detalles; los siete seed se
conservaron. Rangos finales de ID: 1..objetivo, sin huecos en las filas existentes.

`MIN(pedido.fecha)=2026-03-01`; `MAX=2026-09-23`; **65 fechas distintas**.
La tabla agrupa únicamente días que tienen el mismo conteo:

| Fecha o intervalo inclusivo | Días | Pedidos por día | Pedidos del intervalo |
|---|---:|---:|---:|
| 2026-03-01 (seed) | 1 | 2 | 2 |
| 2026-03-05, 2026-03-06, 2026-03-07 (seed) | 3 | 1 | 3 |
| 2026-07-25 a 2026-07-29 | 5 | 2999 | 14995 |
| 2026-07-30 a 2026-09-22 | 55 | 3000 | 165000 |
| 2026-09-23 | 1 | 20000 | 20000 |

No hay fechas futuras. Las bajas de pedidos históricos se concentran, por la
interacción modular de las fórmulas, en 2026-07-25 (599), 2026-08-14 (600) y
2026-09-03 (600). El 2026-09-23 tiene 200; las restantes fechas, cero.

## 5. CURRENT_DATE, bajas y distribución de productos

| Diagnóstico del día 2026-09-23 | Cantidad | Porcentaje sobre su conjunto |
|---|---:|---:|
| Pedidos totales | 20000 | 100 % |
| Pedidos eliminados | 200 | 1 % |
| Pedidos vigentes | 19800 | 99 % |
| Detalles asociados totales | 50000 | 100 % |
| Detalles eliminados | 500 | 1 % |
| Detalles no eliminados, sin filtrar pedido | 49500 | 99 % |
| Detalles utilizables por ambos filtros del reporte | 48900 | 97.8 % |
| Categorías del reporte | 8 | 8 de 8 |

En toda la población sintética: pedidos eliminados **1999/199995 = 0.999525 %**;
detalles eliminados **5000/499993 = 1.000014 %** (porcentajes redondeados a seis
decimales). La semántica de baja del detalle no implica reposición de stock.

| Categoría | Productos |
|---|---:|
| 1 — Pizzas | 6251 |
| 2 — Bebidas | 6250 |
| 3 — __U4_LAB_CATEGORIA_03__ | 6249 |
| 4 — __U4_LAB_CATEGORIA_04__ | 6250 |
| 5 — __U4_LAB_CATEGORIA_05__ | 6250 |
| 6 — __U4_LAB_CATEGORIA_06__ | 6250 |
| 7 — __U4_LAB_CATEGORIA_07__ | 6250 |
| 8 — __U4_LAB_CATEGORIA_08__ | 6250 |

| Detalles por pedido | MIN | MAX | AVG | P50 discreto |
|---|---:|---:|---:|---:|
| Todos los pedidos | 1 | 3 | 2.5 | 3 |
| Solo sintéticos | 2 | 3 | 2.5000275006875172 | 3 |

## 6. Integridad e identidades

Las aserciones del script y las consultas independientes posteriores comprobaron:

| Control | Inconsistencias |
|---|---:|
| subtotal frente a cantidad*precio_unitario, todas las filas | 0 |
| total frente a SUM(subtotal) de detalles vigentes, con LEFT JOIN | 0 |
| Referencias huérfanas, cuatro FK | 0 |
| Duplicados del par pedido/producto | 0 |
| Duplicados de usuario.mail / categoria.nombre | 0 / 0 |
| Violaciones de los seis CHECK | 0 |
| NULL en columnas obligatorias | 0 |
| Precio histórico sintético frente al catálogo durante la carga | 0 |
| Fechas futuras | 0 |

Se conservaron idénticos los snapshots de columnas/defaults, restricciones, ENUM,
OID y definiciones de índices. Las huellas de **todas las filas seed**, incluidos
created_at y precios históricos, coinciden antes/después. Muzzarella conserva
su precio de catálogo 1050 y la línea seed histórica de 1000.

Después del COMMIT se aplicó setval al máximo existente en las cinco secuencias.
Un INSERT real encadenado, usando DEFAULT identity y RETURNING dentro de una
transacción revertida, obtuvo **9 / 20001 / 50001 / 200001 / 500001**.
No persistió ninguna fila de prueba. Cada secuencia conservó ese valor consumido:
el próximo sería **10 / 20002 / 50002 / 200002 / 500002**. Esto deja un hueco
documentado por secuencia, no una desincronización. setval/nextval no revierten con
ROLLBACK; no se reajustaron después para ocultar el ensayo.

## 7. Validación semántica del Top 5, sin tiempos

Se ejecutó el SELECT normalizado de la consigna, sin EXPLAIN. Suma dp.subtotal,
usa ped.fecha=CURRENT_DATE y excluye pedidos/detalles eliminados. No agrega filtros
por estado, usuario, producto o categoría; no modifica su ORDER BY para desempatar.

| Orden | Categoría | total_vendido | Integra Top 5 |
|---:|---|---:|---|
| 1 | __U4_LAB_CATEGORIA_07__ | 194538488.00 | Sí |
| 2 | __U4_LAB_CATEGORIA_03__ | 90236048.00 | Sí |
| 3 | __U4_LAB_CATEGORIA_06__ | 88912722.00 | Sí |
| 4 | __U4_LAB_CATEGORIA_05__ | 74717570.00 | Sí |
| 5 | __U4_LAB_CATEGORIA_08__ | 40242037.00 | Sí |
| 6 | Bebidas | 30106340.22 | No |
| 7 | __U4_LAB_CATEGORIA_04__ | 20242660.00 | No |
| 8 | Pizzas | 15522518.00 | No |

**Ocho agregados distintos; grupos empatados = 0.** El SELECT con
`ORDER BY total_vendido DESC LIMIT 5` devolvió exactamente las primeras cinco
filas. Estos importes son resultados funcionales, no métricas de rendimiento.

## 8. Mantenimiento y diagnóstico físico

Ejecutados después de la carga y de revertir los INSERT de prueba:

```sql
VACUUM (ANALYZE) categoria;
VACUUM (ANALYZE) usuario;
VACUUM (ANALYZE) producto;
VACUUM (ANALYZE) pedido;
VACUUM (ANALYZE) detalle_pedido;
```

Sin VACUUM FULL, CLUSTER ni modificación de configuración global. Los siguientes
son valores observados posteriores al mantenimiento, expresados en bytes:

| Tabla | pg_relation_size | pg_total_relation_size | n_live_tup | n_dead_tup |
|---|---:|---:|---:|---:|
| producto | 7454720 | 15220736 | 50000 | 1 |
| pedido | 16891904 | 36552704 | 200000 | 1 |
| detalle_pedido | 46546944 | 73637888 | 500000 | 1 |

n_live_tup/n_dead_tup son estadísticas diagnósticas estimadas; el valor observado
de muertas es **1, no 0**. No se interpreta como medición de bloat ni benchmark.

| Índice | Bytes |
|---|---:|
| categoria_pkey / categoria_nombre_key | 16384 / 16384 |
| usuario_pkey | 466944 |
| usuario_mail_key / idx_usuario_mail_lower | 1736704 / 1736704 |
| producto_pkey | 1138688 |
| idx_producto_categoria | 344064 |
| idx_producto_nombre_vig | 2506752 |
| idx_producto_stock_bajo | 3735552 |
| pedido_pkey | 4513792 |
| idx_pedido_usuario | 2269184 |
| idx_pedido_fecha_reciente | 12845056 |
| detalle_pedido_pkey | 11255808 |
| uq_detalle_pedido_pedido_producto | 15794176 |

Los catorce índices conservan definición/OID. Los tres TP5 siguen presentes:
idx_producto_stock_bajo, idx_pedido_fecha_reciente e idx_usuario_mail_lower.

## 9. Backup nuevo del checkpoint

Archivo local ignorado por Git, creado sin sobrescribir uno existente:

`C:\Users\facu\Documents\UTN\Base_datos_II\foodStore\backups\foodstore_u4_revalidacion_phase3.dump`

- Formato custom de pg_dump; **10.918.392 bytes**.
- Creación: **2026-09-23 09:21:46 -03:00**; finalización: **09:21:49 -03:00**.
- SHA-256: `75DE3D6B072AF714B44944C862767B1CA6E619716A425F8194C7B248F93F24CE`.
- pg_dump: **exit code 0**. pg_restore --list: **exit code 0**.
- Cabecera del archivo: 45 entradas TOC; 41 entradas seleccionadas listadas.
- **No restaurado.** Leer el TOC acredita legibilidad del catálogo del archivo,
  no reemplaza una prueba integral de restauración.

Comandos de creación/verificación, solo reproducibles con un destino nuevo autorizado:

```powershell
pg_dump -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_u4_revalidacion -Fc -f .\backups\foodstore_u4_revalidacion_phase3.dump
pg_restore --list .\backups\foodstore_u4_revalidacion_phase3.dump
```

## 10. Estado final y límites

Cinco tablas canónicas; conteos exactos; seed intacto; cero rutinas no sistema,
triggers no internos, objetos FNBC, vistas/materializadas o categoría redundante
en detalle. El catálogo fue preservado y las identidades avanzaron de manera
controlada. TPI sigue excluido del baseline primario, no declarado obsoleto.

El fixture es determinístico y adecuado para cobertura, **no un modelo estadístico
de demanda real**. La uniformidad de productos no implica uniformidad de ventas:
precios, cantidades, categorías y bajas tienen correlaciones modulares, incluida
la concentración de bajas por fecha. No se seleccionó una fórmula por tiempos
favorables ni se manipularon filas posteriormente para obtener este Top 5.

CURRENT_DATE está anclado a 2026-09-23. Ejecutar el reporte otro día cambia su
población; el dump conserva fechas, no un día móvil. Cualquier fase posterior
debe validar ese contexto antes de medir, sin corregir fechas silenciosamente.
La ejecución diagnóstica y VACUUM pueden afectar cachés; no se presupone un estado
de caché fría ni equivalencia física universal entre reconstrucciones.

La siguiente fase autorizable es obtener un baseline bajo un protocolo comparable.
Esta fase no eligió entre columna redundante y vista materializada, no implementó
ninguna de ellas y no autoriza avanzar automáticamente a la Parte 2.
