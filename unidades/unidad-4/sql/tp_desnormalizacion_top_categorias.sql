-- Unidad 4, Fase 6E: remediación experimental serializada; no ADOPTED.
-- Ruta cerrada autorizada: LOGIN real u4_app y cuatro API SECURITY DEFINER.
-- El fallo anterior permanece en Git y en su evidencia; no se reescribe.
-- Requiere foodstore_u4_revalidacion, checkpoint Phase3 y fuentes canónicas.
-- Ejecutar con psql -X -w -v ON_ERROR_STOP=1 -f <este archivo>, sin -1 externo.
-- El contrato revisado está en ../specs/u4_desnormalizacion_top_categorias.md.
-- El SQL anterior permanece en Git (95fbfbf); no reutilizar sus métricas.
-- La instalación bloquea producto/detalle y administra su transacción.
-- No crea índices, no instala TPI y no ejecuta benchmark de lectura AFTER.
-- \timing informa duración de instrucciones de migración desde psql;
-- no equivale a Execution Time de EXPLAIN ni a una prueba de rendimiento READ.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
\pset pager off
\pset format unaligned
\pset tuples_only on
\timing off
SELECT current_database()='foodstore_u4_revalidacion'
 AND CURRENT_DATE=DATE '2026-09-23'
 AND current_setting('server_version')='17.11' AS guard_ok \gset
\if :guard_ok
\else
\echo STOP: base_fecha_version
SELECT 1/0;
\endif
BEGIN;
LOCK TABLE public.producto IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.detalle_pedido IN ACCESS EXCLUSIVE MODE;
SELECT current_database()='foodstore_u4_revalidacion' AND CURRENT_DATE=DATE '2026-09-23' AND current_setting('server_version')='17.11' AS guard_ok \gset
\if :guard_ok
\echo PASS: base_fecha_version
\else
\echo STOP: base_fecha_version
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f'))=5
 AND NOT EXISTS (SELECT 1 FROM (VALUES ('categoria'),('usuario'),('producto'),('pedido'),('detalle_pedido')) x(nombre)
   WHERE NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relname=x.nombre AND c.relkind='r'))
 AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema')
 AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal)
 AND NOT EXISTS (SELECT 1 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='detalle_pedido' AND column_name='categoria_id') AS guard_ok \gset
\if :guard_ok
\echo PASS: catalogo_sin_U4_TPI_FNBC
\else
\echo STOP: catalogo_sin_U4_TPI_FNBC
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM pg_indexes WHERE schemaname='public')=14
 AND NOT EXISTS (
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
 WHERE i.indexname IS NULL OR i.indexdef<>x.definicion OR NOT ix.indisvalid OR NOT ix.indisready) AS guard_ok \gset
\if :guard_ok
\echo PASS: indices_raiz_TP5
\else
\echo STOP: indices_raiz_TP5
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM categoria)=8
 AND (SELECT count(*) FROM usuario)=20000
 AND (SELECT count(*) FROM producto)=50000
 AND (SELECT count(*) FROM pedido)=200000
 AND (SELECT count(*) FROM detalle_pedido)=500000
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE)=20000
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE AND NOT eliminado)=19800
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE AND eliminado)=200
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE)=50000
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado)=49500
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado AND NOT p.eliminado)=48900
 AND (SELECT count(DISTINCT pr.categoria_id) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id
      JOIN producto pr ON pr.id=d.producto_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado AND NOT p.eliminado)=8 AS guard_ok \gset
\if :guard_ok
\echo PASS: conteos_y_poblacion_del_dia
\else
\echo STOP: conteos_y_poblacion_del_dia
SELECT 1/0;
\endif

