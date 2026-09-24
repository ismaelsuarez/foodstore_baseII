-- Unidad 4, Fase 3: dataset determinístico del modelo canónico, no benchmark.
-- Ejecutar con psql -X -v ON_ERROR_STOP=1, sin -1: administra transacciones
-- y ejecuta VACUUM fuera de ellas. Solo foodstore_u4_revalidacion.
-- Fuentes: schema.sql y datos_iniciales.sql; conserva los tres índices TP5.
-- No instala FNBC, TPI ni desnormalización. No restaura dumps ni borra el seed.
-- La única dependencia temporal del generador es CURRENT_DATE: para repetir
-- una comparación en otra fecha se debe preparar y autorizar otro checkpoint.
\set ON_ERROR_STOP on
\set VERBOSITY verbose

BEGIN;
SET LOCAL search_path = public, pg_catalog;

DO $guarda_base$
BEGIN
    IF current_database() <> 'foodstore_u4_revalidacion' THEN
        RAISE EXCEPTION 'Base no autorizada para la carga U4';
    END IF;
    IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','f')) <> 5
       OR EXISTS (
        SELECT 1 FROM (VALUES ('categoria'),('usuario'),('producto'),('pedido'),
                             ('detalle_pedido')) x(nombre)
        WHERE NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                          WHERE n.nspname='public' AND c.relname=x.nombre AND c.relkind='r')
       ) THEN
        RAISE EXCEPTION 'Se requieren exclusivamente las cinco tablas canónicas';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema')
       OR EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal) THEN
        RAISE EXCEPTION 'Rutinas o triggers inesperados: no instalar TPI/U4/FNBC';
    END IF;
END;
$guarda_base$;

-- Evita escrituras concurrentes durante guardas y carga; no bloquea SELECT.
LOCK TABLE categoria, usuario, producto, pedido, detalle_pedido
    IN SHARE ROW EXCLUSIVE MODE;

DO $guarda_contrato$
DECLARE
    v_tabla text;
    v_limite bigint;
    v_cantidad bigint;
    v_minimo bigint;
    v_maximo bigint;
