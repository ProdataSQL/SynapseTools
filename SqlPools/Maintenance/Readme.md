# Maintenance Solution
 [[_TOC_]]

## ColumnstoreOptimize
ColumnstoreOptimize is stored procedure for maintaining column stores based on Best practise guidance from MS sites below and community.
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-index
- https://github.com/rgl/azure-content/blob/master/articles/sql-data-warehouse/sql-data-warehouse-manage-columnstore-indexes.md 
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-memory-optimizations-for-columnstore-compression
- https://docs.microsoft.com/en-gb/archive/blogs/sqlserverstorageengine/columnstore-index-defragmentation-using-reorganize-command
- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/performance-tuning-ordered-cci
- https://github.com/NikoNeugebauer/CISL/blob/master/SQL%20DW/alignment.sql
<BR>

### Usage: 
exec [dbo].[ColumnstoreOptimize] , @Tables, @DensityThreshold, @OpenThreshold ,@DeleteThreshold, @TimeLimit , @Execute 	



#### Parameters

##### @Tables 
Select Tables to be included. The minus character is used to exclude objects and wildcards (%) are also supported as SQL Like clause. Use this to exclude more complex tables, exclude staging, or only include relevant schemas and objects

| Value | Description  |
|--|--|
| Null | All Tables in Pool |
| dbo.% | Tables in dbo schema  |
| %.Fact% | All Fact tables, regardless of Schema |
| %.Fact%,-FactBig | All Fact tables, Except one called FactBig |

#### @DensityThreshold
Default 25%. This is the difference between the avg row size of a compressed row group and the ideal value (1024*1024). If the fragementation density in a target table excludes the specified value, then a REGORGANISE will be issued.

Note: in some cases we may get chrun where a table alwasy has a low density, in this case use the view <i>vCS_rg_physical_stats</i> to examine the TRIM reason
* MEMORY_LIMITATION is a sign that the job needs to run with more memory. Eg a higher [resource class](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/resource-classes-for-workload-management) such as xlargerc.
* DICTIONARY_SIZE is a sign that a large high cardinality string is taking more than the 16MB allowed. In this case not much cab done without reducing cardinality, or moving columns to a different table. 
<BR>
See [Maximising rowgroup quality for columnstore indexes in dedicated SQL pool](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-memory-optimizations-for-columnstore-compression)


#### @OpenThreshold

#### @DeleteThreshold

#### @TimeLimit 

#### @Execute 	


<HR>

## StatsOptimise

StatsOptimise is stored procedure for updating and other maintenance of Statistics for Synapse SQL Pools based on Best practise guidance from MS sites below and community.
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





