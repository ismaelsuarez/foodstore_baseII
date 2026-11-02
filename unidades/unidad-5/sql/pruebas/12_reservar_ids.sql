-- Auxiliar incluido una sola vez antes de 20_permisos y 30_equivalencia.
-- Reserva IDs de las secuencias reales (VP-12), sin asumir nombres *_id_seq.
-- nextval no revierte: pueden quedar huecos; no se intenta restaurar secuencias.
\ir 00_guardas.sql
DO $g$
DECLARE r record; v_id bigint; v_existe boolean;
BEGIN
 FOR r IN SELECT * FROM (VALUES
 ('c1','categoria'), ('u1','usuario'), ('u2','usuario'), ('ua','usuario'),
 ('p1','producto'), ('p2','producto'), ('p3','producto'), ('p4','producto'),
 ('o1','pedido'), ('o2','pedido'), ('o3','pedido')) f(ref,tabla)
 LOOP
  v_id := nextval(pg_get_serial_sequence('public.'||r.tabla,'id')::regclass);
  EXECUTE format('SELECT EXISTS(SELECT FROM public.%I WHERE id=$1)',r.tabla)
      INTO v_existe USING v_id;
  IF v_existe THEN RAISE EXCEPTION 'Secuencia desalineada; detener sin corregir datos'; END IF;
  PERFORM set_config('u5.' || r.ref,v_id::text,false);
 END LOOP;
END $g$;
