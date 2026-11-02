# SEC-04 / M03 — revisión final de reidentificación

**Veredicto: aceptación provisional — pendiente de aceptación formal del equipo.**

Texto humano literal: «La revisión humana acepta provisionalmente el uso académico de datos sintéticos y agregados, pero no autoriza exposición de datos personales reales.»

Se inventariaron TODAS las relaciones legibles efectivamente mediante has_table_privilege(rol_reportes, oid, SELECT), incluidos catálogos y vistas del sistema, y sus columnas/definiciones sin leer sus datos. 01/02 conservan ese inventario, no solo los GRANT directos. La analítica no-sistema utilizada es public.mv_facturacion_categoria_mes (03); no se usa una v_resumen_ventas_rol_mes ni se instala otra analítica.

Columnas: categoria_id, categoria_nombre, mes, cantidad_pedidos, unidades_vendidas, facturacion_total. Agrupamiento: c.id, c.nombre, date_trunc('month',pedido.fecha)::date. Se agrega subtotal físico, sin usuarios individuales. Las cohortes del seed por categoría/mes se registran en 04: Pizzas=3 usuarios y Bebidas=2, ambas marzo 2026. No hay cohorte unitaria aquí, pero estos tamaños NO anonimizan ni acreditan ausencia de reidentificación.

Riesgos: conocimiento auxiliar de compras o categorías singulares; cruces con otras fuentes o perfiles; identificación por cantidades/importes raros; diferencias entre snapshots/refresh que revelen una única compra; granularidad mensual combinada con categoría; cambios de dataset que generen cohortes de tamaño uno. USAGE y metadatos públicos no equivalen a acceso a datos privados, pero pueden facilitar comprensión de la estructura. La denegación de usuario/pedido para rol_reportes reduce cruces internos, no elimina fuentes externas ni privilegios de otra identidad.

Condiciones para aceptación formal: revisión explícita del equipo documentada; confirmar dataset exclusivamente sintético y alcance académico; mantener la matriz exacta sin accesos personales; revisar todos los objetos nuevos y cambios de ADP; definir amenaza, mínimo de cohorte/supresión y política contra diferencias temporales si hubiera datos reales; evaluar cruces auxiliares y granularidad; repetir la revisión tras cambios de datos/esquema/refresh; no publicar datos reales ni atribuir garantías de anonimización. La aceptación provisional no autoriza exposición real ni convierte este documento en PASS automático de M03/SEC-04.
