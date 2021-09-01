/* Query Store DMV SUmmary for Syanpse SQL Pool */

SELECT TOP 10 *
FROM [sys].[query_store_query];
GO


/* Query Text. Notice that SQL is tokenised to remove literals */
SELECT TOP 10 *
FROM [sys].[query_store_query_text];
GO

SELECT TOP 10 *
FROM [sys].[query_store_plan];
GO


/* run time stats. Notice that a lot of the metrics do not get shown in SQL Pools */
SELECT TOP 10 *
FROM [sys].[query_store_runtime_stats];
GO

/* Note. There are no wait stats like traditional SQL*/