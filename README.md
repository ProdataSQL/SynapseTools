# SynapseTools
## Welcome
Welcome to the [Prodata](https://www.prodata.ie) open source library for dedicated SQL Pool maintenance and monitoring. The code contained here is open source/free with no warranty or support implied. Feel free to ping me bob@prodata.ie if you found it useful.


## Getting Started
* Install Maintenance Solution from [MaintenanceSolution.sql](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Maintenance/MaintenanceSolution.sql)
* View [Maintenance Source Code](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Maintenance)
* View [Monitoring Source Code](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Monitoring)

Click on one of the above linkes ot get started or you can read more details, syntax and example from the below  section


## SQL Pool Maintenance Solution
Goto [Maintenance](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Maintenance) for details on the Synapse SQL Pool maintenance solutiuon for Columnstore and Statistics maintenance.
https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Maintenance

This solution will help automate daily/weekly maintenance in a simialr syntax to the ubiquitous  [Ola Hallogren SQL Maintenance Solution](https://ola.hallengren.com/), but for SQL dedicated Pools.

Note that maintenance on Synapse SQL Pools is very different than the traditional DB Engine due to scale out archietcture and less DMVs exposed to track usage.


## SQL Pool Monitoring
Selection of sample stored procedures to help with SQL Pool monitoring based on the SQL Pool DMVs and the awesome  [sp_WhoIsActive](http://whoisactive.com/) from [Adam machanic](http://dataeducation.com/about/). Albeit a lot more limited due to restrictions in SQL Pool DMVs.

https://github.com/ProdataSQL/SynapseTools/tree/main/SqlPools/Monitoring

Views and SProcs include
* [Requests](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Monitoring/Requests.sql) View. 
Showing  all requests and an analysis of step timing. use this to spot shuffles, movement and other performance issues
* [sp_WhoIsActive](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Monitoring/sp_WhoIsActive.sql). A wrapper for the Requests View showing currently running requests and timing
* [sp_WhoWasActive](https://github.com/ProdataSQL/SynapseTools/blob/main/SqlPools/Monitoring/sp_WhoWasActive.sql). A wrapper for the Requests View showing historical requests and timing.






