# TPI Food Store — Primera Entrega Parcial

**Nueve objetivos cubiertos con alcance explícito y evidencia verificable.**
La entrega integra U1–U3; U4 es complementaria y no sustituye esa cobertura.
El [informe técnico](informe_tecnico.md) contiene la matriz final, decisiones,
resultados y límites. Este cierre documental no repite pruebas.

**Integrantes:** Avalos Pablo, Blangetti Sofia y Suarez Ismael.

## Lectura principal

| Recurso | Contenido |
|---|---|
| [Informe técnico](informe_tecnico.md) | Explicación y matriz 9/9 con artefacto, evidencia y alcance |
| [ER](modelo/modelo_er.md) y [relacional](modelo/modelo_relacional.md) | Cinco entidades, 40 atributos, PK/FK/UK, cardinalidades y N:M |
| [Normalización](modelo/normalizacion.md) | DF, claves, excepción subtotal y lossless teórico |
| [Evidencia oficial](evidencia_modelo_oficial.md) | Instalación, batería, tres escenarios READ COMMITTED y HAVING |
| [Cierre 3/5](evidencia_cierre_objetivos_3_5.md) | Defensa académica y RANK canónico ejecutado |
| [Cierre 8](evidencia_cierre_objetivo_8.md) | SAVEPOINT, REPEATABLE READ y SERIALIZABLE 40001, con arnés versionado |

## Modelo y resultados

La autoridad es [schema.sql](../schema.sql), seguido del [seed](../datos_iniciales.sql).
Tablas: categoria, usuario, producto, pedido y detalle_pedido; todas tienen
PK id y baja lógica eliminado. Pedido usa usuario_id y fecha DATE. Detalle posee
PK técnica id y UNIQUE(pedido_id, producto_id); conserva precio histórico.
Disponibilidad de producto y baja lógica son condiciones diferentes.

**Normalización: PASS académico, no FNBC física universal.** Usuario/categoría/
producto y pedido cumplen 3FN/FNBC bajo sus DF identificadas. Detalle cumple
1FN/2FN, no 3FN/FNBC estricta por `{cantidad, precio_unitario} → subtotal`.
Subtotal es redundancia derivada deliberada y controlada por fn_set_subtotal y
trg_subtotal; la descomposición lossless expuesta es teórica, no una migración.

| Verificación real preservada | Resultado |
|---|---|
| Motor | PostgreSQL 17.11, satisface 16+; no se acredita otra ejecución en 16 |
| Schema/seed/objetos | PASS; 7 rutinas y 5 triggers |
| Batería funcional | 29 grupos / 37 variantes / 30 NOTICE PASS; exit 0 |
| Atomicidad | Detalle, subtotal, total y stock revierten juntos |
| READ COMMITTED | Tres escenarios PASS con bloqueos observados; evidencia anterior preservada |
| HAVING | Ana Gómez 2; Luis Paz 2 |
| RANK canónico | Marta Ruiz 6200.00/1; Ana Gómez 5950.00/2; Luis Paz 2550.00/3 |
| SAVEPOINT | 50 → 49 → 47 → 49 → 50 |
| REPEATABLE READ | A 50; B confirma 51; A sigue en 50; nueva transacción ve 51 |
| SERIALIZABLE | A confirma 52; B aborta con 40001; luego se restaura a 50 |

HAVING y ventana excluyen pedidos eliminados, pero conservan usuarios históricos
aunque estén dados de baja. No hubo empates en el seed. Los dos cierres nuevos
tienen bases y evidencias separadas; no se atribuyen a los ensayos anteriores.

## Reproducción mínima TPI

Comandos para **PowerShell desde la raíz**, PostgreSQL/psql disponibles y
autenticación local ya configurada, sin publicar secretos. Solo sobre una base
**nueva, inexistente** llamada `foodstore_tpi_oficial`. No hay borrado ni
recreación automática. Si ya existe, detenerse y acordar otro ensayo.

