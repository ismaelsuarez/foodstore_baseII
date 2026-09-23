# Unidad 4 — Revalidación FNBC sobre el modelo canónico

## Resultado y alcance

**Ejecución FNBC: PASS.** La migración reconstruyó 3 / 3 filas, con diagnóstico
de F2 = 0, EXCEPT bidireccional = 0 / 0 y cero duplicados o filas espurias.
Las cuatro pruebas negativas rechazaron las operaciones por las restricciones
previstas. El DOWN se ejecutó realmente y dejó el laboratorio sin objetos FNBC.

Esta evidencia corresponde únicamente a la Parte 1. No acredita Parte 2,
rendimiento, desnormalización ni concurrencia. No se ejecutaron benchmarks.
El checkpoint Git se revisa separadamente: este documento registra la ejecución,
no presupone que ya se haya creado un commit.

## 1. Entorno y fuentes

| Dato | Valor |
|---|---|
| Fecha | 2026-09-23 |
| Motor | PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit |
| Repositorio | C:\Users\facu\Documents\UTN\Base_datos_II\foodStore |
| Rama de trabajo | fix/u4-revalidacion-canonica |
| Commit base | e5282f68a4af6975fb953c4f4b74f2e13240a0a6 |
| Base descartable exclusiva | foodstore_u4_revalidacion |
| Bootstrap | schema.sql y datos_iniciales.sql del commit base |
| Optimización heredada | Los tres índices aceptados de TP5 |
| TPI | EXCLUDED_FROM_PRIMARY_U4_BASELINE |
| Parte 2 | NOT_INSTALLED_NOT_EXECUTED |

Artefactos: [spec FNBC](../specs/u4_fnbc_control_lote.md) y
[SQL ejecutado](../sql/tp_fnbc_control_lote.sql).
La [evidencia anterior del laboratorio foodstore_u4_oficial](evidencia_modelo_oficial.md)
se conserva como antecedente histórico, sin trasladar sus métricas a este ensayo.
README e informes anteriores permanecen intactos por el alcance autorizado.

## 2. Fixture y dependencias funcionales

No se creó, insertó, actualizó ni eliminó ningún usuario. Se reutilizaron
Ana Gómez (id 1) y Luis Paz (id 2), ambos no eliminados. El identificador lógico
801 del ejemplo se mapea a 1; 802 se mapea a 2. Son fixtures, no reglas del dominio.

| LoteID (L) | DepositoID (D) | ResponsableControlID (R) |
|---:|---:|---:|
| 501 | 30 | 1 |
| 502 | 30 | 1 |
| 503 | 31 | 2 |

Las reglas de negocio son **F1: LD → R** y **F2: R → D**. Provienen de la
consigna; no se deducen de coincidencias de la instancia mínima.

| Clausura | Resultado |
|---|---|
| L+ | {L} |
| D+ | {D} |
| R+ | {R,D} |
| LD+ | {L,D,R} |
| LR+ | {L,R,D} |
| DR+ | {D,R} |

Las claves candidatas son exactamente **{L,D} y {L,R}**. L nunca aparece en
el lado derecho de una DF, por lo que toda clave debe contenerlo. L solo no
es superclave; agregar D o R produce toda la relación. Ambas parejas son
mínimas; LDR no lo es. No existen otras claves mínimas.

L, D y R son atributos primos porque pertenecen a alguna clave candidata.
No hay atributos no primos.

## 3. FNBC y anomalías

FNBC exige que el determinante de toda DF no trivial sea superclave.
F1 no viola esta condición: LD es clave. **F2 sí la viola**: R+ = RD no contiene
L, por lo que R no es superclave. Que todos los atributos sean primos permite
3FN bajo estas DF, pero no convierte la relación en FNBC.

- **Actualización:** el responsable 1 tiene depósito 30 en dos filas. Cambiar
  una sola rompe R → D; cambiar su asignación exige modificar ambas.
- **Inserción:** no puede almacenarse solamente que un responsable pertenece
  a un depósito sin contar todavía con un lote para completar la relación.
- **Borrado:** eliminar el único control del responsable 2 hace desaparecer
  la única evidencia de su pertenencia al depósito 31.

## 4. Descomposición y garantías formales

Aplicando la DF violatoria R → D sobre S(L,D,R):

- S1(R,D): `responsable_control_deposito`, PK R, FK R → usuario y D → deposito.
- S2(L,R): `control_lote_responsable`, PK (L,R), FK L → lote y R → S1.

