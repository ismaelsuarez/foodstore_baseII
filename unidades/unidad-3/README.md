# Food Store — Base de Datos II

## TP Unidad 3 — Semana 5
## Índices, vistas y vistas materializadas — Modelo oficial

**Entrega vigente:** contratos corregidos y validación real en PostgreSQL
17.11 sobre `foodstore_tp5_oficial`. Los tres índices se aceptan para el
TP; las cuatro vistas, la seguridad y la materializada fueron verificadas.

## Integrantes

- Avalos Pablo
- Blangetti Sofia
- Suarez Ismael

## Ruta de lectura

1. [Informe vigente](informes/informe_mediciones.md): decisiones y resultados resumidos.
2. [Evidencia técnica](informes/evidencia_modelo_oficial.md): consultas exactas,
   corridas, planes completos, controles y bootstrap/carga del laboratorio.
3. [DUIA vigente](duia/duia.md): corrección del modelo, uso de herramientas
   y decisiones humanas.

El contrato utiliza `usuario`, `usuario_id`, `mail`, `eliminado`,
`disponible`, `estado`, `total` y `subtotal` físico. Disponibilidad y
eliminación lógica tienen semánticas distintas. El subtotal almacenado
no se reemplaza por una expresión calculada en las consultas vigentes.

## Base utilizada y límites

| Dato | Valor registrado |
|---|---|
| Motor | PostgreSQL 17.11, Windows x86_64 |
| Base descartable | `foodstore_tp5_oficial` |
| Fecha local de ejecución | 20/09/2026, America/Buenos_Aires |
| Filas | 8 categorías; 50.000 productos; 20.000 usuarios; 200.000 pedidos; 500.000 detalles |

**El `schema.sql` raíz no reconstruye esta base:** conserva el esquema
histórico anterior. Tampoco deben aplicarse los datos iniciales raíz ni
la carga de TP3 para reproducir estas mediciones. No se modificaron esos
archivos ni otros trabajos prácticos.

La copia descartable usa el contrato oficial aportado por el usuario.
El bootstrap temporal registra los supuestos adicionales de laboratorio
sobre tipos, nulabilidad y carga sintética: no es una migración ni un
nuevo esquema canónico entregable. Los tiempos no son universales y no
se garantiza repetirlos en otra máquina o corrida.

## Scripts y specs vigentes

| Script | Alcance |
|---|---|
| [sql/queries.sql](sql/queries.sql) | Ocho consultas manuales de referencia. |
| [sql/indices.sql](sql/indices.sql) | Tres índices: stock bajo, pedidos recientes y búsqueda por mail. |
| [sql/views.sql](sql/views.sql) | Cuatro vistas convencionales, incluida la pública de usuarios. |
| [sql/seguridad.sql](sql/seguridad.sql) | GRANT de lectura de la vista pública; requiere rol existente. |
| [sql/materializadas.sql](sql/materializadas.sql) | Facturación por categoría/mes y su índice UNIQUE lógico. |

| Spec | Contrato |
|---|---|
| [indice_producto_stock_bajo.md](specs/indice_producto_stock_bajo.md) | Reposición sin filtrar disponibilidad. |
| [indice_pedido_fecha_reciente.md](specs/indice_pedido_fecha_reciente.md) | Fecha DATE, eliminación lógica y cobertura. |
| [indice_usuario_mail_lower.md](specs/indice_usuario_mail_lower.md) | Expresión no UNIQUE para mail. |
| [vista_productos_vigentes.md](specs/vista_productos_vigentes.md) | Producto/categoría no eliminados. |
| [vista_pedidos_resumen.md](specs/vista_pedidos_resumen.md) | Pedidos sin ocultar historial por baja del usuario. |
| [vista_pedido_detalle.md](specs/vista_pedido_detalle.md) | Subtotal físico e historial de producto. |
| [vista_usuarios_publico.md](specs/vista_usuarios_publico.md) | Proyección segura sin contrasena ni celular. |
| [vista_materializada_facturacion_categoria_mes.md](specs/vista_materializada_facturacion_categoria_mes.md) | Agregación histórica y actualización propuesta. |

SQL y specs conservan sus estados de candidato/validación pendiente del
**Bloque 1**, previo a ejecutar. No se reescribieron en este cierre:
los resultados posteriores y la aceptación para el TP constan en el
informe vigente y la evidencia del **Bloque 2**.

## Reproducción controlada

Estas instrucciones son para una nueva ejecución autorizada, no describen
benchmarks nuevos durante el cierre documental. Se requiere PostgreSQL
17.x, `psql`, Git y autenticación local configurada sin exponer secretos.
Ejecutar desde `unidades/unidad-3/`.

### 1. Preparar exclusivamente la copia descartable

