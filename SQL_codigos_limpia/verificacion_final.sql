USE OTC;
-- 99. Verificación general de tablas limpias
-- No modifica los datos.

SELECT 'Colaboradores' AS tabla, COUNT(*) AS registros
FROM clean_colaboradores

UNION ALL

SELECT 'Asignaciones', COUNT(*)
FROM clean_asignaciones

UNION ALL

SELECT 'Clientes', COUNT(*)
FROM clean_clientes

UNION ALL

SELECT 'Departamentos', COUNT(*)
FROM clean_departamentos

UNION ALL

SELECT 'Roles', COUNT(*)
FROM clean_roles

UNION ALL

SELECT 'Habilidades', COUNT(*)
FROM clean_habilidades

UNION ALL

SELECT 'Matriz', COUNT(*)
FROM clean_matriz

UNION ALL

SELECT 'Activos', COUNT(*)
FROM clean_activos;