Las columnas son BIGINT NOT NULL. R determina toda S1; en S2 no hay una DF
no trivial proyectada con determinante no superclave. Ambas están en FNBC.

**Unión sin pérdida:** S1 ∩ S2 = {R}; R → RD = S1. El atributo común determina
una relación completa, cumpliendo el criterio binario de lossless join.

**Preservación parcial:** F2 queda garantizada localmente por la PK de S1.
F1 no queda preservada: bajo la unión de las DF proyectadas, LD+ = LD, sin R.
La comprobación de F1 requiere reconstruir el JOIN u otro mecanismo adicional;
esta fase no inventa un trigger para ello.

Contraejemplo conceptual, no cargado: RD = {(1,30),(2,30)} y
LR = {(501,1),(501,2)} satisfacen sus claves locales, pero el JOIN genera
(501,30,1) y (501,30,2), violando LD → R. Esto no contradice la unión sin
pérdida de las proyecciones de una instancia original válida.

## 5. Ejecución y catálogo académico

Comando ejecutado desde la raíz, con salida completa inspeccionada:

```powershell
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_u4_revalidacion -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f .\unidades\unidad-4\sql\tp_fnbc_control_lote.sql
```

**Exit code 0; seis NOTICE PASS; errores SQL inesperados: 0.** No se utilizó
`-1`: el script administra BEGIN/COMMIT y sus SAVEPOINT. Su guarda exige la base
autorizada y los responsables 1/2 vigentes antes de crear objetos.

SHA-256 de los bytes del SQL efectivamente ejecutado, antes de staging:
`A38F4C557D3DE034C3E9AE10028ACEB64B45975FBF9B0CB180237CEBB1992BDC`.
Git advirtió normalización LF/CRLF al tocar el archivo; esta huella identifica
los bytes de ejecución, no promete igualdad con otra representación de saltos.

| Objeto creado | Función | PK verificada |
|---|---|---|
| deposito | Maestro auxiliar: 30,31 | deposito_pkey (id) |
| lote | Maestro auxiliar: 501,502,503 | lote_pkey (id) |
| control_lote_almacen | Instancia original | pk_control_lote_almacen (lote_id, deposito_id) |
| responsable_control_deposito | Proyección RD | responsable_control_deposito_pkey (responsable_control_id) |
| control_lote_responsable | Proyección LR | pk_control_lote_responsable (lote_id, responsable_control_id) |
| v_control_lote_almacen | JOIN de reconstrucción | No corresponde |

El catálogo confirmó **9 columnas BIGINT NOT NULL, 5 PK y 7 FK**, todas las
restricciones validadas (`convalidated = true`). Las FK académicas usan NO ACTION:

| Restricción | Referencia |
|---|---|
| fk_control_lote_lote | control_lote_almacen.lote_id → lote.id |
| fk_control_lote_deposito | control_lote_almacen.deposito_id → deposito.id |
| fk_control_lote_responsable | control_lote_almacen.responsable_control_id → usuario.id |
| fk_responsable_control_usuario | responsable_control_deposito.responsable_control_id → usuario.id |
| fk_responsable_control_deposito | responsable_control_deposito.deposito_id → deposito.id |
| fk_control_lote_responsable_lote | control_lote_responsable.lote_id → lote.id |
| fk_control_lote_responsable_maestro | control_lote_responsable.responsable_control_id → responsable_control_deposito.responsable_control_id |

Consulta reproducible del catálogo mientras los objetos están instalados:

```sql
SELECT conrelid::regclass AS tabla, conname, contype, convalidated,
       pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE conrelid IN ('deposito'::regclass, 'lote'::regclass,
 'control_lote_almacen'::regclass, 'responsable_control_deposito'::regclass,
 'control_lote_responsable'::regclass)
ORDER BY conrelid::regclass::text, conname;
```

## 6. Migración, equivalencia y negativos

RD resultante: (1,30), (2,31). LR resultante: (501,1), (502,1), (503,2).
La vista reconstruyó exactamente el fixture original.

| Comprobación observada | Resultado |
|---|---:|
| Diagnóstico de F2 | 0 filas |
| Filas originales / reconstruidas | 3 / 3 |
| Original EXCEPT vista / vista EXCEPT original | 0 / 0 |
| Grupos duplicados / filas espurias | 0 / 0 |

Las consultas originales están en el script. Su equivalencia se puede repetir
antes del DOWN con `SELECT * FROM control_lote_almacen EXCEPT SELECT * FROM
v_control_lote_almacen` y el EXCEPT inverso. EXCEPT no conserva multiplicidades:
también se agruparon las tres columnas de la vista con `HAVING COUNT(*) > 1`.

