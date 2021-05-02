# SynapseTools
Prodata sample scripts and tools for managing Synapse and SQLPools.


## Monitoring
Collection of views and SProcs for helping monitor SQL Pools including
* Requests View. 
Showing  all requests and an analysis of step timing. use this to spot shuffles, movement and other performance issues
* sp_WhoIsActive. A wrapper for the Requests View showing currently runing requests and timing
(Shout out to the much fuller and awesome SQL Engine http://whoisactive.com/ by Adam Machanic )
* sp_WhoWasActive. A wrapper for the Requests View showing historical requests and timing.

