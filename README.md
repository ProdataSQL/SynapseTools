# SynapseTools
Prodata Sample Scripts for Syanpse SQL Pool Maintenance and Monitoring

The Maintenance Scripts support two key SProcs to help maintaing Syanpse SQL Pools <a>ColumnStoreOptimize</a> and StatsOptimize.
These implement best practise maintenance in the same style as the popular [[ola hallogren scripts](https://ola.hallengren.com/) for SQL Server DB Engine. 
Note that maintenance on Synapse SQL Pools is very different than the traditional DB Engine due to scale out archietcture and less DMVs exposed to track usage.


### Getting Started
Download and run [Maintenance Solution](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Maintenance/MaintenanceSolution.sql). This script creates all objects inside your SQL Pool. To run the SProcs create an ADF package, or other way to run the SProc on a schedule or as part of your ETL orchestration

## StatsOptimise
StatsOptimise is stored procedure for updating and other miantenance of Statistics for Synapse SQL Pools based on Best practise guidance from MS sites below and community.
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



## Monitoring
Collection of views and SProcs for helping monitor SQL Pools including
* Requests View. 
Showing  all requests and an analysis of step timing. use this to spot shuffles, movement and other performance issues
* [sp_WhoIsActive](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Monitoring/sp_WhoIsActive.sql). A wrapper for the Requests View showing currently runing requests and timing
(Shout out to the much fuller and awesome SQL Engine http://whoisactive.com/ by Adam Machanic )
* [sp_WhoWasActive](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Monitoring/sp_WhoWasActive.sql). A wrapper for the Requests View showing historical requests and timing.

