USE OTC;

-- 2. Identificación de inconsistencias en los nombres de columnas
-- Se detectaron caracteres invisibles que impiden
-- consultar algunas columnas por su nombre.

SELECT
    COLUMN_NAME,
    HEX(COLUMN_NAME) AS nombre_hexadecimal
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'otc'
  AND TABLE_NAME = 'stg_colaboradores'
  AND COLUMN_NAME LIKE '%puesto%';


CREATE TABLE clean_colaboradores
LIKE stg_colaboradores;

INSERT INTO clean_colaboradores
SELECT * FROM stg_colaboradores;

SELECT COUNT(*) AS total_registros
FROM clean_colaboradores;

-- 4. Corregir nombres de columnas
-- Se eliminan caracteres invisibles de los nombres.

SET SESSION group_concat_max_len = 100000;

SELECT GROUP_CONCAT(
    CONCAT(
        'CHANGE COLUMN `',
        REPLACE(COLUMN_NAME, '`', '``'),
        '` `',
        REPLACE(
            REPLACE(
                REPLACE(COLUMN_NAME,
                    CONVERT(0xE281A0 USING utf8mb4), ''),
                CONVERT(0xE280AF USING utf8mb4), ''),
            ' ', ''
        ),
        '` VARCHAR(255) NULL'
    )
    ORDER BY ORDINAL_POSITION
    SEPARATOR ', '
)
INTO @columnas
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'clean_colaboradores'
  AND (
      HEX(COLUMN_NAME) LIKE '%E281A0%'
      OR HEX(COLUMN_NAME) LIKE '%E280AF%'
  );

