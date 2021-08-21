WITH autostats (
	object_id
	,stats_id
	,name
	,column_id
	)
AS (
	SELECT sys.stats.object_id
		,sys.stats.stats_id
		,sys.stats.name
		,sc.column_id
	FROM sys.stats
	INNER JOIN sys.stats_columns sc ON sys.stats.object_id = sc.object_id
		AND sys.stats.stats_id = sc.stats_id
	WHERE sys.stats.auto_created = 1
		AND sc.stats_column_id = 1
	)
SELECT t.object_id
	,s.name AS schema_name
	,t.name AS table_name
	,'<ExtendedInfo><Column>' + c.name + '</Column><Overlapped>' + ss.name + '</Overlapped>' + '</ExtendedInfo>'
	,'DROP STATISTICS [' + OBJECT_SCHEMA_NAME(ss.object_id) + '].[' + OBJECT_NAME(ss.object_id) + '].[' + autostats.name + ']' AS SqlCommand
FROM sys.stats ss
INNER JOIN sys.stats_columns sc ON ss.object_id = sc.object_id
	AND ss.stats_id = sc.stats_id
INNER JOIN autostats ON sc.object_id = autostats.object_id
	AND sc.column_id = autostats.column_id
INNER JOIN sys.columns c ON ss.object_id = c.object_id
	AND sc.column_id = c.column_id
INNER JOIN sys.tables t ON t.object_id = ss.object_id
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE ss.auto_created = 0
	AND sc.stats_column_id = 1
	AND sc.stats_id != autostats.stats_id
	AND OBJECTPROPERTY(ss.object_id, 'IsMsShipped') = 0