<#
.SYNOPSIS
Synchronizes BoxCollider components with scaled models/dev/box.vmdl renderers.

.DESCRIPTION
S&Box applies the GameObject transform scale to both ModelRenderer and
BoxCollider. For the built-in dev box model, the renderer's local bounds are
50 x 50 x 50 units, so the matching BoxCollider.Scale is also 50,50,50 with a
zero center. Do not write already-scaled world dimensions into BoxCollider.Scale
on scaled GameObjects, or the editor collision outline will appear too large.

By default this scans Assets/scenes/main.scene and Assets/prefabs/environment.
Use -All to audit every .scene and .prefab under Assets. The script is a dry run
unless -Apply is passed.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\sync_box_colliders_to_renderers.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\sync_box_colliders_to_renderers.ps1 -All -Apply
#>

param(
    [string[]]$Path,
    [switch]$All,
    [switch]$Apply,
    [switch]$IncludeTriggers,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$BoxModel = "models/dev/box.vmdl"
$DevBoxSize = 50.0

function ConvertTo-Array($Value) {
    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return $Value
    }

    return @($Value)
}

function Get-JsonPropertyValue($Object, [string]$Name) {
    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function ConvertFrom-VectorString([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parts = $Value.Split(",")
    if ($parts.Count -lt 3) {
        return $null
    }

    return @(
        [double]::Parse($parts[0].Trim(), $InvariantCulture),
        [double]::Parse($parts[1].Trim(), $InvariantCulture),
        [double]::Parse($parts[2].Trim(), $InvariantCulture)
    )
}

function Format-Scalar([double]$Value) {
    $nearestInteger = [math]::Round($Value)
    if ([math]::Abs($Value - $nearestInteger) -lt 0.001) {
        return ([int]$nearestInteger).ToString($InvariantCulture)
    }

    $normalized = [math]::Round($Value, 4)
    if ([math]::Abs($normalized) -lt 0.000001) {
        $normalized = 0
    }

    return $normalized.ToString("0.####", $InvariantCulture)
}

function Format-Vector([double[]]$Vector) {
    return "{0},{1},{2}" -f (Format-Scalar $Vector[0]), (Format-Scalar $Vector[1]), (Format-Scalar $Vector[2])
}

function Get-ExpectedColliderScale([string]$ObjectScale) {
    # BoxCollider.Scale is local to the GameObject. The transform scale is applied
    # afterward, so matching models/dev/box.vmdl means using the model's local
    # 50x50x50 bounds here, not the already-scaled world size.
    return @($DevBoxSize, $DevBoxSize, $DevBoxSize)
}

function Get-GameObjectChildren($GameObject) {
    return ConvertTo-Array (Get-JsonPropertyValue $GameObject "Children")
}

function Get-GameObjectComponents($GameObject) {
    return ConvertTo-Array (Get-JsonPropertyValue $GameObject "Components")
}

function Find-ColliderTargets($GameObject, [string]$ObjectPath, [System.Collections.Generic.List[object]]$Targets, [ref]$ScannedCount) {
    if ($null -eq $GameObject) {
        return
    }

    $name = [string](Get-JsonPropertyValue $GameObject "Name")
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "<unnamed>"
    }

    $currentPath = if ([string]::IsNullOrWhiteSpace($ObjectPath)) { $name } else { "$ObjectPath/$name" }
    $components = Get-GameObjectComponents $GameObject
    $modelRenderer = $components | Where-Object {
        (Get-JsonPropertyValue $_ "Model") -eq $BoxModel
    } | Select-Object -First 1

    if ($null -ne $modelRenderer) {
        $ScannedCount.Value++
        $objectScale = [string](Get-JsonPropertyValue $GameObject "Scale")
        $expectedScale = Get-ExpectedColliderScale $objectScale

        if ($null -ne $expectedScale) {
            $colliders = $components | Where-Object {
                $null -ne (Get-JsonPropertyValue $_ "Center") -and
                $null -ne (Get-JsonPropertyValue $_ "Scale") -and
                $null -eq (Get-JsonPropertyValue $_ "Model")
            }

            foreach ($collider in $colliders) {
                $isTrigger = Get-JsonPropertyValue $collider "IsTrigger"
                if (-not $IncludeTriggers -and $isTrigger -eq $true) {
                    continue
                }

                $colliderGuid = [string](Get-JsonPropertyValue $collider "__guid")
                if ([string]::IsNullOrWhiteSpace($colliderGuid)) {
                    continue
                }

                $oldCenter = [string](Get-JsonPropertyValue $collider "Center")
                $oldScale = [string](Get-JsonPropertyValue $collider "Scale")
                $newCenter = "0,0,0"
                $newScale = Format-Vector $expectedScale

                if ($oldCenter -ne $newCenter -or $oldScale -ne $newScale) {
                    $Targets.Add([pscustomobject]@{
                        ObjectPath = $currentPath
                        ColliderGuid = $colliderGuid
                        OldCenter = $oldCenter
                        NewCenter = $newCenter
                        OldScale = $oldScale
                        NewScale = $newScale
                    }) | Out-Null
                }
            }
        }
    }

    foreach ($child in Get-GameObjectChildren $GameObject) {
        Find-ColliderTargets $child $currentPath $Targets $ScannedCount
    }
}

function Get-RootGameObjects($Document) {
    $prefabRoot = Get-JsonPropertyValue $Document "RootObject"
    if ($null -ne $prefabRoot) {
        return @($prefabRoot)
    }

    return ConvertTo-Array (Get-JsonPropertyValue $Document "GameObjects")
}

function Find-EnclosingObjectRange([string[]]$Lines, [int]$AnchorIndex) {
    $start = -1
    for ($i = $AnchorIndex; $i -ge 0; $i--) {
        if ($Lines[$i] -match "^\s*\{") {
            $start = $i
            break
        }
    }

    if ($start -lt 0) {
        throw "Could not locate JSON object start near line $($AnchorIndex + 1)."
    }

    $depth = 0
    for ($i = $start; $i -lt $Lines.Count; $i++) {
        $depth += ([regex]::Matches($Lines[$i], "\{")).Count
        $depth -= ([regex]::Matches($Lines[$i], "\}")).Count

        if ($depth -eq 0) {
            return @{ Start = $start; End = $i }
        }
    }

    throw "Could not locate JSON object end near line $($AnchorIndex + 1)."
}

function Set-JsonStringPropertyLine([string[]]$Lines, [hashtable]$Range, [string]$PropertyName, [string]$NewValue) {
    for ($i = $Range.Start; $i -le $Range.End; $i++) {
        if ($Lines[$i] -match "^(?<indent>\s*)`"$([regex]::Escape($PropertyName))`"\s*:\s*`"(?<value>[^`"]*)`"(?<comma>,?)\s*$") {
            $Lines[$i] = "{0}`"{1}`": `"{2}`"{3}" -f $Matches.indent, $PropertyName, $NewValue, $Matches.comma
            return $true
        }
    }

    return $false
}