BEGIN
    -- COUNT/MIN/MAX y PK verificadas abajo implican ausencia de huecos.
    FOR v_tabla, v_limite IN
        SELECT * FROM (VALUES ('categoria',2),('usuario',3),('producto',3),
                              ('pedido',5),('detalle_pedido',7)) x(tabla,limite)
    LOOP
        EXECUTE format('SELECT count(*), min(id), max(id) FROM public.%I',v_tabla)
            INTO v_cantidad,v_minimo,v_maximo;
        IF v_cantidad <> v_limite OR v_minimo <> 1 OR v_maximo <> v_limite THEN
            RAISE EXCEPTION 'Seed/rango inesperado en %: count=%, min=%, max=%',
                v_tabla,v_cantidad,v_minimo,v_maximo;
        END IF;
    END LOOP;

    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public') <> 40 OR EXISTS (
        SELECT 1 FROM (VALUES
          ('categoria','id','bigint',true),('categoria','nombre','character varying(100)',true),
          ('categoria','descripcion','character varying(255)',false),('categoria','eliminado','boolean',true),
          ('categoria','created_at','timestamp with time zone',true),
          ('usuario','id','bigint',true),('usuario','nombre','character varying(80)',true),
          ('usuario','apellido','character varying(80)',true),('usuario','mail','character varying(120)',true),
          ('usuario','celular','character varying(30)',false),('usuario','contrasena','character varying(255)',true),
          ('usuario','rol','rol',true),('usuario','eliminado','boolean',true),
          ('usuario','created_at','timestamp with time zone',true),
          ('producto','id','bigint',true),('producto','nombre','character varying(120)',true),
          ('producto','precio','numeric(12,2)',true),('producto','descripcion','character varying(255)',false),
          ('producto','stock','integer',true),('producto','imagen','character varying(255)',false),
          ('producto','disponible','boolean',true),('producto','categoria_id','bigint',true),
          ('producto','eliminado','boolean',true),('producto','created_at','timestamp with time zone',true),
          ('pedido','id','bigint',true),('pedido','fecha','date',true),('pedido','estado','estado_pedido',true),
          ('pedido','total','numeric(12,2)',true),('pedido','forma_pago','forma_pago',true),
          ('pedido','usuario_id','bigint',true),('pedido','eliminado','boolean',true),
          ('pedido','created_at','timestamp with time zone',true),
          ('detalle_pedido','id','bigint',true),('detalle_pedido','cantidad','integer',true),
          ('detalle_pedido','precio_unitario','numeric(12,2)',true),('detalle_pedido','subtotal','numeric(12,2)',true),
          ('detalle_pedido','pedido_id','bigint',true),('detalle_pedido','producto_id','bigint',true),
          ('detalle_pedido','eliminado','boolean',true),('detalle_pedido','created_at','timestamp with time zone',true)
        ) x(tabla,columna,tipo,no_nulo)
        LEFT JOIN pg_attribute a ON a.attrelid=to_regclass('public.'||x.tabla)
                                  AND a.attname=x.columna AND a.attnum>0 AND NOT a.attisdropped
        WHERE a.attname IS NULL OR format_type(a.atttypid,a.atttypmod)<>x.tipo
              OR a.attnotnull<>x.no_nulo OR (x.columna='id' AND a.attidentity<>'a')
    ) THEN
        RAISE EXCEPTION 'Columnas, tipos, nulabilidad o identidad no canónicos';
    END IF;

    IF (SELECT count(*) FROM pg_constraint WHERE conrelid IN
        ('categoria'::regclass,'usuario'::regclass,'producto'::regclass,
         'pedido'::regclass,'detalle_pedido'::regclass)) <> 18 OR EXISTS (
        SELECT 1 FROM (VALUES
          ('categoria','categoria_pkey','p','PRIMARY KEY (id)'),
          ('categoria','categoria_nombre_key','u','UNIQUE (nombre)'),
          ('usuario','usuario_pkey','p','PRIMARY KEY (id)'),
          ('usuario','usuario_mail_key','u','UNIQUE (mail)'),
          ('producto','producto_pkey','p','PRIMARY KEY (id)'),
          ('pedido','pedido_pkey','p','PRIMARY KEY (id)'),
          ('detalle_pedido','detalle_pedido_pkey','p','PRIMARY KEY (id)'),
          ('detalle_pedido','uq_detalle_pedido_pedido_producto','u','UNIQUE (pedido_id, producto_id)'),
          ('producto','fk_producto_categoria','f','FOREIGN KEY (categoria_id) REFERENCES categoria(id) ON DELETE RESTRICT'),
          ('pedido','fk_pedido_usuario','f','FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE RESTRICT'),
          ('detalle_pedido','fk_detalle_pedido_pedido','f','FOREIGN KEY (pedido_id) REFERENCES pedido(id) ON DELETE RESTRICT'),
          ('detalle_pedido','fk_detalle_pedido_producto','f','FOREIGN KEY (producto_id) REFERENCES producto(id) ON DELETE RESTRICT'),
          ('producto','chk_producto_precio','c','CHECK ((precio >= (0)::numeric))'),
          ('producto','chk_producto_stock','c','CHECK ((stock >= 0))'),
          ('pedido','chk_pedido_total','c','CHECK ((total >= (0)::numeric))'),
          ('detalle_pedido','chk_detalle_pedido_cantidad','c','CHECK ((cantidad > 0))'),
          ('detalle_pedido','chk_detalle_pedido_precio_unitario','c','CHECK ((precio_unitario >= (0)::numeric))'),
          ('detalle_pedido','chk_detalle_pedido_subtotal','c','CHECK ((subtotal >= (0)::numeric))')
        ) x(tabla,nombre,tipo,definicion)
        LEFT JOIN pg_constraint c ON c.conrelid=to_regclass('public.'||x.tabla) AND c.conname=x.nombre
        WHERE c.oid IS NULL OR c.contype::text<>x.tipo OR NOT c.convalidated
              OR c.condeferrable OR pg_get_constraintdef(c.oid)<>x.definicion
    ) THEN
        RAISE EXCEPTION 'PK/FK/UNIQUE/CHECK faltantes o diferentes del schema';
    END IF;

    IF (SELECT count(*) FROM pg_indexes WHERE schemaname='public') <> 14 OR EXISTS (
        SELECT 1 FROM (VALUES
          ('idx_producto_categoria','CREATE INDEX idx_producto_categoria ON public.producto USING btree (categoria_id)'),
          ('idx_pedido_usuario','CREATE INDEX idx_pedido_usuario ON public.pedido USING btree (usuario_id)'),
          ('idx_producto_nombre_vig','CREATE INDEX idx_producto_nombre_vig ON public.producto USING btree (nombre) WHERE (eliminado = false)'),
          ('idx_producto_stock_bajo','CREATE INDEX idx_producto_stock_bajo ON public.producto USING btree (stock, nombre) INCLUDE (id, precio) WHERE (eliminado = false)'),
          ('idx_pedido_fecha_reciente','CREATE INDEX idx_pedido_fecha_reciente ON public.pedido USING btree (fecha DESC) INCLUDE (id, usuario_id, estado, forma_pago, total) WHERE (eliminado = false)'),
          ('idx_usuario_mail_lower','CREATE INDEX idx_usuario_mail_lower ON public.usuario USING btree (lower((mail)::text)) WHERE (eliminado = false)')
        ) x(nombre,definicion)
        LEFT JOIN pg_indexes i ON i.schemaname='public' AND i.indexname=x.nombre
        LEFT JOIN pg_index ix ON ix.indexrelid=to_regclass('public.'||x.nombre)
        WHERE i.indexname IS NULL OR i.indexdef<>x.definicion OR NOT ix.indisvalid OR NOT ix.indisready
    ) THEN
        RAISE EXCEPTION 'Índices raíz/TP5 inesperados o inválidos';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_constraint c ON c.oid=t.tgconstraint
               WHERE c.connamespace='public'::regnamespace AND t.tgenabled<>'O') THEN
        RAISE EXCEPTION 'Triggers internos de integridad deshabilitados';
    END IF;
    IF EXISTS (SELECT 1 FROM pedido WHERE fecha >= CURRENT_DATE) THEN
        RAISE EXCEPTION 'El seed debe ser anterior a CURRENT_DATE para aislar 20000 pedidos del día';
    END IF;
    RAISE NOTICE 'PASS: guardas de base, seed, columnas, constraints e índices';
