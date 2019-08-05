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

foreach ($change in $responseResourceChanges.value ) {
write-host "change: $change"    
if ($change.changeId) {
    # Body Change Details
    $bodyHashTableResourceChangeDetails = @{
        resourceId = $resourceID 
        changeId = $change.changeId
    }
    
    $bodyJsonResourceChangeDetails = $bodyHashTableResourceChangeDetails |ConvertTo-Json
    # Change details API
    $restUriResourceChangeDetails = "https://management.azure.com/providers/Microsoft.ResourceGraph/resourceChangeDetails?api-version=2018-09-01-preview"
    # invoke
    $responseResourceChangeDetails = Invoke-RestMethod -Uri $restUriResourceChangeDetails -Method Post -Body $bodyJsonResourceChangeDetails -Headers $authHeader 
}  
$changeBefore = $responseResourceChangeDetails.beforeSnapshot.content |ConvertTo-Json
$changeAfter = $responseResourceChangeDetails.afterSnapshot.content |ConvertTo-Json


#compare-object -ReferenceObject $responseResourceChangeDetails.beforeSnapshot.content -DifferenceObject $responseResourceChangeDetails.afterSnapshot.content -IncludeEqual


$changeBefore > a.txt
$changeAfter > b.txt
$checkA = get-content a.txt
$checkB = get-content b.txt
$checkA = $checkA |Where-Object {$_ -notmatch 'lastModifiedTimeUtc'}
$checkB = $checkB |Where-Object {$_ -notmatch 'lastModifiedTimeUtc'}

# Compare changes

if ($change.changeId){
    Write-Host "Detected change on resource: $resourceID"
    
    $changes += (Compare-Object -ReferenceObject $checkB -DifferenceObject $checkA -PassThru) + "`n"
    #|format-table @{L='Change Details';E={$_.InputObject}}
}


$output = $changes
}

if ($resourceID) {
    $status = [HttpStatusCode]::OK
    $body = "$output"
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
