# DUIA — Declaración de Uso de IA
## Food Store — Unidad 3 / Semana 5 — Modelo oficial

**Declaración vigente.** Esta revisión documenta la corrección de una
iteración previa desalineada con el modelo oficial y las decisiones
humanas basadas en mediciones nuevas. No sustituye ni modifica los relatos
y prompts de la [DUIA histórica](duia_historica.md).

Integrantes: Avalos Pablo, Blangetti Sofia y Suarez Ismael.

## 1. Secuencia real y responsabilidades

| Paso | Participación | Alcance y evidencia |
|---|---|---|
| 1. Especificación original | Kiro | Specs anteriores a generación, según la DUIA histórica. |
| 2. Generación inicial | OpenCode | Candidatos SQL y documentación derivados de esas specs. |
| 3. Revisión humana inicial | Estudiante/equipo | Revisión de propuestas y decisiones registradas en la iteración anterior. |
| 4. Detección posterior | Revisión humana y auditoría asistida | Se identificó la desalineación estructural con el modelo oficial; la revisión inicial no la había resuelto. |
| 5. Contraste oficial | Usuario como fuente del contrato | Se aportó el contrato contrastado con DER, material oficial y resolución modelo; no se exigió copiar todos los índices o tiempos de esa resolución. |
| 6. Rectificación de contratos | Instrucciones humanas | Se fijaron relaciones, eliminación lógica, disponibilidad, fecha DATE, subtotal físico y límites de modificación. |
| 7. Implementación del Bloque 1 | Codex | Corrección de scripts y specs, sin ejecución SQL ni resultados inventados. |
| 8. Ejecución del Bloque 2 | PostgreSQL 17.11, mediante Codex autorizado | Bootstrap y carga temporales, mediciones reales, equivalencias, seguridad y refresh en `foodstore_tp5_oficial`. |
| 9. Decisión final y cierre | Usuario/equipo; documentación asistida por Codex | Aceptación de tres índices, descarte del covering y preservación separada de evidencia histórica. |

La consulta del DER/material se registra a través del contrato oficial
provisto por el usuario. **No se atribuye a Codex una inspección directa
de documentos externos no incorporados a esta ejecución.**

El relato histórico de mediciones manuales pertenece a esa iteración.
En el Bloque 2 corregido, Codex ejecutó comandos autorizados contra
PostgreSQL; el motor produjo tiempos, planes y resultados. No fueron
mediciones manuales del estudiante ni estimaciones generadas por IA.

## 2. Corrección del modelo y control humano

El usuario estableció como contrato vigente `usuario`, `usuario_id`,
`mail`, `eliminado`, `disponible`, `estado`, `total` y `subtotal` físico.
La asistencia automatizada anterior no garantizó ese alineamiento. La
corrección se conserva como revisión humana explícita del trabajo
asistido, sin ocultar el error ni reemplazar su registro histórico.

Se aplicaron estas decisiones:

- No confundir disponibilidad comercial con eliminación lógica.
- Conservar pedidos aunque el usuario se dé de baja, y detalles aunque
  el producto se elimine posteriormente.
- Sumar el subtotal almacenado y excluir de facturación solo pedidos y
  detalles eliminados, no productos/categorías por su estado actual.
- Separar resumen de pedidos de la vista de seguridad; esta última
  omite `contrasena` y `celular`.
- No introducir unicidad case-insensitive ni modificar tablas base.

El esquema raíz, los datos iniciales y los trabajos anteriores quedaron
fuera de esta reparación. El bootstrap temporal sirve exclusivamente al
laboratorio, no constituye un esquema canónico nuevo.

## 3. Decisión humana sobre índices

Decisión final solicitada por el usuario en el cierre del TP:

| Objeto | Estado | Evidencia y condición |
|---|---|---|
| `idx_producto_stock_bajo` | **ACEPTADO** | 9.4390 → 0.2975 ms; `Index Only Scan`; INSERT +14.96 %. |
| `idx_pedido_fecha_reciente` | **ACEPTADO** | 264.3715 → 1.2250 ms; `Index Only Scan`; INSERT +9.54 %. |
| `idx_usuario_mail_lower` | **ACEPTADO** | 10.8865 → 0.1360 ms; acceso bitmap; INSERT +91.88 %. |
| `idx_usuario_mail_lower_covering` | **DESCARTADO** | 2.621.440 frente a 999.424 bytes del simple; 2.62x el tamaño para una búsqueda de una fila. |

El covering se construyó solo para medir tamaño en una transacción
revertida; no quedó instalado. **No se midieron beneficios temporales
adicionales** de esa alternativa y no se le atribuyen.

La aceptación del índice simple de mail considera una búsqueda
interactiva y la **carga de trabajo asumida** de pocas altas frente a
muchas consultas. Esa frecuencia no fue medida. El costo relativo de
escritura es importante y obliga a revisar la decisión si cambia el uso;
la mejora de lectura no basta para justificar cualquier despliegue.

## 4. Qué se verificó realmente

La [evidencia detallada](../informes/evidencia_modelo_oficial.md) registra
PostgreSQL 17.11, fecha local 20/09/2026 y el dataset de 8 categorías,
50.000 productos, 20.000 usuarios, 200.000 pedidos y 500.000 detalles.

- Tres lecturas antes/después y tres INSERT sobre las tablas indexadas:
  un calentamiento y dos corridas válidas por caso.
- Cuatro vistas con `EXCEPT` bidireccional **0 / 0**.
- `rol_soporte NOLOGIN` temporal: lectura de vista permitida, acceso
  directo a las dos columnas sensibles denegado con SQLSTATE `42501`;
  rol eliminado al finalizar, sin alterar roles preexistentes.
- Materializada: **192 filas**, equivalencia **0 / 0**, lectura homogénea
  **1188.4945 → 0.2230 ms**. Los **0.1220 ms** corresponden a otro
  ordenamiento y no se usan como comparación homogénea.
- `REFRESH MATERIALIZED VIEW CONCURRENTLY`: ejecución exitosa y nueva
  equivalencia **0 / 0**, gracias al índice UNIQUE lógico.

No se midieron concurrencia de producción, frecuencia real de altas,
duración del refresh ni rendimiento universal. El resumen legible está
en el [informe vigente](../informes/informe_mediciones.md).

## 5. Política de actualización: propuesta, no automatización

La política heredada de refresco cada **60 minutos** se conserva como
**propuesta**, pendiente de ratificación del equipo antes del despliegue.
La prueba real fue un refresh manual exitoso; no se instaló un planificador
ni se comprobó la frecuencia propuesta. La materializada admite staleness
y no representa información transaccional en tiempo real.

## 6. Trazabilidad Git y documental

Rama de trabajo: `fix/alinear-foodstore-der-oficial`.

- La DUIA y el informe anteriores se preservan mediante `git mv` como
  `duia_historica.md` e `informe_mediciones_historico.md`, sin editar su
  contenido. Sus commits y prompts siguen siendo evidencia de aquella
  iteración, no acreditación de los resultados corregidos.
- Los contratos corregidos están en [`../specs/`](../specs/) y los objetos
  en [`../sql/`](../sql/). Sus textos de validación pendiente representan
  el estado previo a ejecución del Bloque 1; el Bloque 2 está acreditado
  en su evidencia y en el informe vigente.
- La evidencia del Bloque 2 se conserva sin cambios. Sus referencias
  temporales al informe/DUIA anteriores corresponden ahora a los archivos
  históricos; no se reescribe retrospectivamente su narración.
- Este cierre prepara únicamente Unidad 3 para el próximo commit. No se
  atribuye un SHA nuevo ni se afirma un commit o push que no se realizó.

La documentación de resultados no mezcla mediciones de ambas iteraciones.
Los nombres, decisiones y resultados vigentes se verifican contra la
evidencia real, no contra una expectativa de la herramienta de IA.