SELECT NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE subtotal IS DISTINCT FROM cantidad*precio_unitario)
 AND NOT EXISTS (SELECT 1 FROM pedido p LEFT JOIN detalle_pedido d ON d.pedido_id=p.id
   GROUP BY p.id,p.total HAVING p.total IS DISTINCT FROM COALESCE(SUM(d.subtotal) FILTER(WHERE NOT d.eliminado),0))
 AND NOT EXISTS (SELECT 1 FROM producto p LEFT JOIN categoria c ON c.id=p.categoria_id WHERE c.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM pedido p LEFT JOIN usuario u ON u.id=p.usuario_id WHERE u.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido d LEFT JOIN pedido p ON p.id=d.pedido_id
   LEFT JOIN producto pr ON pr.id=d.producto_id WHERE p.id IS NULL OR pr.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido GROUP BY pedido_id,producto_id HAVING count(*)>1)
 AND NOT EXISTS (SELECT 1 FROM producto WHERE precio<0 OR stock<0)
 AND NOT EXISTS (SELECT 1 FROM pedido WHERE total<0)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE cantidad<=0 OR precio_unitario<0 OR subtotal<0) AS guard_ok \gset
\if :guard_ok
\echo PASS: integridad
\else
\echo STOP: integridad
SELECT 1/0;
\endif

-- Restricciones estructurales antes de alterar; no reparar contratos divergentes.
DO LANGUAGE plpgsql $precheck$
BEGIN
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public') <> 40
       OR (SELECT count(*) FROM pg_constraint
           WHERE conrelid IN ('public.categoria'::regclass,'public.usuario'::regclass,
             'public.producto'::regclass,'public.pedido'::regclass,
             'public.detalle_pedido'::regclass)) <> 18
       OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgisinternal AND tgenabled <> 'O')
    THEN RAISE EXCEPTION 'STOP: columnas, restricciones o triggers estructurales'; END IF;
    IF EXISTS (
        SELECT 1 FROM (VALUES
          ('fk_producto_categoria','public.producto'::regclass,'public.categoria'::regclass),
          ('fk_pedido_usuario','public.pedido'::regclass,'public.usuario'::regclass),
          ('fk_detalle_pedido_pedido','public.detalle_pedido'::regclass,'public.pedido'::regclass),
          ('fk_detalle_pedido_producto','public.detalle_pedido'::regclass,'public.producto'::regclass)
        ) x(nombre,origen,destino)
        LEFT JOIN pg_constraint c ON c.conname=x.nombre AND c.conrelid=x.origen
        WHERE c.oid IS NULL OR c.contype <> 'f' OR c.confrelid <> x.destino
          OR c.confdeltype <> 'r' OR NOT c.convalidated
    ) THEN RAISE EXCEPTION 'STOP: FK canónicas'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid='public.detalle_pedido'::regclass
          AND conname='uq_detalle_pedido_pedido_producto' AND contype='u'
          AND pg_get_constraintdef(oid)='UNIQUE (pedido_id, producto_id)')
    THEN RAISE EXCEPTION 'STOP: unicidad del detalle'; END IF;
    IF EXISTS (
        SELECT 1 FROM (VALUES
          ('public.pedido'::regclass,'fecha','date'),
          ('public.pedido'::regclass,'total','numeric(12,2)'),
          ('public.detalle_pedido'::regclass,'subtotal','numeric(12,2)'),
          ('public.producto'::regclass,'categoria_id','bigint')
        ) x(tabla,columna,tipo)
        LEFT JOIN pg_attribute a ON a.attrelid=x.tabla AND a.attname=x.columna
          AND a.attnum>0 AND NOT a.attisdropped
        WHERE a.attnum IS NULL OR format_type(a.atttypid,a.atttypmod)<>x.tipo
          OR NOT a.attnotnull
    ) OR NOT EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid='public.detalle_pedido'::regclass AND contype='p'
          AND pg_get_constraintdef(oid)='PRIMARY KEY (id)')
    THEN RAISE EXCEPTION 'STOP: tipos canónicos o PK del detalle'; END IF;
END;
$precheck$;

-- Roles exclusivos. La contraseña efímera se provisiona fuera del repo sin logs.
DO LANGUAGE plpgsql $roles$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname IN ('u4_app','u4_owner'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname='u4_api')
    THEN RAISE EXCEPTION 'STOP: roles o schema experimental preexistentes'; END IF;
END;
$roles$;
CREATE ROLE u4_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE u4_app LOGIN PASSWORD NULL NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE SCHEMA u4_api AUTHORIZATION u4_owner;
REVOKE ALL ON SCHEMA u4_api FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO u4_owner,u4_app;
GRANT USAGE ON SCHEMA u4_api TO u4_app;
GRANT CONNECT ON DATABASE foodstore_u4_revalidacion TO u4_app;

