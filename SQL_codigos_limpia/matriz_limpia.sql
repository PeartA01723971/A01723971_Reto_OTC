USE OTC;

-- 25. Revisión de la matriz de habilidades
-- Se verifica la cantidad de registros y columnas
-- antes de transformar su estructura.

SELECT
    COUNT(*) AS total_registros
FROM stg_matriz;

SELECT
    COUNT(*) AS total_columnas
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'otc'
  AND TABLE_NAME = 'stg_matriz';

-- Revisar los nombres de las columnas

SELECT
    ORDINAL_POSITION AS posicion,
    COLUMN_NAME AS nombre_columna
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'otc'
  AND TABLE_NAME = 'stg_matriz'
ORDER BY ORDINAL_POSITION;

-- 26. Preparación de la matriz de habilidades
-- Se conserva la tabla original sin modificaciones.

CREATE TABLE clean_matriz
LIKE stg_matriz;

INSERT INTO clean_matriz
SELECT * FROM stg_matriz;

-- Verificar que se copiaron los 54 registros

SELECT COUNT(*) AS total_registros
FROM clean_matriz;

-- Revisar los niveles de habilidades
-- Se utilizan los nombres originales de las columnas.

SELECT
    `⁠ h0002 ⁠` AS nivel_h0002,
    `⁠ h0003 ⁠` AS nivel_h0003,
    `⁠ h0004 ⁠` AS nivel_h0004
FROM clean_matriz
LIMIT 10;

-- 27. Identificación de columnas de habilidades
-- Se separan las columnas de habilidades
-- de los datos generales del colaborador.

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
  AND TABLE_NAME = 'clean_matriz'
ORDER BY ORDINAL_POSITION;

-- 28. Transformación de la matriz de habilidades
-- Se convierte la matriz de formato ancho a formato largo.
-- Se conservan los datos originales en clean_matriz.

DROP TABLE IF EXISTS clean_matriz_habilidades;

CREATE TABLE clean_matriz_habilidades (
    id_colaborador VARCHAR(255),
    id_habilidad VARCHAR(20),
    nivel VARCHAR(255)
);

-- Generar automáticamente la transformación
-- de las 71 columnas de habilidades.

SET SESSION group_concat_max_len = 100000;

SELECT GROUP_CONCAT(
    CONCAT(
        'SELECT `',
        REPLACE(c_id.COLUMN_NAME, '`', '``'),
        '` AS id_colaborador, ',
        QUOTE(
            REGEXP_REPLACE(
                c.COLUMN_NAME,
                '[^a-zA-Z0-9_]',
                ''
            )
        ),
        ' AS id_habilidad, ',
        'NULLIF(TRIM(`',
        REPLACE(c.COLUMN_NAME, '`', '``'),
        '`), '''') AS nivel ',
        'FROM clean_matriz'
    )
    ORDER BY c.ORDINAL_POSITION
    SEPARATOR ' UNION ALL '
)
INTO @consultas
FROM INFORMATION_SCHEMA.COLUMNS c
CROSS JOIN (
    SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'clean_matriz'
      AND REGEXP_REPLACE(
          COLUMN_NAME, '[^a-zA-Z0-9_]', ''
      ) = 'id_colaborador'
) c_id
WHERE c.TABLE_SCHEMA = DATABASE()
  AND c.TABLE_NAME = 'clean_matriz'
  AND REGEXP_LIKE(
      REGEXP_REPLACE(
          c.COLUMN_NAME, '[^a-zA-Z0-9_]', ''
      ),
      '^[hs][0-9]{4}$'
  );

SET @sql = CONCAT(
    'INSERT INTO clean_matriz_habilidades ',
    '(id_colaborador, id_habilidad, nivel) ',
    'SELECT id_colaborador, id_habilidad, nivel ',
    'FROM (', @consultas, ') AS datos ',
    'WHERE nivel IS NOT NULL'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verificar la transformación

SELECT
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_colaborador) AS colaboradores,
    COUNT(DISTINCT id_habilidad) AS habilidades
FROM clean_matriz_habilidades;

-- 29. Validación de niveles de habilidades
-- Se identifican los niveles registrados
-- y posibles inconsistencias de escritura.

SELECT
    nivel,
    COUNT(*) AS total_registros
FROM clean_matriz_habilidades
GROUP BY nivel
ORDER BY total_registros DESC;

-- 30. Estandarización de niveles de habilidades
-- Se asigna un valor numérico a cada nivel.
-- Escala provisional para fines de análisis.

ALTER TABLE clean_matriz_habilidades
ADD COLUMN nivel_numerico INT NULL;

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_matriz_habilidades
SET nivel_numerico =
    CASE
        WHEN UPPER(TRIM(nivel)) = 'BÁSICO' THEN 1
        WHEN UPPER(TRIM(nivel)) = 'INTERMEDIO' THEN 2
        WHEN UPPER(TRIM(nivel)) = 'AVANZADO' THEN 3
        WHEN UPPER(TRIM(nivel)) = 'EXPERTO' THEN 4
        ELSE NULL
    END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados

SELECT
    nivel,
    nivel_numerico,
    COUNT(*) AS total_registros
FROM clean_matriz_habilidades
GROUP BY nivel, nivel_numerico
ORDER BY nivel_numerico;

-- 33. Validación de colaboradores en la matriz
-- Se comprueba que los colaboradores registrados
-- en la matriz existan en el catálogo oficial.

SELECT
    m.id_colaborador,
    COUNT(*) AS total_habilidades
FROM clean_matriz_habilidades m
LEFT JOIN clean_colaboradores c
    ON UPPER(TRIM(m.id_colaborador)) =
       UPPER(TRIM(c.id))
WHERE c.id IS NULL
GROUP BY m.id_colaborador
ORDER BY m.id_colaborador;

-- 41. Validación de calidad de la matriz de habilidades
-- Se revisan duplicados, datos faltantes
-- y niveles sin clasificación numérica.

SELECT
    COUNT(*) AS total_registros,

    COUNT(DISTINCT
        CONCAT(
            TRIM(id_colaborador),
            '|',
            TRIM(id_habilidad)
        )
    ) AS combinaciones_unicas,

    SUM(
        CASE
            WHEN id_colaborador IS NULL
              OR TRIM(id_colaborador) = ''
            THEN 1 ELSE 0
        END
    ) AS colaboradores_vacios,

    SUM(
        CASE
            WHEN id_habilidad IS NULL
              OR TRIM(id_habilidad) = ''
            THEN 1 ELSE 0
        END
    ) AS habilidades_vacias,

    SUM(
        CASE
            WHEN nivel_numerico IS NULL
            THEN 1 ELSE 0
        END
    ) AS niveles_sin_clasificar

FROM clean_matriz_habilidades;
