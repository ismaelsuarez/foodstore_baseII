-- Food Store: modelo canónico oficial. Instalación sobre una base vacía.
-- Todas las entidades usan eliminación lógica mediante eliminado.

CREATE TYPE forma_pago AS ENUM (
    'EFECTIVO',
    'TARJETA',
    'TRANSFERENCIA'
);

CREATE TYPE rol AS ENUM (
    'ADMIN',
    'USUARIO'
);

CREATE TYPE estado_pedido AS ENUM (
    'PENDIENTE',
    'CONFIRMADO',
    'TERMINADO',
    'CANCELADO'
);

CREATE TABLE categoria (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion VARCHAR(255),
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE usuario (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL,
    apellido VARCHAR(80) NOT NULL,
    mail VARCHAR(120) NOT NULL UNIQUE,
    celular VARCHAR(30),
    contrasena VARCHAR(255) NOT NULL,
    rol rol NOT NULL DEFAULT 'USUARIO',
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- disponible expresa disponibilidad comercial; eliminado, existencia lógica.
CREATE TABLE producto (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    precio NUMERIC(12,2) NOT NULL,
    descripcion VARCHAR(255),
    stock INTEGER NOT NULL DEFAULT 0,
    imagen VARCHAR(255),
    disponible BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id BIGINT NOT NULL,
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (categoria_id)
        REFERENCES categoria(id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_producto_precio
        CHECK (precio >= 0),
    CONSTRAINT chk_producto_stock
        CHECK (stock >= 0)
);

-- PENDIENTE es una decisión de implementación para pedidos nuevos,
-- no un estado recuperado del dataset histórico.
-- fecha es la fecha comercial; created_at conserva la marca temporal técnica.
CREATE TABLE pedido (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    estado estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    total NUMERIC(12,2) NOT NULL DEFAULT 0,
    forma_pago forma_pago NOT NULL,
    usuario_id BIGINT NOT NULL,
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_pedido_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuario(id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_pedido_total
        CHECK (total >= 0)
);

-- id es la PK; el par pedido/producto conserva una restricción UNIQUE.
-- subtotal y pedido.total son físicos y deliberadamente derivados.
-- Su mantenimiento automático pertenece a la siguiente capa de objetos
-- programables; este esquema no instala esa lógica todavía.
CREATE TABLE detalle_pedido (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cantidad INTEGER NOT NULL,
    precio_unitario NUMERIC(12,2) NOT NULL,
    subtotal NUMERIC(12,2) NOT NULL,
    pedido_id BIGINT NOT NULL,
    producto_id BIGINT NOT NULL,
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_detalle_pedido_pedido
        FOREIGN KEY (pedido_id)
        REFERENCES pedido(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_detalle_pedido_producto
        FOREIGN KEY (producto_id)
        REFERENCES producto(id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_detalle_pedido_pedido_producto
        UNIQUE (pedido_id, producto_id),
    CONSTRAINT chk_detalle_pedido_cantidad
        CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_pedido_precio_unitario
        CHECK (precio_unitario >= 0),
    CONSTRAINT chk_detalle_pedido_subtotal
        CHECK (subtotal >= 0)
);

-- Índices base; los candidatos evaluados en Unidad 3 se instalan por separado.
CREATE INDEX idx_producto_categoria
    ON producto(categoria_id);

CREATE INDEX idx_pedido_usuario
    ON pedido(usuario_id);

CREATE INDEX idx_producto_nombre_vig
    ON producto(nombre)
    WHERE eliminado = FALSE;