-- Capturar todas las columnas originales; categoria_id será excluida al comparar.
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS before_producto FROM public.producto t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS before_detalle FROM public.detalle_pedido t \gset
SELECT md5(string_agg(indexname||indexdef,'' ORDER BY indexname)) AS before_indexes FROM pg_indexes WHERE schemaname='public' \gset
\echo MIGRATION_ADD_COLUMN_BEGIN
\timing on
ALTER TABLE public.detalle_pedido ADD COLUMN categoria_id BIGINT;
\timing off
\echo MIGRATION_ADD_COLUMN_END
\echo MIGRATION_BACKFILL_BEGIN
\timing on
UPDATE public.detalle_pedido dp
SET categoria_id=pr.categoria_id
FROM public.producto pr
WHERE pr.id=dp.producto_id;
\timing off
\echo MIGRATION_BACKFILL_END
DO LANGUAGE plpgsql $backfill$
BEGIN
    IF (SELECT count(*) FROM public.detalle_pedido) <> 500000
       OR EXISTS (SELECT 1 FROM public.detalle_pedido dp
          LEFT JOIN public.producto pr ON pr.id=dp.producto_id
          WHERE dp.categoria_id IS NULL OR pr.id IS NULL
             OR dp.categoria_id IS DISTINCT FROM pr.categoria_id)
    THEN RAISE EXCEPTION 'STOP: backfill incompleto o desincronizado'; END IF;
    RAISE NOTICE 'PASS: backfill 500000, NULL 0, desincronización 0';
END;
$backfill$;
-- NOT NULL se aplica antes de la FK: el backfill ya acreditó ausencia de NULL
-- y correspondencia con producto. Ambas restricciones se confirman juntas.
\echo MIGRATION_NOT_NULL_BEGIN
\timing on
ALTER TABLE public.detalle_pedido ALTER COLUMN categoria_id SET NOT NULL;
\timing off
\echo MIGRATION_NOT_NULL_END
\echo MIGRATION_FK_BEGIN
\timing on
ALTER TABLE public.detalle_pedido
    ADD CONSTRAINT fk_detalle_pedido_categoria
    FOREIGN KEY (categoria_id) REFERENCES public.categoria(id) ON DELETE RESTRICT;
\timing off
\echo MIGRATION_FK_END
\echo MIGRATION_FUNCTIONS_TRIGGERS_BEGIN
\timing on
-- BEFORE STATEMENT no intercepta SELECT FOR UPDATE. La barrera principal es
-- la API que toma el gate antes de acceder a filas, con DML directo revocado.
CREATE FUNCTION u4_api.fn_gate_categoria()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $func$
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(21812,1);
    RETURN NULL;
END;
$func$;

CREATE FUNCTION u4_api.fn_detalle_pedido_set_categoria()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $func$
DECLARE
    v_categoria_id bigint;
BEGIN
    IF NEW.producto_id IS NULL THEN
        RETURN NEW; -- NOT NULL estructural: no convertir NULL en 23503.
    END IF;
    SELECT pr.categoria_id INTO v_categoria_id
    FROM public.producto pr WHERE pr.id=NEW.producto_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='23503',
            MESSAGE='Producto inexistente para derivar la categoría del detalle',
            DETAIL=pg_catalog.format('producto_id=%s no existe en public.producto',NEW.producto_id),
            SCHEMA='public', TABLE='detalle_pedido', COLUMN='producto_id',
            CONSTRAINT='fk_detalle_pedido_producto';
    END IF;
    NEW.categoria_id := v_categoria_id;
    RETURN NEW;
END;
$func$;

CREATE FUNCTION u4_api.fn_producto_sync_categoria_detalle()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $func$
BEGIN
    IF NEW.categoria_id IS DISTINCT FROM OLD.categoria_id THEN
        UPDATE public.detalle_pedido SET categoria_id=NEW.categoria_id
        WHERE producto_id=NEW.id AND categoria_id IS DISTINCT FROM NEW.categoria_id;
    END IF;
    RETURN NEW;
END;
$func$;

