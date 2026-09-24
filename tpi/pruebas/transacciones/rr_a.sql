-- El orquestador conserva esta conexión y separa las barreras por confirmación.
\set ON_ERROR_STOP on
\ir guard.sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT 'RR_A_ISOLATION=' || current_setting('transaction_isolation');
SELECT 'A_READ_1=' || stock FROM public.producto WHERE id = 1;
-- BARRIER --
-- Se ejecuta solo después del COMMIT confirmado de B.
SELECT 'A_READ_2=' || stock FROM public.producto WHERE id = 1;
COMMIT;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT 'AFTER_A_NEW_TRANSACTION=' || stock FROM public.producto WHERE id = 1;
COMMIT;
