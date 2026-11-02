-- SEC-16: solo lectura. Antes de CUALQUIER llamada a autenticación/reset,
-- incluso casos con NULL. No configura el servidor ni instala extensiones.
-- design §7.1: log_statement=mod (no all); supresión de valores enlazados
-- tanto en sentencias normales como en errores; archivo de log 0600.
DO $g$
BEGIN
 IF current_setting('log_parameter_max_length') <> '0'
 OR current_setting('log_parameter_max_length_on_error') <> '0'
 OR current_setting('log_statement') <> 'mod'
 OR current_setting('log_file_mode') <> '0600'
 OR current_setting('password_encryption') <> 'scram-sha-256' THEN
  RAISE EXCEPTION 'SEC16: faltan controles preventivos; no probar credenciales';
 END IF;
 IF NOT EXISTS (SELECT FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
                WHERE e.extname='pgcrypto' AND n.nspname='public') THEN
  RAISE EXCEPTION 'VP-07: se requiere pgcrypto en public; no instalar desde pruebas';
 END IF;
END $g$;
