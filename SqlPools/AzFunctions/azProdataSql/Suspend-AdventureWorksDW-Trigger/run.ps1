# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Interact with query parameters or the body of the request.
$ServerName   = $Request.Body.ServerName
$DatabaseName  = $Request.Body.DatabaseName

If (!$ServerName ) {$ServerName =$env:ServerName }
If (!$DatabaseName ) {$DatabaseName  =$env:DatabaseName }

Write-Host "ServerName =" + $ServerName 
Write-Host "DatabaseName =" + $DatabaseName 

Suspend-AzSynapseSqlPool -WorkspaceName $ServerName -Name $DatabaseName  
    

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"
