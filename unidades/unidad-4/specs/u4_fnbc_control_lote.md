# Spec — Unidad 4 — FNBC — ControlLoteAlmacen

## 1. Contexto

Food Store incorpora una extensión mayorista donde se controlan lotes

de mercadería desde depósitos.

Relación inicial conceptual:

ControlLoteAlmacen(

    LoteID,

    DepositoID,

    ResponsableControlID

)

Reglas de negocio confirmadas por la consigna:

R1.

Para un lote y un depósito dados existe un único responsable de control.

Notación:

{LoteID, DepositoID} -> ResponsableControlID

R2.

Cada responsable de control pertenece a un único depósito.

Notación:

ResponsableControlID -> DepositoID

IMPORTANTE:

Estas dependencias provienen de reglas de negocio de la consigna.

No deben inferirse solamente observando los datos.

## 2. Clausuras

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

{DepositoID, ResponsableControlID}+

= {DepositoID, ResponsableControlID}

## 3. Claves candidatas

Conjunto completo:

- {LoteID, DepositoID}

- {LoteID, ResponsableControlID}

Atributos primos:

- LoteID

- DepositoID

- ResponsableControlID

No hay atributos no primos.

## 4. Diagnóstico FNBC

La relación NO cumple FNBC.

Dependencia violatoria:

ResponsableControlID -> DepositoID

Justificación:

ResponsableControlID no es superclave porque su clausura es:

{ResponsableControlID, DepositoID}

y no permite obtener LoteID.

FNBC exige que todo determinante de una dependencia funcional no trivial

sea superclave.

## 5. Anomalías

Instancia de referencia:

(501, 30, 801)

(502, 30, 801)

(503, 31, 802)

ACTUALIZACIÓN:

801 aparece asociado al depósito 30 en más de una fila.

Si cambia de depósito deben modificarse todas las filas.

Una actualización parcial genera inconsistencia.

INSERCIÓN:

No puede registrarse la relación maestro

ResponsableControlID -> DepositoID

para un responsable nuevo si todavía no existe un lote que controlar.

BORRADO:

Si se elimina la única fila correspondiente al responsable 802,

también se pierde el único registro que indica que pertenece al depósito 31.

## 6. Descomposición objetivo

Separar el dato maestro del dato transaccional.

Tabla 1:

responsable_control_deposito(

    responsable_control_id PK,

    deposito_id FK

)

Debe representar:

ResponsableControlID -> DepositoID

Tabla 2:

control_lote_responsable(

    lote_id,

    responsable_control_id,

    PK(lote_id, responsable_control_id)

)

Debe contener las relaciones transaccionales de control.

La columna común de ambas tablas es:

responsable_control_id

## 7. Descomposición sin pérdida

Justificación:

responsable_control_id

es clave primaria de responsable_control_deposito.

Por lo tanto, el atributo común es superclave de al menos una de las

relaciones resultantes.

La reconstrucción conceptual es:

control_lote_responsable

JOIN responsable_control_deposito

USING (responsable_control_id)

## 8. Vista de compatibilidad

Crear la vista de compatibilidad (validada en el Bloque 2):

v_control_lote_almacen

que exponga exactamente:

- lote_id

- deposito_id

- responsable_control_id

y reconstruya la relación original mediante JOIN.

## 9. Modelo oficial y tablas de apoyo

El modelo oficial de Food Store contiene `usuario`, incluido su borrado
lógico mediante `eliminado`. Unidad 4 no crea, inserta ni elimina usuarios.
`responsable_control_id` mantiene su FK hacia `usuario(id)`.

Solo `deposito` y `lote` son tablas maestras mínimas creadas por esta
extensión académica en la copia de laboratorio, sin modificar schema.sql.
El archivo raíz conserva el modelo histórico y no es el bootstrap de la
copia oficial que requiere esta práctica.

Antes de crear las tablas del ejercicio, consultar:

```sql
SELECT id
FROM usuario
WHERE id IN (801, 802)
  AND eliminado = FALSE;
```

