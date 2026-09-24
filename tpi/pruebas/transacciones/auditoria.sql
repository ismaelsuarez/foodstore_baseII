-- Solo lectura. No imprime datos personales: conserva huellas de cada tabla.
\set ON_ERROR_STOP on
SELECT json_build_object(
 'database', current_database(),
 'version', version(),
 'server_version', current_setting('server_version'),
 'observed_at', now(),
 'counts', json_build_object('categoria',(SELECT COUNT(*) FROM public.categoria),
   'usuario',(SELECT COUNT(*) FROM public.usuario),'producto',(SELECT COUNT(*) FROM public.producto),
   'pedido',(SELECT COUNT(*) FROM public.pedido),'detalle_pedido',(SELECT COUNT(*) FROM public.detalle_pedido)),
 'stock', (SELECT stock FROM public.producto WHERE id = 1),
 'catalog_counts',json_build_object(
   'tables',(SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'),
   'pk',(SELECT COUNT(*) FROM pg_constraint k JOIN pg_namespace n ON n.oid=k.connamespace WHERE n.nspname='public' AND k.contype='p'),
   'fk',(SELECT COUNT(*) FROM pg_constraint k JOIN pg_namespace n ON n.oid=k.connamespace WHERE n.nspname='public' AND k.contype='f'),
   'checks',(SELECT COUNT(*) FROM pg_constraint k JOIN pg_namespace n ON n.oid=k.connamespace WHERE n.nspname='public' AND k.contype='c'),
   'unique',(SELECT COUNT(*) FROM pg_constraint k JOIN pg_namespace n ON n.oid=k.connamespace WHERE n.nspname='public' AND k.contype='u'),
   'unvalidated',(SELECT COUNT(*) FROM pg_constraint k JOIN pg_namespace n ON n.oid=k.connamespace WHERE n.nspname='public' AND NOT k.convalidated)),
 'subtotal_errors',(SELECT COUNT(*) FROM public.detalle_pedido WHERE subtotal IS DISTINCT FROM cantidad * precio_unitario),
 'total_errors',(SELECT COUNT(*) FROM public.pedido p WHERE total IS DISTINCT FROM
   (SELECT COALESCE(SUM(subtotal),0) FROM public.detalle_pedido d WHERE d.pedido_id=p.id AND NOT d.eliminado)),
 'fk_errors',
   (SELECT COUNT(*) FROM public.producto p LEFT JOIN public.categoria c ON c.id=p.categoria_id WHERE c.id IS NULL) +
   (SELECT COUNT(*) FROM public.pedido p LEFT JOIN public.usuario u ON u.id=p.usuario_id WHERE u.id IS NULL) +
   (SELECT COUNT(*) FROM public.detalle_pedido d LEFT JOIN public.pedido p ON p.id=d.pedido_id WHERE p.id IS NULL) +
   (SELECT COUNT(*) FROM public.detalle_pedido d LEFT JOIN public.producto p ON p.id=d.producto_id WHERE p.id IS NULL),
 'unique_errors',
   (SELECT COUNT(*) FROM (SELECT pedido_id,producto_id FROM public.detalle_pedido GROUP BY pedido_id,producto_id HAVING COUNT(*)>1) x) +
   (SELECT COUNT(*) FROM (SELECT mail FROM public.usuario GROUP BY mail HAVING COUNT(*)>1) x) +
   (SELECT COUNT(*) FROM (SELECT nombre FROM public.categoria GROUP BY nombre HAVING COUNT(*)>1) x),
 'check_errors',
   (SELECT COUNT(*) FROM public.producto WHERE precio<0 OR stock<0) +
   (SELECT COUNT(*) FROM public.pedido WHERE total<0) +
   (SELECT COUNT(*) FROM public.detalle_pedido WHERE cantidad<=0 OR precio_unitario<0 OR subtotal<0),
 'null_errors',
   (SELECT COUNT(*) FROM public.categoria WHERE id IS NULL OR nombre IS NULL OR eliminado IS NULL OR created_at IS NULL) +
   (SELECT COUNT(*) FROM public.usuario WHERE id IS NULL OR nombre IS NULL OR apellido IS NULL OR mail IS NULL OR contrasena IS NULL OR rol IS NULL OR eliminado IS NULL OR created_at IS NULL) +
   (SELECT COUNT(*) FROM public.producto WHERE id IS NULL OR nombre IS NULL OR precio IS NULL OR stock IS NULL OR disponible IS NULL OR categoria_id IS NULL OR eliminado IS NULL OR created_at IS NULL) +
   (SELECT COUNT(*) FROM public.pedido WHERE id IS NULL OR fecha IS NULL OR estado IS NULL OR total IS NULL OR forma_pago IS NULL OR usuario_id IS NULL OR eliminado IS NULL OR created_at IS NULL) +
   (SELECT COUNT(*) FROM public.detalle_pedido WHERE id IS NULL OR cantidad IS NULL OR precio_unitario IS NULL OR subtotal IS NULL OR pedido_id IS NULL OR producto_id IS NULL OR eliminado IS NULL OR created_at IS NULL),
 'data_fingerprints', json_build_object(
   'categoria',(SELECT md5(string_agg(row_to_json(t)::text,E'\n' ORDER BY id)) FROM public.categoria t),
   'usuario',(SELECT md5(string_agg(row_to_json(t)::text,E'\n' ORDER BY id)) FROM public.usuario t),
   'producto',(SELECT md5(string_agg(row_to_json(t)::text,E'\n' ORDER BY id)) FROM public.producto t),
   'pedido',(SELECT md5(string_agg(row_to_json(t)::text,E'\n' ORDER BY id)) FROM public.pedido t),
   'detalle_pedido',(SELECT md5(string_agg(row_to_json(t)::text,E'\n' ORDER BY id)) FROM public.detalle_pedido t)),
 'sequences', (SELECT json_agg(x ORDER BY name) FROM (
   SELECT 'categoria_id_seq' AS name,last_value,is_called FROM public.categoria_id_seq UNION ALL
   SELECT 'usuario_id_seq',last_value,is_called FROM public.usuario_id_seq UNION ALL
   SELECT 'producto_id_seq',last_value,is_called FROM public.producto_id_seq UNION ALL
   SELECT 'pedido_id_seq',last_value,is_called FROM public.pedido_id_seq UNION ALL
   SELECT 'detalle_pedido_id_seq',last_value,is_called FROM public.detalle_pedido_id_seq) x),
 'routines',(SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'),
 'triggers',(SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal AND t.tgenabled='O'),
 'catalog_fingerprint',(SELECT md5(string_agg(def,E'\n' ORDER BY def)) FROM (
   SELECT pg_get_functiondef(p.oid) AS def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
   UNION ALL SELECT pg_get_triggerdef(t.oid) || ':' || t.tgenabled::text FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal
   UNION ALL SELECT c.relname || ':' || k.conname || ':' || pg_get_constraintdef(k.oid) || ':' || k.convalidated::text FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'
   UNION ALL SELECT tablename || ':' || indexdef FROM pg_indexes WHERE schemaname='public'
   UNION ALL SELECT table_name || ':' || column_name || ':' || data_type || ':' || is_nullable || ':' || COALESCE(column_default,'') FROM information_schema.columns WHERE table_schema='public') c)
);