function Apply-ColliderTargets([string]$FilePath, [object[]]$Targets) {
    if ($Targets.Count -eq 0) {
        return 0
    }

    $lines = [System.IO.File]::ReadAllLines($FilePath)

    $changed = 0
    foreach ($target in $Targets) {
        $guidPattern = "^\s*`"__guid`"\s*:\s*`"$([regex]::Escape($target.ColliderGuid))`""
        $guidIndex = -1

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $guidPattern) {
                $guidIndex = $i
                break
            }
        }

        if ($guidIndex -lt 0) {
            throw "Could not find collider $($target.ColliderGuid) in $FilePath."
        }

        $range = Find-EnclosingObjectRange $lines $guidIndex
        $centerChanged = Set-JsonStringPropertyLine $lines $range "Center" $target.NewCenter
        $scaleChanged = Set-JsonStringPropertyLine $lines $range "Scale" $target.NewScale

        if (-not $centerChanged) {
            throw "Could not update Center for collider $($target.ColliderGuid) in $FilePath."
        }

        if (-not $scaleChanged) {
            throw "Could not update Scale for collider $($target.ColliderGuid) in $FilePath."
        }

        $changed++
    }

    [System.IO.File]::WriteAllLines($FilePath, $lines)
    return $changed
}

function Get-TargetFiles {
    if ($All) {
        return Get-ChildItem -Path "Assets" -Recurse -File -Include "*.scene", "*.prefab" |
            Where-Object { $_.FullName -notmatch "\\\.source2\\" } |
            Select-Object -ExpandProperty FullName
    }

    if ($Path -and $Path.Count -gt 0) {
        return $Path | ForEach-Object {
            if ([System.IO.Path]::IsPathRooted($_)) {
                $_
            } else {
                Join-Path (Get-Location) $_
            }
        }
    }

    $defaults = @("Assets/scenes/main.scene")
    $environmentDir = Join-Path (Get-Location) "Assets/prefabs/environment"
    if (Test-Path $environmentDir) {
        $defaults += (Get-ChildItem -Path $environmentDir -Filter "*.prefab" -File | Select-Object -ExpandProperty FullName)
    }

    return $defaults | ForEach-Object {
        if ([System.IO.Path]::IsPathRooted($_)) {
            $_
        } else {
            Join-Path (Get-Location) $_
        }
    }
}

$files = @(Get-TargetFiles | Select-Object -Unique)
if ($files.Count -eq 0) {
    Write-Error "No scene or prefab files matched."
    exit 1
}

$totalScanned = 0
$totalTargets = 0
$totalApplied = 0

foreach ($file in $files) {
    if (-not (Test-Path $file)) {
        Write-Error "File not found: $file"
        exit 1
    }

    $document = Get-Content -Path $file -Raw | ConvertFrom-Json
    $targets = [System.Collections.Generic.List[object]]::new()
    $scanned = 0
    $scannedRef = [ref]$scanned

    foreach ($root in Get-RootGameObjects $document) {
        Find-ColliderTargets $root "" $targets $scannedRef
    }

    $totalScanned += $scannedRef.Value
    $totalTargets += $targets.Count

    if ($targets.Count -gt 0 -and $Apply) {
        $totalApplied += Apply-ColliderTargets $file $targets.ToArray()
    }

    if (-not $Quiet) {
        $relative = Resolve-Path -Path $file -Relative
        if ($targets.Count -eq 0) {
            Write-Host "${relative}: scanned $($scannedRef.Value), no collider changes needed"
        } else {
            $mode = if ($Apply) { "updated" } else { "would update" }
            Write-Host "${relative}: scanned $($scannedRef.Value), $mode $($targets.Count) collider(s)"
            foreach ($target in $targets) {
                Write-Host "  $($target.ObjectPath)"
                Write-Host "    Center: $($target.OldCenter) -> $($target.NewCenter)"
                Write-Host "    Scale:  $($target.OldScale) -> $($target.NewScale)"
            }
        }
    }
}

if ($Apply) {
    Write-Host "Done. Scanned $totalScanned box-renderer object(s); updated $totalApplied collider(s) across $($files.Count) file(s)."
} else {
    Write-Host "Dry run. Scanned $totalScanned box-renderer object(s); $totalTargets collider(s) need updates across $($files.Count) file(s). Re-run with -Apply to write changes."
}
