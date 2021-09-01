
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[QueryStore]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[QueryStore] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[QueryStore]
AS SELECT Txt.query_text_id as query_id, Txt.query_sql_text as query_text, sp.plan_id, sp.query_plan as query_plan_xml,  Qry.count_compiles,  qry.last_execution_time
, rs.count_executions
, rs.avg_duration
, rs.min_duration
, rs.max_duration
, Qry.object_id
FROM sys.query_store_plan AS sp
INNER JOIN sys.query_store_query AS Qry
    ON sp.query_id = Qry.query_id
INNER JOIN sys.query_store_query_text AS Txt
    ON Qry.query_text_id = Txt.query_text_id
INNER JOIN (
	select plan_id, sum(count_executions) as count_executions
	, sum(rs.avg_duration * rs. count_executions) / sum(rs.count_executions)/1000000 as avg_duration
	, min(convert(numeric (14,3),rs.min_duration )) /1000000 as min_duration 
	, max(convert(numeric (14,3),rs.max_duration )) /1000000 as max_duration 
	from sys.query_store_runtime_stats  rs
	GROUP BY rs.plan_id
) rs on rs.plan_id=sp.plan_id
