# Maintenance Solution


## ColumnstoreOptimize
ColumnstoreOptimize is stored procedure for maintaining columnstore indexes in SQL dedicated Pools. Key features include
- Automatically determine if REORGANISE requried based on density
- Automatically support closin open rowgroups with threshold
- Automatically support removing deleted rowgs from the delat store based on threshold
- [Ola Hallogren](https://ola.hallengren.com/) style features such as CommandLog, Time Limit, and @Table parameer to set scope.

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

## StatsOptimise

StatsOptimise is stored procedure for updating and other maintenance of Statistics for Synapse SQL Pools. Ket features include:


It is based on Best practise guidance from MS sites below and community.
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/develop-tables-statistics
- https://ola.hallengren.com/
- https://github.com/abrahams1/Azure_Synapse_Toolbox/tree/master/SQL_Queries/Statistics 
- https://www.sqlskills.com/blogs/tim/when-updating-statistics-is-too-expensive/
- https://www.sqlskills.com/blogs/erin/updating-statistics-with-ola-hallengrens-script/
- https://docs.microsoft.com/en-us/sql/relational-databases/statistics/statistics?view=sql-server-2017 


### Usage: 
exec [dbo].[StatsOptimize] , @Tables, @StatisticsModificationLevel, @StatisticsSample ,@OnlyModifiedStatistics,@DeleteOverlappingStats, @TimeLimit , @Execute 	

#### Parameters

##### @Tables 

#### @StatisticsModificationLevel

#### @StatisticsSample 

#### @OnlyModifiedStatistics

#### @DeleteOverlappingStats

#### @TimeLimit 

#### @Execute 	