```powershell
$exists = psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d postgres -At -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) FROM pg_database WHERE datname='foodstore_tpi_oficial';"
if ($LASTEXITCODE -ne 0 -or "$exists".Trim() -ne '0') { throw 'Base existente o precheck fallido; detenerse.' }

createdb -w -h 127.0.0.1 -p 5432 -U postgres foodstore_tpi_oficial
if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la base.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -1 -f .\schema.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló schema.sql.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -f .\datos_iniciales.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló datos_iniciales.sql.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -1 -f .\tpi\sql\objetos_programables.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló la instalación de objetos.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -f .\tpi\pruebas\pruebas_objetos_programables.sql
if ($LASTEXITCODE -ne 0) { throw 'Falló la batería; no continuar.' }

psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -f .\tpi\sql\consultas_cobertura_tpi.sql
if ($LASTEXITCODE -ne 0) { throw 'Fallaron las consultas HAVING/ventana.' }
```

`-1` corresponde solo a schema y objetos. El seed administra BEGIN/COMMIT y la
batería BEGIN/ROLLBACK, con guarda literal de base; correrla sin otros escritores.
La batería revierte fixtures, no objetos instalados; las identidades pueden
conservar huecos. El seed contiene 2 categorías, 3 usuarios, 3 productos,
5 pedidos y 7 detalles: el stock es una fotografía, no una venta reejecutada.
`SEED_NO_AUTH` es un marcador académico, no una credencial real.

## Transacciones multisesión: laboratorio separado

Preparar exclusivamente `foodstore_tpi_cierre_b` con schema/seed/objetos siguiendo
el [README del arnés](pruebas/transacciones/README.md). Requiere PowerShell 7+,
laboratorio exclusivo y sus guardas de seed/objetos. Después:

```powershell
pwsh -NoProfile -File .\tpi\pruebas\transacciones\ejecutar.ps1
if ($LASTEXITCODE -ne 0) { throw 'TPI-B falló; preservar la base y revisar logs.' }
```

Los SQL y la coordinación SAVEPOINT/RR/SERIALIZABLE están versionados. Los logs
se guardan bajo TEMP, fuera del repo. El arnés exige exactamente 40001 en la
sesión abortada, no acepta 40P01 ni errores genéricos, y verifica restauración
lógica e integridad. Puede repetirse tras PASS según su guía.

Los tres casos READ COMMITTED anteriores conservan su evidencia; sus scripts
temporales no quedaron íntegramente versionados. La ejecución del nuevo arnés
no los repite ni se presenta como reproducción de esos intercalados.

## U3: instalación y mediciones separadas

Los tres índices aceptados, cuatro vistas y materializada **no pertenecen a la
instalación mínima raíz/TPI**. Seguir [README U3](../unidades/unidad-3/README.md),
[informe vigente](../unidades/unidad-3/informes/informe_mediciones.md) y
[evidencia con bootstrap/carga y planes](../unidades/unidad-3/informes/evidencia_modelo_oficial.md).
No instalar candidatos antes de medir BEFORE ni ejecutar recreaciones sin
autorización expresa para esa base. Seguridad requiere revisar el rol y permisos;
no se instala un rol de despliegue por seguir el TPI mínimo.

Las métricas provienen del laboratorio U3 masivo, no del seed mínimo ni de U4.
Su guía conserva la cronología anterior a la reparación del schema raíz:
hoy schema.sql es canónico, pero no reconstruye por sí solo esa carga medida.
Los SQL/specs que dicen «pendiente» registran su autoría previa; el informe y
la evidencia U3 acreditan las ejecuciones posteriores. No se reescribe historia.

## Alcance y límites

La venta soportada usa CALL registrar_detalle_pedido; DML directo de detalle
mantiene derivados, no inventario. Bajas, reactivaciones y DELETE no reponen
stock automáticamente. No se acreditan ausencia universal de deadlocks, CALL
seguro bajo cualquier aislamiento, DML arbitrario concurrente ni rendimiento
bajo estrés. El 40001 ensayado también puede ocurrir bajo REPEATABLE READ: no
es una prueba exclusiva de SSI ni una estrategia automática de reintento.

La incidencia histórica 42601 del helper de cleanup se preserva separada de
los resultados productivos PASS. U1/U2 e informes previos permanecen intactos.
La revisión independiente TPI-D y la integración Git no se declaran realizadas
por este cierre documental. Volver al [informe](informe_tecnico.md) para la
matriz, optimización, IA y decisiones; a la [raíz](../README.md) para el proyecto.
