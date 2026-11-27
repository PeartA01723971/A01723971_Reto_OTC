USE OTC;

-- 31. Revisión del catálogo de habilidades
-- Se identifican los nombres de las columnas
-- antes de relacionarlo con la matriz.

SELECT
    ORDINAL_POSITION AS posicion,
    COLUMN_NAME AS nombre_original,
    REGEXP_REPLACE(
        COLUMN_NAME,
        '[^a-zA-Z0-9_]',
        ''
    ) AS nombre_limpio
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'stg_habilidades'
ORDER BY ORDINAL_POSITION;

-- 32. Preparación del catálogo de habilidades
-- Se conserva la tabla original sin modificaciones.

CREATE TABLE clean_habilidades
LIKE stg_habilidades;

INSERT INTO clean_habilidades
SELECT * FROM stg_habilidades;

-- Corregir los nombres de las columnas

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
  AND TABLE_NAME = 'clean_habilidades';

SET @sql = CONCAT(
    'ALTER TABLE clean_habilidades ',
    @columnas
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Validar los identificadores de habilidades

SELECT
    m.id_habilidad,
    COUNT(*) AS total_registros
FROM clean_matriz_habilidades m
LEFT JOIN clean_habilidades h
    ON UPPER(TRIM(m.id_habilidad)) =
       UPPER(TRIM(h.codigo))
WHERE h.codigo IS NULL
GROUP BY m.id_habilidad
ORDER BY m.id_habilidad;

-- 34. Colaboradores activos con habilidades registradas
-- Se relacionan colaboradores, habilidades y
-- su estado de asignación.

SELECT
    c.id,
    c.nombre_completo,
    c.estado_asignacion,
    COUNT(DISTINCT m.id_habilidad) AS total_habilidades,
    SUM(
        CASE
            WHEN m.nivel_numerico >= 3 THEN 1
            ELSE 0
        END
    ) AS habilidades_avanzadas_expertas

FROM clean_colaboradores c

LEFT JOIN clean_matriz_habilidades m
    ON TRIM(c.id) = TRIM(m.id_colaborador)

WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'

GROUP BY
    c.id,
    c.nombre_completo,
    c.estado_asignacion

ORDER BY
    total_habilidades DESC;
    
-- 34.1 Verificar el total de colaboradores activos

SELECT COUNT(*) AS total_colaboradores_activos
FROM clean_colaboradores
WHERE UPPER(TRIM(estatus)) = 'ACTIVO';

-- 34.2 Contar colaboradores activos
-- que aparecen al relacionarlos con la matriz

SELECT COUNT(DISTINCT c.id) AS total_colaboradores
FROM clean_colaboradores c
LEFT JOIN clean_matriz_habilidades m
    ON TRIM(c.id) = TRIM(m.id_colaborador)
WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO';

-- 35. Colaboradores activos sin asignación registrada
-- con habilidades avanzadas o expertas.

SELECT
    c.id,
    c.estado_asignacion,
    COUNT(DISTINCT m.id_habilidad) AS total_habilidades,
    COUNT(DISTINCT CASE
        WHEN m.nivel_numerico >= 3
        THEN m.id_habilidad
    END) AS habilidades_avanzadas_expertas

FROM clean_colaboradores c

INNER JOIN clean_matriz_habilidades m
    ON TRIM(c.id) = TRIM(m.id_colaborador)

WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'
  AND c.estado_asignacion = 'Sin asignación registrada'

GROUP BY
    c.id,
    c.estado_asignacion

HAVING habilidades_avanzadas_expertas > 0

ORDER BY
    habilidades_avanzadas_expertas DESC,
    total_habilidades DESC;
    
-- 36. Habilidades avanzadas y expertas
-- de colaboradores activos sin asignación registrada.

SELECT
    c.id AS id_colaborador,
    h.codigo AS codigo_habilidad,
    h.descripcion AS habilidad,
    m.nivel,
    m.nivel_numerico

FROM clean_colaboradores c

INNER JOIN clean_matriz_habilidades m
    ON TRIM(c.id) = TRIM(m.id_colaborador)

INNER JOIN clean_habilidades h
    ON UPPER(TRIM(m.id_habilidad)) =
       UPPER(TRIM(h.codigo))

WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'
  AND c.estado_asignacion = 'Sin asignación registrada'
  AND m.nivel_numerico >= 3

ORDER BY
    c.id,
    m.nivel_numerico DESC,
    h.descripcion;
    
-- 37. Habilidades avanzadas y expertas más frecuentes
-- entre colaboradores activos sin asignación registrada.

SELECT
    h.codigo AS codigo_habilidad,
    h.descripcion AS habilidad,

    COUNT(DISTINCT c.id) AS colaboradores_con_habilidad,

    COUNT(DISTINCT CASE
        WHEN m.nivel_numerico = 4
        THEN c.id
    END) AS colaboradores_expertos,

    COUNT(DISTINCT CASE
        WHEN m.nivel_numerico = 3
        THEN c.id
    END) AS colaboradores_avanzados

FROM clean_colaboradores c

INNER JOIN clean_matriz_habilidades m
    ON TRIM(c.id) = TRIM(m.id_colaborador)

INNER JOIN clean_habilidades h
    ON UPPER(TRIM(m.id_habilidad)) =
       UPPER(TRIM(h.codigo))

WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'
  AND c.estado_asignacion = 'Sin asignación registrada'
  AND m.nivel_numerico >= 3

GROUP BY
    h.codigo,
    h.descripcion

ORDER BY
    colaboradores_con_habilidad DESC,
    colaboradores_expertos DESC,
    h.descripcion

LIMIT 15;

-- 38. Cobertura de habilidades de colaboradores activos
-- Se identifica cuántos tienen información
-- registrada en la matriz de habilidades.

SELECT
    CASE
        WHEN m.id_colaborador IS NULL
        THEN 'Sin habilidades registradas'
        ELSE 'Con habilidades registradas'
    END AS estado_habilidades,

    COUNT(DISTINCT c.id) AS total_colaboradores

FROM clean_colaboradores c

LEFT JOIN (
    SELECT DISTINCT id_colaborador
    FROM clean_matriz_habilidades
) m
    ON TRIM(c.id) = TRIM(m.id_colaborador)

WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'

GROUP BY
    CASE
        WHEN m.id_colaborador IS NULL
        THEN 'Sin habilidades registradas'
        ELSE 'Con habilidades registradas'
    END;
    
-- 39. Cobertura de habilidades según estado de asignación
-- Se identifican colaboradores activos con y sin
-- habilidades registradas en cada grupo.

SELECT
    c.estado_asignacion,

    COUNT(DISTINCT c.id) AS total_colaboradores,

    COUNT(DISTINCT CASE
        WHEN m.id_colaborador IS NOT NULL
        THEN c.id
    END) AS con_habilidades,

    COUNT(DISTINCT CASE
        WHEN m.id_colaborador IS NULL
        THEN c.id
    END) AS sin_habilidades

FROM clean_colaboradores c

LEFT JOIN (
    SELECT DISTINCT id_colaborador
    FROM clean_matriz_habilidades
) m
    ON TRIM(c.id) = TRIM(m.id_colaborador)

WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'

GROUP BY
    c.estado_asignacion

ORDER BY
    total_colaboradores DESC;
    
-- 40. Validación de calidad del catálogo de habilidades
-- Se revisan códigos duplicados y datos faltantes.

SELECT
    COUNT(*) AS total_habilidades,

    COUNT(DISTINCT UPPER(TRIM(codigo)))
        AS codigos_unicos,

    SUM(
        CASE
            WHEN codigo IS NULL OR TRIM(codigo) = ''
            THEN 1 ELSE 0
        END
    ) AS codigos_vacios,

    SUM(
        CASE
            WHEN descripcion IS NULL OR TRIM(descripcion) = ''
            THEN 1 ELSE 0
        END
    ) AS descripciones_vacias

FROM clean_habilidades;
