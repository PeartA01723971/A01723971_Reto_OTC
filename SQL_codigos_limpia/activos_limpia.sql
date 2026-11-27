USE OTC;

-- 71. Exploración inicial de activos
-- No modifica los datos originales.

SELECT COUNT(*) AS total_activos
FROM stg_activos;

SHOW COLUMNS FROM stg_activos;

SELECT *
FROM stg_activos
LIMIT 10;

-- 72. Revisar nombres y tipos de columnas
-- No modifica los datos.

SHOW COLUMNS FROM stg_activos;

-- 73. Crear tabla de trabajo para activos
-- La tabla original stg_activos no se modifica.

CREATE TABLE clean_activos LIKE stg_activos;

INSERT INTO clean_activos
SELECT *
FROM stg_activos;

-- Verificar la cantidad de registros copiados.

SELECT COUNT(*) AS total_activos
FROM clean_activos;

-- 74. Preparar la corrección de nombres de columnas
-- Todavía no modifica la tabla.

SET SESSION group_concat_max_len = 100000;

SELECT GROUP_CONCAT(
    CONCAT(
        'RENAME COLUMN `',
        REPLACE(COLUMN_NAME, '`', '``'),
        '` TO `',
        REGEXP_REPLACE(COLUMN_NAME, '[^a-zA-Z0-9_]', ''),
        '`'
    )
    ORDER BY ORDINAL_POSITION
    SEPARATOR ', '
)
INTO @columnas_activos
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'clean_activos'
  AND COLUMN_NAME <> REGEXP_REPLACE(
      COLUMN_NAME, '[^a-zA-Z0-9_]', ''
  );

SELECT @columnas_activos AS correcciones_preparadas;

-- 75. Aplicar la corrección de nombres de columnas
-- No modifica los datos de los activos.