SET @sql = CONCAT(
    'ALTER TABLE clean_colaboradores ',
    @columnas
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT puesto
FROM clean_colaboradores
LIMIT 5;

-- 5. Identificación de valores faltantes
-- Se revisan puestos, sueldos y departamentos.

SELECT
    COUNT(*) AS total_colaboradores,

    SUM(
        puesto IS NULL
        OR TRIM(puesto) = ''
        OR UPPER(TRIM(puesto)) = 'PENDIENTE'
    ) AS puestos_pendientes,

    SUM(
        sueldo_total_integrado IS NULL
        OR TRIM(sueldo_total_integrado) = ''
        OR TRIM(sueldo_total_integrado) = '0'
    ) AS sueldos_vacios_o_cero,

    SUM(
        departamento IS NULL
        OR TRIM(departamento) = ''
        OR UPPER(TRIM(departamento)) = 'PENDIENTE'
    ) AS departamentos_pendientes

FROM clean_colaboradores;

-- 6. Limpieza de puestos y departamentos
-- Se reemplazan valores pendientes por NULL.
-- Los registros originales se conservan en staging.

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_colaboradores
SET puesto = NULL
WHERE puesto IS NULL
   OR TRIM(puesto) = ''
   OR UPPER(TRIM(puesto)) IN ('PENDIENTE', 'N/A');

UPDATE clean_colaboradores
SET departamento = NULL
WHERE departamento IS NULL
   OR TRIM(departamento) = ''
   OR UPPER(TRIM(departamento)) IN ('PENDIENTE', 'N/A');

-- Verificar los resultados de la limpieza

SELECT
    COUNT(*) AS total_colaboradores,
    SUM(puesto IS NULL) AS puestos_sin_informacion,
    SUM(departamento IS NULL) AS departamentos_sin_informacion
FROM clean_colaboradores;

-- 7. Revisión de sueldos vacíos o en cero
-- Se agrupan por estatus del colaborador.

SELECT
    estatus,
    COUNT(*) AS total_colaboradores,
    SUM(
        sueldo_total_integrado IS NULL
        OR TRIM(sueldo_total_integrado) = ''
        OR TRIM(sueldo_total_integrado) = '0'
    ) AS sueldos_vacios_o_cero
FROM clean_colaboradores
GROUP BY estatus
ORDER BY estatus;

-- 8. Identificación de sueldos que requieren revisión
-- Se consultan los colaboradores activos con sueldo
-- integrado vacío o en cero.

SELECT
    id,
    nombre_completo,
    estatus,
    sueldo_neto_imss,
    sueldo_asimilados_sindicato,
    sueldo_complementos,
    sueldo_neto_total,
    comision_nomina,
    impuestos_imss,
    sueldo_total_integrado
FROM clean_colaboradores
WHERE UPPER(TRIM(estatus)) = 'ACTIVO'
  AND (
      sueldo_total_integrado IS NULL
      OR TRIM(sueldo_total_integrado) = ''
      OR TRIM(sueldo_total_integrado) = '0'
  );
  
  -- 9. Identificación de sueldos que requieren revisión
-- No se modifican los importes originales.

ALTER TABLE clean_colaboradores
ADD COLUMN revision_sueldo VARCHAR(50);

UPDATE clean_colaboradores
SET revision_sueldo =
    CASE
        WHEN sueldo_total_integrado IS NULL
          OR TRIM(sueldo_total_integrado) = ''
          OR TRIM(sueldo_total_integrado) = '0'
        THEN 'Requiere revisión'
        ELSE 'Sin observaciones'
    END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados

SELECT
    estatus,
    revision_sueldo,
    COUNT(*) AS colaboradores
FROM clean_colaboradores
GROUP BY estatus, revision_sueldo
ORDER BY estatus, revision_sueldo;

-- 19. Indicadores de asignación de colaboradores
-- Se calcula cuántos colaboradores activos
-- tienen o no una asignación en curso.

SELECT
    COUNT(*) AS total_activos,

    SUM(
        CASE WHEN EXISTS (
            SELECT 1
            FROM clean_asignaciones a
            WHERE TRIM(a.id_colaborador) = TRIM(c.id)
              AND UPPER(TRIM(a.estatus_asignacion)) = 'EN CURSO'
        )
        THEN 1 ELSE 0 END
    ) AS colaboradores_asignados,

    SUM(
        CASE WHEN NOT EXISTS (
            SELECT 1
            FROM clean_asignaciones a
            WHERE TRIM(a.id_colaborador) = TRIM(c.id)
              AND UPPER(TRIM(a.estatus_asignacion)) = 'EN CURSO'
        )
        THEN 1 ELSE 0 END
    ) AS colaboradores_sin_asignacion,

    ROUND(
        100.0 * SUM(
            CASE WHEN NOT EXISTS (
                SELECT 1
                FROM clean_asignaciones a
                WHERE TRIM(a.id_colaborador) = TRIM(c.id)
                  AND UPPER(TRIM(a.estatus_asignacion)) = 'EN CURSO'
            )
            THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS porcentaje_sin_asignacion

FROM clean_colaboradores c
WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO';

-- 20. Revisión de los costos de colaboradores
-- Se revisa el formato del sueldo integrado
-- antes de calcular el costo por hora.

SELECT
    id,
    nombre_completo,
    estatus,
    sueldo_neto_total,
    comision_nomina,
    impuestos_imss,
    sueldo_total_integrado
FROM clean_colaboradores
WHERE UPPER(TRIM(estatus)) = 'ACTIVO'
  AND revision_sueldo = 'Sin observaciones'
LIMIT 10;

-- 21. Validación del costo integrado mensual
-- Se comprueba que el costo integrado coincida
-- con la suma de sus componentes.

SELECT
    id,
    nombre_completo,
    estatus,

    CAST(sueldo_total_integrado AS DECIMAL(15,2))
        AS costo_integrado_registrado,

    ROUND(
        CAST(sueldo_neto_total AS DECIMAL(15,2)) +
        CAST(comision_nomina AS DECIMAL(15,2)) +
        CAST(impuestos_imss AS DECIMAL(15,2)),
        2
    ) AS costo_integrado_calculado,

    ROUND(
        CAST(sueldo_total_integrado AS DECIMAL(15,2)) -
        (
            CAST(sueldo_neto_total AS DECIMAL(15,2)) +
            CAST(comision_nomina AS DECIMAL(15,2)) +
            CAST(impuestos_imss AS DECIMAL(15,2))
        ),
        2
    ) AS diferencia

FROM clean_colaboradores
ORDER BY ABS(diferencia) DESC;

-- 22. Cálculo del costo por hora
-- Se utilizan 160 horas laborables mensuales
-- como supuesto provisional.
-- Pendiente de validación con OT Consulting.

ALTER TABLE clean_colaboradores
ADD COLUMN costo_por_hora DECIMAL(15,2) NULL;

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_colaboradores
SET costo_por_hora =
    CASE
        WHEN sueldo_total_integrado IS NOT NULL
         AND TRIM(sueldo_total_integrado) <> ''
         AND CAST(sueldo_total_integrado AS DECIMAL(15,2)) > 0
        THEN ROUND(
            CAST(sueldo_total_integrado AS DECIMAL(15,2)) / 160,
            2
        )
        ELSE NULL
    END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados

SELECT
    id,
    nombre_completo,
    estatus,
    sueldo_total_integrado,
    costo_por_hora
FROM clean_colaboradores
WHERE UPPER(TRIM(estatus)) = 'ACTIVO'
ORDER BY costo_por_hora IS NULL, costo_por_hora DESC;

-- 23. Costo mensual de colaboradores sin asignación
-- Se consideran colaboradores activos que no tienen
-- asignaciones registradas como "En Curso".

SELECT
    COUNT(*) AS colaboradores_sin_asignacion,

    SUM(
        CASE
            WHEN c.costo_por_hora IS NOT NULL
            THEN 1 ELSE 0
        END
    ) AS colaboradores_con_costo,

    SUM(
        CASE
            WHEN c.costo_por_hora IS NULL
            THEN 1 ELSE 0
        END
    ) AS colaboradores_sin_costo,

    ROUND(
        SUM(
            CASE
                WHEN c.costo_por_hora IS NOT NULL
                THEN CAST(c.sueldo_total_integrado AS DECIMAL(15,2))
                ELSE 0
            END
        ),
        2
    ) AS costo_mensual_conocido

FROM clean_colaboradores c
WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'
  AND NOT EXISTS (
      SELECT 1
      FROM clean_asignaciones a
      WHERE TRIM(a.id_colaborador) = TRIM(c.id)
        AND UPPER(TRIM(a.estatus_asignacion)) = 'EN CURSO'
  );
  
  -- 24. Clasificación de colaboradores por asignación
-- Se identifica si cada colaborador activo
-- tiene una asignación registrada como "En Curso".

ALTER TABLE clean_colaboradores
ADD COLUMN estado_asignacion VARCHAR(50) NULL;

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_colaboradores c
SET estado_asignacion =
    CASE
        WHEN UPPER(TRIM(c.estatus)) <> 'ACTIVO'
            THEN 'Colaborador de baja'

        WHEN EXISTS (
            SELECT 1
            FROM clean_asignaciones a
            WHERE TRIM(a.id_colaborador) = TRIM(c.id)
              AND UPPER(TRIM(a.estatus_asignacion)) = 'EN CURSO'
        )
            THEN 'Con asignación'

        ELSE 'Sin asignación registrada'
    END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados

SELECT
    estado_asignacion,
    COUNT(*) AS total_colaboradores
FROM clean_colaboradores
GROUP BY estado_asignacion
ORDER BY total_colaboradores DESC;
