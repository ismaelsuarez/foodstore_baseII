# Informe — Unidad 4

## FNBC y Desnormalización Controlada — Food Store

Integrantes:

- Avalos Pablo

- Blangetti Sofia

- Suarez Ismael

---

## 1. Objetivo

El trabajo tuvo dos partes:

1. Analizar y descomponer una relación que viola FNBC.

2. Aplicar una desnormalización controlada basada en evidencia real

   de EXPLAIN ANALYZE.

Todas las pruebas se realizaron sobre la copia:

foodstore_u4

y nunca sobre una base productiva.

---

## 2. Parte 1 — ControlLoteAlmacen

Relación:

ControlLoteAlmacen(

    LoteID,

    DepositoID,

    ResponsableControlID

)

Reglas de negocio:

F1:

{LoteID, DepositoID} -> ResponsableControlID

F2:

ResponsableControlID -> DepositoID

---

## 3. Clausuras y claves candidatas

{LoteID, DepositoID}+

= {LoteID, DepositoID, ResponsableControlID}

{LoteID, ResponsableControlID}+

= {LoteID, ResponsableControlID, DepositoID}

ResponsableControlID+

= {ResponsableControlID, DepositoID}

LoteID+

= {LoteID}

DepositoID+

= {DepositoID}

Claves candidatas:

- {LoteID, DepositoID}

- {LoteID, ResponsableControlID}

Todos los atributos son primos.

---

## 4. Violación de FNBC

La dependencia:

ResponsableControlID -> DepositoID

viola FNBC porque ResponsableControlID no es superclave.

Su clausura es:

{ResponsableControlID, DepositoID}

y no permite obtener LoteID.

FNBC exige que todo determinante de una dependencia funcional no

trivial sea superclave.

---

## 5. Anomalías

Instancia de referencia:

(501, 30, 801)

(502, 30, 801)

(503, 31, 802)

Anomalía de actualización:

801 aparece asociado al depósito 30 en más de una fila.

Si cambia de depósito deben modificarse todas las filas.

Una actualización parcial genera inconsistencia.

Anomalía de inserción:

No puede registrarse la relación maestro

ResponsableControlID -> DepositoID

para un responsable nuevo si todavía no existe un lote que controlar.

Anomalía de borrado:

Si se elimina la única fila correspondiente al responsable 802,

también se pierde el único registro que indica que pertenece al depósito 31.

---

## 6. Descomposición

Tabla 1:

responsable_control_deposito(

    responsable_control_id PK,

    deposito_id FK

)

Tabla 2:

control_lote_responsable(

    lote_id,

    responsable_control_id,

    PK(lote_id, responsable_control_id)

)

Vista de compatibilidad:

v_control_lote_almacen

El JOIN es sin pérdida porque:

responsable_control_id

es atributo común y clave primaria de responsable_control_deposito.

Por lo tanto es superclave de al menos una de las relaciones resultantes,

lo que garantiza la propiedad de descomposición sin pérdida.

---

## 7. Verificación real — Parte 1

Consulta diagnóstica ResponsableControlID -> DepositoID:

0 filas

Conteo:

filas_original = 3

filas_reconstruidas = 3

EXCEPT original menos vista:

0 filas

EXCEPT vista menos original:

0 filas

Conclusión:

la vista reconstruye exactamente la instancia original sin pérdida

ni filas espurias.

---

## 8. Preservación de dependencias

Después de la descomposición:

ResponsableControlID -> DepositoID

queda preservada localmente en responsable_control_deposito.

Pero:

{LoteID, DepositoID} -> ResponsableControlID

ya no puede validarse observando una única tabla.

Esto es un costo posible de una descomposición a FNBC.

---

## 9. Parte 2 — Contexto real

La consigna teórica utiliza:

dp.subtotal

dp.eliminado

ped.eliminado

CURRENT_DATE

El schema real no contiene esas columnas.

Se adaptó correctamente:

subtotal =

dp.cantidad * dp.precio_unitario

No se inventaron columnas.

pedido.fecha es TIMESTAMPTZ.

CURRENT_DATE durante la práctica era:

2026-09-19

pero el dataset contiene pedidos entre:

