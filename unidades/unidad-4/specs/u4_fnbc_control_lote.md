# Spec — Unidad 4 — FNBC — ControlLoteAlmacen

Contrato de revalidación sobre `foodstore_u4_revalidacion`, construida con
`schema.sql` y `datos_iniciales.sql` del commit base
`e5282f68a4af6975fb953c4f4b74f2e13240a0a6`, más los tres índices aceptados de TP5.
No instala TPI ni Parte 2. Los resultados nuevos se registran separadamente en
[evidencia de revalidación FNBC](../informes/evidencia_revalidacion_fnbc_modelo_canonico.md);
los criterios de esta spec no sustituyen la ejecución real.

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

Notación abreviada: L = LoteID, D = DepositoID, R = ResponsableControlID.
Las DF son F1: LD -> R y F2: R -> D.

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

Es el conjunto **completo**, no solo dos ejemplos: L no aparece en el lado
derecho de ninguna DF, por lo que toda clave debe contener L. L por sí solo
no es superclave. Agregar D produce LD+ = LDR; agregar R produce LR+ = LRD.
Ambas son mínimas y LDR no lo es porque contiene esas claves. No queda otra
clave mínima posible.

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

F1 no viola FNBC porque LD es clave candidata. F2 sí la viola. La definición
aplicada es la de FNBC, no la de 3FN: bajo estas DF la relación puede satisfacer
3FN (todos los atributos son primos) y aun así no satisfacer FNBC.

## 5. Anomalías

Instancia de referencia:

(501, 30, 1)

(502, 30, 1)

(503, 31, 2)

ACTUALIZACIÓN:

1 aparece asociado al depósito 30 en más de una fila.

Si cambia de depósito deben modificarse todas las filas.

Una actualización parcial genera inconsistencia.

INSERCIÓN:

No puede registrarse la relación maestro

ResponsableControlID -> DepositoID

para un responsable nuevo si todavía no existe un lote que controlar.

BORRADO:

Si se elimina la única fila correspondiente al responsable 2,

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

Aplicación del algoritmo sobre S(L,D,R) usando R -> D:
S1 = RD y S2 = S - (D - R) = LR. En RD, R determina toda la relación;
en LR no queda una DF no trivial proyectada que tenga un determinante no
superclave. Ambas relaciones resultantes satisfacen FNBC bajo estas DF.

Contrato físico:

- `responsable_control_deposito`: responsable_control_id BIGINT PK y FK a
  usuario(id); deposito_id BIGINT NOT NULL y FK a deposito(id).
- `control_lote_responsable`: lote_id y responsable_control_id BIGINT NOT NULL;
  PK del par; FK a lote(id) y a responsable_control_deposito respectivamente.
- Las PK implican NOT NULL. Las FK académicas mantienen la acción predeterminada
  NO ACTION del SQL; no cambian las cuatro FK RESTRICT del modelo canónico.

## 7. Descomposición sin pérdida

Justificación:

responsable_control_id

es clave primaria de responsable_control_deposito.

Por lo tanto, el atributo común es superclave de al menos una de las

relaciones resultantes.

Formalmente, S1 ∩ S2 = {R} y R -> RD = S1. Se cumple el criterio binario
de unión sin pérdida respecto de las DF originales. Esta garantía no equivale
a preservación completa de dependencias en futuras escrituras independientes.

La reconstrucción conceptual es:

control_lote_responsable

JOIN responsable_control_deposito

USING (responsable_control_id)

## 8. Vista de compatibilidad

Crear la vista de compatibilidad (su nueva ejecución debe revalidarse):

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
El archivo raíz actual es el contrato canónico y el bootstrap de esta copia.
La iteración anterior usó otro laboratorio; su evidencia no se modifica.

Antes de crear las tablas del ejercicio, consultar:

```sql
SELECT id
FROM usuario
WHERE id IN (1, 2)
  AND eliminado = FALSE;
```

El seed canónico contiene a Ana Gómez (1) y Luis Paz (2), además de Marta Ruiz
(3). El ejemplo académico se mapea 801 lógico -> usuario 1 y 802 lógico ->
usuario 2. Los identificadores son fixtures del laboratorio, no parte de las DF.
Se requieren ambos responsables vigentes, no que usuario tenga solo dos filas.
El script aborta si falta alguno, está eliminado o la base no es exactamente
`foodstore_u4_revalidacion`. No inserta usuarios auxiliares.

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

1

2

Instancia original:

(501, 30, 1)

(502, 30, 1)

(503, 31, 2)

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

D. Diagnóstico de F2: agrupar por responsable y buscar más de un depósito;
debe retornar 0 filas. Esto prueba compatibilidad de la instancia, no el origen
de la regla de negocio.