CREATE TRIGGER trg_detalle_pedido_gate_categoria
BEFORE INSERT OR UPDATE OF producto_id, categoria_id ON public.detalle_pedido
FOR EACH STATEMENT EXECUTE FUNCTION u4_api.fn_gate_categoria();
CREATE TRIGGER trg_producto_gate_categoria
BEFORE UPDATE OF categoria_id ON public.producto
FOR EACH STATEMENT EXECUTE FUNCTION u4_api.fn_gate_categoria();
CREATE TRIGGER trg_detalle_pedido_set_categoria
BEFORE INSERT OR UPDATE OF producto_id, categoria_id ON public.detalle_pedido
FOR EACH ROW EXECUTE FUNCTION u4_api.fn_detalle_pedido_set_categoria();
CREATE TRIGGER trg_producto_sync_categoria_detalle
AFTER UPDATE OF categoria_id ON public.producto
FOR EACH ROW EXECUTE FUNCTION u4_api.fn_producto_sync_categoria_detalle();

-- Cada API toma el gate como primera instrucción. VOLATILE y READ COMMITTED:
-- la sentencia posterior al PERFORM lee su snapshot después de la espera.
-- No STRICT: los NULL deben alcanzar las restricciones originales.
-- IDs explícitos; sin acceso a secuencias ni generación implícita de fixtures.
CREATE FUNCTION u4_api.insertar_detalles(p_detalles jsonb)
RETURNS SETOF bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $func$
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(21812,1);
    RETURN QUERY
    INSERT INTO public.detalle_pedido AS dp
        (id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,
         eliminado,created_at,categoria_id)
    OVERRIDING SYSTEM VALUE
    SELECT x.id,x.cantidad,x.precio_unitario,x.subtotal,x.pedido_id,x.producto_id,
           COALESCE(x.eliminado,FALSE),COALESCE(x.created_at,pg_catalog.now()),x.categoria_id
    FROM pg_catalog.jsonb_to_recordset(p_detalles) AS x(
        id bigint,cantidad integer,precio_unitario numeric(12,2),subtotal numeric(12,2),
        pedido_id bigint,producto_id bigint,eliminado boolean,
        created_at timestamptz,categoria_id bigint)
    RETURNING dp.id;
END;
$func$;

