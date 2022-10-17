# Maintenance Solution
![image](https://user-images.githubusercontent.com/19823837/196261541-ed86c81c-2b54-4940-9340-d22615f3f4d7.png)

https://www.youtube.com/embed/G73WcVxPNmk


## ColumnstoreOptimize
ColumnstoreOptimize is stored procedure for maintaining columnstore indexes in SQL dedicated Pools. Key features include.
- Automatically determine if REORGANISE or REBUILD requried based on density, open rows and deleted rows.
- Automatically support closin open rowgroups with threshold.
- Automatically support removing deleted rowgs from the delat store based on threshold.
- [Ola Hallogren](https://ola.hallengren.com/) style features such as CommandLog, @Time Limit, and @Table parameer to set scope.

All executed commands are logged to the [CommandLog](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Maintenance/CommandLog.sql) table. 

It is based on Best practise guidance from MS sites below and community.
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-index
- https://github.com/rgl/azure-content/blob/master/articles/sql-data-warehouse/sql-data-warehouse-manage-columnstore-indexes.md 
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-memory-optimizations-for-columnstore-compression
- https://docs.microsoft.com/en-gb/archive/blogs/sqlserverstorageengine/columnstore-index-defragmentation-using-reorganize-command
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/performance-tuning-ordered-cci
- https://github.com/NikoNeugebauer/CISL/blob/master/SQL%20DW/alignment.sql
<BR>

This is an improved and productionised version of the sample view provided by Microsoft (<i>vColumnstoreDensity]</i>) [here](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-index)

### Usage: 
````
exec [dbo].[ColumnstoreOptimize] , @Tables, @DensityThreshold, @OpenThreshold ,@DeleteThreshold, @TimeLimit , @Execute 	
````


#### Parameters

##### @Tables 
Select Tables to be included. The minus character is used to exclude objects and wildcards (%) are also supported as SQL Like clause. Use this to exclude more complex tables, exclude staging, or only include relevant schemas and objects
|--|--|
| Value | Description  |
|--|--|
| Null | All Tables in Pool |
| dbo.% | Tables in dbo schema  |
| %.Fact% | All Fact tables, regardless of Schema |
| %.Fact%,-FactBig | All Fact tables, Except one called FactBig |

#### @DensityThreshold
Default 25%. This is the difference between the avg row size of a compressed row group and the ideal value (1024*1024). If the fragementation density in a target table excludes the specified value, then a REGORGANISE will be issued.

Note: in some cases we may get churn where a table alwasy has a low density, in this case use the view <i>vCS_rg_physical_stats</i> to examine the TRIM reason and consider excluding table or using a higher threshold.

Common TRIM reasons that prevent optimisation:
* MEMORY_LIMITATION is a sign that the job needs to run with more memory. Eg a higher [resource class](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/resource-classes-for-workload-management) such as xlargerc.
* DICTIONARY_SIZE is a sign that a large high cardinality string is taking more than the 16MB allowed. In this case not much cab done without reducing cardinality, or moving columns to a different table. 

See [Maximising rowgroup quality for columnstore indexes in dedicated SQL pool](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-memory-optimizations-for-columnstore-compression)


#### @OpenThreshold
Default 200k. Force a close of open row groups if the number of uncompressed </i>Inserted</i> rows that are in the delta store is > threshold. You can use the view <i>vColumnStoreStats</i> to see how many uncompressed rows are in each table.

Note that the tuple mover will eventually close open rows, but its threshold is very high.

#### @DeleteThreshold
Default 200k. Force a REBUILD (expensive) if the number of deletes rows is greater than the threshold.

Note that the tuple mover will rebuild compressed rowgroups and remove dleeted rows when more than 10% of rows are deleted, but we may want to do earlier and more pro-active maintenance.

#### @TimeLimit 
Default Null or infinite. Set a time limit in seconds for the job to run. No more commands will be started after time limit (but existing ones will finish). Use this if you have a short maintenace windows and do not want to exceed time.

#### @Execute 	
Default Y. Set to N to only show commands but not execute or log them. Useful for seeing experimental maintenance commands before actually executing them.

### Example Usage
Optimise FactFinance table if more than 30% fragmentation. Do not close open row groups or remove deleted rows. Onlt show commnds, do not execute.
```
exec [dbo].[ColumnstoreOptimize]   @Tables= '%.FactFinance',@DensityThreshold=30, @OpenThreshold=-1,@DeleteThreshold=-1,@TimeLimit=null, @Execute ='N'	
```

Do default maintenance on all fact tables except FactBigNasty. Only run for 1 hour
```
exec [dbo].[ColumnstoreOptimize]   @Tables= 'ALL,-FactBigNasty',@DensityThreshold=null, @OpenThreshold=null,@DeleteThreshold=null,@TimeLimit=3600, @Execute =null
```
Do default maintenance only in dbo schema.
```
exec [dbo].[ColumnstoreOptimize]   @Tables= 'dbo.%',@DensityThreshold=null, @OpenThreshold=null,@DeleteThreshold=null,@TimeLimit=3600, @Execute =null
```
Close any open rowgroups in all tables if more than 100k rows. Do not deal with deleted rows or look at density.
```
exec [dbo].[ColumnstoreOptimize]   @Tables= '%.%',@DensityThreshold=-1, @OpenThreshold=100000,@DeleteThreshold=-1,@TimeLimit=null, @Execute =null
```

<HR>

## StatsOptimize
StatsOptimize is stored procedure for updating Statistics for Synapse SQL Pools. This can be critical for SQL Pools as while they support auto create of stats they do not support auto updte of statistics. This procedure is like a replacement for auto update and allows for more control and flexibility.

Key features include:
- Dynamic determine modification level based on imporved algorithm.
- Dynamically determine sampling level or support setting sample level.
- Support removal of duplicate statistics (covering same column).
- [Ola Hallogren](https://ola.hallengren.com/) style features such as CommandLog, @Time Limit, and @Table parameer to set scope.

All executed commands are logged to the [CommandLog](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Maintenance/CommandLog.sql) table. 

It is based on Best practise guidance from MS sites below and community.
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/develop-tables-statistics
- https://github.com/abrahams1/Azure_Synapse_Toolbox/tree/master/SQL_Queries/Statistics 
- https://www.sqlskills.com/blogs/tim/when-updating-statistics-is-too-expensive/
- https://www.sqlskills.com/blogs/erin/updating-statistics-with-ola-hallengrens-script/
- https://docs.microsoft.com/en-us/sql/relational-databases/statistics/statistics?view=sql-server-2017 
- https://ola.hallengren.com/


### Usage: 
````
exec [dbo].[StatsOptimize] , @Tables, @StatisticsModificationLevel, @StatisticsSample ,@OnlyModifiedStatistics, @DeleteOverlappingStats, @TimeLimit , @Execute 	
````
#### Parameters

##### @Tables 
Select Tables nd optionally columns to be included. The minus character is used to exclude objects and wildcards (%) are also supported as SQL Like clause. Use this to exclude more complex tables, exclude staging, or only include relevant schemas and objects
|--|--|
| Value | Description  |
|--|--|
| Null | All Tables in Pool |
| dbo.% | Tables in dbo schema  |
| %.Fact% | All Fact tables (prefix of Fact), regardless of Schema |
| %.Fact%,-FactBig | All Fact tables, Except one called FactBig |
| %.%.Date,%.%.AccountKey | ONLY do stats maintenance on Date and AccountKey columns. 

Note that usually we just do stats maintenance at the table level, but there is also support for specifing column(s). This is a special case to support columns that need frequent updates like low cardinatlity incremental values (Eg Business Date) which is recommended by Microsoft [here](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/develop-tables-statistics)

#### @StatisticsModificationLevel
By default the SProc will only update a stat if the number of modified rows is greater than either
- 20% or specified value in parameter
- an Adaptive algorithm of  SQRT(1000 * [row count)] based on improved stats algorithm introduced in SQL 2014 

The SProc uses the view vTableStats to return meta data such as the nuber of rows per table and the number of rows in the statistcis. The main difference between SQL Pools and a traditional SQL Server is that in a SQL Pool we can only track the estimated row count at the the table/partition level and not per statistic. Eg we do not have [sys.dm_db_stats_properties](https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-stats-properties-transact-sql?view=sql-server-ver15) but we do have [pdw_table_distribution_properties](https://docs.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-pdw-table-distribution-properties-transact-sql?view=aps-pdw-2016-au7) with per stat data.

This ommission is largely due to the fact that statistics are per distribution, so it is much more complex to amalgamate and sychronise the set of 60 stat objects. This is also why we have no auto stats for SQL Pools (as of 31/08/2021).


#### @StatisticsSample 
This is the sample rate. if this is null, then the SProc uses an adaptive sample rate 
- sqrt([row count]) *1000/ [row count]*100 

While syanpse uses a default of 20% for the sample rate, there is a recommendation to use about 2% when we reach a billion rows. The adaptive sample rate generates recommendations such as:


| Row Count | Sample %  |
|--|--|
| 1000 | FULLSCAN |
| 100k | FULLSCAN  |
| 1 million | FULLSCAN  |
| 10 million | 31  |
| 100 million | 10 |
| 1 billion | 3 |
| 10 billion+ | 1 |

#### @OnlyModifiedStatistics
Default Y. Set this to N to 

#### @DeleteOverlappingStats
Default N. Set to Y to delete any auto stats which overlap an existing statistic.

#### @TimeLimit 
Default Null or infinite. Set a time limit in seconds for the job to run. No more commands will be started after time limit (but existing ones will finish). Use this if you have a short maintenace windows and do not want to exceed time.

#### @Execute 	
Default Y. Set to N to only show commands but not execute or log them. Useful for seeing experimental maintenance commands before actually executing them.

### Example Usage
Default Best Practise with smart defaults.
```
exec  dbo.[StatsOptimize]  @Tables=null, @StatisticsModificationLevel=null, @StatisticsSample=null ,@OnlyModifiedStatistics=null,@DeleteOverlappingStats=null, @TimeLimit=null , @Execute=null 
```

Update stats in dbo schema except FactBig and use a FULLSCAN if any rows have changed 
```
exec  dbo.[StatsOptimize]  @Tables='dbo.%,-FactBig', @StatisticsModificationLevel=0, @StatisticsSample=100 ,@OnlyModifiedStatistics=null,@DeleteOverlappingStats=null, @TimeLimit=null , @Execute=null 
```

Update all Column Stats based on Columns DateKey or AccountKey
```
exec  dbo.[StatsOptimize]  @Tables='%.%.DateKey,%.%.AccountKey', @StatisticsModificationLevel=0, @StatisticsSample=null ,@OnlyModifiedStatistics=null,@DeleteOverlappingStats=null, @TimeLimit=null , @Execute=null 
```



