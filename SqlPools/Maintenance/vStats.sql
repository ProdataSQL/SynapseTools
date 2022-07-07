SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[vStats]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[vStats] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[vStats] AS SELECT 
/*
	Description:Return data on individual Statistics including last updated date
	Source:		https://github.com/ProdataSQL/SynapseTools
	History:	12/08/2021 Bob, Created
				07/07/2022 Bov, Added Stats Sample Rate
*/
ss.object_id, ss.name as stat_name  , vs.table_name, vs.schema_name
, ss.stats_id, ss.auto_created, ss.filter_definition, STATS_DATE(ss.object_id, ss.stats_id) as last_updated_date
, sc.stat_columns
, vs.stats_row_count
, vs.actual_row_count
, vs.stats_difference_percent
, vs.stats_sample_rate
, 'UPDATE STATISTICS ' + quotename(vs.[schema_name]) + '.' + quotename(vs.[table_name])  + ' (' + ss.name  + ')'
	+ coalesce(case when vs.stats_sample_rate  >=100 THEN ' WITH FULLSCAN' ELSE  ' WITH SAMPLE ' + convert(varchar,vs.stats_sample_rate)  + ' PERCENT' END,'') as sqlCommand
FROM sys.stats ss
INNER JOIN (
	select sc.object_id, sc.stats_id, string_agg(c.name, ',') as stat_columns
	from sys.stats_columns sc 
	INNER JOIN sys.columns c on c.object_id=sc.object_id and c.column_id=sc.column_id
	GROUP BY sc.object_id, stats_id 
) sc on sc.object_id=ss.object_id and sc.stats_id=ss.stats_id
INNER JOIN dbo.vTableStats vs on vs.object_id=ss.object_id;
GO
GO

