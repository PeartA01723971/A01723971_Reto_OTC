USE OTC;

-- 42. Revisión de la estructura del catálogo de clientes
-- Se identifican los nombres de las columnas
-- antes de realizar la limpieza.

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
  AND TABLE_NAME = 'stg_clientes'

ORDER BY ORDINAL_POSITION;

-- 43. Creación de la tabla limpia de clientes
-- Se conserva la tabla original sin modificaciones.

CREATE TABLE clean_clientes
LIKE stg_clientes;

INSERT INTO clean_clientes
SELECT * FROM stg_clientes;

-- Corregir caracteres invisibles de las columnas

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
  AND TABLE_NAME = 'clean_clientes';

SET @sql = CONCAT(
    'ALTER TABLE clean_clientes ',
    @columnas
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verificar que se copiaron todos los clientes

SELECT COUNT(*) AS total_clientes
FROM clean_clientes;

-- 44. Revisión de calidad de datos del catálogo de clientes

SELECT
    COUNT(*) AS total_registros,

    COUNT(DISTINCT NULLIF(TRIM(cod_cliente), ''))
        AS codigos_unicos,

    SUM(
        CASE
            WHEN cod_cliente IS NULL OR TRIM(cod_cliente) = ''
            THEN 1 ELSE 0
        END
    ) AS codigos_vacios,

    SUM(
        CASE
            WHEN cliente IS NULL OR TRIM(cliente) = ''
            THEN 1 ELSE 0
        END
    ) AS nombres_vacios,

    SUM(
        CASE
            WHEN rfc IS NULL OR TRIM(rfc) = ''
            THEN 1 ELSE 0
        END
    ) AS rfc_vacios,

    SUM(
        CASE
            WHEN email_contacto IS NULL OR TRIM(email_contacto) = ''
            THEN 1 ELSE 0
        END
    ) AS emails_vacios,

    SUM(
        CASE
            WHEN proyecto IS NULL OR TRIM(proyecto) = ''
            THEN 1 ELSE 0
        END
    ) AS proyectos_vacios,

    SUM(
        CASE
            WHEN fecha_inicio IS NULL OR TRIM(fecha_inicio) = ''
            THEN 1 ELSE 0
        END
    ) AS fechas_inicio_vacias,

    SUM(
        CASE
            WHEN fecha_fin IS NULL OR TRIM(fecha_fin) = ''
            THEN 1 ELSE 0
        END
    ) AS fechas_fin_vacias

FROM clean_clientes;

-- 45. Revisión de estados de clientes y proyectos
-- Se identifican los diferentes estados registrados.

SELECT
    estatus_cliente,
    estatus_proyecto,
    COUNT(*) AS total_registros

FROM clean_clientes

GROUP BY
    estatus_cliente,
    estatus_proyecto

ORDER BY
    estatus_cliente,
    estatus_proyecto;
    
-- 46. Revisión de clientes con múltiples proyectos
-- Se identifica cuántos registros y proyectos
-- tiene cada cliente.

SELECT
    cod_cliente,
    cliente,

    COUNT(*) AS total_registros,

    COUNT(DISTINCT proyecto) AS proyectos_diferentes,

    GROUP_CONCAT(
        DISTINCT proyecto
        ORDER BY proyecto
        SEPARATOR ' | '
    ) AS lista_proyectos

FROM clean_clientes

GROUP BY
    cod_cliente,
    cliente

ORDER BY
    total_registros DESC,
    cliente;
    
-- 47. Revisión de fechas según el estado del proyecto
-- Se identifican fechas faltantes en proyectos
-- en curso y por iniciar.

SELECT
    estatus_proyecto,

    COUNT(*) AS total_proyectos,

    SUM(
        CASE
            WHEN fecha_inicio IS NULL
              OR TRIM(fecha_inicio) = ''
            THEN 1 ELSE 0
        END
    ) AS sin_fecha_inicio,

    SUM(
        CASE
            WHEN fecha_fin IS NULL
              OR TRIM(fecha_fin) = ''
            THEN 1 ELSE 0
        END
    ) AS sin_fecha_fin,

    SUM(
        CASE
            WHEN fecha_inicio IS NOT NULL
             AND TRIM(fecha_inicio) <> ''
            THEN 1 ELSE 0
        END
    ) AS con_fecha_inicio,

    SUM(
        CASE
            WHEN fecha_fin IS NOT NULL
             AND TRIM(fecha_fin) <> ''
            THEN 1 ELSE 0
        END
    ) AS con_fecha_fin

FROM clean_clientes

GROUP BY estatus_proyecto

ORDER BY estatus_proyecto;

-- 48. Revisión del formato de las fechas de proyectos
-- Se consultan las fechas originales para identificar
-- su formato antes de realizar conversiones.

SELECT
    cod_cliente,
    cliente,
    proyecto,
    estatus_proyecto,
    fecha_inicio,
    fecha_fin

FROM clean_clientes

ORDER BY
    cod_cliente,
    proyecto;
    
-- 49. Identificación de proyectos que requieren revisión
-- Se conservan las fechas y estados originales.

ALTER TABLE clean_clientes
ADD COLUMN revision_fechas VARCHAR(100);

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_clientes
SET revision_fechas =
    CASE
        WHEN estatus_proyecto = 'En Curso'
             AND NULLIF(TRIM(fecha_fin), '') IS NOT NULL
             AND STR_TO_DATE(fecha_fin, '%Y-%m-%d') < CURDATE()
        THEN 'Fecha de fin vencida'

        WHEN estatus_proyecto = 'Por Iniciar'
             AND NULLIF(TRIM(fecha_inicio), '') IS NOT NULL
             AND STR_TO_DATE(fecha_inicio, '%Y-%m-%d') < CURDATE()
        THEN 'Fecha de inicio anterior a hoy'

        WHEN fecha_inicio IS NULL
             OR TRIM(fecha_inicio) = ''
        THEN 'Sin fecha de inicio'

        ELSE 'Sin observaciones'
    END;

SET SQL_SAFE_UPDATES = 1;

-- Consultar resultados de la revisión

SELECT
    revision_fechas,
    COUNT(*) AS total_proyectos

FROM clean_clientes

GROUP BY revision_fechas

ORDER BY total_proyectos DESC;

-- 50. Revisión de columnas de la tabla de asignaciones
-- Se identifican los campos disponibles para
-- relacionar asignaciones con clientes y proyectos.

SELECT
    ORDINAL_POSITION AS posicion,
    COLUMN_NAME AS nombre_columna,
    DATA_TYPE AS tipo_dato

FROM INFORMATION_SCHEMA.COLUMNS

WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'clean_asignaciones'

ORDER BY ORDINAL_POSITION;

-- 51. Validación de clientes entre asignaciones y catálogo
-- Se revisa si los clientes de las asignaciones
-- coinciden con los registrados en clean_clientes.

SELECT
    a.cliente AS cliente_asignacion,

    COUNT(*) AS total_asignaciones,

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM clean_clientes c
            WHERE UPPER(TRIM(c.cliente)) =
                  UPPER(TRIM(a.cliente))
        )
        THEN 'Coincide con catálogo'
        ELSE 'No coincide con catálogo'
    END AS validacion_cliente

