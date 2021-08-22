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
		+  CASE WHEN cs.[fragmentation_deletes] >  @DeleteThreshold  and @DeleteThreshold  >= 0 then 'REBUILD ' + coalesce(' PARTITION=' + convert(varchar,cs.partition_number) ,'') 
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
		OR (cs.[fragmentation_deletes] >  @DeleteThreshold  and @DeleteThreshold  > -1)
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