SET @sql = CONCAT(
    'ALTER TABLE clean_activos ',
    @columnas_activos
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verificar los nombres corregidos.

SHOW COLUMNS FROM clean_activos;

-- 76. Validación inicial de calidad de activos
-- No modifica los datos.

SELECT
    COUNT(*) AS total_activos,

    COUNT(DISTINCT NULLIF(TRIM(cod_activo), ''))
        AS codigos_unicos,

    SUM(cod_activo IS NULL OR TRIM(cod_activo) = '')
        AS codigos_vacios,

    SUM(descripcion IS NULL OR TRIM(descripcion) = '')
        AS descripciones_vacias,

    SUM(marca IS NULL OR TRIM(marca) = '')
        AS marcas_vacias,

    SUM(modelo IS NULL OR TRIM(modelo) = '')
        AS modelos_vacios,

    SUM(serie IS NULL OR TRIM(serie) = '')
        AS series_vacias,

    SUM(tipo IS NULL OR TRIM(tipo) = '')
        AS tipos_vacios,

    SUM(estatus IS NULL OR TRIM(estatus) = '')
        AS estatus_vacios,

    SUM(costo IS NULL OR TRIM(costo) = '')
        AS costos_vacios,

    SUM(TRIM(costo) = '0')
        AS costos_en_cero,

    SUM(colaborador_asignado IS NULL
        OR TRIM(colaborador_asignado) = '')
        AS colaboradores_vacios,

    SUM(fecha_inicio IS NULL OR TRIM(fecha_inicio) = '')
        AS fechas_inicio_vacias,

    SUM(fecha_fin IS NULL OR TRIM(fecha_fin) = '')
        AS fechas_fin_vacias

FROM clean_activos;

-- 77. Revisión de costos de activos
-- No modifica los datos.

SELECT
    tipo,
    COUNT(*) AS total_activos,

    SUM(
        TRIM(costo) = '0'
    ) AS costos_en_cero,

    SUM(
        CASE
            WHEN TRIM(costo) REGEXP '^[0-9]+([.][0-9]+)?$'
                 AND CAST(TRIM(costo) AS DECIMAL(15,2)) > 0
            THEN 1
            ELSE 0
        END
    ) AS costos_positivos

FROM clean_activos
GROUP BY tipo
ORDER BY total_activos DESC;

-- 78. Revisión de fechas de los activos
-- No modifica los datos.

SELECT
    COUNT(*) AS total_activos,

    SUM(TRIM(fecha_inicio) = '1990-01-01')
        AS fechas_inicio_1990,

    SUM(TRIM(fecha_fin) = 'Activo')
        AS fecha_fin_con_activo,

    SUM(fecha_inicio IS NULL OR TRIM(fecha_inicio) = '')
        AS fechas_inicio_vacias,

    SUM(fecha_fin IS NULL OR TRIM(fecha_fin) = '')
        AS fechas_fin_vacias

FROM clean_activos;

-- 79. Revisión de estados de los activos
-- No modifica los datos.

SELECT
    estatus,
    COUNT(*) AS total_activos
FROM clean_activos
GROUP BY estatus
ORDER BY total_activos DESC;

-- 80. Clasificación de fechas de finalización
-- No modifica los datos.

SELECT
    CASE
        WHEN fecha_fin IS NULL
             OR TRIM(fecha_fin) = ''
            THEN 'Sin información'

        WHEN UPPER(TRIM(fecha_fin)) = 'ACTIVO'
            THEN 'Activo (sin fecha de fin)'

        WHEN TRIM(fecha_fin) REGEXP
             '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN 'Fecha registrada'

        ELSE 'Valor no reconocido'
    END AS clasificacion_fecha_fin,

    COUNT(*) AS total_activos

FROM clean_activos

GROUP BY clasificacion_fecha_fin
ORDER BY total_activos DESC;

-- 81. Revisión de activos con fecha de finalización
-- No modifica los datos.

SELECT
    cod_activo,
    descripcion,
    marca,
    modelo,
    colaborador_asignado,
    fecha_inicio,
    fecha_fin,
    estatus

FROM clean_activos

WHERE TRIM(fecha_fin) REGEXP
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

ORDER BY fecha_fin;

-- 82. Clasificación de asignaciones de activos
-- No modifica los datos.

SELECT
    CASE
        WHEN UPPER(TRIM(fecha_fin)) = 'ACTIVO'
            THEN 'Asignación posiblemente vigente'

        WHEN fecha_fin IS NULL
             OR TRIM(fecha_fin) = ''
            THEN 'Asignación sin información'

        WHEN TRIM(fecha_fin) REGEXP
             '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
             AND STR_TO_DATE(fecha_fin, '%Y-%m-%d') < CURDATE()
            THEN 'Fecha de asignación finalizada'

        WHEN TRIM(fecha_fin) REGEXP
             '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
             AND STR_TO_DATE(fecha_fin, '%Y-%m-%d') >= CURDATE()
            THEN 'Fecha de finalización vigente o futura'

        ELSE 'Requiere revisión'
    END AS estado_asignacion_activo,

    COUNT(*) AS total_activos

FROM clean_activos

GROUP BY estado_asignacion_activo

ORDER BY total_activos DESC;

-- 83. Identificación de activos sin modelo
-- No modifica los datos.

SELECT
    cod_activo,
    descripcion,
    marca,
    modelo,
    serie,
    tipo,
    estatus,
    colaborador_asignado

FROM clean_activos

WHERE modelo IS NULL
   OR TRIM(modelo) = '';
   
-- 84. Revisión de activos sin asignar
-- No modifica los datos.

SELECT
    colaborador_asignado,
    COUNT(*) AS total_activos

FROM clean_activos

WHERE UPPER(TRIM(colaborador_asignado)) IN
    ('SIN ASIGNAR', 'NO ASIGNADO', 'PENDIENTE', 'N/A')

GROUP BY colaborador_asignado
ORDER BY total_activos DESC;

-- 85. Relación entre asignación y fechas
-- No modifica los datos.

SELECT
    CASE
        WHEN UPPER(TRIM(colaborador_asignado)) = 'SIN ASIGNAR'
            THEN 'Sin asignar'
        ELSE 'Con colaborador registrado'
    END AS situacion_asignacion,

    CASE
        WHEN fecha_fin IS NULL OR TRIM(fecha_fin) = ''
            THEN 'Sin fecha de fin'

        WHEN UPPER(TRIM(fecha_fin)) = 'ACTIVO'
            THEN 'Activo'

        ELSE 'Fecha registrada'
    END AS situacion_fecha_fin,

    COUNT(*) AS total_activos

FROM clean_activos

GROUP BY
    situacion_asignacion,
    situacion_fecha_fin

ORDER BY
    situacion_asignacion,
    total_activos DESC;
    
-- 86. Relación entre asignación y fecha de inicio
-- No modifica los datos.

SELECT
    CASE
        WHEN UPPER(TRIM(colaborador_asignado)) = 'SIN ASIGNAR'
            THEN 'Sin asignar'
        ELSE 'Con colaborador registrado'
    END AS situacion_asignacion,

    CASE
        WHEN fecha_inicio IS NULL
             OR TRIM(fecha_inicio) = ''
            THEN 'Sin fecha de inicio'

        WHEN TRIM(fecha_inicio) = '1990-01-01'
            THEN 'Fecha posiblemente provisional'

        ELSE 'Fecha registrada'
    END AS situacion_fecha_inicio,

    COUNT(*) AS total_activos

FROM clean_activos

GROUP BY
    situacion_asignacion,
    situacion_fecha_inicio

ORDER BY
    situacion_asignacion,
    total_activos DESC;
    
-- 87. Validación del formato de los costos
-- No modifica los datos.

SELECT
    COUNT(*) AS total_activos,

    SUM(
        TRIM(costo) REGEXP '^[0-9]+([.][0-9]+)?$'
    ) AS costos_formato_valido,

    SUM(
        TRIM(costo) NOT REGEXP '^[0-9]+([.][0-9]+)?$'
    ) AS costos_formato_invalido

FROM clean_activos;

-- 88. Convertir los costos a formato numérico
-- Solo modifica clean_activos.
-- Conserva los costos en cero.

ALTER TABLE clean_activos
MODIFY COLUMN costo DECIMAL(15,2) NULL;

-- Verificar el tipo de dato.

SHOW COLUMNS FROM clean_activos LIKE 'costo';

-- Confirmar que se conservaron los registros.

SELECT
    COUNT(*) AS total_activos,
    SUM(costo = 0) AS costos_en_cero,
    SUM(costo > 0) AS costos_positivos
FROM clean_activos;

-- 89. Análisis del valor registrado de los activos
-- No modifica los datos.

SELECT
    tipo,
    COUNT(*) AS total_activos,

    SUM(costo > 0) AS activos_con_costo,

    SUM(costo = 0) AS activos_sin_costo_registrado,

    ROUND(SUM(costo), 2) AS valor_total_registrado,

    ROUND(
        AVG(NULLIF(costo, 0)), 2
    ) AS costo_promedio_conocido

FROM clean_activos

GROUP BY tipo
ORDER BY valor_total_registrado DESC;

-- 90. Crear indicadores de calidad de los activos
-- Solo modifica clean_activos.

ALTER TABLE clean_activos
ADD COLUMN revision_costo VARCHAR(50),
ADD COLUMN revision_fecha_inicio VARCHAR(50),
ADD COLUMN revision_modelo VARCHAR(50);

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_activos
SET
    revision_costo = CASE
        WHEN costo = 0 THEN 'Requiere revisión'
        ELSE 'Sin observaciones'
    END,

    revision_fecha_inicio = CASE
        WHEN TRIM(fecha_inicio) = '1990-01-01'
            THEN 'Fecha por confirmar'
        WHEN fecha_inicio IS NULL OR TRIM(fecha_inicio) = ''
            THEN 'Sin fecha registrada'
        ELSE 'Sin observaciones'
    END,

    revision_modelo = CASE
        WHEN modelo IS NULL OR TRIM(modelo) = ''
            THEN 'Modelo pendiente'
        ELSE 'Sin observaciones'
    END;
    
SET SQL_SAFE_UPDATES = 1;

-- Verificar los indicadores.

SELECT
    revision_costo,
    revision_fecha_inicio,
    revision_modelo,
    COUNT(*) AS total_activos
FROM clean_activos
GROUP BY
    revision_costo,
    revision_fecha_inicio,
    revision_modelo
ORDER BY total_activos DESC;

-- 91. Indicador general de revisión de activos
-- Solo modifica clean_activos.

ALTER TABLE clean_activos
ADD COLUMN revision_general VARCHAR(50);

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_activos
SET revision_general = CASE
    WHEN revision_costo = 'Requiere revisión'
      OR revision_fecha_inicio <> 'Sin observaciones'
      OR revision_modelo = 'Modelo pendiente'
    THEN 'Requiere revisión'
    ELSE 'Sin observaciones'
END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados.

SELECT
    revision_general,
    COUNT(*) AS total_activos
FROM clean_activos
GROUP BY revision_general
ORDER BY total_activos DESC;

-- 92. Revisar las columnas de colaboradores
-- No modifica ninguna tabla.

SHOW COLUMNS FROM clean_colaboradores;

-- 93. Validar colaboradores asignados a los activos
-- No modifica ninguna tabla.

SELECT
    COUNT(*) AS total_activos,

    SUM(
        UPPER(TRIM(a.colaborador_asignado)) = 'SIN ASIGNAR'
    ) AS activos_sin_asignar,

    SUM(
        UPPER(TRIM(a.colaborador_asignado)) <> 'SIN ASIGNAR'
        AND EXISTS (
            SELECT 1
            FROM clean_colaboradores c
            WHERE UPPER(TRIM(c.nombre_completo)) =
                  UPPER(TRIM(a.colaborador_asignado))
        )
    ) AS colaboradores_encontrados,

    SUM(
        UPPER(TRIM(a.colaborador_asignado)) <> 'SIN ASIGNAR'
        AND NOT EXISTS (
            SELECT 1
            FROM clean_colaboradores c
            WHERE UPPER(TRIM(c.nombre_completo)) =
                  UPPER(TRIM(a.colaborador_asignado))
        )
    ) AS colaboradores_no_encontrados

FROM clean_activos a;

-- 94. Revisar activos asignados a colaboradores dados de baja
-- No modifica ninguna tabla.

SELECT
    a.cod_activo,
    a.descripcion,
    a.marca,
    a.modelo,
    a.colaborador_asignado,
    c.estatus AS estatus_colaborador,
    a.fecha_inicio,
    a.fecha_fin

FROM clean_activos a

INNER JOIN clean_colaboradores c
    ON UPPER(TRIM(a.colaborador_asignado)) =
       UPPER(TRIM(c.nombre_completo))

WHERE UPPER(TRIM(c.estatus)) = 'BAJA'

ORDER BY a.colaborador_asignado;

-- 95. Activos asociados a colaboradores dados de baja
-- que todavía aparecen con asignación activa.
-- No modifica ninguna tabla.

SELECT
    a.cod_activo,
    a.marca,
    a.modelo,
    a.colaborador_asignado,
    c.estatus AS estatus_colaborador,
    a.fecha_inicio,
    a.fecha_fin

FROM clean_activos a

INNER JOIN clean_colaboradores c
    ON UPPER(TRIM(a.colaborador_asignado)) =
       UPPER(TRIM(c.nombre_completo))

WHERE UPPER(TRIM(c.estatus)) = 'BAJA'
  AND UPPER(TRIM(a.fecha_fin)) = 'ACTIVO'

ORDER BY a.colaborador_asignado;

-- 96. Identificar activos que requieren seguimiento
-- Solo modifica clean_activos.

ALTER TABLE clean_activos
ADD COLUMN revision_asignacion VARCHAR(60);

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_activos a
SET revision_asignacion = CASE
    WHEN UPPER(TRIM(a.colaborador_asignado)) = 'SIN ASIGNAR'
        THEN 'Sin asignar'

    WHEN EXISTS (
        SELECT 1
        FROM clean_colaboradores c
        WHERE UPPER(TRIM(c.nombre_completo)) =
              UPPER(TRIM(a.colaborador_asignado))
          AND UPPER(TRIM(c.estatus)) = 'BAJA'
          AND UPPER(TRIM(a.fecha_fin)) = 'ACTIVO'
    )
        THEN 'Revisar devolución'

    WHEN EXISTS (
        SELECT 1
        FROM clean_colaboradores c
        WHERE UPPER(TRIM(c.nombre_completo)) =
              UPPER(TRIM(a.colaborador_asignado))
          AND UPPER(TRIM(c.estatus)) = 'BAJA'
    )
        THEN 'Baja con fecha de fin'

    ELSE 'Sin observaciones'
END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados.

SELECT
    revision_asignacion,
    COUNT(*) AS total_activos
FROM clean_activos
GROUP BY revision_asignacion
ORDER BY total_activos DESC;

-- 97. Validación de calidad y asignación de activos
-- No modifica los datos.

SELECT
    revision_general,
    revision_asignacion,
    COUNT(*) AS total_activos

FROM clean_activos

GROUP BY
    revision_general,
    revision_asignacion

ORDER BY
    revision_general,
    total_activos DESC;
    
-- 98. Validación final de la limpieza de activos
-- No modifica los datos.

SELECT
    COUNT(*) AS total_activos,

    COUNT(DISTINCT cod_activo) AS codigos_unicos,

    SUM(costo = 0) AS costos_en_cero,

    SUM(revision_general = 'Requiere revisión')
        AS activos_revision_datos,

    SUM(revision_asignacion = 'Sin asignar')
        AS activos_sin_asignar,

    SUM(revision_asignacion = 'Revisar devolución')
        AS activos_revisar_devolucion,

    SUM(revision_asignacion = 'Baja con fecha de fin')
        AS activos_baja_con_fecha,

    SUM(
        revision_general = 'Sin observaciones'
        AND revision_asignacion = 'Sin observaciones'
    ) AS activos_sin_observaciones

FROM clean_activos;

