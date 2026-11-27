USE OTC;

-- 13. Revisión del formato de las fechas
-- Se comprueba cómo están registradas las fechas
-- de inicio y finalización.

SELECT
    id_colaborador,
    proyecto,
    fecha_inicio,
    fecha_fin
FROM clean_asignaciones
WHERE fecha_fin IS NOT NULL;

-- 14. Cálculo de días para finalizar una asignación
-- Se agrega un atributo para conocer cuántos días
-- faltan para terminar cada asignación.

ALTER TABLE clean_asignaciones
ADD COLUMN dias_para_finalizar INT NULL;

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_asignaciones
SET dias_para_finalizar =
    CASE
        WHEN fecha_fin IS NOT NULL
        THEN DATEDIFF(
            STR_TO_DATE(fecha_fin, '%Y-%m-%d'),
            CURDATE()
        )
        ELSE NULL
    END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar los resultados

SELECT
    id_colaborador,
    proyecto,
    fecha_fin,
    dias_para_finalizar
FROM clean_asignaciones
ORDER BY dias_para_finalizar IS NULL,
         dias_para_finalizar;
         
-- 15. Clasificación de asignaciones por fecha de finalización
-- Se identifican asignaciones próximas a terminar.

ALTER TABLE clean_asignaciones
ADD COLUMN estado_vencimiento VARCHAR(50);

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_asignaciones
SET estado_vencimiento =
    CASE
        WHEN dias_para_finalizar IS NULL
            THEN 'Fecha pendiente'
        WHEN dias_para_finalizar < 0
            THEN 'Fecha vencida'
        WHEN dias_para_finalizar <= 30
            THEN 'Próximos 30 días'
        WHEN dias_para_finalizar <= 60
            THEN 'Próximos 60 días'
        WHEN dias_para_finalizar <= 90
            THEN 'Próximos 90 días'
        ELSE 'Más de 90 días'
    END;

SET SQL_SAFE_UPDATES = 1;

-- Verificar la clasificación

SELECT
    estado_vencimiento,
    COUNT(*) AS total_asignaciones
FROM clean_asignaciones
GROUP BY estado_vencimiento
ORDER BY total_asignaciones DESC;

-- 16. Identificación de colaboradores sin asignación
-- Se comparan los colaboradores activos con las
-- asignaciones vigentes registradas.

SELECT
    c.id,
    c.nombre_completo,
    c.estatus,
    c.puesto,
    c.departamento
FROM clean_colaboradores c
WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'
  AND NOT EXISTS (
      SELECT 1
      FROM clean_asignaciones a
      WHERE TRIM(a.id_colaborador) = TRIM(c.id)
        AND UPPER(TRIM(a.estatus_asignacion)) = 'ACTIVA'
  )
ORDER BY c.nombre_completo;

-- 17. Revisión de estados de asignación
-- Se identifican los valores utilizados por OT Consulting.

SELECT
    estatus_asignacion,
    COUNT(*) AS total_asignaciones
FROM clean_asignaciones
GROUP BY estatus_asignacion
ORDER BY total_asignaciones DESC;

-- 18. Identificación de colaboradores sin asignación
-- Se utiliza el estado real "En Curso".

SELECT
    c.id,
    c.nombre_completo,
    c.estatus,
    c.puesto,
    c.departamento
FROM clean_colaboradores c
WHERE UPPER(TRIM(c.estatus)) = 'ACTIVO'
  AND NOT EXISTS (
      SELECT 1
      FROM clean_asignaciones a
      WHERE TRIM(a.id_colaborador) = TRIM(c.id)
        AND UPPER(TRIM(a.estatus_asignacion)) = 'EN CURSO'
  )
ORDER BY c.nombre_completo;