CREATE FUNCTION u4_api.cambiar_producto_detalle(p_detalle_id bigint,p_producto_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $func$
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(21812,1);
    UPDATE public.detalle_pedido SET producto_id=p_producto_id WHERE id=p_detalle_id;
END;
$func$;

CREATE FUNCTION u4_api.normalizar_categoria_detalle(p_detalle_id bigint,p_categoria_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $func$
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(21812,1);
    UPDATE public.detalle_pedido SET categoria_id=p_categoria_id WHERE id=p_detalle_id;
END;
$func$;

CREATE FUNCTION u4_api.recategorizar_producto(p_producto_id bigint,p_categoria_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $func$
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(21812,1);
    UPDATE public.producto SET categoria_id=p_categoria_id WHERE id=p_producto_id;
END;
$func$;

ALTER FUNCTION u4_api.fn_gate_categoria() OWNER TO u4_owner;
ALTER FUNCTION u4_api.fn_detalle_pedido_set_categoria() OWNER TO u4_owner;
ALTER FUNCTION u4_api.fn_producto_sync_categoria_detalle() OWNER TO u4_owner;
ALTER FUNCTION u4_api.insertar_detalles(jsonb) OWNER TO u4_owner;
ALTER FUNCTION u4_api.cambiar_producto_detalle(bigint,bigint) OWNER TO u4_owner;
ALTER FUNCTION u4_api.normalizar_categoria_detalle(bigint,bigint) OWNER TO u4_owner;
ALTER FUNCTION u4_api.recategorizar_producto(bigint,bigint) OWNER TO u4_owner;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA u4_api FROM PUBLIC;

-- Owner sin propiedad de tablas ni membresías. UPDATE(categoria_id) permite
-- FOR SHARE sobre producto; ninguna autoridad de stock/subtotal/total se agrega.
GRANT SELECT(id,categoria_id), UPDATE(categoria_id)
    ON public.producto TO u4_owner;
GRANT SELECT(id,producto_id,categoria_id), UPDATE(producto_id,categoria_id),
    INSERT(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,
           eliminado,created_at,categoria_id)
    ON public.detalle_pedido TO u4_owner;
GRANT SELECT ON public.categoria,public.producto,public.pedido,public.detalle_pedido TO u4_app;
GRANT EXECUTE ON FUNCTION u4_api.insertar_detalles(jsonb),
    u4_api.cambiar_producto_detalle(bigint,bigint),
    u4_api.normalizar_categoria_detalle(bigint,bigint),
    u4_api.recategorizar_producto(bigint,bigint) TO u4_app;
\timing off
\echo MIGRATION_FUNCTIONS_TRIGGERS_END

-- Privilegios EFECTIVOS, incluidos los recibidos por PUBLIC.
DO LANGUAGE plpgsql $acl$
DECLARE
    v_tabla text;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members
        WHERE roleid IN ('u4_app'::regrole,'u4_owner'::regrole)
           OR member IN ('u4_app'::regrole,'u4_owner'::regrole))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_class
          WHERE relnamespace='public'::regnamespace
            AND relowner IN ('u4_app'::regrole,'u4_owner'::regrole))
       OR pg_catalog.has_schema_privilege('u4_app','public','CREATE')
       OR pg_catalog.has_schema_privilege('u4_app','u4_api','CREATE')
       OR pg_catalog.has_table_privilege('u4_app','public.usuario','SELECT')
    THEN RAISE EXCEPTION 'STOP: privilegios o propiedad fuera de contrato'; END IF;
    FOREACH v_tabla IN ARRAY ARRAY['categoria','producto','pedido','detalle_pedido','usuario'] LOOP
        IF pg_catalog.has_table_privilege('u4_app','public.'||v_tabla,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
           OR pg_catalog.has_any_column_privilege('u4_app','public.'||v_tabla,'INSERT,UPDATE,REFERENCES')
        THEN RAISE EXCEPTION 'STOP: u4_app tiene escritura directa en %',v_tabla; END IF;
    END LOOP;
    IF pg_catalog.has_function_privilege('u4_app','u4_api.fn_gate_categoria()','EXECUTE')
       OR pg_catalog.has_function_privilege('u4_app','u4_api.fn_detalle_pedido_set_categoria()','EXECUTE')
       OR pg_catalog.has_function_privilege('u4_app','u4_api.fn_producto_sync_categoria_detalle()','EXECUTE')
    THEN RAISE EXCEPTION 'STOP: helper ejecutable directamente por u4_app'; END IF;
END;
$acl$;

-- Solo categoría actual incluidas bajas, sin tocar stock/subtotal/total.
-- El superusuario queda fuera del contrato; no usar SET ROLE para acreditar LOGIN.
SELECT NOT EXISTS (SELECT 1 FROM public.detalle_pedido dp
  LEFT JOIN public.producto pr ON pr.id=dp.producto_id
  LEFT JOIN public.categoria c ON c.id=dp.categoria_id
  WHERE dp.categoria_id IS NULL OR pr.id IS NULL OR c.id IS NULL
     OR dp.categoria_id IS DISTINCT FROM pr.categoria_id)
 AND :'before_producto'=(SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.producto t)
 AND :'before_detalle'=(SELECT md5(string_agg(md5((to_jsonb(t)-'categoria_id')::text),'' ORDER BY id)) FROM public.detalle_pedido t)
 AND :'before_indexes'=(SELECT md5(string_agg(indexname||indexdef,'' ORDER BY indexname)) FROM pg_indexes WHERE schemaname='public')
 AND (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal)=4
 AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema')=7 AS guard_ok \gset
\if :guard_ok
\echo PASS: candidato_instalado_auditoria_canonica_0
\else
\echo STOP: auditoria_final_UP
SELECT 1/0;
\endif
COMMIT;

-- Diagnóstico legible y consulta semántica: no constituyen benchmark READ AFTER.
\pset format aligned
\pset tuples_only off
SELECT count(*) AS detalles,
       count(*) FILTER (WHERE dp.categoria_id IS NULL) AS categorias_null,
       count(*) FILTER (WHERE pr.id IS NULL OR c.id IS NULL) AS referencias_huerfanas,
       count(*) FILTER (WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id) AS desincronizados
FROM public.detalle_pedido dp
LEFT JOIN public.producto pr ON pr.id=dp.producto_id
LEFT JOIN public.categoria c ON c.id=dp.categoria_id;

SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN categoria c ON c.id=dp.categoria_id
JOIN pedido ped ON ped.id=dp.pedido_id
WHERE ped.fecha=CURRENT_DATE
  AND dp.eliminado=FALSE
  AND ped.eliminado=FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- El coordinador documenta el mantenimiento posterior autorizado (VACUUM/ANALYZE)
-- por separado. Este UP no instala índices ni ejecuta mediciones de lectura.

-- DOWN manual: extraer únicamente entre marcadores, revisar y ejecutar con
-- autorización en BEGIN; validar catálogo/datos; ROLLBACK si se debe conservar
-- el candidato instalado. Este archivo NO ejecuta el DOWN automáticamente.
/*
-- BEGIN_DOWN
-- Administrador, sin conexiones de u4_app abiertas. No CASCADE ni DROP OWNED.
DO LANGUAGE plpgsql $down_guard$
BEGIN
    IF current_database()<>'foodstore_u4_revalidacion'
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_stat_activity WHERE usename IN ('u4_app','u4_owner'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members
           WHERE roleid IN ('u4_app'::regrole,'u4_owner'::regrole)
              OR member IN ('u4_app'::regrole,'u4_owner'::regrole))
    THEN RAISE EXCEPTION 'STOP: base, sesiones o membresías impiden DOWN'; END IF;
END;
$down_guard$;
DROP TRIGGER trg_producto_sync_categoria_detalle ON public.producto;
DROP TRIGGER trg_detalle_pedido_set_categoria ON public.detalle_pedido;
DROP TRIGGER trg_producto_gate_categoria ON public.producto;
DROP TRIGGER trg_detalle_pedido_gate_categoria ON public.detalle_pedido;
DROP FUNCTION u4_api.insertar_detalles(jsonb);
DROP FUNCTION u4_api.cambiar_producto_detalle(bigint,bigint);
DROP FUNCTION u4_api.normalizar_categoria_detalle(bigint,bigint);
DROP FUNCTION u4_api.recategorizar_producto(bigint,bigint);
DROP FUNCTION u4_api.fn_producto_sync_categoria_detalle();
DROP FUNCTION u4_api.fn_detalle_pedido_set_categoria();
DROP FUNCTION u4_api.fn_gate_categoria();
ALTER TABLE public.detalle_pedido DROP CONSTRAINT fk_detalle_pedido_categoria;
REVOKE SELECT(id,categoria_id), UPDATE(categoria_id) ON public.producto FROM u4_owner;
REVOKE SELECT(id,producto_id,categoria_id), UPDATE(producto_id,categoria_id),
    INSERT(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,
           eliminado,created_at,categoria_id) ON public.detalle_pedido FROM u4_owner;
REVOKE SELECT ON public.categoria,public.producto,public.pedido,public.detalle_pedido FROM u4_app;
ALTER TABLE public.detalle_pedido DROP COLUMN categoria_id;
REVOKE USAGE ON SCHEMA u4_api FROM u4_app;
DROP SCHEMA u4_api;
REVOKE USAGE ON SCHEMA public FROM u4_app,u4_owner;
REVOKE CONNECT ON DATABASE foodstore_u4_revalidacion FROM u4_app;
DO LANGUAGE plpgsql $down_dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_shdepend
        WHERE refclassid='pg_catalog.pg_authid'::regclass
          AND refobjid IN ('u4_app'::regrole,'u4_owner'::regrole))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members
           WHERE roleid IN ('u4_app'::regrole,'u4_owner'::regrole)
              OR member IN ('u4_app'::regrole,'u4_owner'::regrole))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_stat_activity WHERE usename IN ('u4_app','u4_owner'))
    THEN RAISE EXCEPTION 'STOP: dependencias, membresías o sesiones remanentes'; END IF;
END;
$down_dependencies$;
DROP ROLE u4_app;
DROP ROLE u4_owner;
-- END_DOWN
*/
