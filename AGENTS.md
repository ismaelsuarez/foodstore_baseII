# AGENTS.md — Food Store / Base de Datos II

## Propósito

Proyecto académico PostgreSQL de UTN, con SQL y documentación Markdown.
No hay aplicación, backend ni frontend: la batería es SQL/PL/pgSQL y se ejecuta
con psql. Comenzar por [README](README.md) y, para la Primera Entrega, por
[TPI](tpi/README.md), su [informe](tpi/informe_tecnico.md) y la
[evidencia oficial](tpi/evidencia_modelo_oficial.md).

## Fuentes de verdad

Aplicar este orden de autoridad, sin reconstruir contratos desde memoria:

1. [schema.sql](schema.sql): estructura canónica vigente.
2. [datos_iniciales.sql](datos_iniciales.sql): dataset inicial canónico.
3. [tpi/modelo](tpi/modelo/): ER, modelo relacional y normalización.
4. [Objetos programables](tpi/sql/objetos_programables.sql): comportamiento TPI.
5. [tpi/pruebas](tpi/pruebas/): batería de verificación.
6. README vigentes de raíz, TPI y unidades.
7. Evidencia e informes: resultados observados y límites de cada ensayo.

Las specs locales describen contratos del ejercicio; las DUIA documentan
propuestas de IA, revisión y decisiones humanas. Una evidencia no autoriza
por sí sola a modificar contratos ni a repetir el ensayo.

## Modelo canónico

Las cinco tablas son categoria, usuario, producto, pedido y detalle_pedido.
Todas tienen PK id BIGINT GENERATED ALWAYS AS IDENTITY y baja lógica mediante
eliminado. Los ENUM son forma_pago, rol y estado_pedido; leer sus valores y
defaults en el schema.

- usuario es una entidad real: incluye mail UNIQUE, celular, contrasena, rol
  y baja lógica. No es una tabla auxiliar de Unidad 4.
- categoria.nombre es UNIQUE; producto.nombre no lo es.
- producto.disponible expresa disponibilidad comercial y no equivale a
  producto.eliminado. Precio y stock no pueden ser negativos.
- pedido.usuario_id referencia al usuario; fecha es DATE y created_at es
  TIMESTAMPTZ. estado y total físico pertenecen al modelo oficial.
- detalle_pedido.id es la PK. Las FK pedido_id y producto_id forman una clave
  candidata alternativa mediante UNIQUE(pedido_id, producto_id) y NOT NULL,
  no la PK. Incluye cantidad positiva, precio histórico y subtotal físico.
  Las cuatro FK usan ON DELETE RESTRICT.
- Las bajas posteriores de usuario, producto o categoría no deben destruir
  el historial existente. No inventar políticas de cancelación o reposición.

subtotal es una **REDUNDANCIA DERIVADA DELIBERADA** del modelo oficial.
Con la regla {cantidad, precio_unitario} -> subtotal, el detalle cumple 1FN/2FN,
pero no se presenta como 3FN/FNBC estricta. No eliminar la columna para aparentar
normalización. pedido.total agrega filas de otra relación; su existencia no
demuestra por sí sola una DF interna que viole FNBC de pedido.
Consultar [normalización](tpi/modelo/normalizacion.md).

## Autoridades del comportamiento

| Responsabilidad | Autoridad |
|---|---|
| Registro de venta y descuento de stock | registrar_detalle_pedido |
| Subtotal de una línea | fn_set_subtotal / trg_subtotal |
| Total de detalles no eliminados | calcular_total_pedido y tres triggers AFTER por sentencia |
| Vigencia en altas/reasignaciones | fn_validar_detalle_vigente / trg_detalle_vigente |

No duplicar definiciones de subtotal o total. El agregado usa el subtotal físico,
no una segunda multiplicación. Los triggers de total emplean transition tables
y recalculan ambos pedidos cuando una línea cambia de pedido.

El procedimiento bloquea en orden **pedido FOR UPDATE → usuario FOR SHARE →
producto FOR UPDATE**. La transacción pertenece al llamante. DML directo del
detalle no administra inventario; bajas, reactivaciones y DELETE no reponen
stock automáticamente. No presentar esa ruta como API completa de venta.

La instalación TPI define exactamente 7 rutinas y 5 triggers, listados en la
[evidencia](tpi/evidencia_modelo_oficial.md). No instalar ni retirar objetos
sin autorización de la tarea.

## Historia protegida y unidades cerradas