END;
$guarda_contrato$;

-- Las huellas incluyen todos los atributos, también created_at: no se altera
-- ninguna fila seed. No se fija la relación usuario/fecha por ID del pedido.
CREATE TEMP TABLE u4_seed_snapshot ON COMMIT DROP AS
SELECT 'categoria'::text AS tabla,md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) AS huella FROM categoria t
UNION ALL SELECT 'usuario',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM usuario t
UNION ALL SELECT 'producto',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM producto t
UNION ALL SELECT 'pedido',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM pedido t
UNION ALL SELECT 'detalle_pedido',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM detalle_pedido t;

INSERT INTO categoria(id,nombre,descripcion,eliminado,created_at) OVERRIDING SYSTEM VALUE
SELECT g,'__U4_LAB_CATEGORIA_'||lpad(g::text,2,'0')||'__',
       'Categoría sintética del laboratorio U4',false,CURRENT_DATE::timestamp AT TIME ZONE 'UTC'
FROM generate_series(3,8) g ORDER BY g;

-- SEED_NO_AUTH es un marcador académico; no es una credencial ni autenticación.
INSERT INTO usuario(id,nombre,apellido,mail,contrasena,rol,eliminado,created_at) OVERRIDING SYSTEM VALUE
SELECT g,'U4 Usuario '||g,'Laboratorio','u4.lab.'||g||'@foodstore.invalid',
       'SEED_NO_AUTH','USUARIO'::rol,false,CURRENT_DATE::timestamp AT TIME ZONE 'UTC'
FROM generate_series(4,20000) g ORDER BY g;