Recuperar los archivos temporales del Bloque 2 si todavía existen. Si no,
copiar **literalmente** los dos bloques SQL del **Anexo B** de la
[evidencia](informes/evidencia_modelo_oficial.md) a:

```text
$env:TEMP\foodstore_tp5_oficial_schema.sql
$env:TEMP\foodstore_tp5_oficial_data.sql
```

El primero es el bootstrap; el segundo contiene carga, reconciliación
de totales y `VACUUM ANALYZE`. Revisar ambos antes de aplicarlos.
El bootstrap incluye únicamente PK/UNIQUE e índices base de cátedra,
no los tres candidatos TP5. Confirmar que solo esa base es descartable;
**los comandos siguientes eliminan su contenido** y ningún otro nombre
está autorizado para eliminación.

```powershell
psql --version
psql -X -w -h 127.0.0.1 -U postgres -d postgres -c "SELECT version();"
dropdb -h 127.0.0.1 -U postgres --if-exists foodstore_tp5_oficial
createdb -h 127.0.0.1 -U postgres foodstore_tp5_oficial
psql -X -w -h 127.0.0.1 -U postgres -d foodstore_tp5_oficial -v ON_ERROR_STOP=1 -1 -f "$env:TEMP\foodstore_tp5_oficial_schema.sql"
psql -X -w -h 127.0.0.1 -U postgres -d foodstore_tp5_oficial -v ON_ERROR_STOP=1 -f "$env:TEMP\foodstore_tp5_oficial_data.sql"
```

Verificar el código de salida después de **cada comando**; ante cualquier
error, detenerse. No envolver toda la carga en `-1`: contiene su propia
transacción y un `VACUUM ANALYZE` posterior fuera de ella. Confirmar conteos,
inventario inicial y ausencia de los tres candidatos (evidencia, sección 2).

### 2. Medir índices y costo de escritura

Para cada candidato: `ANALYZE`, tres EXPLAIN antes, creación de **solo ese
índice**, `ANALYZE` y tres EXPLAIN después. Descartar la primera corrida y
promediar 2 y 3. No ejecutar `indices.sql` completo antes de las líneas base.

Usar las consultas exactas de la sección 4 de la evidencia: pedidos utiliza
`CURRENT_DATE - 30`, no el literal fijo de `queries.sql`; mail utiliza
`usuario8452@foodstore.test`, no su literal ilustrativo. Así se conserva
la selectividad prevista al regenerar fechas relativas.

La alternativa covering solo se crea dentro de `BEGIN`/`ROLLBACK` para
medir `pg_relation_size`; verificar después su ausencia. Para escritura,
retirar **solo los tres candidatos**, nunca los índices base, medir 1.000
INSERT en cada tabla, recrearlos mediante `indices.sql`, analizar y repetir.
Cada corrida de INSERT usa `BEGIN`/`ROLLBACK`, con calentamiento y dos
mediciones válidas. Seguir la sección 6 de la evidencia, incluido el
`VACUUM ANALYZE` previo; las secuencias pueden avanzar pese al rollback.

### 3. Validar vistas, seguridad y materializada

```powershell
psql -X -w -h 127.0.0.1 -U postgres -d foodstore_tp5_oficial -v ON_ERROR_STOP=1 -f sql\views.sql
```

Comparar las cuatro vistas individualmente con las consultas 4–7 de
`queries.sql` mediante EXCEPT en ambos sentidos y registrar conteos.
Las comprobaciones ejecutadas están en la sección 7 de la evidencia.

Para seguridad, inventariar primero `rol_soporte`. Si no existe, crear
`NOLOGIN` solo para la prueba, aplicar `seguridad.sql`, comprobar lectura
de vista y denegaciones sobre `contrasena`/`celular` con `SET ROLE`, luego
`RESET ROLE`, revocar y eliminar únicamente el rol creado. Las pruebas
negativas deben capturar SQLSTATE `42501` y permitir el RESET; no evaluar
solo el código de salida de psql. Si el rol ya existe, no alterarlo,
revocarlo ni eliminarlo: limitarse al inventario de privilegios y resolver
por separado la autorización de cualquier cambio. El GRANT no borra
permisos anteriores (sección 8 de la evidencia).

Medir la consulta 8 original **antes** de crear la materializada; después:

```powershell
psql -X -w -h 127.0.0.1 -U postgres -d foodstore_tp5_oficial -v ON_ERROR_STOP=1 -f sql\materializadas.sql
```

