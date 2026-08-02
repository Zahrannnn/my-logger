param([switch]$LibraryOnly)

$ErrorActionPreference = "Stop"

function Get-MyLoggerHome { Join-Path $env:USERPROFILE ".config\my-logger" }

function Get-MyLoggerSettingsPath { Join-Path (Get-MyLoggerHome) "settings.json" }

function Read-MyJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Required file not found: $Path" }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Save-MyJson {
    param([object]$Object, [string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($Object | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Load-MyLoggerSettings {
    $path = Get-MyLoggerSettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Settings not initialized. Settings path: $path"
    }
    Read-MyJson -Path $path
}

function Get-MyLoggerPublicBase   { "http://41.33.149.212:3000/api/v1" }
function Get-MyLoggerInternalBase { "http://10.100.102.6:3000/api/v1"   }

function Test-MyLoggerReachable {
    param([string]$ApiBase)
    try {
        Invoke-WebRequest -Uri "$ApiBase/users/login" -Method Post -ContentType "application/json" -Body '{}' -TimeoutSec 5 -UseBasicParsing -SkipHttpErrorCheck -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}

function Resolve-MyLoggerApiBase {
    param([object]$Settings)

    $publicBase = Get-MyLoggerPublicBase
    if (Test-MyLoggerReachable -ApiBase $publicBase) {
        $Settings.apiBase = $publicBase
        return [pscustomobject]@{
            reachable  = $true
            endpoint   = "public"
            apiBase    = $publicBase
            publicIp   = "41.33.149.212"
            publicPort = 3000
            message    = "API reachable on public IP 41.33.149.212:3000"
        }
    }

    $internalBase = Get-MyLoggerInternalBase
    if (Test-MyLoggerReachable -ApiBase $internalBase) {
        $Settings.apiBase = $internalBase
        return [pscustomobject]@{
            reachable  = $true
            endpoint   = "internal"
            apiBase    = $internalBase
            publicIp   = $null
            publicPort = $null
            message    = "API reachable on internal IP 10.100.102.6:3000 (Egyptian VPN)"
        }
    }

    throw "BACKEND_DOWN: Cannot reach API on public ($publicBase) or internal ($internalBase). Connect to the Egyptian VPN and retry. If still failing, the back-end may be down — contact Ahmed Kamal (Backend Engineer) AKA@corelia.ai or Abdo (Frontend Engineer) AUM@corelia.ai."
}

function Invoke-MyLogin {
    param([object]$Settings)

    $resolved = Resolve-MyLoggerApiBase -Settings $Settings
    $Settings.apiBase = $resolved.apiBase

    $body = @{
        email = [string]$Settings.email
        password = [string]$Settings.password
    } | ConvertTo-Json -Compress

    $uri = "$($Settings.apiBase)/users/login"
    Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body
}

function Invoke-MyApi {
    param(
        [object]$Settings,
        [string]$Token,
        [string]$Path,
        [string]$Method = "GET",
        [object]$Body = $null
    )

    $uri = "$($Settings.apiBase)$Path"
    $headers = @{ Authorization = "Bearer $Token" }
    $params = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        ContentType = "application/json"
    }
    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
    }
    Invoke-RestMethod @params
}

function Get-MyProjects {
    param(
        [object]$Settings,
        [string]$Token
    )
    Invoke-MyApi -Settings $Settings -Token $Token -Path "/projects" -Method "GET"
}

function Get-MyUserActivities {
    param(
        [object]$Settings,
        [string]$Token
    )
    Invoke-MyApi -Settings $Settings -Token $Token -Path "/activities/user/$($Settings.userId)" -Method "GET"
}

function New-MyActivity {
    param(
        [object]$Settings,
        [string]$Token,
        [object]$Activity
    )
    Invoke-MyApi -Settings $Settings -Token $Token -Path "/activities" -Method "POST" -Body $Activity
}

function Update-MyActivity {
    param(
        [object]$Settings,
        [string]$Token,
        [int]$Id,
        [object]$Patch
    )
    Invoke-MyApi -Settings $Settings -Token $Token -Path "/activities/$Id" -Method "PATCH" -Body $Patch
}

function Remove-MyActivity {
    param(
        [object]$Settings,
        [string]$Token,
        [int]$Id
    )
    Invoke-MyApi -Settings $Settings -Token $Token -Path "/activities/$Id" -Method "DELETE"
}

function Convert-LocalToUtcIso {
    param(
        [datetime]$LocalTime,
        [string]$TimeZoneId
    )
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    $utc = [System.TimeZoneInfo]::ConvertTimeToUtc($LocalTime, $tz)
    $utc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

function Get-ProportionalMinutes {
    param(
        [double[]]$Weights,
        [int]$TotalMinutes
    )

    $totalWeight = ($Weights | Measure-Object -Sum).Sum
    if (-not $totalWeight) {
        $Weights = @(1..$Weights.Count | ForEach-Object { 1.0 })
        $totalWeight = ($Weights | Measure-Object -Sum).Sum
    }

    $allocations = for ($i = 0; $i -lt $Weights.Count; $i++) {
        $exact = ($Weights[$i] / $totalWeight) * $TotalMinutes
        [pscustomobject]@{
            Index = $i
            WholeMinutes = [Math]::Floor($exact)
            Fraction = $exact - [Math]::Floor($exact)
        }
    }

    $remaining = $TotalMinutes - (($allocations | Measure-Object -Property WholeMinutes -Sum).Sum)
    foreach ($item in ($allocations | Sort-Object Fraction -Descending | Select-Object -First $remaining)) {
        $item.WholeMinutes++
    }

    @($allocations | Sort-Object Index | ForEach-Object { [int]$_.WholeMinutes })
}

function Build-MyActivityObjects {
    param(
        [object[]]$Items,
        [object]$Settings,
        [string]$DateText,
        [object[]]$ExistingActivities = @(),
        [switch]$LiteralHours
    )

    $tz = [string]($Settings.timezoneId ?? "Egypt Standard Time")
    $start = [string]($Settings.workdayStartLocal ?? "09:00")
    $totalHours = [double]($Settings.totalHours ?? 9)
    $totalMinutes = [int]($totalHours * 60)

    if ($LiteralHours) {
        $minutes = @($Items | ForEach-Object { [int]([double]$_.hours * 60) })
    } else {
        $weights = @($Items | ForEach-Object { if ($_.hours) { [double]$_.hours } else { 1.0 } })
        $minutes = Get-ProportionalMinutes -Weights $weights -TotalMinutes $totalMinutes
    }

    $workdayStart = [datetime]::ParseExact(
        "$DateText $start",
        "yyyy-MM-dd HH:mm",
        [System.Globalization.CultureInfo]::InvariantCulture
    )

    $busy = @()
    foreach ($ex in $ExistingActivities) {
        try {
            $sUtc = [datetime]::Parse(([string]$ex.startTime), $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $eUtc = [datetime]::Parse(([string]$ex.endTime), $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $tzInfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($tz)
            $sLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc($sUtc, $tzInfo)
            $eLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc($eUtc, $tzInfo)
            $busy += [pscustomobject]@{ Start = $sLocal; End = $eLocal }
        } catch { }
    }
    $busy = @($busy | Sort-Object Start)

    $cursor = $workdayStart
    if ($busy.Count -gt 0) {
        $lastEnd = ($busy | ForEach-Object { $_.End } | Measure-Object -Maximum).Maximum
        if ($lastEnd -gt $cursor) { $cursor = $lastEnd }
    }

    $overlaps = {
        param([datetime]$s, [datetime]$e)
        foreach ($b in $busy) {
            if ($s -lt $b.End -and $e -gt $b.Start) { return $true }
        }
        return $false
    }

    $result = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        $dur = $minutes[$i]
        $projectId = if ($item.projectId) { [int]$item.projectId } else { [int]$Settings.defaultProjectId }

        $slotStart = $cursor
        $slotEnd = $slotStart.AddMinutes($dur)

        if ($item.startTimeLocal) {
            try {
                $pinned = [datetime]::ParseExact(
                    "$DateText $([string]$item.startTimeLocal)",
                    "yyyy-MM-dd HH:mm",
                    [System.Globalization.CultureInfo]::InvariantCulture
                )
                $pinnedEnd = $pinned.AddMinutes($dur)
                if (-not (& $overlaps -s $pinned -e $pinnedEnd)) {
                    $slotStart = $pinned
                    $slotEnd = $pinnedEnd
                }
            } catch { }
        }

        $result += [pscustomobject]@{
            userId = [int]$Settings.userId
            projectId = $projectId
            title = [string]$item.title
            startTime = Convert-LocalToUtcIso -LocalTime $slotStart -TimeZoneId $tz
            endTime = Convert-LocalToUtcIso -LocalTime $slotEnd -TimeZoneId $tz
            status = "completed"
            notes = [string]$item.notes
            competencyIds = @()
        }

        $busy += [pscustomobject]@{ Start = $slotStart; End = $slotEnd }
        $cursor = $slotEnd
    }

    $result
}

function Filter-ActivitiesByDate {
    param(
        [object[]]$Activities,
        [string]$DateText,
        [string]$TimeZoneId = "Egypt Standard Time"
    )

    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    $dayStart = [datetime]::ParseExact("$DateText 00:00", "yyyy-MM-dd HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    $dayEnd = $dayStart.AddDays(1)

    @($Activities | Where-Object {
        try {
            $start = [System.TimeZoneInfo]::ConvertTimeFromUtc(
                [datetime]::Parse(([string]$_.startTime), $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal),
                $tz
            )
            $start -ge $dayStart -and $start -lt $dayEnd
        } catch { $false }
    })
}

function Write-MyJsonOut {
    param([object]$Object)
    $Object | ConvertTo-Json -Depth 10 -Compress
}

function Get-MyDayActivitiesJson {
    param(
        [object]$Settings,
        [string]$Token,
        [string]$DateText
    )
    $all = Get-MyUserActivities -Settings $Settings -Token $Token
    $items = @($all.data)
    if ($items.Count -eq 0) { $items = @($all) }
    $tz = [string]($Settings.timezoneId ?? "Egypt Standard Time")
    $dayItems = Filter-ActivitiesByDate -Activities $items -DateText $DateText -TimeZoneId $tz
    @($dayItems | ForEach-Object {
        [pscustomobject]@{
            id = if ($_.id) { [int]$_.id } else { 0 }
            title = [string]$_.title
            notes = [string]$_.notes
            projectId = if ($_.projectId) { [int]$_.projectId } else { 0 }
            startTime = [string]$_.startTime
            endTime = [string]$_.endTime
        }
    })
}

if (-not $LibraryOnly) {
    Write-Error "my-api.ps1 is a library. Dot-source with -LibraryOnly or call specific helper scripts."
}