E. Buscar duplicados en las tres columnas de la vista: 0 grupos duplicados.
EXCEPT elimina duplicados, por lo que no reemplaza este control de multiplicidad.

F. Aserciones antes del COMMIT: conteos 3 / 3, diagnóstico F2 = 0, EXCEPT 0 / 0,
duplicados = 0; cualquier incumplimiento aborta. Consultar en catálogo las cinco
PK y siete FK de las cinco tablas académicas, sus columnas y destinos.

G. Cuatro pruebas negativas, cada una con SAVEPOINT y ROLLBACK TO / RELEASE:

| Intento | SQLSTATE esperado, pendiente de observar | Restricción objetivo |
|---|---|---|
| Responsable 1 con otro depósito | 23505 | responsable_control_deposito_pkey |
| Control con responsable ausente del maestro RD | 23503 | fk_control_lote_responsable_maestro |
| Control con lote inexistente | 23503 | fk_control_lote_responsable_lote |
| Maestro con depósito inexistente | 23503 | fk_responsable_control_deposito |

Los bloques capturan únicamente el SQLSTATE previsto y obtienen
RETURNED_SQLSTATE / CONSTRAINT_NAME; una restricción distinta o un INSERT
indebidamente aceptado aborta. Los IDs inexistentes se derivan con MAX + 1.
Para aislar la última FK se retiran temporalmente el control y maestro del
responsable 2 dentro de su SAVEPOINT; ROLLBACK TO restaura ambos. No se requiere
un tercer usuario ni se modifica usuario. Una aserción posterior confirma la
restauración de las relaciones descompuestas y la equivalencia.

## 13. Preservación de dependencias

Después de la descomposición:

ResponsableControlID -> DepositoID

queda preservada localmente en responsable_control_deposito.

Pero:

{LoteID, DepositoID} -> ResponsableControlID

ya no puede verificarse observando una sola tabla.

La proyección sobre RD contiene R -> D; la proyección sobre LR no incorpora
una DF no trivial adicional. En la unión de estas proyecciones, (LD)+ = LD:
no puede deducirse R. Por lo tanto F1 **no queda preservada** por la
descomposición; no es solamente una dificultad sintáctica de una consulta.

Contraejemplo conceptual (no es el fixture cargado): RD = {(1,30),(2,30)} y
LR = {(501,1),(501,2)} satisfacen sus claves locales, pero su JOIN produce
(501,30,1) y (501,30,2), violando LD -> R. Esto no contradice la unión sin
pérdida de las proyecciones de una instancia original que satisface las DF.

Esto es un costo posible de una descomposición a FNBC.

No inventar un trigger todavía.

El eventual mecanismo para preservar R1 debe decidirse y documentarse

separadamente antes de implementarlo.

## 14. Reversibilidad

El SQL final debe permitir rollback transaccional durante las pruebas.

El script contiene un DOWN manual comentado, con guarda de base y transacción.
La revalidación exige ejecutarlo realmente después de las comprobaciones:
vista, control_lote_responsable, responsable_control_deposito,
control_lote_almacen, lote y deposito, en ese orden y sin CASCADE.

El DOWN elimina exclusivamente objetos académicos. Antes y después se compara
un snapshot del catálogo y datos canónicos: las cinco tablas y los seis índices
explícitos raíz + TP5 deben permanecer intactos. No restaura dumps anteriores.
El estado final elegido para este laboratorio descartable es sin objetos FNBC,
sin TPI y sin Parte 2. La evidencia nueva debe registrar el DOWN observado;
su resultado no se infiere del orden estático.

## 15. Criterios de aceptación

**Antecedente histórico conservado:** el Bloque 2 registró
PASS_ON_OFFICIAL_MODEL en foodstore_u4_oficial, con usuarios 801/802 y
EXCEPT 0 / 0. Ver [evidencia anterior](../informes/evidencia_modelo_oficial.md).
Ese antecedente no constituye el resultado de la revalidación canónica.

Los siguientes son criterios de aceptación de esta fase. Su resultado real
debe consultarse en la [evidencia nueva](../informes/evidencia_revalidacion_fnbc_modelo_canonico.md):

- Usuarios 1 y 2 existentes y no eliminados antes de crear tablas.
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

- Cuatro rechazos observados por las PK/FK correctas, sin efectos residuales.
- Catálogo verificado y DOWN ejecutado: cero objetos FNBC al finalizar.
- Datos, estructuras canónicas e índices TP5 intactos; TPI y Parte 2 ausentes.
- No se atribuye PASS de ejecución a una validación únicamente estática.
