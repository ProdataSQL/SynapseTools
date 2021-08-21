/****** Object:  StoredProcedure [admin].[StatsOptimize]    Script Date: 13/08/2021 17:22:32 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[StatsOptimize]
@Tables varchar(4000)				-- Exclude or only include certain TABLES. Example 'ALL_INDEXES, -dbo.OrderStatus' ,'ThisTable, ThatTable'
,@StatisticsModificationLevel int	-- Specify a percentage of modified rows for when the statistics should be updated. Statistics will also be updated when the number of modified rows has reached a decreasing, dynamic threshold, SQRT(number of rows * 1000).
,@StatisticsSample int				-- Indicate, as a percentage, how much of a table is gathered when updating statistics. A value of 100 is equivalent to a full scan. If no value is specified, then SQL Server automatically computes the required sample.
									-- as per new intelligent method SQRT(1000 * Table rows)
,@OnlyModifiedStatistics char(1)	-- Y (default) Update statistics only if any rows have been modified since the most recent statistics update.
,@DeleteOverlappingStats char(1)	-- Y (default) is a flag to delete any overlapping statistics such as single column stats where there is also another multi columnn stats with that as first column
,@TimeLimit int						-- Time Limit on Seconds. After this no more updates are issued, but any in progress will finish. Eg 3600 seconds =1 Hour
,@Execute char(1)					-- IF 'N' WILL not execute but just show the commands
AS
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
	exec [StatsOptimize] @Tables'ALL,-FactFinance', ,@StatisticsModificationLevel=5, @StatisticsSample=null, @DeleteOverlappingStats ='N',@Exdcute='Y'

	--Stats Updates with FULL Sample (no missing or de-dupe), only if > 10% difference. Stop after 1 hour
	exec [StatsOptimize] null,10,100,'Y','N',3600,'Y'

	--Stats Updates just in dbo Schema
	exec [StatsOptimize] @Tables='dbo.%' ,@StatisticsModificationLevel =null, @StatisticsSample=null, @OnlyModifiedStatistics=null,@DeleteOverlappingStats=null,@TimeLimit=null,@Execute=null
	
	--Only Delete Overlapping Statistics
	exec dbo.[StatsOptimize] null,null,null,'N','Y',null,null

	--Force Update of All Stats in STG Schema
	exec dbo.[StatsOptimize] 'stg.%',0,null,null,null,null,null

History:		12/08/2021 Bob, Created
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

  
  /* Select Objects for Inclusion in Scan*/
  ;With Param1 as (
		SELECT CASE WHEN left(ltrim(ss.value),1) IN ('+','-') THEN left(ltrim(ss.value),1) else '+' end  as Op
		, CASE WHEN left(ltrim(ss.value),1) IN ('+','-') THEN substring(ltrim(ss.value),2,4000) else ltrim(ss.value) END as [Object]
		FROM string_split(@Tables,',') ss
	),
	Param2 as (
		SELECT ss.Op
		, case when charindex ('.', ss.Object) > 0 then left( ss.Object,charindex ('.', ss.Object) -1) else '%' END as [Schema]
		, case when charindex ('.', ss.Object) > 0 then substring( ss.Object,charindex ('.', ss.Object)+1, 4000) else case when ss.Object like 'ALL%' then '%' else ss.object END END as [Table]
		FROM Param1 ss
	)
	, Param3 as (
	select t.object_id, s.name as [Schema], t.name as [Table] 
		FROM Param2 p
		CROSS JOIN sys.tables t 
		INNER JOIN sys.schemas s on s.schema_id =t.schema_id
		WHERE t.type='U'  and is_external=0 
		and ( s.name like p.[schema] AND t.name like p.[Table] )
		GROUP BY t.object_id , s.name, t.name
		having max(p.Op) ='+'
	)
	INSERT INTO #rsStats (object_id, schema_name, table_name, stats_row_count, actual_row_count, stats_difference_percent, SqlCommand, UpdateLevel, ExtendedInfo)
	SELECT TOP 1000000 s.[object_id], s.[schema_name], s.[table_name],  s.[stats_row_count], s.[actual_row_count], s.[stats_difference_percent]
	, 'UPDATE STATISTICS ' + quotename(s.[schema_name]) + '.' + quotename(s.[table_name]) 
	+ coalesce(case when @StatisticsSample =100 THEN ' WITH FULLSCAN' ELSE  ' WITH SAMPLE ' + convert(varchar,@StatisticsSample)  + ' PERCENT' END,'')
	as SqlCommand
	, convert(bigint,SQRT(1000 * s.[actual_row_count]))  as UpdateLevel
	,'<ExtendedInfo><StatsRowCount>' + convert (varchar, s.stats_row_count) + '</StatsRowCount><ActualRowCount>' + convert (varchar, s.actual_row_count) + '</ActualRowCount><UpdateLevel>' + convert (varchar,convert(bigint,SQRT(1000 * s.[actual_row_count])))  + '</UpdateLevel></ExtendedInfo>' as ExtendedInfo
	FROM dbo.vTableStats s
	INNER JOIN Param3 p on p.object_id=s.object_id
	WHERE (@OnlyModifiedStatistics ='Y' and (
		( s.stats_difference_percent >= @StatisticsModificationLevel) 
		OR (abs( [actual_row_count]- [stats_row_count]) >=  SQRT(1000 * s.[actual_row_count])  and s.[actual_row_count] > 0 )
		)
	)
	ORDER by s.schema_name, s.table_name

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
		INSERT INTO #rsStats (object_id, schema_name, table_name,  ExtendedInfo ,SqlCommand )
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
	--exec [StatsOptimize]  null ,1,null,'Y','N',3600,'N'


		exec dbo.[StatsOptimize] null,null,null,'N','Y',null,null



	-- select * from CommandLog where StatisticsName is not null




