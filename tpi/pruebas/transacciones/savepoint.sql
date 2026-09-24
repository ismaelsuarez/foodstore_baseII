-- No usa errores artificiales. El ROLLBACK final devuelve el stock a 50.
\set ON_ERROR_STOP on
\ir guard.sql
SELECT 'BEFORE=' || stock FROM public.producto WHERE id = 1;
BEGIN;
UPDATE public.producto SET stock = stock - 1 WHERE id = 1;
SELECT 'AFTER_FIRST_CHANGE=' || stock FROM public.producto WHERE id = 1;
SAVEPOINT sp_tpi;
UPDATE public.producto SET stock = stock - 2 WHERE id = 1;
SELECT 'AFTER_SECOND_CHANGE=' || stock FROM public.producto WHERE id = 1;
ROLLBACK TO SAVEPOINT sp_tpi;
SELECT 'AFTER_ROLLBACK_TO_SAVEPOINT=' || stock FROM public.producto WHERE id = 1;
ROLLBACK;
SELECT 'FINAL=' || stock FROM public.producto WHERE id = 1;
