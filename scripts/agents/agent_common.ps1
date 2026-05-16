$ErrorActionPreference = "Stop"

function Get-AgentProjectRoot {
    param([string]$StartPath = (Get-Location).Path)

    $item = Get-Item -LiteralPath $StartPath
    if (-not $item.PSIsContainer) {
        $item = $item.Directory
    }

    while ($null -ne $item) {
        if (Test-Path -LiteralPath (Join-Path $item.FullName "dronevsplayers.sbproj")) {
            return $item.FullName
        }
        $item = $item.Parent
    }

    throw "Could not find S&Box project root from '$StartPath'."
}

function ConvertTo-AgentRelativePath {
    param(
        [string]$Path,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        $resolvedPath = $Path
        if (Test-Path -LiteralPath $Path) {
            $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
        }

        $rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd("\") + "\"
        $rootUri = New-Object System.Uri($rootPath)
        $pathUri = New-Object System.Uri($resolvedPath)
        $relativeUri = $rootUri.MakeRelativeUri($pathUri).ToString()
        return [System.Uri]::UnescapeDataString($relativeUri).Replace("\", "/")
    }
    catch {
        return $Path.Replace("\", "/")
    }
}

function New-AgentIssue {
    param(
        [ValidateSet("Error", "Warning", "Info")]
        [string]$Severity,
        [string]$Area,
        [string]$Path,
        [string]$Message,
        [string]$Recommendation = ""
    )

    [pscustomobject]@{
        Severity = $Severity
        Area = $Area
        Path = $Path
        Message = $Message
        Recommendation = $Recommendation
    }
}

function Add-AgentIssue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [ValidateSet("Error", "Warning", "Info")]
        [string]$Severity,
        [string]$Area,
        [string]$Path,
        [string]$Message,
        [string]$Recommendation = ""
    )

    $Issues.Add((New-AgentIssue -Severity $Severity -Area $Area -Path $Path -Message $Message -Recommendation $Recommendation))
}

function Read-AgentJson {
    param([string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSON '$Path': $($_.Exception.Message)"
    }
}

function Write-AgentSection {
    param([string]$Title)

    Write-Host ""
    Write-Host "== $Title =="
}

function Write-AgentIssues {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [switch]$ShowInfo
    )

    $visibleIssues = @($Issues | Where-Object { $ShowInfo -or $_.Severity -ne "Info" })
    if ($visibleIssues.Count -eq 0) {
        Write-Host "No blocking issues found."
        return
    }

    foreach ($issue in $visibleIssues) {
        $location = if ([string]::IsNullOrWhiteSpace($issue.Path)) { "" } else { " [$($issue.Path)]" }
        Write-Host "[$($issue.Severity)] $($issue.Area)$location - $($issue.Message)"
        if (-not [string]::IsNullOrWhiteSpace($issue.Recommendation)) {
            Write-Host "  Recommendation: $($issue.Recommendation)"
        }
    }
}

function Get-AgentExitCode {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [switch]$FailOnWarning
    )

    if (@($Issues | Where-Object { $_.Severity -eq "Error" }).Count -gt 0) {
        return 1
    }

    if ($FailOnWarning -and @($Issues | Where-Object { $_.Severity -eq "Warning" }).Count -gt 0) {
        return 1
    }

    return 0
}

function Resolve-AgentResourcePath {
    param(
        [string]$ResourcePath,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($ResourcePath)) {
        return $null
    }

    $normalized = $ResourcePath.Replace("\", "/").TrimStart("/")
    if ($normalized -match "^(https?:|file:|asset:)" -or $normalized -match "\$\{") {
        return $null
    }

    $skipPrefixes = @(
        "models/dev/",
        "models/citizen/",
        "models/effects/",
        "models/sbox_props/",
        "materials/default",
        "materials/dev/",
        "materials/editor/",
        "materials/skybox/",
        "textures/"
    )

    foreach ($prefix in $skipPrefixes) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
    }

    if ($normalized.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $Root $normalized
    }

    $projectPrefixes = @("prefabs/", "models/", "materials/", "sounds/", "scenes/", "ui/")
    foreach ($prefix in $projectPrefixes) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return Join-Path (Join-Path $Root "Assets") $normalized
        }
    }

    return $null
}

function Get-AgentChangedFiles {
    param([string]$Root)

    Push-Location $Root
    try {
        $status = @(git status --short --untracked-files=all 2>$null)
        if ($LASTEXITCODE -ne 0) {
            return @()
        }
    }
    finally {
        Pop-Location
    }

    $files = @()
    foreach ($line in $status) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
            continue
        }

        $statusCode = $line.Substring(0, 2)
        $path = $line.Substring(3).Trim()
        if ($path -match " -> ") {
            $path = ($path -split " -> ")[-1].Trim()
        }

        $files += [pscustomobject]@{
            Status = $statusCode.Trim()
            Path = $path.Replace("\", "/")
        }
    }

    return $files
}

function Get-AgentSboxLogDirectories {
    param([string]$Root)

    $dirs = New-Object System.Collections.Generic.List[string]

    $project = if ([string]::IsNullOrWhiteSpace($Root)) {
        $null
    }
    else {
        Join-Path $Root "Code\dronevsplayers.csproj"
    }

    if ($project -and (Test-Path -LiteralPath $project)) {
        $projectText = Get-Content -LiteralPath $project -Raw
        $matches = [regex]::Matches($projectText, '[A-Z]:[/\\][^"<>|]*?steamapps[/\\]common[/\\]sbox', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($match in $matches) {
            $dirs.Add((Join-Path $match.Value.Replace("/", "\") "logs"))
        }
    }

    $programFiles = [Environment]::GetFolderPath("ProgramFiles")
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    foreach ($base in @($programFiles, $programFilesX86, "D:\SteamLibrary", "C:\SteamLibrary")) {
        if ([string]::IsNullOrWhiteSpace($base)) {
            continue
        }

        if ($base.EndsWith("SteamLibrary", [System.StringComparison]::OrdinalIgnoreCase)) {
            $dirs.Add((Join-Path $base "steamapps\common\sbox\logs"))
        }
        else {
            $dirs.Add((Join-Path $base "Steam\steamapps\common\sbox\logs"))
        }
    }

    return @($dirs | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_)
    } | Select-Object -Unique)
}

function Get-AgentFiles {
    param(
        [string]$Root,
        [string[]]$Include,
        [string[]]$ExcludeDirectoryNames = @(".git", ".sbox", ".tmpbuild", "bin", "obj", "node_modules")
    )

    $allFiles = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue
    $files = @($allFiles | Where-Object {
        $matched = $false
        foreach ($pattern in $Include) {
            if ($_.Name -like $pattern) {
                $matched = $true
                break
            }
        }
        return $matched
    })

    return @($files | Where-Object {
        $full = $_.FullName
        foreach ($name in $ExcludeDirectoryNames) {
            if ($full -match [regex]::Escape("\$name\")) {
                return $false
            }
        }
        return $true
    })
}
