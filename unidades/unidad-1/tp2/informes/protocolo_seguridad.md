# Protocolo de seguridad — Food Store

## 1. Copia de trabajo

Para realizar el Trabajo Práctico de Laboratorio se utiliza una copia de la base de datos original, evitando trabajar directamente sobre la base principal del proyecto.

Base original:

`foodstore`

Base de trabajo para el laboratorio:

`foodstore_tp2`

La copia fue creada con el siguiente comando:

```powershell
createdb -U postgres -T foodstore foodstore_tp2
```

Luego se verificó que la copia contuviera las mismas tablas y datos iniciales que la base original.

Todas las pruebas de concurrencia, restricciones y modificaciones del TP2 se realizarán sobre `foodstore_tp2`.

## 2. Transacción

Todo script o sentencia que modifique datos se prueba primero dentro de una transacción.

El flujo utilizado es:

```sql
BEGIN;

-- operación o script a probar

ROLLBACK;
```

Primero se inspecciona el resultado y se verifica que los cambios sean los esperados.

Si la prueba es correcta, se vuelve a ejecutar la operación dentro de una nueva transacción y recién entonces se confirma con:

```sql
COMMIT;
```

Durante la preparación del proyecto se verificó este procedimiento cargando `datos_iniciales.sql` dentro de una transacción, comprobando los registros insertados y ejecutando luego `ROLLBACK`.

Después se repitió la carga dentro de una nueva transacción y, una vez verificado que el resultado era correcto, se confirmó con `COMMIT`.

## 3. Respaldo

Antes de aplicar cambios estructurales sobre la base de trabajo se realiza un respaldo independiente mediante `pg_dump`.

El respaldo de la copia `foodstore_tp2` se generó con:

```powershell
pg_dump -U postgres -Fc -d foodstore_tp2 -f .\backups\foodstore_tp2_inicial.dump
```

El archivo de respaldo se guarda en:

`.\backups\foodstore_tp2_inicial.dump`

Se verificó que el archivo `foodstore_tp2_inicial.dump` fuera creado correctamente antes de continuar con modificaciones estructurales o pruebas que pudieran afectar la base.