FROM clean_asignaciones a

GROUP BY a.cliente

ORDER BY
    validacion_cliente,
    total_asignaciones DESC;

-- 52. Validación de proyectos entre asignaciones y clientes
-- Se compara cada proyecto considerando también
-- el nombre del cliente correspondiente.

SELECT
    a.cliente,
    a.proyecto AS proyecto_asignacion,

    COUNT(*) AS total_asignaciones,

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM clean_clientes c
            WHERE UPPER(TRIM(c.cliente)) =
                  UPPER(TRIM(a.cliente))
              AND UPPER(TRIM(c.proyecto)) =
                  UPPER(TRIM(a.proyecto))
        )
        THEN 'Coincide con catálogo'
        ELSE 'No coincide con catálogo'
    END AS validacion_proyecto

FROM clean_asignaciones a

GROUP BY
    a.cliente,
    a.proyecto

ORDER BY
    a.cliente,
    total_asignaciones DESC;
    
-- 53. Proyectos con y sin asignaciones registradas
-- Se relaciona el catálogo de proyectos
-- con las asignaciones de colaboradores.

SELECT
    c.cod_cliente,
    c.cliente,
    c.proyecto,
    c.estatus_proyecto,

    COUNT(a.id_colaborador) AS total_asignaciones,

    CASE
        WHEN COUNT(a.id_colaborador) > 0
        THEN 'Con asignaciones'
        ELSE 'Sin asignaciones registradas'
    END AS estado_asignaciones

FROM clean_clientes c

LEFT JOIN clean_asignaciones a
    ON UPPER(TRIM(c.cliente)) =
       UPPER(TRIM(a.cliente))
   AND UPPER(TRIM(c.proyecto)) =
       UPPER(TRIM(a.proyecto))

GROUP BY
    c.cod_cliente,
    c.cliente,
    c.proyecto,
    c.estatus_proyecto

ORDER BY
    total_asignaciones DESC,
    c.cliente;
    
-- 54. Identificación de proyectos que requieren revisión
-- según su estado y las asignaciones registradas.

ALTER TABLE clean_clientes
ADD COLUMN revision_asignaciones VARCHAR(100);

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_clientes c
SET revision_asignaciones =
    CASE
        WHEN c.estatus_proyecto = 'Por Iniciar'
             AND EXISTS (
                 SELECT 1
                 FROM clean_asignaciones a
                 WHERE UPPER(TRIM(a.cliente)) =
                       UPPER(TRIM(c.cliente))
                   AND UPPER(TRIM(a.proyecto)) =
                       UPPER(TRIM(c.proyecto))
             )
        THEN 'Por iniciar con asignaciones'

        WHEN c.estatus_proyecto = 'En Curso'
             AND NOT EXISTS (
                 SELECT 1
                 FROM clean_asignaciones a
                 WHERE UPPER(TRIM(a.cliente)) =
                       UPPER(TRIM(c.cliente))
                   AND UPPER(TRIM(a.proyecto)) =
                       UPPER(TRIM(c.proyecto))
             )
        THEN 'En curso sin asignaciones'

        ELSE 'Sin observaciones'
    END;

SET SQL_SAFE_UPDATES = 1;

-- Consultar los resultados

SELECT
    revision_asignaciones,
    COUNT(*) AS total_proyectos

FROM clean_clientes

GROUP BY revision_asignaciones

ORDER BY total_proyectos DESC;
