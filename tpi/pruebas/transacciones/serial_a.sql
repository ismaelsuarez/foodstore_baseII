\set ON_ERROR_STOP on
\ir guard.sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT 'SERIAL_A_ISOLATION=' || current_setting('transaction_isolation');
SELECT 'SERIAL_A_READ=' || stock FROM public.producto WHERE id = 1;
-- BARRIER --
-- B ya tiene snapshot; A mantiene su escritura sin confirmar.
UPDATE public.producto SET stock = stock + 2 WHERE id = 1;
SELECT 'SERIAL_A_UNCOMMITTED=' || stock FROM public.producto WHERE id = 1;
-- BARRIER --
-- El monitor debe observar B esperando a A antes de permitir este COMMIT.
COMMIT;
SELECT 'SERIAL_A_COMMITTED=' || stock FROM public.producto WHERE id = 1;
