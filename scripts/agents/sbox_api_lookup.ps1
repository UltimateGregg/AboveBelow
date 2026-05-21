param(
    [string]$Root = "",
    [string]$Query = "",
    [Alias("Type")]
    [string]$TypeName = "",
    [string]$Member = "",
    [int]$Limit = 20,
    [switch]$Exact,
    [switch]$ShowMembers,
    [switch]$Json
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

function Resolve-SboxApiJsonPath {
    param([string]$ProjectRoot)

    foreach ($candidate in @("API.json", "api.json")) {
        $path = Join-Path $ProjectRoot $candidate
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    return $null
}

function Get-ApiMemberCollections {
    param([object]$ApiType)

    return @(
        [pscustomobject]@{ Kind = "Constructor"; Values = @($ApiType.Constructors) },
        [pscustomobject]@{ Kind = "Method"; Values = @($ApiType.Methods) },
        [pscustomobject]@{ Kind = "Property"; Values = @($ApiType.Properties) },
        [pscustomobject]@{ Kind = "Field"; Values = @($ApiType.Fields) },
        [pscustomobject]@{ Kind = "Event"; Values = @($ApiType.Events) }
    )
}

function Get-ApiMemberType {
    param([object]$MemberInfo)

    foreach ($property in @("ReturnType", "PropertyType", "FieldType", "EventHandlerType")) {
        if ($MemberInfo.PSObject.Properties.Name -contains $property) {
            $value = $MemberInfo.$property
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    return ""
}

function Format-ApiMemberSignature {
    param(
        [string]$Kind,
        [object]$MemberInfo
    )

    $memberType = Get-ApiMemberType -MemberInfo $MemberInfo
    $name = if ([string]::IsNullOrWhiteSpace($MemberInfo.Name)) { "<unnamed>" } else { $MemberInfo.Name }
    $parameters = @()
    if ($MemberInfo.PSObject.Properties.Name -contains "Parameters") {
        foreach ($parameter in @($MemberInfo.Parameters)) {
            if ($null -ne $parameter) {
                $parameters += "$($parameter.Type) $($parameter.Name)"
            }
        }
    }

    $prefix = if ([string]::IsNullOrWhiteSpace($memberType)) { $Kind } else { $memberType }
    if ($Kind -eq "Method" -or $Kind -eq "Constructor") {
        return "$prefix $name($($parameters -join ', '))"
    }

    return "$prefix $name"
}

function Test-ApiTextMatch {
    param(
        [string]$Value,
        [string]$Needle,
        [switch]$ExactMatch
    )

    if ([string]::IsNullOrWhiteSpace($Needle)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    if ($ExactMatch) {
        return $Value -eq $Needle
    }

    return $Value.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

$apiPath = Resolve-SboxApiJsonPath -ProjectRoot $Root
if ([string]::IsNullOrWhiteSpace($apiPath)) {
    Write-Error "Could not find API.json or api.json at project root '$Root'."
    exit 1
}

try {
    $api = Read-AgentJson -Path $apiPath
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

$types = @($api.Types)
$results = New-Object System.Collections.Generic.List[object]

if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($TypeName) -and [string]::IsNullOrWhiteSpace($Member)) {
    $summary = [pscustomobject]@{
        ApiPath = ConvertTo-AgentRelativePath -Path $apiPath -Root $Root
        TypeCount = $types.Count
        Assemblies = @($types | Group-Object Assembly | Sort-Object Count -Descending | Select-Object -First 10 Count, Name)
        Namespaces = @($types | Group-Object Namespace | Sort-Object Count -Descending | Select-Object -First 10 Count, Name)
    }

    if ($Json) {
        $summary | ConvertTo-Json -Depth 6
    }
    else {
        Write-AgentSection "S&Box API Lookup"
        Write-Host "API: $($summary.ApiPath)"
        Write-Host "Types: $($summary.TypeCount)"
        Write-Host ""
        Write-Host "Use -Query, -Type, or -Member to inspect exact API symbols."
    }
    exit 0
}

$typeNeedle = if (-not [string]::IsNullOrWhiteSpace($TypeName)) { $TypeName } else { $Query }
if (-not [string]::IsNullOrWhiteSpace($TypeName)) {
    $candidateTypes = @($types | Where-Object { $_.FullName -eq $TypeName -or $_.Name -eq $TypeName })
    if ($candidateTypes.Count -eq 0 -and -not $Exact) {
        $candidateTypes = @($types | Where-Object {
            (Test-ApiTextMatch -Value $_.FullName -Needle $typeNeedle) -or
            (Test-ApiTextMatch -Value $_.Name -Needle $typeNeedle)
        })
    }
}
else {
    $candidateTypes = @($types | Where-Object {
        (Test-ApiTextMatch -Value $_.FullName -Needle $typeNeedle -ExactMatch:$Exact) -or
        (Test-ApiTextMatch -Value $_.Name -Needle $typeNeedle -ExactMatch:$Exact)
    })
}

foreach ($apiType in $candidateTypes | Select-Object -First $Limit) {
    $summary = if ($apiType.Documentation -and $apiType.Documentation.Summary) {
        ($apiType.Documentation.Summary -replace "\s+", " ").Trim()
    }
    else {
        ""
    }

    $typeResult = [pscustomobject]@{
        Kind = "Type"
        FullName = $apiType.FullName
        Name = $apiType.Name
        Namespace = $apiType.Namespace
        Assembly = $apiType.Assembly
        Group = $apiType.Group
        Summary = $summary
        Members = @()
    }

    if ($ShowMembers -or -not [string]::IsNullOrWhiteSpace($Member)) {
        $members = New-Object System.Collections.Generic.List[object]
        foreach ($collection in Get-ApiMemberCollections -ApiType $apiType) {
            foreach ($memberInfo in @($collection.Values)) {
                if ($null -eq $memberInfo) {
                    continue
                }

                $memberBlob = @(
                    $memberInfo.Name,
                    $memberInfo.FullName,
                    $memberInfo.DocId,
                    (Get-ApiMemberType -MemberInfo $memberInfo),
                    $memberInfo.Documentation.Summary
                ) -join " "

                if (-not (Test-ApiTextMatch -Value $memberBlob -Needle $Member -ExactMatch:$false)) {
                    continue
                }

                $members.Add([pscustomobject]@{
                    Kind = $collection.Kind
                    Name = $memberInfo.Name
                    FullName = $memberInfo.FullName
                    Signature = Format-ApiMemberSignature -Kind $collection.Kind -MemberInfo $memberInfo
                    Summary = if ($memberInfo.Documentation -and $memberInfo.Documentation.Summary) { ($memberInfo.Documentation.Summary -replace "\s+", " ").Trim() } else { "" }
                })
            }
        }
        $typeResult.Members = @($members | Select-Object -First $Limit)
    }

    $results.Add($typeResult)
}

if ([string]::IsNullOrWhiteSpace($TypeName) -and -not [string]::IsNullOrWhiteSpace($Query)) {
    foreach ($apiType in $types) {
        foreach ($collection in Get-ApiMemberCollections -ApiType $apiType) {
            foreach ($memberInfo in @($collection.Values)) {
                if ($null -eq $memberInfo) {
                    continue
                }

                $memberBlob = @(
                    $memberInfo.Name,
                    $memberInfo.FullName,
                    $memberInfo.DocId,
                    (Get-ApiMemberType -MemberInfo $memberInfo),
                    $memberInfo.Documentation.Summary
                ) -join " "

                if (-not (Test-ApiTextMatch -Value $memberBlob -Needle $Query -ExactMatch:$false)) {
                    continue
                }

                if ($results.Count -ge $Limit) {
                    break
                }

                $results.Add([pscustomobject]@{
                    Kind = "Member"
                    Type = $apiType.FullName
                    MemberKind = $collection.Kind
                    Name = $memberInfo.Name
                    FullName = $memberInfo.FullName
                    Signature = Format-ApiMemberSignature -Kind $collection.Kind -MemberInfo $memberInfo
                    Summary = if ($memberInfo.Documentation -and $memberInfo.Documentation.Summary) { ($memberInfo.Documentation.Summary -replace "\s+", " ").Trim() } else { "" }
                })
            }
            if ($results.Count -ge $Limit) {
                break
            }
        }
        if ($results.Count -ge $Limit) {
            break
        }
    }
}

if ($results.Count -eq 0) {
    Write-Error "No API matches found."
    exit 1
}

if ($Json) {
    $results | ConvertTo-Json -Depth 8
    exit 0
}

Write-AgentSection "S&Box API Lookup"
Write-Host "API: $(ConvertTo-AgentRelativePath -Path $apiPath -Root $Root)"
foreach ($result in $results) {
    if ($result.Kind -eq "Type") {
        Write-Host ""
        Write-Host "[Type] $($result.FullName) ($($result.Assembly), $($result.Group))"
        if (-not [string]::IsNullOrWhiteSpace($result.Summary)) {
            Write-Host "  $($result.Summary)"
        }
        foreach ($memberInfo in @($result.Members)) {
            Write-Host "  - [$($memberInfo.Kind)] $($memberInfo.Signature)"
            if (-not [string]::IsNullOrWhiteSpace($memberInfo.Summary)) {
                Write-Host "    $($memberInfo.Summary)"
            }
        }
    }
    else {
        Write-Host ""
        Write-Host "[Member] $($result.Type) :: $($result.Signature)"
        if (-not [string]::IsNullOrWhiteSpace($result.Summary)) {
            Write-Host "  $($result.Summary)"
        }
    }
}