El Bloque 2 confirmó exactamente dos usuarios. Al reproducir, el script
incluye una guarda que aborta si falta alguno o está eliminado. No debe
insertar usuarios auxiliares para suplir esta precondición.

## 10. Instancia mínima

Datos maestros necesarios:

lotes:

501

502

503

depósitos:

30

31

responsables/usuarios:

801

802

Instancia original:

(501, 30, 801)

(502, 30, 801)

(503, 31, 802)

## 11. Migración

El script final debe seguir esta secuencia:

1. Validar los dos usuarios preexistentes y crear solo deposito y lote.

2. Crear control_lote_almacen original.

3. Insertar la instancia proporcionada.

4. Crear responsable_control_deposito.

5. Migrar con SELECT DISTINCT responsable_control_id, deposito_id.

6. Crear control_lote_responsable.

7. Migrar lote_id y responsable_control_id.

8. Crear v_control_lote_almacen.

9. Verificar equivalencia.

Todo debe ejecutarse dentro de una transacción.

## 12. Verificaciones obligatorias

A. Conteo antes/después.

B. EXCEPT original menos vista:

SELECT lote_id, deposito_id, responsable_control_id

FROM control_lote_almacen

EXCEPT

SELECT lote_id, deposito_id, responsable_control_id

FROM v_control_lote_almacen;

Debe devolver 0 filas.

C. EXCEPT vista menos original:

SELECT lote_id, deposito_id, responsable_control_id

FROM v_control_lote_almacen

EXCEPT

SELECT lote_id, deposito_id, responsable_control_id

FROM control_lote_almacen;

Debe devolver 0 filas.

Ambas direcciones son obligatorias:

una detecta pérdida y la otra filas espurias.

## 13. Preservación de dependencias

Después de la descomposición:

ResponsableControlID -> DepositoID

queda preservada localmente en responsable_control_deposito.

Pero:

{LoteID, DepositoID} -> ResponsableControlID

ya no puede verificarse observando una sola tabla.

Esto es un costo posible de una descomposición a FNBC.

No inventar un trigger todavía.

El eventual mecanismo para preservar R1 debe decidirse y documentarse

separadamente antes de implementarlo.

## 14. Reversibilidad

El SQL final debe permitir rollback transaccional durante las pruebas.

El script documenta un DOWN manual, revisado estáticamente. No se ejecutó

la reversión sobre la copia medida.

El DOWN elimina exclusivamente los objetos creados por Unidad 4, nunca
la tabla base usuario. Antes de ejecutar, crear y verificar un backup de
la copia oficial fuera del repositorio; el respaldo histórico no acredita
protección de esta nueva base. No versionar el dump.

## 15. Criterios de aceptación

**VALIDATION_STATUS: PASS_ON_OFFICIAL_MODEL**. PostgreSQL 17.11,
foodstore_u4_oficial. El Bloque 2 confirmó diagnóstico de F2 = 0 violaciones
observadas, conteos 3 / 3 y EXCEPT 0 / 0. La instancia respeta la regla;
la dependencia proviene del negocio, no se deduce únicamente de esos datos.
Los usuarios 801/802 se reutilizaron y la tabla usuario permaneció intacta.
Ver [evidencia oficial](../informes/evidencia_modelo_oficial.md).
Los criterios siguientes se conservan como contrato de aceptación:

- Exactamente dos usuarios no eliminados (801 y 802) antes de crear tablas.
- No crear, insertar ni eliminar usuario desde este laboratorio.

- Dependencias funcionales correctas.

- Clausuras documentadas.

- Dos claves candidatas identificadas.

- Todos los atributos reconocidos como primos.

- Violación FNBC correctamente demostrada.

- Tres anomalías documentadas.

- Descomposición sin pérdida justificada.

- Datos migrados sin pérdida.

- COUNT coincide.

- EXCEPT en ambas direcciones devuelve 0 filas.

- Vista de compatibilidad reconstruye exactamente la relación original.

- No se modifica schema.sql.

- No se ejecuta SQL durante la creación de esta spec.