Validar EXCEPT bidireccional y medir con el mismo orden del original:
`ORDER BY mes ASC, facturacion_total DESC`. El orden `categoria_id, mes`
es un caso separado. Ejecutar `REFRESH MATERIALIZED VIEW CONCURRENTLY
mv_facturacion_categoria_mes` y repetir equivalencia. Los índices y la
materializada no usan `IF NOT EXISTS`: no reinstalarlos a ciegas sobre
objetos existentes. Esta guía no es una migración de vistas previas.

## Resultados y decisiones

| Objeto | Antes, ms | Después, ms | Decisión |
|---|---:|---:|---|
| `idx_producto_stock_bajo` | 9.4390 | 0.2975 | Aceptado; mejora observada 31.73x. |
| `idx_pedido_fecha_reciente` | 264.3715 | 1.2250 | Aceptado; mejora observada 215.81x. |
| `idx_usuario_mail_lower` | 10.8865 | 0.1360 | Aceptado; mejora observada 80.05x. |
| Materializada, mismo orden | 1188.4945 | 0.2230 | Equivalencia 0/0; 192 filas. |

El covering se rechazó: 2.621.440 frente a 999.424 bytes del simple, sin
beneficio temporal adicional medido. Los INSERT aumentaron +14.96 %,
+9.54 % y +91.88 % en producto, pedido y usuario. Conservar el índice de
mail depende del supuesto de pocas altas frente a búsquedas interactivas;
no es una frecuencia de producción medida.

Las cuatro vistas dieron EXCEPT 0/0. La vista pública permitió lectura y
los accesos directos a las columnas sensibles fallaron con `42501`;
el rol temporal fue eliminado. El refresh concurrente fue **ejecutado**
con éxito, no solo habilitado por el índice UNIQUE.

### Política de refresh

**Propuesta heredada:** cada 60 minutos, pendiente de ratificación del
equipo antes del despliegue. **Ejecución de prueba:** un refresh manual
concurrente exitoso. No se programó una tarea ni se validó esa frecuencia.
La materializada admite staleness; duración y fallos pueden aumentar el
atraso, por lo que no se promete un máximo garantizado de una hora.

## Auditoría contra rúbrica

PASS indica cobertura documentada y, donde corresponde, ejecución real;
no certifica un despliegue de producción.

| Requisito | Estado | Evidencia |
|---|---|---|
| Plan de indexado | PASS | Specs y tres candidatos, inventario y decisiones; informe §§1–4. |
| EXPLAIN antes/después | PASS | Evidencia §4 y anexo A: planes y corridas reales. |
| Costo escritura | PASS | Evidencia §6: INSERT en las tres tablas indexadas. |
| Índice descartado | PASS | Evidencia §5: tamaño covering y rollback. |
| Vistas + EXCEPT | PASS | Evidencia §7: cuatro pares 0/0 y conteos. |
| Seguridad real | PASS | Evidencia §8: SET ROLE, denegaciones 42501 y limpieza. |
| Vista materializada | PASS | Evidencia §9: 192 filas, comparación homogénea y EXCEPT. |
| Índice UNIQUE materializada | PASS | SQL y evidencia §9: clave lógica y refresh exitoso. |
| Refresh policy | PASS | Propuesta explícita de 60 minutos, no automatizada ni ratificada para despliegue. |
| Kiro + IA + revisión humana | PASS | DUIA vigente §1 y DUIA histórica preservada. |
| DUIA | PASS | Declaración vigente separa corrección, ejecución y decisiones. |
| Trazabilidad Git | PASS | Historial previo y renombres preservados; cierre local pendiente de commit, sin SHA nuevo. |

## Evidencia histórica

- [informe_mediciones_historico.md](informes/informe_mediciones_historico.md)
- [duia_historica.md](duia/duia_historica.md)

Ambos corresponden a una iteración basada en un esquema no alineado con
el modelo oficial. Se renombraron mediante `git mv` sin editar su contenido
y se conservan **solo por trazabilidad**, no como solución vigente.
Sus resultados y afirmaciones no se trasladan al informe actual.

La evidencia del Bloque 2 permanece intacta: sus menciones temporales al
informe y DUIA anteriores deben leerse con estos nuevos destinos. Las
referencias externas a Unidad 3 no se modifican dentro de este cierre.

## Puntos para la defensa

1. Por qué eliminación lógica y disponibilidad no son filtros equivalentes.
2. Cómo cambió cada plan realmente y qué aporta `INCLUDE`, sin garantizar optimalidad.
3. Por qué `UNIQUE(mail)` no decide la unicidad de `lower(mail)`.
4. Cómo justificar lectura frente a INSERT y el descarte por tamaño del covering.
5. Qué demuestra EXCEPT y cómo las vistas conservan historial y protegen datos.
6. Por qué se comparan órdenes iguales y qué costo/atraso introduce materializar.
7. Qué corrigió la revisión humana y cómo se distingue evidencia vigente de histórica.
