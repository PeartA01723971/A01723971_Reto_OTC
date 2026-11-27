USE OTC; 

-- 55. Revisión de la estructura del catálogo de departamentos
-- Se identifican los nombres y tipos de datos
-- antes de realizar cualquier limpieza.

SELECT
    ORDINAL_POSITION AS posicion,
    COLUMN_NAME AS nombre_original,
    REGEXP_REPLACE(
        COLUMN_NAME,
        '[^a-zA-Z0-9_]',
        ''
    ) AS nombre_limpio,
    DATA_TYPE AS tipo_dato

FROM INFORMATION_SCHEMA.COLUMNS

WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'stg_departamentos'

ORDER BY ORDINAL_POSITION;

-- 56. Creación de la tabla limpia de departamentos
-- Se conserva la tabla original sin modificaciones.

CREATE TABLE clean_departamentos
LIKE stg_departamentos;

INSERT INTO clean_departamentos
SELECT * FROM stg_departamentos;

-- Corregir caracteres invisibles en los nombres
-- de las columnas.

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
  AND TABLE_NAME = 'clean_departamentos';

SET @sql = CONCAT(
    'ALTER TABLE clean_departamentos ',
    @columnas
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verificar el número de departamentos

SELECT COUNT(*) AS total_departamentos
FROM clean_departamentos;

-- 57. Validación de calidad del catálogo de departamentos
-- Se revisan códigos duplicados y datos faltantes.

SELECT
    COUNT(*) AS total_departamentos,

    COUNT(DISTINCT NULLIF(TRIM(codigo), ''))
        AS codigos_unicos,

    SUM(
        CASE
            WHEN codigo IS NULL OR TRIM(codigo) = ''
            THEN 1 ELSE 0
        END
    ) AS codigos_vacios,

    SUM(
        CASE
            WHEN nombre IS NULL OR TRIM(nombre) = ''
            THEN 1 ELSE 0
        END
    ) AS nombres_vacios,

    SUM(
        CASE
            WHEN centro_costos IS NULL OR TRIM(centro_costos) = ''
            THEN 1 ELSE 0
        END
    ) AS centros_costos_vacios,

    SUM(
        CASE
            WHEN responsable IS NULL OR TRIM(responsable) = ''
            THEN 1 ELSE 0
        END
    ) AS responsables_vacios,

    SUM(
        CASE
            WHEN estatus IS NULL OR TRIM(estatus) = ''
            THEN 1 ELSE 0
        END
    ) AS estatus_vacios

FROM clean_departamentos;

-- 58. Revisión de departamentos registrados
-- Se consultan los nombres, códigos y estados
-- para identificar posibles inconsistencias.

SELECT
    codigo,
    nombre,
    objetivo,
    estatus,
    centro_costos,
    responsable

FROM clean_departamentos

ORDER BY codigo;

-- 59. Validación de departamentos de colaboradores
-- Se revisan los departamentos registrados
-- y su correspondencia con el catálogo oficial.

SELECT
    c.departamento AS departamento_colaborador,

    COUNT(*) AS total_colaboradores,

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM clean_departamentos d
            WHERE UPPER(TRIM(d.nombre)) =
                  UPPER(TRIM(c.departamento))
               OR UPPER(TRIM(d.codigo)) =
                  UPPER(TRIM(c.departamento))
        )
        THEN 'Coincide con catálogo'
        ELSE 'No coincide con catálogo'
    END AS validacion_departamento

FROM clean_colaboradores c

WHERE c.departamento IS NOT NULL
  AND TRIM(c.departamento) <> ''

GROUP BY c.departamento

ORDER BY total_colaboradores DESC;

-- 60. Revisión de la estructura del catálogo de roles
-- Se identifican los nombres y tipos de datos
-- antes de realizar cualquier limpieza.

SELECT
    ORDINAL_POSITION AS posicion,
    COLUMN_NAME AS nombre_original,
    REGEXP_REPLACE(
        COLUMN_NAME,
        '[^a-zA-Z0-9_]',
        ''
    ) AS nombre_limpio,
    DATA_TYPE AS tipo_dato

FROM INFORMATION_SCHEMA.COLUMNS

WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'stg_roles'

ORDER BY ORDINAL_POSITION;