-- Stock es una fotografía del catálogo, no se reconstruye ni descuenta por ventas.
-- NUMERIC exacto; la categoría aporta un componente al precio, no un ranking forzado.
INSERT INTO producto(id,nombre,precio,descripcion,stock,disponible,categoria_id,eliminado,created_at)
OVERRIDING SYSTEM VALUE
SELECT g,'__U4_LAB_PRODUCTO_'||lpad(g::text,5,'0')||'__',
       (1000*(1+(g-1)%8)+(g*17)%97+((g*13)%100)::numeric/100)::numeric(12,2),
       'Producto sintético del laboratorio U4',100+g%401,true,1+(g-1)%8,false,
       CURRENT_DATE::timestamp AT TIME ZONE 'UTC'
FROM generate_series(4,50000) g ORDER BY g;

CREATE TEMP TABLE u4_pedidos_staging ON COMMIT DROP AS
SELECT i,i+5 AS id,
       CASE WHEN i<=20000 THEN CURRENT_DATE ELSE CURRENT_DATE-(1+(i-20001)%60) END AS fecha,
       (ARRAY['PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO']::estado_pedido[])[1+i%4] AS estado,
       (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA']::forma_pago[])[1+i%3] AS forma_pago,
       1+(i*13)%20000 AS usuario_id,i%100=0 AS eliminado
FROM generate_series(1,199995) i;

-- Dos líneas por pedido sintético. Tercera: 10000 pedidos del día y 90003 históricos.
-- El paso 997 es menor a 50000 y sus dos primeros múltiplos no coinciden módulo50000.
CREATE TEMP TABLE u4_detalles_staging ON COMMIT DROP AS
WITH lineas AS (
    SELECT o.i,o.id AS pedido_id,o.fecha,j AS linea,
           1+((o.i*37+(j-1)*997)%50000) AS producto_id,1+(o.i+j)%4 AS cantidad
    FROM u4_pedidos_staging o
    CROSS JOIN LATERAL generate_series(1,2+CASE
        WHEN o.i<=20000 AND o.i%2=0 THEN 1
        WHEN o.i>20000 AND o.i-20000<=90003 THEN 1 ELSE 0 END) j
), identificadas AS (
    SELECT 7+row_number() OVER(ORDER BY i,linea) AS id,* FROM lineas
)
SELECT d.id,d.pedido_id,d.producto_id,d.cantidad,p.precio AS precio_unitario,
       (d.cantidad*p.precio)::numeric(12,2) AS subtotal,d.id%100=0 AS eliminado,d.fecha
FROM identificadas d JOIN producto p ON p.id=d.producto_id;

-- El total se deriva en staging antes del INSERT, sin UPDATE masivo de pedido.
INSERT INTO pedido(id,fecha,estado,total,forma_pago,usuario_id,eliminado,created_at)
OVERRIDING SYSTEM VALUE
SELECT o.id,o.fecha,o.estado,t.total,o.forma_pago,o.usuario_id,o.eliminado,
       o.fecha::timestamp AT TIME ZONE 'UTC'
FROM u4_pedidos_staging o
JOIN (SELECT pedido_id,COALESCE(SUM(subtotal) FILTER(WHERE NOT eliminado),0)::numeric(12,2) AS total
      FROM u4_detalles_staging GROUP BY pedido_id) t ON t.pedido_id=o.id
ORDER BY o.id;

INSERT INTO detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,eliminado,created_at)
OVERRIDING SYSTEM VALUE
SELECT id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,eliminado,
       fecha::timestamp AT TIME ZONE 'UTC'
FROM u4_detalles_staging ORDER BY id;

