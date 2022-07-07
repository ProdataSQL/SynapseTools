SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U'))
CREATE TABLE [dbo].[CommandLog]
(
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseName] [sysname] NULL,
	[SchemaName] [sysname] NULL,
	[ObjectName] [sysname] NULL,
	[ObjectType] [char](2) NULL,
	[IndexName] [sysname] NULL,
	[IndexType] [tinyint] NULL,
	[StatisticsName] [sysname] NULL,
	[PartitionNumber] [int] NULL,
	[ExtendedInfo] [nvarchar](max) NULL,
	[Command] [nvarchar](max) NOT NULL,
	[CommandType] [nvarchar](60) NOT NULL,
	[StartTime] [datetime] NOT NULL,
	[EndTime] [datetime] NULL,
	[ErrorNumber] [int] NULL,
	[ErrorMessage] [nvarchar](max) NULL,
 CONSTRAINT [PK_CommandLog] PRIMARY KEY NONCLUSTERED 
	(
		[ID] ASC
	) NOT ENFORCED 
)
WITH
(
	DISTRIBUTION = ROUND_ROBIN,
	CLUSTERED INDEX
	(
		[ID] ASC
	)
)
GO


SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[vTableStats]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[vTableStats] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[vTableStats] AS with
/*
	Description:Return data on outdated and missing statistics. Use this for Index Maintenance
	Source:		https://github.com/ProdataSQL/SynapseTools
				Concept copied from https://github.com/abrahams1/Azure_Synapse_Toolbox/tree/master/SQL_Queries/Statistics 
	History:	12/08/2021 Bob, Created
*/
cmp_summary as
(
	select tm.object_id, sum(ps.row_count) cmp_row_count
	, case when sum(ps.row_count) =0 then  100 else sqrt(sum(ps.row_count)) *1000/ sum(ps.row_count)*100 end as stats_sample_rate
	, convert(bigint,SQRT(1000 * sum(ps.row_count)))  as dynamic_threshold_rows
	from sys.dm_pdw_nodes_db_partition_stats ps
		inner join sys.pdw_nodes_tables nt on nt.object_id=ps.object_id and ps.distribution_id=nt.distribution_id 
		inner join sys.pdw_table_mappings tm on tm.physical_name=nt.name
	where ps.index_id<2
	group by tm.object_id

)
, ctl_summary as
(
	select  t.object_id, s.name [schema_name], t.name table_name,  i.type_desc table_type, dp.distribution_policy_desc distribution_type, sum(p.rows) ctl_row_count
	from sys.schemas s
		inner join sys.tables t on t.schema_id=s.schema_id
		inner join sys.pdw_table_distribution_properties dp on dp.object_id=t.object_id
		inner join sys.indexes i on i.object_id=t.object_id and i.index_id<2
		inner join sys.partitions p on p.object_id=t.object_id and p.index_id=i.index_id
	group by t.object_id, s.name, t.name, i.type_desc, dp.distribution_policy_desc
)
, [all_results] as
(
	select ctl.object_id, ctl.[schema_name], ctl.table_name, ctl.table_type, ctl.distribution_type
		, ctl.ctl_row_count as stats_row_count, cmp.cmp_row_count as actual_row_count, convert(decimal(10,2),(abs(ctl.ctl_row_count - cmp.cmp_row_count)*100.0 / nullif(cmp.cmp_row_count,0))) stats_difference_percent
		, convert(int,case when cmp.stats_sample_rate < 1 then 1 when cmp.stats_sample_rate > 100 then 100 else cmp.stats_sample_rate  end ) as stats_sample_rate
		, cmp.dynamic_threshold_rows
	from ctl_summary ctl
		inner join cmp_summary cmp on ctl.object_id=cmp.object_id
)
select [object_id], [schema_name], [table_name], [table_type], [distribution_type], [stats_row_count], [actual_row_count], [stats_difference_percent]
, dynamic_threshold_rows
, [stats_sample_rate]
, case when stats_difference_percent >=20  or abs([actual_row_count] - [stats_row_count]) > dynamic_threshold_rows then 1 else 0 end as recommend_update
,  'UPDATE STATISTICS ' + quotename([schema_name]) + '.' + quotename([table_name]) 
	+ coalesce(case when stats_sample_rate  >=100 THEN ' WITH FULLSCAN' ELSE  ' WITH SAMPLE ' + convert(varchar,stats_sample_rate)  + ' PERCENT' END,'') as sqlCommand
from [all_results];
GO


SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[vPartitionStats]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[vPartitionStats] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[vPartitionStats]
AS with
/*
	Description:Return data on outdated and missing statistics. Use this for Index Maintenance
	Source:		https://github.com/ProdataSQL/SynapseTools
				Concept copied from https://github.com/abrahams1/Azure_Synapse_Toolbox/tree/master/SQL_Queries/Statistics 
	History:	12/08/2021 Bob, Created
*/
cmp_summary as
(
	select tm.object_id, ps.partition_number, sum(ps.row_count) cmp_row_count
	from sys.dm_pdw_nodes_db_partition_stats ps
		inner join sys.pdw_nodes_tables nt on nt.object_id=ps.object_id and ps.distribution_id=nt.distribution_id 
		inner join sys.pdw_table_mappings tm on tm.physical_name=nt.name
	group by tm.object_id, ps.partition_number

)
, ctl_summary as
(
	select  t.object_id, s.name [schema_name], t.name table_name, case when ps.name is not null then p.partition_number end as partition_number, ps.name as partition_scheme, i.type_desc table_type, dp.distribution_policy_desc distribution_type, sum(p.rows) ctl_row_count
	from sys.schemas s
		inner join sys.tables t on t.schema_id=s.schema_id
		inner join sys.pdw_table_distribution_properties dp on dp.object_id=t.object_id
		inner join sys.indexes i on i.object_id=t.object_id and i.index_id<2
		inner join sys.partitions p on p.object_id=t.object_id and p.index_id=i.index_id
		left join sys.partition_schemes ps on ps.data_space_id=i.data_space_id
	group by t.object_id, s.name, t.name, i.type_desc, dp.distribution_policy_desc,p.partition_number, ps.name
)
, [all_results] as
(
	select ctl.object_id, ctl.[schema_name], ctl.table_name, ctl.partition_number, ctl.table_type, ctl.distribution_type
		, ctl.ctl_row_count as stats_row_count, cmp.cmp_row_count as actual_row_count, convert(decimal(10,2),(abs(ctl.ctl_row_count - cmp.cmp_row_count)*100.0 / nullif(cmp.cmp_row_count,0))) stats_difference_percent
		
	from ctl_summary ctl
		inner join cmp_summary cmp on ctl.object_id=cmp.object_id and (ctl.partition_number=cmp.partition_number or ctl.partition_number is null)

)
select * from [all_results];
GO


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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[vColumnstoreStats]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[vColumnstoreStats] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[vColumnstoreStats] AS WITH ColumnStats as ( 
	/*
		Description:View for querying ColumnStore Stats and Fragmentation.
		used By:	ColumnstoreOptimze SProc
		History: 
					10/08/2021 Bob, Created for Synapse Dedicated Pools
					07/07/2022 Bob, Adjusted density calculation if < 60 million
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
		WHERE rg.[State] IN (1,3)
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
	, 100-convert(numeric(10,4),convert(float,avg(cs.compressed_row_count)) / CASE WHEN sum(cs.compressed_row_count) > 60000000 then 1048576 else max(cs.compressed_row_count) end )*100 as fragmentation_density
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





SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ColumnstoreOptimize]') AND type in (N'P'))
EXEC dbo.sp_executesql @statement = N'CREATE PROC [dbo].[ColumnstoreOptimize] AS SELECT 1 as Dummy'
GO
/****** Object:  StoredProcedure [dbo].[ColumnstoreOptimize]    Script Date: 22/08/2021 15:20:01 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[ColumnstoreOptimize] @Tables [nvarchar](4000),@DensityThreshold [numeric](6,2),@OpenThreshold [int],@DeleteThreshold [int],@TimeLimit [int],@Execute [char](1) AS
/*
Description:	Maintenance for Clustered Column Store Indexes. This accounts for three scenarios and will issue appropriate command
					- Fragmentation caused by deletes (REBUILD)
					- Fragmentation caused by open row stores (delta) aka inserts (REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON)
					- Fragmentation caused byt low density in row stores (REORGANIZE)
Example:		exec [dbo].[ColumnstoreOptimize]   null, 0,0,0,null,'N'     /* Default Defrag and also remove open/deleted rows if > 60 RowGroups */
				exec [dbo].[ColumnstoreOptimize]   '%.Fact%',-1,-1,0,null,'N'	/* Only remove deleted rows on fact Tables */ 
				exec [dbo].[ColumnstoreOptimize]   '%.FactFinance',0,null,null,'N'	/* Force rebuild of ColumnStore on Fact Finance */
History:		
		10/08/2021 Bob, Created for Synapse SQL Maintenance

*/
BEGIN
	SET NOCOUNT ON;
	DECLARE @MinRowgroupCount int=120 /* Ignore Density in Columns stores with under 120 row groups, or 2 per distribution (about 130 million rows)*/
	DECLARE @table_name sysname
		, @schema_name sysname
		, @object_id int
		, @SqlCommand nvarchar(4000)
		, @row_group_count int
		, @row_count bigint
		, @compressed_rowgroup_count bigint
		, @compressed_row_count bigint
		, @deleted_row_count bigint
		, @open_row_count int
		, @fragmentation_density numeric(10,2)
		, @fragmentation_open numeric(10,2)
		, @fragmentation_deletes numeric(10,2)
		, @partition_number int
		, @index_name sysname
		, @StartTime datetime
		, @db_name sysname =db_name()
		, @ID int
		, @LastID int
		, @object_name sysname
		, @ExtendedInfo nvarchar(4000)
		, @Error int
		, @ErrorMessage nvarchar(4000)
		, @Parameters nvarchar(max)
		, @ProcStartTime datetime
		, @StartMessage nvarchar(max)
		, @Duration int

	SELECT  @DensityThreshold =coalesce( @DensityThreshold,25)
	, @OpenThreshold =coalesce(@OpenThreshold ,200000)
	, @DeleteThreshold =coalesce(@DeleteThreshold ,200000)
	, @Execute =coalesce(@Execute,'Y')
	

	SET @Parameters = '@Tables= ' + ISNULL('''' + REPLACE(@Tables,'''','''''') + '''','ALL')
	SET @Parameters += ', @DensityThreshold = ' + ISNULL(CAST( @DensityThreshold AS nvarchar),'NULL')
	SET @Parameters += ', @OpenThreshold = ' + ISNULL(CAST(@OpenThreshold AS nvarchar),'NULL')
	SET @Parameters += ', @DeleteThreshold = ' + ISNULL(CAST(@DeleteThreshold AS nvarchar),'NULL')
	SET @Parameters += ', @Execute = ' + ISNULL(CAST(@Execute AS nvarchar),'NULL')

	SET @StartMessage = 'Date and time: ' + CONVERT(nvarchar,getdate(),120)
	RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
	SET @StartMessage = 'Server: ' + CAST(SERVERPROPERTY('ServerName') AS nvarchar(max))
	RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
	SET @StartMessage = 'Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))
	RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
	SET @StartMessage = 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(max))
	RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
	SET @StartMessage = 'Parameters: ' + @Parameters
	RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
	SET @StartMessage = 'Version: ' + @@version
	RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
	SET @StartMessage = 'Source: https://github.com/ProdataSQL/SynapseTools/tree/main/SqlPools/Maintenance'
	RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT


	IF OBJECT_ID('dbo.CommandLog') is null
		CREATE TABLE [dbo].[CommandLog](
		[ID] [int] IDENTITY(1,1) NOT NULL,
		[DatabaseName] [sysname] NULL,
		[SchemaName] [sysname] NULL,
		[ObjectName] [sysname] NULL,
		[ObjectType] [char](2) NULL,
		[IndexName] [sysname] NULL,
		[IndexType] [tinyint] NULL,
		[StatisticsName] [sysname] NULL,
		[PartitionNumber] [int] NULL,
		[ExtendedInfo] [nvarchar](max) NULL,
		[Command] [nvarchar](max) NOT NULL,
		[CommandType] [nvarchar](60) NOT NULL,
		[StartTime] [datetime] NOT NULL,
		[EndTime] [datetime] NULL,
		[ErrorNumber] [int] NULL,
		[ErrorMessage] [nvarchar](max) NULL,
	 CONSTRAINT [PK_CommandLog] PRIMARY KEY NONCLUSTERED (	[ID] ASC) NOT ENFORCED )
	 WITH (  DISTRIBUTION = ROUND_ROBIN,CLUSTERED INDEX (ID))


	if OBJECT_ID('tempdb.dbo.#work_queue') is not null
		DROP TABLE #work_queue

	;CREATE TABLE #work_queue
	WITH ( DISTRIBUTION = ROUND_ROBIN,CLUSTERED INDEX (table_name))
	AS
		 With Param1 as (
			SELECT CASE WHEN left(ltrim(ss.value),1) IN ('+','-') THEN left(ltrim(ss.value),1) else '+' end  as Op
			, CASE WHEN left(ltrim(ss.value),1) IN ('+','-') THEN substring(ltrim(ss.value),2,4000) else ltrim(ss.value) END as [Object]
			FROM string_split(@Tables,',') ss
		),
		Param2 as (
			SELECT ss.Op
			, case when charindex ('.', ss.Object) > 0 then left( ss.Object,charindex ('.', ss.Object) -1) else '%' END as [Schema]
			, case when charindex ('.', ss.Object) > 0 then substring( ss.Object,charindex ('.', ss.Object)+1, 4000) else case when ss.Object like 'ALL%' then '%' else ss.object END END as [Table]
			FROM Param1 ss
		), ParamTables as (
			select t.object_id, s.name as [Schema], t.name as [Table]
			FROM Param2 p
			CROSS JOIN sys.tables t 
			INNER JOIN sys.schemas s on s.schema_id =t.schema_id
			WHERE t.type='U'  and is_external=0 
			and ( s.name like p.[schema] AND t.name like p.[Table] )
			GROUP BY t.object_id , s.name, t.name
		having max(p.Op) ='+'
		)
		SELECT 	ROW_NUMBER() OVER (ORDER BY cs.schema_name, cs.table_name, cs.partition_number) as ID  , cs.object_id,  quotename(cs.schema_name) + '.' + quotename(cs.table_name)  as table_name, cs.schema_name, cs.table_name as object_name, cs.partition_number, ''
		+  CASE WHEN cs.deleted_row_count >  @DeleteThreshold  and @DeleteThreshold  >= 0 then 'REBUILD ' + coalesce(' PARTITION=' + convert(varchar,cs.partition_number) ,'') 
				WHEN cs.open_row_count >= @OpenThreshold and @OpenThreshold > -1  then 'REORGANIZE' +   coalesce(' PARTITION=' + convert(varchar,cs.partition_number),'') + ' WITH (COMPRESS_ALL_ROW_GROUPS = ON)'	
				WHEN cs.[fragmentation_density] >= @DensityThreshold and cs.[compressed_rowgroup_count] > @MinRowgroupCount and @DensityThreshold  > -1  then 'REORGANIZE' + coalesce(' PARTITION=' + convert(varchar,cs.partition_number),'')
				ELSE 'N/A'
		END as SqlCommand 
		, cs.compressed_row_count
		, cs.compressed_rowgroup_count
		, cs.[row_group_count]
		, cs.[row_count]
		, cs.deleted_row_count
		, cs.open_row_count
		, cs.[fragmentation_density]
		, cs.[fragmentation_deletes]
		, cs.[fragmentation_open]
		, i.[name] as index_name
		FROM [dbo].[vColumnstoreStats] cs
		INNER JOIN sys.indexes i on i.object_id=cs.object_id and i.type=5 /* Ony CCS */
		INNER JOIN ParamTables t on t.object_id=cs.object_id 
		WHERE (cs.[fragmentation_density] > @DensityThreshold and cs.[compressed_rowgroup_count] > @MinRowgroupCount and @DensityThreshold >=0 )
		OR (cs.deleted_row_count >  @DeleteThreshold  and @DeleteThreshold  > -1)
		OR (cs.open_row_count >= @OpenThreshold and @OpenThreshold > -1)
		 
	SELECT TOP 1 @ID=ID,@ProcStartTime =getdate(), @Duration =0 FROM #work_queue ORDER BY ID
	WHILE (@ID is not null) AND (@Duration < @TimeLimit OR @TimeLimit is null)
	BEGIN
		SET @object_id=null
		SELECT @LastID=q.ID, @object_id=q.[object_id], @schema_name =[schema_name], @table_name=table_name, @partition_number= partition_number, @sqlCommand =sqlCommand, @row_group_count=row_group_count, @row_count=row_count, @deleted_row_count=deleted_row_count, @open_row_count=open_row_count
		, @fragmentation_density = fragmentation_density, @fragmentation_open= fragmentation_open, @fragmentation_deletes=fragmentation_deletes, @index_name=index_name
		, @StartTime=getdate(), @compressed_row_count =compressed_row_count, @compressed_rowgroup_count=compressed_rowgroup_count, @object_name=[object_name]
		FROM #work_queue q
		WHERE ID = @ID

		SET @ExtendedInfo='<ExtendedInfo><RowGroups>' + convert(varchar,@compressed_rowgroup_count) + '</RowGroups><Rows>' + convert(varchar,@row_count )   +  '</Rows><OpenRows>' + convert(varchar,@open_row_count ) + '</OpenRows><DeletedRows>' + convert(varchar,@deleted_row_count) + '</DeletedRows><DensityFragmentation>' +  convert( varchar,@fragmentation_density)  +'%</DensityFragmentation></ExtendedInfo>'
		SET @SqlCommand='ALTER INDEX ' + @index_name + ' ON '+ @table_name + ' ' + @SqlCommand 

		SET @StartMessage = 'Date and time: ' + CONVERT(nvarchar,SYSDATETIME(),120)
		RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
		RAISERROR('%s',10,1,@table_name) WITH NOWAIT
		SET @StartMessage = 'SqlCommand: ' + @sqlCommand
		RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
		RAISERROR('%s',10,1,@ExtendedInfo) WITH NOWAIT

		IF @object_id is not null and @Execute='Y'
		BEGIN
			INSERT INTO dbo.CommandLog (DatabaseName, SchemaName, ObjectName, ObjectType, IndexName, IndexType,  PartitionNumber, Command, CommandType, StartTime, ExtendedInfo)
			VALUES (@db_name, @schema_name, @object_name, 'U',@index_name, 5, @partition_number, @SqlCommand, 'ALTER INDEX', @StartTime, @ExtendedInfo)
			
			SELECT TOP 1 @ID=ID from dbo.CommandLog ORDER BY StartTime desc 
	
			BEGIN TRY  
				exec (@SqlCommand)
			END TRY  
			BEGIN CATCH
				  SET @Error = ERROR_NUMBER()
				  SET @ErrorMessage = ERROR_MESSAGE()

				  SET @ErrorMessage = 'Msg ' + CAST(ERROR_NUMBER() AS nvarchar) + ', ' + ISNULL(ERROR_MESSAGE(),'')
				  UPDATE dbo.CommandLog SET [ErrorNumber]=@Error, ErrorMessage=@ErrorMessage
				  WHERE ID=@ID
				  RAISERROR ('%s',16,1,@ErrorMessage) WITH NOWAIT;
			END CATCH
	    	UPDATE dbo.CommandLog SET EndTime=getdate() WHERE ID=@ID
		END

		SET @ID=null
		SELECT TOP 1 @ID =ID FROM #work_queue WHERE ID > @LastID ORDER BY ID 	
		SET @Duration=datediff(second,@ProcStartTime, getdate())

	END
END;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[StatsOptimize]') AND type in (N'P'))
EXEC dbo.sp_executesql @statement = N'CREATE PROC [dbo].[StatsOptimize] AS SELECT 1 as Dummy'
GO
ALTER  PROC [dbo].[StatsOptimize] @Tables [varchar](4000),@StatisticsModificationLevel [int],@StatisticsSample [int],@OnlyModifiedStatistics [char](1),@DeleteOverlappingStats [char](1),@TimeLimit [int],@Execute [char](1) AS
BEGIN
/*
description:	Stats Maintenance for Synapse SQL Pools
				Concepts crteated from from 
					- ola halogren scripts  https://ola.hallengren.com/
					- https://github.com/abrahams1/Azure_Synapse_Toolbox/tree/master/SQL_Queries/Statistics 
					- https://www.sqlskills.com/blogs/tim/when-updating-statistics-is-too-expensive/
					- https://www.sqlskills.com/blogs/erin/updating-statistics-with-ola-hallengrens-script/
					- https://docs.microsoft.com/en-us/sql/relational-databases/statistics/statistics?view=sql-server-2017  Why SQRT (rows*1000)
Example: 
	--Default Best Practise with smart defaults 
	exec dbo.[StatsOptimize] null,null,null,null,null,null,null

	--Exclude 1 Table and use a 5% change threshold (plus auto at SQRT algorithm). Dont add Missing Stats or Delete Overlapping Stats
	exec [StatsOptimize] @Tables='ALL,-FactFinance',  @StatisticsModificationLevel=5, @StatisticsSample=null,@OnlyModifiedStatistics ='Y' ,@DeleteOverlappingStats ='N', @TimeLimit=null,@Execute='N'

	--Stats Updates with FULL Sample (no missing or de-dupe), only if > 10% difference. Stop after 1 hour
	exec [StatsOptimize] null,10,100,'Y','N',3600,'N'

	--Stats Updates just in dbo Schema
	exec [StatsOptimize] @Tables='dbo.%' ,@StatisticsModificationLevel =null, @StatisticsSample=null, @OnlyModifiedStatistics=null,@DeleteOverlappingStats=null,@TimeLimit=null,@Execute='N'
	
	--Only Delete Overlapping Statistics
	exec dbo.[StatsOptimize] null,null,null,'N','Y',null,'N'

	--Force Update of All Stats in STG Schema
	exec dbo.[StatsOptimize] 'stg.%',0,null,null,null,null,null

History:		12/08/2021 Bob, Created
				31/08/2021 Bob, Added Adaptive SamplingRate. Fixerd bug in removing duplicate stats (null stats name)
*/

--Default Parameters (Synapse cant do default parameters at declaration)
SELECT @Tables =coalesce(@Tables,'ALL')
	, @OnlyModifiedStatistics =coalesce(@OnlyModifiedStatistics,'Y')
	, @StatisticsModificationLevel=coalesce(@StatisticsModificationLevel,null) --Default ius to sue new SQRT algorithm
	, @StatisticsSample =coalesce(@StatisticsSample,null)
	, @DeleteOverlappingStats =coalesce(@DeleteOverlappingStats,'N')
	, @Execute=coalesce(@Execute,'Y')
	
  SET NOCOUNT ON
  SET ARITHABORT ON
  SET NUMERIC_ROUNDABORT OFF

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @DatabaseMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)
  DECLARE @Severity int
  DECLARE @Parameters nvarchar(max)
  DECLARE @EmptyLine nvarchar(max) = CHAR(9)
  DECLARE @CurrentCommand nvarchar(max)
  DECLARE @CurrentMessage nvarchar(max)
  DECLARE @CurrentSeverity int
  DECLARE @CurrentState int
  DECLARE @Version numeric(18,10) = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))
  DECLARE @ID int
	, @LastID int
	, @object_id int
	, @schema_name sysname
	, @table_name sysname
	, @stats_row_count bigint
	, @actual_row_count bigint
	, @stats_difference_percent numeric (10,4)
	, @sqlCommand nvarchar(4000)
	, @UpdateLevel bigint
	, @ExtendedInfo nvarchar(4000)
	, @DatabaseName sysname =db_name()
	, @StartTime datetime
	, @EndTime datetime
	, @LogID int
	, @Error int
	, @ProcStartTime datetime
	, @Duration int
	, @StatisticsName sysname

  IF OBJECT_ID('tempdb.dbo.#Errors') is not null DROP TABLE #Errors
  CREATE TABLE #Errors (ID int IDENTITY,
                         [Message] nvarchar(max) NOT NULL,
                         Severity int NOT NULL,
                         [State] int) WITH (DISTRIBUTION=ROUND_ROBIN, HEAP)
  
  IF OBJECT_ID('tempdb.dbo.#rsStats') is not null DROP TABLE #rsStats
  CREATE TABLE #rsStats (ID int IDENTITY 
						, object_id int not null
						, schema_name sysname not null
						, table_name sysname not null
						, stats_name sysname not null
						, stats_row_count bigint null
						, actual_row_count bigint null
						, stats_difference_percent numeric (10,2) null
						, SqlCommand nvarchar(4000) not null
						, UpdateLevel bigint
						, ExtendedInfo nvarchar(4000) not null) WITH (DISTRIBUTION=ROUND_ROBIN, HEAP)
				

	  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------
  SET @Parameters = '@Tables= ' + ISNULL('''' + REPLACE(@Tables,'''','''''') + '''','ALL')
  SET @Parameters += ', @OnlyModifiedStatistics = ' + ISNULL('''' + REPLACE(@OnlyModifiedStatistics,'''','''''') + '''','NULL')
  SET @Parameters += ', @StatisticsModificationLevel = ' + ISNULL(CAST(@StatisticsModificationLevel AS nvarchar),'NULL')
  SET @Parameters += ', @StatisticsSample = ' + ISNULL(CAST(@StatisticsSample AS nvarchar),'NULL')
  SET @Parameters += ', @DeleteOverlappingStats = ' + ISNULL(CAST(@DeleteOverlappingStats AS nvarchar),'NULL')
  SET @Parameters += ', @TimeLimit = ' + ISNULL(CAST(@TimeLimit AS nvarchar),'NULL')
  SET @Parameters += ', @Execute = ' + ISNULL(CAST(@Execute AS nvarchar),'NULL')

  SET @StartMessage = 'Date and time: ' + CONVERT(nvarchar,getdate(),120)
  RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT

  SET @StartMessage = 'Server: ' + CAST(SERVERPROPERTY('ServerName') AS nvarchar(max))
  RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT

  SET @StartMessage = 'Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))
  RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT

  SET @StartMessage = 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(max))
  RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT

  SET @StartMessage = 'Parameters: ' + @Parameters
  RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT

  SET @StartMessage = 'Version: ' + @@version
  RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT

  SET @StartMessage = 'Source: https://github.com/ProdataSQL/SynapseTools/tree/main/SqlPools/Maintenance'
  RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT

  RAISERROR(@EmptyLine,10,1) WITH NOWAIT


  IF object_id ('dbo.vTableStats','V') is null 
   BEGIN
    INSERT INTO #Errors ([Message], Severity, [State])
    SELECT 'The View [vTableStats is required. Please download/install this.', 16, 1
  END  
  ----------------------------------------------------------------------------------------------------
  IF @OnlyModifiedStatistics NOT IN('Y','N') OR @OnlyModifiedStatistics IS NULL
  BEGIN
    INSERT INTO #Errors ([Message], Severity, [State])
    SELECT 'The value for the parameter @OnlyModifiedStatistics is not supported.', 16, 1
  END

  ----------------------------------------------------------------------------------------------------

  IF @StatisticsModificationLevel < 0 OR @StatisticsModificationLevel > 100
  BEGIN
    INSERT INTO #Errors ([Message], Severity, [State])
    SELECT 'The value for the parameter @StatisticsModificationLevel is not supported.', 16, 1
  END

  ----------------------------------------------------------------------------------------------------

  IF @StatisticsSample <= 0 OR @StatisticsSample  > 100
  BEGIN
    INSERT INTO #Errors ([Message], Severity, [State])
    SELECT 'The value for the parameter @StatisticsSample is not supported.', 16, 1
  END

  IF @TimeLimit < 0
  BEGIN
    INSERT INTO #Errors ([Message], Severity, [State])
    SELECT 'The value for the parameter @TimeLimit is not supported.', 16, 1
  END

  ----------------------------------------------------------------------------------------------------
  --// Raise errors                                                                               //--
  ----------------------------------------------------------------------------------------------------
  SELECT TOP 1  @CurrentMessage =Message, @CurrentSeverity=Severity, @CurrentState=State
  FROM #Errors 

  IF @CurrentMessage is not null
  BEGIN
	SELECT * FROM #Errors
	RAISERROR('%s', @CurrentSeverity, @CurrentState, @CurrentMessage) WITH NOWAIT
    RAISERROR(@EmptyLine, 10, 1) WITH NOWAIT
  END


  /* Select Objects for Inclusion in Scan based on "Table" level Stats */
  ;With Param1 as (
		SELECT CASE WHEN left(ltrim(ss.value),1) IN ('+','-') THEN left(ltrim(ss.value),1) else '+' end  as Op
		, CASE WHEN left(ltrim(ss.value),1) IN ('+','-') THEN substring(ltrim(ss.value),2,4000) else ltrim(ss.value) END as [Object]
		FROM string_split(@Tables,',') ss
	),
	Param2 as (
		SELECT ss.Op
		, case when charindex ('.', ss.Object) > 0 then left( ss.Object,charindex ('.', ss.Object) -1) else '%' END as [Schema]
		, case when charindex ('.', ss.Object) > 0 then substring( ss.Object,charindex ('.', ss.Object)+1, 4000) else case when ss.Object like 'ALL%' then '%' else ss.object END END as [Object]
		FROM Param1 ss
	), Param3 as (
		SELECT ss.Op, ss.[Schema]
		, case when charindex ('.', ss.Object) > 0 then left( ss.Object,charindex ('.', ss.Object)-1) else case when ss.Object like 'ALL%' then '%' else ss.object END END as [Table]
		, case when charindex ('.', ss.Object) > 0 then substring( ss.Object,charindex ('.', ss.Object)+1, 4000) else null END as [Column]
		FROM Param2 ss
	)
	, ParamTables as (
		select t.object_id, s.name as [Schema], t.name as [Table]
		FROM Param3 p
		CROSS JOIN sys.tables t 
		INNER JOIN sys.schemas s on s.schema_id =t.schema_id
		WHERE t.type='U'  and is_external=0 
		and ( s.name like p.[schema] AND t.name like p.[Table] )
		AND (p.[Column] is null or p.[Column]='%')
		GROUP BY t.object_id , s.name, t.name, p.[Column]
		having max(p.Op) ='+'
	), ParamColumns as (
		select t.object_id, s.name as [Schema], t.name as [Table], c.name as [Column]
		FROM Param3 p
		CROSS JOIN sys.tables t 
		INNER JOIN sys.schemas s on s.schema_id =t.schema_id
		INNER JOIN sys.columns c on c.object_id=t.object_id
		WHERE t.type='U'  and is_external=0 
		and ( s.name like p.[schema] AND t.name like p.[Table] )
		AND (p.[Column] <> '%' and p.[Column] is not null)
		AND c.name like p.[Column]
		GROUP BY t.object_id , s.name, t.name, c.name
		having max(p.Op) ='+'
	) 
	INSERT INTO #rsStats (object_id, schema_name, table_name, stats_name, stats_row_count, actual_row_count, stats_difference_percent, SqlCommand, UpdateLevel, ExtendedInfo)
	/* Table Level Stats Management (Recommended) */
	SELECT * FROM (
		SELECT TOP 1000000 s.[object_id], s.[schema_name], s.[table_name], 'ALL' as stats_name, s.[stats_row_count], s.[actual_row_count], s.[stats_difference_percent]
		, 'UPDATE STATISTICS ' + quotename(s.[schema_name]) + '.' + quotename(s.[table_name]) 
		+ coalesce(case when coalesce(@StatisticsSample , s.[stats_sample_rate]) =100 THEN ' WITH FULLSCAN' ELSE  ' WITH SAMPLE ' + convert(varchar,coalesce(@StatisticsSample , s.[stats_sample_rate]))  + ' PERCENT' END,'')
		as SqlCommand
		, convert(bigint,SQRT(1000 * s.[actual_row_count]))  as UpdateLevel
		,'<ExtendedInfo><StatsRowCount>' + convert (varchar, s.stats_row_count) + '</StatsRowCount><ActualRowCount>' + convert (varchar, s.actual_row_count) + '</ActualRowCount><UpdateLevel>' + convert (varchar,convert(bigint,SQRT(1000 * s.[actual_row_count])))  + '</UpdateLevel></ExtendedInfo>' as ExtendedInfo
		FROM dbo.vTableStats s
		INNER JOIN ParamTables p on p.object_id=s.object_id 
		WHERE (@OnlyModifiedStatistics ='Y' and (
			( s.stats_difference_percent >= @StatisticsModificationLevel and s.stats_difference_percent>0) 
			OR (abs( [actual_row_count]- [stats_row_count]) >=  SQRT(1000 * s.[actual_row_count])  and s.[actual_row_count] > 0 )
			)
		)
		ORDER BY s.[schema_name], s.[table_name]
		UNION ALL 
			SELECT TOP 1000000 s.[object_id], s.[schema_name], s.[table_name], s.stat_name as stats_name, s.[stats_row_count], s.[actual_row_count], s.[stats_difference_percent]
		, 'UPDATE STATISTICS ' + quotename(s.[schema_name]) + '.' + quotename(s.[table_name]) + '(' + s.stat_name + ')'
		+ coalesce(case when coalesce(@StatisticsSample , s.[stats_sample_rate]) =100 THEN ' WITH FULLSCAN' ELSE  ' WITH SAMPLE ' + convert(varchar,coalesce(@StatisticsSample , s.[stats_sample_rate]))  + ' PERCENT' END,'')
		as SqlCommand
		, convert(bigint,SQRT(1000 * s.[actual_row_count]))  as UpdateLevel
		,'<ExtendedInfo><StatsRowCount>' + convert (varchar, s.stats_row_count) + '</StatsRowCount><ActualRowCount>' + convert (varchar, s.actual_row_count) + '</ActualRowCount><UpdateLevel>' + convert (varchar,convert(bigint,SQRT(1000 * s.[actual_row_count])))  + '</UpdateLevel><Columns>' + s.stat_columns + '</Columns></ExtendedInfo>' as ExtendedInfo
		FROM dbo.vStats s
		INNER JOIN ParamColumns p on p.object_id=s.object_id and (s.stat_columns like p.[Column] + ',%' or  s.stat_columns =p.[Column])
		WHERE (@OnlyModifiedStatistics ='Y' and (
			( s.stats_difference_percent >= @StatisticsModificationLevel and s.stats_difference_percent>0) 
			OR (abs( [actual_row_count]- [stats_row_count]) >=  SQRT(1000 * s.[actual_row_count])  and s.[actual_row_count] > 0 )
			)
		)
	) a 

	SELECT TOP 1 @ID =ID FROM #rsStats ORDER BY ID 
	SET @ProcStartTime =getdate()
	SET @Duration =0 
	WHILE @ID IS NOT NULL AND (@Duration < @TimeLimit OR @TimeLimit is null)
	BEGIN
		SELECT @LastID =ID
			, @object_id=rs.object_id
			, @schema_name=rs.schema_name
			, @table_name=rs.table_name
			, @stats_row_count=rs.stats_row_count
			, @actual_row_count = rs.actual_row_count
			, @stats_difference_percent=rs.stats_difference_percent
			, @SqlCommand =rs.SqlCommand
			, @UpdateLevel =rs.UpdateLevel
			, @ExtendedInfo =rs.ExtendedInfo
		FROM #rsStats rs
		WHERE rs.ID=@ID
		
		SET @EndMessage = 'Date and time: ' + CONVERT(nvarchar,SYSDATETIME(),120)
		RAISERROR('%s',10,1,@EndMessage) WITH NOWAIT
		SET @StartMessage = 'SqlCommand: ' + @sqlCommand
		RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
		RAISERROR('%s',10,1,@ExtendedInfo) WITH NOWAIT
			
		IF @Execute='Y'
		BEGIN
			SET @StartTime=getdate()
			INSERT INTO dbo.CommandLog (DatabaseName, SchemaName, ObjectName, ObjectType, StatisticsName, ExtendedInfo, Command, StartTime, CommandType)
			VALUES (@DatabaseName, @schema_name, @table_name, 'U', 'ALL',@ExtendedInfo, @SqlCommand, @StartTime,'UPDATE STATISTICS')
		
			SELECT TOP 1 @LogID=ID from dbo.CommandLog ORDER BY StartTime desc 
	
			BEGIN TRY  
				exec (@SqlCommand)
			END TRY  
			BEGIN CATCH
					SET @Error = ERROR_NUMBER()
					SET @ErrorMessage = ERROR_MESSAGE()

					SET @ErrorMessage = 'Msg ' + CAST(ERROR_NUMBER() AS nvarchar) + ', ' + ISNULL(ERROR_MESSAGE(),'')
					UPDATE dbo.CommandLog SET [ErrorNumber]=@Error, ErrorMessage=@ErrorMessage
					WHERE ID=@LogID
					RAISERROR ('%s',16,1,@ErrorMessage) WITH NOWAIT;
			END CATCH
			UPDATE dbo.CommandLog SET EndTime=getdate() WHERE ID=@LogID
		END
		SET @ID=null
		SELECT TOP 1 @ID =ID FROM #rsStats WHERE ID > @LastID ORDER BY ID 	
		SET @Duration=datediff(second,@ProcStartTime, getdate())
	END

	/* Delete Overlapping Statistics */
	IF @DeleteOverlappingStats='Y'
	BEGIN
		TRUNCATE TABLE #rsStats;
		;WITH autostats (
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
		INSERT INTO #rsStats (object_id, schema_name, table_name, stats_name, ExtendedInfo ,SqlCommand )
		SELECT t.object_id
			,s.name AS schema_name
			,t.name AS table_name
			,  autostats.name  as stats_name
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

		SELECT TOP 1 @ID =ID FROM #rsStats ORDER BY ID 
		SET @ProcStartTime =getdate()
		SET @Duration =0 
		WHILE @ID IS NOT NULL AND (@Duration < @TimeLimit OR @TimeLimit is null)
		BEGIN
			SELECT @LastID =ID
				, @object_id=rs.object_id
				, @schema_name=rs.schema_name
				, @table_name=rs.table_name
				, @SqlCommand =rs.SqlCommand
				, @ExtendedInfo =rs.ExtendedInfo
			FROM #rsStats rs
			WHERE rs.ID=@ID

			SET @EndMessage = 'Date and time: ' + CONVERT(nvarchar,SYSDATETIME(),120)
			RAISERROR('%s',10,1,@EndMessage) WITH NOWAIT
			SET @StartMessage = 'SqlCommand: ' + @sqlCommand
			RAISERROR('%s',10,1,@StartMessage) WITH NOWAIT
			RAISERROR('%s',10,1,@ExtendedInfo) WITH NOWAIT

			IF @Execute='Y'
			BEGIN
				SET @StartTime=getdate()
				INSERT INTO dbo.CommandLog (DatabaseName, SchemaName, ObjectName, ObjectType, StatisticsName, ExtendedInfo, Command, StartTime, CommandType)
				VALUES (@DatabaseName, @schema_name, @table_name, 'U', 'ALL',@ExtendedInfo, @SqlCommand, @StartTime,'DROP STATISTICS')
		
				SELECT TOP 1 @LogID=ID from dbo.CommandLog ORDER BY StartTime desc 
	
				BEGIN TRY  
					exec (@SqlCommand)
				END TRY  
				BEGIN CATCH
						SET @Error = ERROR_NUMBER()
						SET @ErrorMessage = ERROR_MESSAGE()

						SET @ErrorMessage = 'Msg ' + CAST(ERROR_NUMBER() AS nvarchar) + ', ' + ISNULL(ERROR_MESSAGE(),'')
						UPDATE dbo.CommandLog SET [ErrorNumber]=@Error, ErrorMessage=@ErrorMessage
						WHERE ID=@LogID
						RAISERROR ('%s',16,1,@ErrorMessage) WITH NOWAIT;
				END CATCH
				UPDATE dbo.CommandLog SET EndTime=getdate() WHERE ID=@LogID
			END
			SET @ID=null
			SELECT TOP 1 @ID =ID FROM #rsStats WHERE ID > @LastID ORDER BY ID 	
			SET @Duration=datediff(second,@ProcStartTime, getdate())
		END

	END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------
  SET @EndMessage = 'Date and time: ' + CONVERT(nvarchar,SYSDATETIME(),120)
  RAISERROR('%s',10,1,@EndMessage) WITH NOWAIT

  RAISERROR(@EmptyLine,10,1) WITH NOWAIT
 
END
GO

