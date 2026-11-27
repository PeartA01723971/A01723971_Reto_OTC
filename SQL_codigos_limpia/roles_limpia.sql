USE OTC; 

-- 61. Creación de la tabla limpia de roles
-- Se conserva la tabla original sin modificaciones.

CREATE TABLE clean_roles
LIKE stg_roles;

INSERT INTO clean_roles
SELECT * FROM stg_roles;

-- Corregir los caracteres invisibles de las columnas.

SET SESSION group_concat_max_len = 100000;

SELECT GROUP_CONCAT(
    CONCAT(
        'RENAME COLUMN `',
        REPLACE(COLUMN_NAME, '`', '``'),
        '` TO `',
        REGEXP_REPLACE(
            COLUMN_NAME,
            '[^a-zA-Z0-9_]',
            ''
        ),
        '`'
    )
    ORDER BY ORDINAL_POSITION
    SEPARATOR ', '
)
INTO @columnas
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'clean_roles';

SET @sql = CONCAT(
    'ALTER TABLE clean_roles ',
    @columnas
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verificar el número de roles registrados.

SELECT COUNT(*) AS total_roles
FROM clean_roles;

-- 62.1. Verificar los nombres actuales de las columnas
-- Se comprueba si todavía contienen caracteres invisibles.

SELECT
    ORDINAL_POSITION AS posicion,
    COLUMN_NAME AS nombre_actual,
    HEX(COLUMN_NAME) AS nombre_hexadecimal,
    REGEXP_REPLACE(
        COLUMN_NAME,
        '[^a-zA-Z0-9_]',
        ''
    ) AS nombre_esperado

FROM INFORMATION_SCHEMA.COLUMNS

WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'clean_roles'

ORDER BY ORDINAL_POSITION;

-- 62.2. Preparar la corrección de nombres
-- Todavía no modifica la tabla.

SET SESSION group_concat_max_len = 100000;

SELECT GROUP_CONCAT(
    CONCAT(
        'RENAME COLUMN `',
        REPLACE(COLUMN_NAME, '`', '``'),
        '` TO `',
        REGEXP_REPLACE(
            COLUMN_NAME,
            '[^a-zA-Z0-9_]',
            ''
        ),
        '`'
    )
    ORDER BY ORDINAL_POSITION
    SEPARATOR ', '
)
INTO @columnas
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'clean_roles'
  AND HEX(COLUMN_NAME) REGEXP 'E281A0|E280AF';

SELECT @columnas AS correcciones_preparadas;

-- 62.3. Aplicar la corrección de nombres
-- Se conservan los 55 registros originales.

SET @sql = CONCAT(
    'ALTER TABLE clean_roles ',
    @columnas
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verificar los nombres corregidos

SHOW COLUMNS FROM clean_roles;

-- 62.4. Validación de calidad del catálogo de roles
-- Se revisan códigos duplicados y datos faltantes.

SELECT
    COUNT(*) AS total_roles,

    COUNT(DISTINCT NULLIF(TRIM(codigo), ''))
        AS codigos_unicos,

    SUM(CASE
        WHEN codigo IS NULL OR TRIM(codigo) = ''
        THEN 1 ELSE 0
    END) AS codigos_vacios,

    SUM(CASE
        WHEN nombre_del_rol IS NULL OR TRIM(nombre_del_rol) = ''
        THEN 1 ELSE 0
    END) AS nombres_vacios,

    SUM(CASE
        WHEN nivel IS NULL OR TRIM(nivel) = ''
        THEN 1 ELSE 0
    END) AS niveles_vacios,

    SUM(CASE
        WHEN departamento IS NULL OR TRIM(departamento) = ''
        THEN 1 ELSE 0
    END) AS departamentos_vacios,

    SUM(CASE
        WHEN descripcion IS NULL OR TRIM(descripcion) = ''
        THEN 1 ELSE 0
    END) AS descripciones_vacias,

    SUM(CASE
        WHEN estatus IS NULL OR TRIM(estatus) = ''
        THEN 1 ELSE 0
    END) AS estatus_vacios

FROM clean_roles;

-- 63. Identificación de roles sin departamento
-- Se revisan los roles que tienen información faltante.
-- No se modifican los datos originales.

SELECT
    codigo,
    nombre_del_rol,
    nivel,
    departamento,
    descripcion,
    estatus

FROM clean_roles

WHERE departamento IS NULL
   OR TRIM(departamento) = ''

ORDER BY codigo;

-- 64. Identificación de valores pendientes en roles
-- Se revisan campos con información no definida.
-- No se modifican los registros.

SELECT
    codigo,
    nombre_del_rol,
    nivel,
    departamento,
    descripcion,
    estatus

FROM clean_roles

WHERE UPPER(TRIM(nombre_del_rol)) IN ('PENDIENTE', 'N/A')
   OR UPPER(TRIM(nivel)) IN ('PENDIENTE', 'N/A')
   OR UPPER(TRIM(departamento)) IN ('PENDIENTE', 'N/A')
   OR UPPER(TRIM(descripcion)) IN ('PENDIENTE', 'N/A')
   OR UPPER(TRIM(estatus)) IN ('PENDIENTE', 'N/A')

ORDER BY codigo;

-- 65. Estandarización de valores pendientes
-- Se reemplazan los valores PENDIENTE y N/A por NULL.
-- Se conserva el registro para su revisión posterior.

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_roles
SET
    nombre_del_rol = CASE
        WHEN UPPER(TRIM(nombre_del_rol)) IN ('PENDIENTE', 'N/A')
        THEN NULL
        ELSE nombre_del_rol
    END,

    descripcion = CASE
        WHEN UPPER(TRIM(descripcion)) IN ('PENDIENTE', 'N/A')
        THEN NULL
        ELSE descripcion
    END

WHERE UPPER(TRIM(nombre_del_rol)) IN ('PENDIENTE', 'N/A')
   OR UPPER(TRIM(descripcion)) IN ('PENDIENTE', 'N/A');

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados de la limpieza.

SELECT
    codigo,
    nombre_del_rol,
    nivel,
    departamento,
    descripcion,
    estatus
FROM clean_roles
WHERE codigo = 'R0142';

-- 66. Validación de departamentos de los roles
-- Se identifican departamentos que no coinciden
-- con el catálogo oficial.

SELECT
    r.departamento,
    COUNT(*) AS total_roles

FROM clean_roles r

LEFT JOIN clean_departamentos d
    ON UPPER(TRIM(r.departamento)) =
       UPPER(TRIM(d.nombre))

WHERE r.departamento IS NOT NULL
  AND TRIM(r.departamento) <> ''
  AND d.codigo IS NULL

GROUP BY r.departamento
ORDER BY total_roles DESC;

-- 67. Revisión de estados de los roles
-- No modifica los datos.

SELECT
    estatus,
    COUNT(*) AS total_roles
FROM clean_roles
GROUP BY estatus
ORDER BY total_roles DESC;

-- 68. Identificación de nombres de roles duplicados
-- No modifica los datos.

SELECT
    UPPER(TRIM(nombre_del_rol)) AS nombre_del_rol,
    COUNT(*) AS total_repeticiones
FROM clean_roles
WHERE nombre_del_rol IS NOT NULL
  AND TRIM(nombre_del_rol) <> ''
GROUP BY UPPER(TRIM(nombre_del_rol))
HAVING COUNT(*) > 1
ORDER BY total_repeticiones DESC;

-- 69. Revisión de niveles de los roles
-- No modifica los datos.

SELECT
    nivel,
    COUNT(*) AS total_roles
FROM clean_roles
GROUP BY nivel
ORDER BY total_roles DESC;

-- 70. Validación final del catálogo de roles
-- No modifica los datos.

SELECT
    COUNT(*) AS total_roles,

    COUNT(DISTINCT codigo) AS codigos_unicos,

    SUM(
        nombre_del_rol IS NULL
        OR TRIM(nombre_del_rol) = ''
    ) AS nombres_pendientes,

    SUM(
        departamento IS NULL
        OR TRIM(departamento) = ''
    ) AS departamentos_pendientes,

    SUM(
        descripcion IS NULL
        OR TRIM(descripcion) = ''
    ) AS descripciones_pendientes

FROM clean_roles;