DO $validacion_carga$
BEGIN
    IF (SELECT count(*) FROM categoria)<>8 OR (SELECT count(*) FROM usuario)<>20000
       OR (SELECT count(*) FROM producto)<>50000 OR (SELECT count(*) FROM pedido)<>200000
       OR (SELECT count(*) FROM detalle_pedido)<>500000 THEN
        RAISE EXCEPTION 'Conteos finales diferentes del contrato';
    END IF;
    IF (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE)<>20000
       OR (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id
           WHERE p.fecha=CURRENT_DATE)<>50000 THEN
        RAISE EXCEPTION 'Volumen del día incorrecto';
    END IF;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE subtotal IS DISTINCT FROM cantidad*precio_unitario)
       OR EXISTS (
        SELECT 1 FROM pedido p LEFT JOIN detalle_pedido d ON d.pedido_id=p.id
        GROUP BY p.id,p.total
        HAVING p.total IS DISTINCT FROM COALESCE(SUM(d.subtotal) FILTER(WHERE NOT d.eliminado),0)
       ) THEN
        RAISE EXCEPTION 'Subtotal o total inconsistente';
    END IF;
    IF EXISTS (SELECT 1 FROM detalle_pedido GROUP BY pedido_id,producto_id HAVING count(*)>1)
       OR EXISTS (SELECT 1 FROM producto p LEFT JOIN categoria c ON c.id=p.categoria_id WHERE c.id IS NULL)
       OR EXISTS (SELECT 1 FROM pedido p LEFT JOIN usuario u ON u.id=p.usuario_id WHERE u.id IS NULL)
       OR EXISTS (SELECT 1 FROM detalle_pedido d LEFT JOIN pedido p ON p.id=d.pedido_id
                  LEFT JOIN producto pr ON pr.id=d.producto_id WHERE p.id IS NULL OR pr.id IS NULL)
       OR EXISTS (SELECT 1 FROM producto WHERE precio<0 OR stock<0)
       OR EXISTS (SELECT 1 FROM pedido WHERE total<0)
       OR EXISTS (SELECT 1 FROM detalle_pedido WHERE cantidad<=0 OR precio_unitario<0 OR subtotal<0) THEN
        RAISE EXCEPTION 'Violación de FK, UNIQUE o CHECK';
    END IF;
    -- NOT NULL y PK/FK/UK/CHECK se mantienen habilitadas durante toda la carga.
    IF EXISTS (
        WITH actual AS (
          SELECT 'categoria'::text AS tabla,md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) AS huella FROM categoria t WHERE id<=2
          UNION ALL SELECT 'usuario',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM usuario t WHERE id<=3
          UNION ALL SELECT 'producto',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM producto t WHERE id<=3
          UNION ALL SELECT 'pedido',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM pedido t WHERE id<=5
          UNION ALL SELECT 'detalle_pedido',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text) FROM detalle_pedido t WHERE id<=7
        ) SELECT 1 FROM actual a JOIN u4_seed_snapshot s USING(tabla) WHERE a.huella IS DISTINCT FROM s.huella
    ) THEN
        RAISE EXCEPTION 'El seed fue alterado';
    END IF;
    IF (SELECT count(DISTINCT pr.categoria_id) FROM detalle_pedido d
        JOIN pedido p ON p.id=d.pedido_id JOIN producto pr ON pr.id=d.producto_id
        WHERE p.fecha=CURRENT_DATE AND NOT p.eliminado AND NOT d.eliminado)<>8
       OR EXISTS (
        WITH agregados AS (
          SELECT pr.categoria_id,SUM(d.subtotal) AS total
          FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id JOIN producto pr ON pr.id=d.producto_id
          WHERE p.fecha=CURRENT_DATE AND NOT p.eliminado AND NOT d.eliminado GROUP BY pr.categoria_id
        ) SELECT 1 FROM agregados GROUP BY total HAVING count(*)>1
       ) THEN
        RAISE EXCEPTION 'Categorías insuficientes o empates en agregados del día';
    END IF;
    RAISE NOTICE 'PASS: volúmenes, seed intacto, integridad y ocho agregados sin empates';
END;
$validacion_carga$;
COMMIT;

