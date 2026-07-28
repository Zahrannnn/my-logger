param(
    [string]$Intent = "save",
    [string]$ConfigJSON
)

$ErrorActionPreference = "Stop"
$apiScript = Join-Path $PSScriptRoot "my-api.ps1"
. $apiScript -LibraryOnly

if ($Intent -eq "template") {
Write-MyJsonOut -Object ([pscustomobject]@{
    apiBase = "http://your-server:3000/api/v1"
    email = ""
    password = ""
    role = ""
    userId = 0
    defaultProjectId = 0
    defaultProjectName = ""
    projects = @()
    totalHours = 9
    workdayStartLocal = "09:00"
    workdayEndLocal = "18:00"
    timezoneId = "UTC"
    maxActivities = 3
    fillerProjectId = 0
})
    return
}

if (-not $ConfigJSON) { throw "ConfigJSON required." }

$config = $ConfigJSON | ConvertFrom-Json

if (-not $config.email -or -not $config.password -or -not $config.apiBase) {
    throw "email, password, and apiBase are required."
}

$bootSettings = [pscustomobject]@{
    apiBase = $config.apiBase
    email = $config.email
    password = $config.password
    role = [string]($config.role ?? "")
    userId = 0
    defaultProjectId = 0
    defaultProjectName = ""
    projects = @()
    totalHours = [double]($config.totalHours ?? 9)
    workdayStartLocal = [string]($config.workdayStartLocal ?? "09:00")
    workdayEndLocal = [string]($config.workdayEndLocal ?? "18:00")
    timezoneId = [string]($config.timezoneId ?? "UTC")
    maxActivities = [int]($config.maxActivities ?? 3)
    fillerProjectId = [int]($config.fillerProjectId ?? 0)
}

$loginResponse = Invoke-MyLogin -Settings $bootSettings
$token = $loginResponse.data.token
if (-not $token) { throw "Login failed. No token returned." }

if ($loginResponse.data.user -and $loginResponse.data.user.id) {
    $bootSettings.userId = [int]$loginResponse.data.user.id
} elseif ($config.userId) {
    $bootSettings.userId = [int]$config.userId
} else {
    throw "userId not found in login response and not provided."
}

$projectsResponse = Get-MyProjects -Settings $bootSettings -Token $token
$allProjects = @($projectsResponse.data)
if ($allProjects.Count -eq 0) { $allProjects = @($projectsResponse) }

$projects = @($allProjects | ForEach-Object {
    [pscustomobject]@{
        id = if ($_.id) { [int]$_.id } else { 0 }
        name = if ($_.name) { [string]$_.name } else { [string]$_.title }
    }
})

if ($projects.Count -gt 0) {
    $bootSettings.projects = $projects
    $bootSettings.defaultProjectId = $projects[0].id
    $bootSettings.defaultProjectName = $projects[0].name
}

$path = Get-MyLoggerSettingsPath
Save-MyJson -Object $bootSettings -Path $path

Write-MyJsonOut -Object ([pscustomobject]@{
    ok = $true
    settingsPath = $path
    userId = $bootSettings.userId
    defaultProjectId = $bootSettings.defaultProjectId
    defaultProjectName = $bootSettings.defaultProjectName
    projects = $bootSettings.projects
})