param(
    [string]$Intent = "gather",
    [string]$PlanJSON,
    [string]$Date,
    [string]$HolidaysCSV
)

$ErrorActionPreference = "Stop"
$apiScript = Join-Path $PSScriptRoot "my-api.ps1"
. $apiScript -LibraryOnly

$settings = Load-MyLoggerSettings
$loginResponse = Invoke-MyLogin -Settings $settings
$token = $loginResponse.data.token
if (-not $token) { throw "Login failed." }

if ($Intent -eq "helpme") {
    $tz = [string]($settings.timezoneId ?? "Egypt Standard Time")
    $tzInfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($tz)
    $todayLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tzInfo).Date
    $sundayOffset = ([int]$todayLocal.DayOfWeek + 6) % 7
    $weekStart = $todayLocal.AddDays(-$sundayOffset)

    $workdayNames = @("Sunday","Monday","Tuesday","Wednesday","Thursday")
    $holidays = @()
    if ($HolidaysCSV) { $holidays = @($HolidaysCSV -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $totalHours = [double]($settings.totalHours ?? 9)
    $totalMinutes = [int]($totalHours * 60)

    $days = @()
    for ($d = 0; $d -lt 5; $d++) {
        $day = $weekStart.AddDays($d)
        $dateText = $day.ToString("yyyy-MM-dd")
        if ($holidays -contains $dateText) {
            $days += [pscustomobject]@{
                date = $dateText
                dayName = $workdayNames[$d]
                holiday = $true
                hoursLogged = 0
                gap = 0
                hasMeeting = $false
            }
            continue
        }

        $existing = Get-MyDayActivitiesJson -Settings $settings -Token $token -DateText $dateText
        $minutesLogged = 0
        $hasMeeting = $false
        foreach ($a in $existing) {
            try {
                $sUtc = [datetime]::Parse($a.startTime, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                $eUtc = [datetime]::Parse($a.endTime, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                $diff = ($eUtc - $sUtc).TotalMinutes
                if ($diff -gt 0 -and $diff -lt 1440) { $minutesLogged += [int]$diff }
            } catch { }
            if ([string]$a.title -match "Weekly\s+Team\s+Meeting|weekly\s+sync|weekly\s+meeting") { $hasMeeting = $true }
        }
        $gapMin = [Math]::Max(0, $totalMinutes - $minutesLogged)
        $days += [pscustomobject]@{
            date = $dateText
            dayName = $workdayNames[$d]
            holiday = $false
            hoursLogged = [Math]::Round($minutesLogged / 60.0, 2)
            gap = [Math]::Round($gapMin / 60.0, 2)
            hasMeeting = $hasMeeting
        }
    }

    Write-MyJsonOut -Object ([pscustomobject]@{
        weekStart = $weekStart.ToString("yyyy-MM-dd")
        role = [string]$settings.role
        defaultProjectId = $settings.defaultProjectId
        fillerProjectId = [int]($settings.fillerProjectId ?? 23)
        totalHours = $totalHours
        days = $days
    })
    return
}

if ($Intent -eq "gather") {
    $projects = Get-MyProjects -Settings $settings -Token $token
    $projectList = @($projects.data)
    if ($projectList.Count -eq 0) { $projectList = @($projects) }

    $targetDate = $Date ?? (Get-Date).ToString("yyyy-MM-dd")
    $existing = Get-MyDayActivitiesJson -Settings $settings -Token $token -DateText $targetDate

    Write-MyJsonOut -Object ([pscustomobject]@{
        settings = [pscustomobject]@{
            userId = $settings.userId
            role = [string]$settings.role
            defaultProjectId = $settings.defaultProjectId
            defaultProjectName = $settings.defaultProjectName
            fillerProjectId = [int]($settings.fillerProjectId ?? 23)
            totalHours = $settings.totalHours
            workdayStartLocal = $settings.workdayStartLocal
            timezoneId = $settings.timezoneId
            maxActivities = $settings.maxActivities
        }
        date = $targetDate
        projects = @($projectList | ForEach-Object {
            [pscustomobject]@{
                id = if ($_.id) { [int]$_.id } else { 0 }
                name = if ($_.name) { [string]$_.name } else { [string]$_.title }
            }
        })
        existing = $existing
    })
    return
}

if ($Intent -eq "post") {
    if (-not $PlanJSON) { throw "PlanJSON required for post intent." }
    $plan = $PlanJSON | ConvertFrom-Json
    $useLiteral = [bool]$plan.literalHours

    $posted = @()
    $failed = @()

    foreach ($day in $plan.days) {
        $dateText = [string]$day.date
        $items = @($day.items)
        if ($items.Count -eq 0) { continue }

        $existing = Get-MyDayActivitiesJson -Settings $settings -Token $token -DateText $dateText
        $activities = Build-MyActivityObjects -Items $items -Settings $settings -DateText $dateText -ExistingActivities $existing -LiteralHours:$useLiteral

        foreach ($activity in $activities) {
            try {
                $resp = New-MyActivity -Settings $settings -Token $token -Activity $activity
                $id = if ($resp.data -and $resp.data.id) { [int]$resp.data.id } else { 0 }
                $posted += [pscustomobject]@{ date = $dateText; responseId = $id }
            } catch {
                $failed += [pscustomobject]@{ date = $dateText; title = $activity.title; error = [string]$_.Exception.Message }
            }
        }
    }

    Write-MyJsonOut -Object @{ posted = $posted; failed = $failed; postedCount = $posted.Count; failedCount = $failed.Count }
    return
}

throw "Unknown intent: $Intent. Use 'gather', 'post', or 'helpme'."