-- setval no es transaccional. Se ejecuta únicamente tras confirmar toda la carga.
-- Una interrupción en esta etapa obliga a detenerse y diagnosticar, no a reejecutar
-- automáticamente este script, cuya guarda rechaza una segunda carga.
SELECT setval(pg_get_serial_sequence('public.categoria','id'),(SELECT max(id) FROM categoria),true);
SELECT setval(pg_get_serial_sequence('public.usuario','id'),(SELECT max(id) FROM usuario),true);
SELECT setval(pg_get_serial_sequence('public.producto','id'),(SELECT max(id) FROM producto),true);
SELECT setval(pg_get_serial_sequence('public.pedido','id'),(SELECT max(id) FROM pedido),true);
SELECT setval(pg_get_serial_sequence('public.detalle_pedido','id'),(SELECT max(id) FROM detalle_pedido),true);

-- Prueba real de DEFAULT identity; filas reversibles, consumo de secuencia no.
-- Queda un hueco por secuencia: no se reajusta para ocultar la prueba.
BEGIN;
DO $identidades$
DECLARE
    v_categoria bigint; v_usuario bigint; v_producto bigint; v_pedido bigint; v_detalle bigint;
BEGIN
    INSERT INTO categoria(nombre,created_at) VALUES('__U4_IDENTITY_PROBE__',CURRENT_DATE::timestamp AT TIME ZONE 'UTC') RETURNING id INTO v_categoria;
    INSERT INTO usuario(nombre,apellido,mail,contrasena,created_at)
      VALUES('U4','Identity','u4.identity.probe@foodstore.invalid','SEED_NO_AUTH',CURRENT_DATE::timestamp AT TIME ZONE 'UTC') RETURNING id INTO v_usuario;
    INSERT INTO producto(nombre,precio,categoria_id,created_at)
      VALUES('__U4_IDENTITY_PROBE__',1,v_categoria,CURRENT_DATE::timestamp AT TIME ZONE 'UTC') RETURNING id INTO v_producto;
    INSERT INTO pedido(fecha,total,forma_pago,usuario_id,created_at)
      VALUES(CURRENT_DATE,1,'EFECTIVO',v_usuario,CURRENT_DATE::timestamp AT TIME ZONE 'UTC') RETURNING id INTO v_pedido;
    INSERT INTO detalle_pedido(cantidad,precio_unitario,subtotal,pedido_id,producto_id,created_at)
      VALUES(1,1,1,v_pedido,v_producto,CURRENT_DATE::timestamp AT TIME ZONE 'UTC') RETURNING id INTO v_detalle;
    IF v_categoria<>9 OR v_usuario<>20001 OR v_producto<>50001 OR v_pedido<>200001 OR v_detalle<>500001 THEN
        RAISE EXCEPTION 'Las identidades no produjeron los siguientes valores esperados';
    END IF;
    RAISE NOTICE 'PASS: INSERT identity reversible produjo %, %, %, %, %',v_categoria,v_usuario,v_producto,v_pedido,v_detalle;
END;
$identidades$;
ROLLBACK;

-- Mantenimiento ordinario explícito: sin VACUUM FULL, CLUSTER ni ajustes globales.
VACUUM (ANALYZE) categoria;
VACUUM (ANALYZE) usuario;
VACUUM (ANALYZE) producto;
VACUUM (ANALYZE) pedido;
VACUUM (ANALYZE) detalle_pedido;

-- Diagnósticos, no mediciones de rendimiento. Sin EXPLAIN ni tiempos comparativos.
SELECT current_database() AS base,CURRENT_DATE AS fecha_sql,version() AS motor;
SELECT 'categoria' AS tabla,count(*) AS filas FROM categoria
UNION ALL SELECT 'usuario',count(*) FROM usuario
UNION ALL SELECT 'producto',count(*) FROM producto
UNION ALL SELECT 'pedido',count(*) FROM pedido
UNION ALL SELECT 'detalle_pedido',count(*) FROM detalle_pedido;

SELECT min(fecha) AS fecha_min,max(fecha) AS fecha_max FROM pedido;
SELECT fecha,count(*) AS pedidos,count(*) FILTER(WHERE eliminado) AS eliminados
FROM pedido GROUP BY fecha ORDER BY fecha;
SELECT count(*) AS pedidos_total,count(*) FILTER(WHERE eliminado) AS pedidos_eliminados,
       count(*) FILTER(WHERE NOT eliminado) AS pedidos_vigentes,
       round(100.0*count(*) FILTER(WHERE eliminado)/count(*),6) AS eliminado_porcentaje
