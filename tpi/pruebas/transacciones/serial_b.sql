\set ON_ERROR_STOP on
\ir guard.sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT 'SERIAL_B_ISOLATION=' || current_setting('transaction_isolation');
SELECT 'SERIAL_B_READ=' || stock FROM public.producto WHERE id = 1;
-- BARRIER --
-- Debe esperar a A y producir 40001 después del COMMIT de A.
-- ON_ERROR_STOP termina esta conexión; no se acepta 40P01 ni otro error.
UPDATE public.producto SET stock = stock + 3 WHERE id = 1;
COMMIT;
