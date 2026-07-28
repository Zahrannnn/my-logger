param(
    [string]$Intent = "list",
    [int]$Id,
    [string]$FieldsJSON,
    [string]$Date
)

$ErrorActionPreference = "Stop"
$apiScript = Join-Path $PSScriptRoot "my-api.ps1"
. $apiScript -LibraryOnly

$settings = Load-MyLoggerSettings
$loginResponse = Invoke-MyLogin -Settings $settings
$token = $loginResponse.data.token
if (-not $token) { throw "Login failed." }

$targetDate = $Date ?? (Get-Date).ToString("yyyy-MM-dd")

if ($Intent -eq "list") {
    $existing = Get-MyDayActivitiesJson -Settings $settings -Token $token -DateText $targetDate
    Write-MyJsonOut -Object @{ date = $targetDate; activities = $existing }
    return
}

if ($Intent -eq "patch") {
    if (-not $Id) { throw "Id required for patch intent." }
    if (-not $FieldsJSON) { throw "FieldsJSON required. Provide title, notes, and/or projectId as JSON." }
    $fields = $FieldsJSON | ConvertFrom-Json

    $patch = [pscustomobject]@{}
    if ($fields.title) { $patch | Add-Member -NotePropertyName title -NotePropertyValue ([string]$fields.title) -Force }
    if ($fields.notes) { $patch | Add-Member -NotePropertyName notes -NotePropertyValue ([string]$fields.notes) -Force }
    if ($fields.projectId) { $patch | Add-Member -NotePropertyName projectId -NotePropertyValue ([int]$fields.projectId) -Force }

    $resp = Update-MyActivity -Settings $settings -Token $token -Id $Id -Patch $patch
    Write-MyJsonOut -Object @{ ok = $true; id = $Id; response = $resp.data }
    return
}

if ($Intent -eq "remove") {
    if (-not $Id) { throw "Id required for remove intent." }
    $resp = Remove-MyActivity -Settings $settings -Token $token -Id $Id
    Write-MyJsonOut -Object @{ ok = $true; id = $Id }
    return
}

throw "Unknown intent: $Intent. Use 'list', 'patch', or 'remove'."