FROM pedido WHERE fecha=CURRENT_DATE;
SELECT count(*) AS detalles_total,count(*) FILTER(WHERE d.eliminado) AS detalles_eliminados,
       count(*) FILTER(WHERE NOT d.eliminado) AS detalles_vigentes,
       count(*) FILTER(WHERE NOT d.eliminado AND NOT p.eliminado) AS detalles_utilizables,
       round(100.0*count(*) FILTER(WHERE d.eliminado)/count(*),6) AS eliminado_porcentaje
FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE;
SELECT 'pedido_sintetico' AS conjunto,count(*) AS filas,count(*) FILTER(WHERE eliminado) AS eliminadas,
       round(100.0*count(*) FILTER(WHERE eliminado)/count(*),6) AS eliminado_porcentaje FROM pedido WHERE id>=6
UNION ALL SELECT 'detalle_sintetico',count(*),count(*) FILTER(WHERE eliminado),
       round(100.0*count(*) FILTER(WHERE eliminado)/count(*),6) FROM detalle_pedido WHERE id>=8;

SELECT c.id,c.nombre,count(p.id) AS productos FROM categoria c LEFT JOIN producto p ON p.categoria_id=c.id
GROUP BY c.id,c.nombre ORDER BY c.id;
WITH cantidades AS (SELECT p.id,count(d.id) AS n FROM pedido p LEFT JOIN detalle_pedido d ON d.pedido_id=p.id GROUP BY p.id)
SELECT min(n) AS minimo,max(n) AS maximo,avg(n) AS promedio,
       percentile_disc(0.5) WITHIN GROUP(ORDER BY n) AS p50 FROM cantidades;
WITH cantidades AS (SELECT pedido_id,count(*) AS n FROM detalle_pedido WHERE pedido_id>=6 GROUP BY pedido_id)
SELECT min(n) AS minimo_sintetico,max(n) AS maximo_sintetico,avg(n) AS promedio_sintetico,
       percentile_disc(0.5) WITHIN GROUP(ORDER BY n) AS p50_sintetico FROM cantidades;

SELECT c.nombre AS categoria,SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp JOIN producto pr ON pr.id=dp.producto_id
JOIN categoria c ON c.id=pr.categoria_id JOIN pedido ped ON ped.id=dp.pedido_id
WHERE ped.fecha=CURRENT_DATE AND dp.eliminado=FALSE AND ped.eliminado=FALSE
GROUP BY c.nombre ORDER BY total_vendido DESC;

SELECT c.nombre AS categoria,SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp JOIN producto pr ON pr.id=dp.producto_id
JOIN categoria c ON c.id=pr.categoria_id JOIN pedido ped ON ped.id=dp.pedido_id
WHERE ped.fecha=CURRENT_DATE AND dp.eliminado=FALSE AND ped.eliminado=FALSE
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;

SELECT count(*) AS subtotal_inconsistencias FROM detalle_pedido
WHERE subtotal IS DISTINCT FROM cantidad*precio_unitario;
SELECT count(*) AS total_inconsistencias FROM (
    SELECT p.id FROM pedido p LEFT JOIN detalle_pedido d ON d.pedido_id=p.id
    GROUP BY p.id,p.total HAVING p.total IS DISTINCT FROM COALESCE(SUM(d.subtotal) FILTER(WHERE NOT d.eliminado),0)
) x;

SELECT relname,pg_relation_size(relid) AS relation_bytes,pg_total_relation_size(relid) AS total_bytes,
       n_live_tup,n_dead_tup FROM pg_stat_user_tables
WHERE schemaname='public' AND relname IN ('producto','pedido','detalle_pedido') ORDER BY relname;
SELECT tablename,indexname,pg_relation_size(to_regclass(format('%I.%I',schemaname,indexname))) AS index_bytes
FROM pg_indexes WHERE schemaname='public' ORDER BY tablename,indexname;
