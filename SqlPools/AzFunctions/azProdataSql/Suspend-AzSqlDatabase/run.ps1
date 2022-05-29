using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

try {
    
    # Write to the Azure Functions log stream.
    Write-Host "PowerShell HTTP trigger Started."

    # Interact with query parameters or the body of the request.
    $ResourceGroupName = $Request.Body.ResourceGroupName
    $ServerName  = $Request.Body.ServerName
    $DatabaseName  = $Request.Body.DatabaseName

    If (!$ResourceGroupName) {$ResourceGroupName =$env:ResourceGroupName}
    If (!$ServerName ) {$ServerName  =$env:ServerName }
    If (!$DatabaseName ) {$DatabaseName  =$env:DatabaseName }

    Write-Host "$ServerName =" + $env:ServerName 
    Write-Host "$DatabaseName =" + $env:DatabaseName 
    

    $body=Suspend-AzSqlDatabase -ServerName $ServerName -DatabaseName $DatabaseName -ResourceGroupName $ResourceGroupName 

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $body
    })

}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::ExpectationFailed
        Body = $error[0].ToString() + $error[0].InvocationInfo.PositionMessage
    })
        
}


