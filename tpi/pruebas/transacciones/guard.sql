-- Guarda compartida: solo laboratorio TPI-B nuevo, instalado y sin otras escrituras.
\set ON_ERROR_STOP on
DO $$
BEGIN
    IF current_database() <> 'foodstore_tpi_cierre_b' THEN
        RAISE EXCEPTION 'Laboratorio incorrecto: %', current_database();
    END IF;
    IF current_setting('session_replication_role') <> 'origin' THEN
        RAISE EXCEPTION 'Se requiere session_replication_role = origin';
    END IF;
    IF (SELECT COUNT(*) FROM public.categoria) <> 2
       OR (SELECT COUNT(*) FROM public.usuario) <> 3
       OR (SELECT COUNT(*) FROM public.producto) <> 3
       OR (SELECT COUNT(*) FROM public.pedido) <> 5
       OR (SELECT COUNT(*) FROM public.detalle_pedido) <> 7 THEN
        RAISE EXCEPTION 'Los conteos no corresponden al seed canónico';
    END IF;
    IF (SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind='r') <> 5 THEN
        RAISE EXCEPTION 'Se requieren exclusivamente las cinco tablas canónicas';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.producto
                   WHERE id = 1 AND nombre = 'Muzzarella' AND stock = 50
                     AND disponible AND NOT eliminado) THEN
        RAISE EXCEPTION 'El fixture controlado producto 1 no coincide con el seed';
    END IF;
    IF (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public') <> 7
       OR (SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND NOT t.tgisinternal AND t.tgenabled = 'O') <> 5 THEN
        RAISE EXCEPTION 'Se requieren las siete rutinas y cinco triggers canónicos';
    END IF;
    IF to_regprocedure('public.registrar_detalle_pedido(bigint,bigint,integer)') IS NULL
       OR to_regprocedure('public.calcular_total_pedido(bigint)') IS NULL
       OR EXISTS (SELECT 1 FROM pg_attribute
                  WHERE attrelid = 'public.detalle_pedido'::regclass
                    AND attname = 'categoria_id' AND NOT attisdropped) THEN
        RAISE EXCEPTION 'Los objetos no corresponden al laboratorio canónico TPI';
    END IF;
END;
$$;
