using namespace System.Net



$Request ="{DatabaseName:SwatDW,ServerName:swat-dev.database.windows.net,ResourceGroupName:swat-dev-rg}"

.\azProdataSql\Suspend-AzSqlDatabase\run.ps1 $Request, 