| Prueba negativa ejecutada | SQLSTATE real | CONSTRAINT_NAME real |
|---|---|---|
| Responsable 1 repetido con depósito distinto | 23505 | responsable_control_deposito_pkey |
| Control con responsable ausente de RD | 23503 | fk_control_lote_responsable_maestro |
| Control con lote inexistente | 23503 | fk_control_lote_responsable_lote |
| Maestro con depósito inexistente | 23503 | fk_responsable_control_deposito |

Cada caso usó SAVEPOINT, captura exclusiva del SQLSTATE esperado y diagnóstico
de la restricción, seguido de ROLLBACK TO y RELEASE. El último caso eliminó
temporalmente un control y un maestro del responsable 2 para aislar la FK de
depósito; ambas filas se restauraron. La aserción posterior confirmó la instancia
intacta. No se capturaron indiscriminadamente errores mediante WHEN OTHERS.

## 7. DOWN real y preservación del modelo canónico

Se extrajo íntegramente la sección DOWN comentada del SQL, comprobando una única
guarda y exactamente seis DROP permitidos. Se ejecutó con psql `-c`, misma base,
ON_ERROR_STOP y transacción. Resultado: **exit code 0**, BEGIN, guarda DO,
un DROP VIEW, cinco DROP TABLE y COMMIT. No hubo reinstalación posterior.

El orden ejecutado fue:

```sql
BEGIN;
DO $$ BEGIN
 IF current_database() <> 'foodstore_u4_revalidacion' THEN
  RAISE EXCEPTION 'Base no autorizada para DOWN FNBC';
 END IF;
END; $$;
DROP VIEW v_control_lote_almacen;
DROP TABLE control_lote_responsable;
DROP TABLE responsable_control_deposito;
DROP TABLE control_lote_almacen;
DROP TABLE lote;
DROP TABLE deposito;
COMMIT;
```

No se usó CASCADE ni se eliminó una tabla canónica. El snapshot JSON previo y
posterior fue exactamente idéntico: **12.650 caracteres**, incluyendo columnas,
tipos, defaults, NOT NULL, IDENTITY, 18 restricciones canónicas, definiciones de
14 índices, OID de objetos, ENUM, secuencias y huellas ordenadas de datos.

| Tabla canónica | OID conservado | Filas | Huella MD5 conservada |
|---|---:|---:|---|
| categoria | 17380 | 2 | 23c8f1d81e0752a59bdb828e6994c898 |
| usuario | 17390 | 3 | eec16e64bda5b3e9ad39517d33786724 |
| producto | 17403 | 3 | b58f43e64795fb0b3874d656efe86af0 |
| pedido | 17422 | 5 | 3fc25026ebda60936ef78d8e71244e94 |
| detalle_pedido | 17439 | 7 | 23982feba359823b9a55d40d24a12563 |

Las huellas se calcularon por tabla como
`md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text)`. Son controles de no alteración,
no garantías criptográficas contra manipulación deliberada. Los OID corresponden
a esta ejecución, no son identificadores portables. Las secuencias conservaron
sus valores 2 / 3 / 3 / 5 / 7 en el mismo orden de tablas.

Los seis índices explícitos conservados son `idx_producto_categoria`,
`idx_pedido_usuario`, `idx_producto_nombre_vig`, `idx_producto_stock_bajo`,
`idx_pedido_fecha_reciente` e `idx_usuario_mail_lower`.

## 8. Estado final observado

- Cinco tablas canónicas; conteos categoria/usuario/producto/pedido/detalle:
  **2 / 3 / 3 / 5 / 7**, sin alteración del seed.
- **0 objetos FNBC**, **0 vistas/materializadas**, **0 rutinas no sistema**
  y **0 triggers no internos**. Los triggers internos de FK no se confunden
  con triggers académicos o TPI.
- `detalle_pedido.categoria_id`: **ausente**.
- Subtotales inconsistentes: **0**. Totales inconsistentes: **0**.
- TPI sigue excluido; Parte 2 no instalada ni ejecutada.
- Schema raíz, seed, Unidad 3, TPI y evidencia anterior no fueron editados.

La Fase 2 acredita el ejercicio FNBC y su reversibilidad real en este laboratorio.
La ausencia de preservación local de F1 es una limitación formal explícita, no
un resultado ocultado por el fixture. Cualquier trabajo de Parte 2 requiere una
nueva autorización y mediciones propias.