2026-03-01 y 2026-04-11

Pedidos de CURRENT_DATE:

0

Por lo tanto se utilizó:

ped.fecha >= DATE '2026-04-11'

AND ped.fecha < DATE '2026-04-12'

Ese día:

4160 pedidos

10400 detalles

---

## 10. Baseline — EXPLAIN ANALYZE

Cinco mediciones reales:

1. 234.451 ms

2. 369.073 ms

3. 231.651 ms

4. 239.969 ms

5. 266.980 ms

Mediana:

239.969 ms

Plan principal:

Parallel Seq Scan detalle_pedido

Parallel Seq Scan pedido

Parallel Hash Join

Nested Loop hacia producto

Index Scan producto_pkey

producto_pkey:

aprox. 10400 ejecuciones

Buffers totales:

aprox. 36400

producto_pkey:

aprox. 31200 buffers

El Sort final:

quicksort, aprox. 25 kB

Conclusión:

el Sort no era el cuello de botella principal.

---

## 11. Desnormalización elegida

Patrón:

Agregar:

detalle_pedido.categoria_id

Fuente de verdad:

producto.categoria_id

Mantenimiento:

triggers

Objetivo:

eliminar el JOIN detalle_pedido -> producto del reporte frecuente.

Se eligió este patrón y no una vista materializada porque:

- el panel requiere actualización frecuente;

- una vista materializada introduce staleness entre refresh;

- la columna redundante permite sincronización inmediata;

- el patrón ataca directamente el JOIN identificado como costoso

  en la medición de EXPLAIN ANALYZE.

---

## 12. Mecanismos de sincronización

A. trg_detalle_pedido_set_categoria

Ante INSERT o cambio de producto_id en detalle_pedido:

obtiene automáticamente producto.categoria_id y lo asigna.

La aplicación no es responsable de decidir categoria_id.

B. trg_producto_sync_categoria_detalle

Si cambia producto.categoria_id:

actualiza detalle_pedido.categoria_id en todas las filas cuyo

producto_id corresponda al producto modificado.

Costo documentado:

un cambio de categoría puede provocar muchas escrituras sobre datos

históricos.

---

## 13. Validación funcional

Backfill:

500007 filas

categoria_id NULL:

0

Auditoría inicial:

0 filas

Resultado consulta normalizada:

Pizzas  = 45884942.00

Bebidas = 28581501.00

Resultado consulta desnormalizada:

Pizzas  = 45884942.00

Bebidas = 28581501.00

EXCEPT original menos desnormalizada:

0 filas

EXCEPT desnormalizada menos original:

0 filas

---

## 14. Pruebas de triggers

Prueba A:

pedido 1 / producto 3 / categoría 2

Se modificó temporalmente producto_id:

3 -> 2

Resultado:

categoria_id = 1

categoria_producto = 1

ROLLBACK ejecutado.

Prueba B:

producto 1

categoría temporal:

1 -> 2

detalles asociados:

3

detalles sincronizados:

3

desincronizados:

0

Auditoría global:

0 filas

ROLLBACK ejecutado.

Auditoría permanente final:

desincronizados = 0

---

## 15. Efecto físico del backfill

Después del UPDATE masivo de 500007 filas:

detalle_pedido antes de compactación:

61 MB

7844 páginas

0 filas muertas tras autovacuum

Se realizó:

VACUUM (FULL, ANALYZE) detalle_pedido;

Después:

33 MB

4167 páginas

500007 filas vivas

0 filas muertas

La medición preliminar de:

291.049 ms

NO se utilizó en el benchmark oficial porque fue realizada antes de

compactar la expansión física provocada por el backfill.

Esta medición no se oculta: se documenta aquí para transparencia.

---

## 16. Mediciones después

Cinco mediciones oficiales posteriores al VACUUM:

1. 341.932 ms

2. 220.722 ms

3. 243.586 ms

4. 217.185 ms

5. 211.096 ms

Mediana:

220.722 ms

Comparación:

ANTES:  239.969 ms

DESPUÉS: 220.722 ms

Diferencia: 19.247 ms

Reducción aproximada: 8.02 %

Speedup aproximado: 1.09x

