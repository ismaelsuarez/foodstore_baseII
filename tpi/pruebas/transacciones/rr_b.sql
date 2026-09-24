\set ON_ERROR_STOP on
\ir guard.sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT 'RR_B_ISOLATION=' || current_setting('transaction_isolation');
SELECT 'B_BEFORE=' || stock FROM public.producto WHERE id = 1;
UPDATE public.producto SET stock = stock + 1 WHERE id = 1;
COMMIT;
SELECT 'B_AFTER_COMMIT=' || stock FROM public.producto WHERE id = 1;
