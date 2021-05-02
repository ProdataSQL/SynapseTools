# SynapseTools
PowerShell module to help simplify Azure Data Factory CI/CD processes. This module was created to meet the demand for a quick and trouble-free deployment of an Azure Data Factory instance to another environment.
The main advantage of the module is the ability to publish all the Azure Data Factory service code from JSON files by calling one method. The module supports now:

Creation of Azure Data Factory, if it doesn't exist
Deployment of all type of objects: pipelines, datasets, linked services, data flows, triggers, integration runtimes
Finding the right order for deploying objects (no more worrying about object names)
Built-in mechanism to replace, remove or add the properties with the indicated values (CSV and JSON file formats supported)
Stopping/starting triggers
Dropping objects when not exist in the source (code)
(new!) Optionally can skip deletion of excluded objects
Filtering (include or exclude) objects to be deployed by name 
