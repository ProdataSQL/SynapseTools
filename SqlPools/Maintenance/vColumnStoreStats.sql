SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[vColumnstoreStats]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[vColumnstoreStats] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[vColumnstoreStats] AS WITH ColumnStats as ( 
	/*
		Description: View for querying ColumnStore Stats and Fragmentation.
		used By: SyanpseColumnstoreOptimze SProc
		History: 10/08/2021 Bob, Created for Synapse Dedicated Pools
	*/
		SELECT t.object_id as object_id
		, s.name AS [schema_name]
		, t.name AS [table_name]
		,  case when ps.name is null then null else rg.[partition_number] end as partition_number
		, rg.[total_rows] AS [row_count]
		, i.name as index_name
		, ps.name as partition_scheme
		, CASE WHEN rg.[State] = 3 THEN rg.[total_rows]  END as compressed_row_count
		, CASE WHEN rg.[State] = 3 Then rg.[deleted_rows] ELSE 0 end as deleted_row_count
		, CASE WHEN rg.[State] = 1 THEN rg.[total_rows] ELSE 0 END as open_row_count
		, CASE WHEN rg.[State] = 3 THEN 1 ELSE 0 END  as compressed_rowgroup_count
		, CASE WHEN rg.[State] = 1 THEN 1 ELSE 0 END  as open_rowgroup_count
		, CASE WHEN rg.[State] IN (1,3) THEN 0 ELSE 1 END  as other_rowgroup_count /* Tombstone or invisible*/
		FROM sys.[pdw_nodes_column_store_row_groups] rg
		INNER JOIN sys.[pdw_nodes_tables] nt ON rg.[object_id] = nt.[object_id]
			AND rg.[pdw_node_id] = nt.[pdw_node_id]
			AND rg.[distribution_id] = nt.[distribution_id]
		INNER JOIN sys.[pdw_table_mappings] mp ON nt.[name] = mp.[physical_name]
		INNER JOIN sys.[tables] t ON mp.[object_id] = t.[object_id]
		INNER JOIN sys.[schemas] s ON t.[schema_id] = s.[schema_id]
		INNER JOIN sys.indexes i on i.object_id=t.object_id and i.type=5 /* CCI */
		LEFT JOIN sys.partition_schemes ps   on i.data_space_id=ps.data_space_id
	)
	SELECT getdate() AS [execution_date]
	, DB_Name()		 AS [database_name]
	, cs.schema_name
	, cs.table_name
	, cs.[partition_number]
	, cs.partition_scheme
	, cs.object_id
	, cs.index_name
	, sum(cs.row_count) as row_count
	, sum(deleted_row_count) as deleted_row_count
	, count(*) as row_group_count
	, sum(cs.compressed_row_count) as compressed_row_count
	, sum(compressed_rowgroup_count) as compressed_rowgroup_count
	, sum(cs.open_rowgroup_count) as open_rowgroup_count
	, sum(cs.open_row_count) as open_row_count
	, max(cs.compressed_row_count)  as compressed_row_max
	, avg(cs.compressed_row_count) as compressed_row_avg
	, 100-convert(numeric(10,4),convert(float,avg(cs.compressed_row_count)) / max(cs.compressed_row_count))*100 as fragmentation_density
	, convert(numeric(10,4),convert(float,sum(cs.deleted_row_count)) / coalesce(max(cs.compressed_row_count),1048576)/60)*100 as fragmentation_deletes
	, convert(numeric(10,4),convert(float,sum(cs.open_row_count)) / coalesce(max(cs.compressed_row_count),1048576)/60)*100 as fragmentation_open
	FROM ColumnStats cs

GROUP BY cs.schema_name
	, cs.table_name
	, cs.[partition_number]
	, cs.partition_scheme
	, cs.index_name
	, cs.object_id;
GO


