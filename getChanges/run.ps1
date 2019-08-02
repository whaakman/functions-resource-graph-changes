using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Get Token through Managed Service Identity
$tokenAuthURI = $env:MSI_ENDPOINT + "?resource=https://management.azure.com&api-version=2017-09-01"
$tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$env:MSI_SECRET"} -Uri $tokenAuthURI

$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $tokenResponse.access_token
}

# Interact with query parameters or the body of the request.
$resourceID = $Request.Query.resourceID
if (-not $resourceID) {
    $resourceID = $Request.Body.resourceID
}

$endTime = (get-date -uformat '+%Y-%m-%dT%H:%M:%S.000Z')
$startTime = (get-date (get-date $endTime).AddHours(-6) -uformat '+%Y-%m-%dT%H:%M:%S.000Z')

# Invoke the REST API
# Body for resource change API
$bodyHashTableResourceChanges = @{
    resourceId = $resourceID 
    interval = @{
        start =  $startTime 
        end = $endTime 
    }
}
$bodyJsonResourceChanges = $bodyHashTableResourceChanges |ConvertTo-Json
# URI Resource changes
$restUriResourceChanges = "https://management.azure.com/providers/Microsoft.ResourceGraph/resourceChanges?api-version=2018-09-01-preview"

# Invoke
$responseResourceChanges = Invoke-RestMethod -Uri $restUriResourceChanges -Method Post -Body $bodyJsonResourceChanges -Headers $authHeader

if ($resourceID) {
    $status = [HttpStatusCode]::OK
    $body = "$responseResourceChanges"
}
else {
    $status = [HttpStatusCode]::BadRequest
    $body = "Please pass a name on the query string or in the request body."
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $body
})