**TP1–TP4 son EVIDENCIA HISTÓRICA EVALUADA.** No modificar
unidades/unidad-1/ ni unidades/unidad-2/ salvo instrucción explícita.
Sus referencias históricas a cliente, activo o una PK compuesta describen
una etapa anterior; no son el contrato vigente ni migraciones pendientes.

- [Unidad 3](unidades/unidad-3/README.md): corregida y cerrada en da5f3e4.
  Índices: idx_producto_stock_bajo, idx_pedido_fecha_reciente,
  idx_usuario_mail_lower. Vistas: v_productos_vigentes, v_pedidos_resumen,
  v_pedido_detalle, v_usuarios_publico. Materializada:
  mv_facturacion_categoria_mes. Seguridad y refresh concurrente tienen
  evidencia real propia. Sus índices candidatos no forman parte de los
  tres índices mínimos del schema raíz.
- [Unidad 4](unidades/unidad-4/README.md): corregida y cerrada en 95fbfbf.
  FNBC PASS. Desnormalización: VALID_EXPERIMENT, pero
  REJECTED_AFTER_MEASUREMENT / DO_NOT_ADOPT.
  **detalle_pedido.categoria_id no es canónico**: no integrar ni instalar
  automáticamente ese SQL experimental. producto.categoria_id sigue siendo
  la fuente de verdad. lote y deposito son extensiones académicas;
  los responsables del ensayo reutilizaron usuarios existentes.

Los avisos de U3/U4 que describen el schema raíz como anterior reflejan el momento
de esos cierres, previo a su reparación canónica. No prevalecen sobre el schema
actual. El seed mínimo tampoco reproduce sus cargas masivas de laboratorio.
No editar esos documentos protegidos para eliminar la cronología sin autorización.

## Validación y límites

- Motor exclusivo: PostgreSQL; validación registrada con **17.11**.
- Probar solo en una base descartable explícitamente autorizada. Una tarea
  documental no autoriza crear, borrar ni recrear bases.
- Para reconstruir TPI, seguir [reproducción](tpi/README.md): schema, seed,
  objetos, batería y consulta HAVING. Usar ON_ERROR_STOP=1; -1 solo para
  schema y objetos, no para seed o batería que administran su transacción.
- Batería acreditada: **29 grupos / 37 variantes / 30 NOTICE PASS**, exit 0.
  P0099 pertenece exclusivamente al ensayo de atomicidad.
- Concurrencia acreditada: tres escenarios de CALL con conexiones distintas
  bajo READ COMMITTED, observando bloqueos y estado final. No garantiza
  ausencia universal de deadlocks, DML directo concurrente, SERIALIZABLE,
  reposición, cancelaciones o comportamiento bajo estrés.
- Equivalencia: EXCEPT bidireccional. Rendimiento: planes y corridas reales
  según el protocolo de cada unidad; no mezclar datasets ni tiempos históricos.
- Separar fallos del producto e incidencias del arnés. Conservar diagnósticos;
  no reescribir evidencia registrada para ajustarla a expectativas.

## Convenciones y prohibiciones

- Español técnico, identificadores snake_case, tablas en singular y FK
  <tabla_referenciada>_id. Usar eliminado para baja lógica vigente.
- Leer schema, restricciones, spec local si existe y objetos afectados antes
  de proponer SQL. No inventar columnas, ENUM, reglas ni resultados.
- No tratar todo SQL bajo unidades/ como una migración automática.
- No reescribir históricos evaluados, mediciones ni prompts DUIA sin instrucción
  explícita. Mantener la diferencia entre propuesta de IA y ejecución real.
- No incluir secretos ni rutas de credenciales. SEED_NO_AUTH es un marcador
  académico, no una credencial real ni un mecanismo de autenticación.
- No duplicar archivos canónicos de otras unidades. Al mover un archivo,
  preservar historial con git mv y actualizar sus enlaces.
- Respetar el alcance autorizado de cada bloque y preservar cambios previos.
  No corregir silenciosamente SQL o evidencia ante un fallo de ejecución.

## Git y estructura

Ver [estructura](.kiro/steering/structure.md). Antes de cerrar un cambio,
comprobar git status, alcance y git diff --check. Commit y staging requieren
el alcance autorizado; nunca hacer push sin autorización explícita.
Usar Conventional Commits sin Co-Authored-By ni atribución de IA en commits.
La responsabilidad final de propuestas, pruebas y decisiones pertenece al equipo.
