# Build Syanpsse MaintenanceSolution
# https://github.com/ProdataSQL/SynapseTools
# Compile Individual TSQL Files into one single file
#
$Solution ="MaintenanceSolution.sql"

Set-Location $PSScriptRoot
Copy-Item -Path CommandLog.sql -Destination $Solution
Get-Content -Path vTableStats.sql | Add-Content -Path $Solution
Get-Content -Path vPartitionStats.sql | Add-Content -Path $Solution
Get-Content -Path vStats.sql | Add-Content -Path $Solution
Get-Content -Path vColumnStoreStats.sql | Add-Content -Path $Solution
Get-Content -Path *Optimize.sql | Add-Content -Path $Solution

Write-Host "Done"