Buffers:

ANTES:  ~36400

DESPUÉS: ~5690

Reducción aproximada de buffers: ~84.4 %

---

## 17. Cambio de plan

ANTES:

detalle_pedido

-> JOIN pedido

-> Nested Loop

-> producto_pkey x 10400

-> categoria

DESPUÉS:

detalle_pedido

-> Parallel Hash Join pedido

-> Hash Join categoria

Desaparece completamente:

- JOIN con producto

- Nested Loop hacia producto

- 10400 Index Scan sobre producto_pkey

---

## 18. Evidencia representativa — EXPLAIN ANALYZE

Estas salidas corresponden a ejecuciones reales realizadas durante

la práctica. No se inventaron valores ni se modificaron los tiempos.

### Antes de la desnormalización

```text
Limit
  -> Sort
       Sort Method: quicksort  Memory: 25kB
       -> Finalize GroupAggregate
            -> Gather Merge
                 -> Partial HashAggregate
                      -> Hash Join
                           -> Nested Loop
                                -> Parallel Hash Join
                                     -> Parallel Seq Scan on detalle_pedido
                                     -> Parallel Seq Scan on pedido
                                          Filter:
                                          fecha >= '2026-04-11'
                                          AND fecha < '2026-04-12'
                                          Rows Removed by Filter: 195845
                                -> Index Scan using producto_pkey on producto
                                     loops=10400
                                     Buffers: shared hit=31201
                           -> Seq Scan on categoria

Buffers: shared hit=36401
Execution Time: 234.451 ms
```

Esta es una ejecución representativa del plan baseline.

Las cinco corridas y la mediana de 239.969 ms se encuentran en

la sección 10. El valor 234.451 ms no se utiliza como mediana; se

muestra únicamente para evidenciar la estructura real del plan.

### Después de la desnormalización

Tomado de la quinta medición oficial (211.096 ms):

```text
Limit
  -> Sort
       Sort Method: quicksort  Memory: 25kB
       -> Finalize GroupAggregate
            -> Gather Merge
                 -> Partial HashAggregate
                      -> Hash Join
                           Hash Cond: (dp.categoria_id = c.id)
                           -> Parallel Hash Join
                                Hash Cond: (dp.pedido_id = ped.id)
                                -> Parallel Seq Scan on detalle_pedido
                                     Buffers: shared hit=496 read=3671
                                -> Parallel Seq Scan on pedido
                                     Filter:
                                     fecha >= '2026-04-11'
                                     AND fecha < '2026-04-12'
                                     Rows Removed by Filter: 195845
                           -> Seq Scan on categoria

Buffers: shared hit=2019 read=3671
Execution Time: 211.096 ms
```

Esta es una ejecución representativa posterior.

Las cinco corridas y la mediana de 220.722 ms se encuentran en

la sección 16.

### Comparación de planes

- Desaparece el Nested Loop hacia producto.

- Desaparecen las 10400 búsquedas por producto_pkey.

- El reporte pasa de cuatro tablas a tres.

- El Sort continúa siendo pequeño y no domina el costo.

- Los tiempos representativos individuales no sustituyen las medianas.

---

## 19. Conclusión

La mejora temporal fue moderada (~8 %).

La reducción de buffers fue muy importante (~84 %).

El plan quedó estructuralmente más simple.

La desnormalización tiene costo de escritura y mayor complejidad

de mantenimiento.

No puede afirmarse que sea una mejora universal.

Para este reporte y este dataset, la evidencia medida justifica la

decisión.

---

## 20. Reversibilidad

La Parte 1 tiene plan DOWN documentado.

La Parte 2 tiene plan DOWN documentado.

producto.categoria_id nunca dejó de ser fuente de verdad.

Eliminar detalle_pedido.categoria_id no pierde información original.

Existe backup externo previo:

backups/foodstore_u4_pre_u4.dump

El dump no está incluido en Git.

---

## 21. Artefactos relacionados

../specs/u4_fnbc_control_lote.md

../sql/tp_fnbc_control_lote.sql

../specs/u4_desnormalizacion_top_categorias.md

../sql/tp_desnormalizacion_top_categorias.sql
