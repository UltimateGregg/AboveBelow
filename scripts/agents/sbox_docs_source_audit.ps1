param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning,
    [switch]$Refresh,
    [switch]$RequireLocalSnapshot,
    [string]$RepoUrl = "https://github.com/Facepunch/sbox-docs.git",
    [string]$Ref = "master"
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "S&Box Docs Source Audit"
Write-Host "Root: $Root"

function Test-FileHasPatterns {
    param(
        [string]$RelativePath,
        [string[]]$Patterns,
        [string]$Area
    )

    $full = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Required S&Box docs source surface is missing." "Restore the file or update sbox_docs_source_audit.ps1 intentionally."
        return
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $RelativePath "Missing required docs source marker '$pattern'." "Keep the official docs source workflow routed through agents, docs, suite wiring, self-test, and hooks."
        }
    }
}

function Invoke-GitCommand {
    param(
        [string[]]$GitArgs,
        [string]$FailurePath,
        [string]$FailureMessage
    )

    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & git @GitArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $detail = ($output -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "git exited $exitCode"
        }
        Add-AgentIssue $issues "Error" "S&Box Docs Source" $FailurePath $FailureMessage $detail
        return $false
    }

    return $true
}

function Invoke-GitCapture {
    param(
        [string[]]$GitArgs
    )

    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & git @GitArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
        Text = (($output | Select-Object -First 1) -join "").Trim()
        Details = (($output | Out-String).Trim())
    }
}

Test-FileHasPatterns "docs/sbox_engine_llm_reference.md" @(
    "Official docs source repo reviewed on \d{4}-\d{2}-\d{2}",
    "https://github\.com/Facepunch/sbox-docs",
    "docfx\.json",
    "docs/\*\*/\*\.md",
    "docs/\*\*/toc\.yml",
    "sbox_docs_source_audit\.ps1",
    "actiongraph",
    "networking",
    "scene",
    "ui"
) "Docs Source Reference"

Test-FileHasPatterns ".agents/sbox/sbox-docs-source-agent.md" @(
    "Purpose",
    "https://github\.com/Facepunch/sbox-docs",
    "\.tmpbuild/sbox-docs",
    "\.tmpbuild/sbox-docs-source-index\.md",
    "sbox_docs_source_audit\.ps1",
    "-Refresh",
    "API\.json",
    "docs/sbox_engine_llm_reference\.md"
) "Docs Source Agent"

Test-FileHasPatterns ".agents/sbox/sbox-engine-reference-agent.md" @(
    "Facepunch/sbox-docs",
    "sbox-docs-source-agent\.md"
) "Engine Reference Agent"

Test-FileHasPatterns "docs/agent_toolkit.md" @(
    "S&Box Docs Source Agent",
    "\.tmpbuild/sbox-docs-source-index\.md",
    "sbox_docs_source_audit\.ps1",
    "run_agent_checks\.ps1 -Suite sbox-docs"
) "Agent Toolkit"

Test-FileHasPatterns ".agents/sbox/README.md" @(
    "sbox-docs-source-agent\.md",
    "sbox_docs_source_audit\.ps1"
) "Agent Routing"

Test-FileHasPatterns "scripts/agents/run_agent_checks.ps1" @(
    '"sbox-docs"',
    "sbox_docs_source_audit\.ps1"
) "Suite Wiring"

Test-FileHasPatterns "scripts/agents/test_full_automation_layer.ps1" @(
    '"sbox-docs"',
    "sbox_docs_source_audit\.ps1"
) "Self Test"

Test-FileHasPatterns "scripts/agents/post_task_training_agent.ps1" @(
    "SboxDocsSource",
    "sbox_docs_source_audit\.ps1",
    "Facepunch/sbox-docs"
) "Training Agent"

Test-FileHasPatterns ".claude/settings.json" @(
    '"id"\s*:\s*"sbox-docs-source-check"',
    "sbox_docs_source_audit\.ps1",
    '"sbox-docs"'
) "Claude Hook"

$snapshotDir = Join-Path $Root ".tmpbuild\sbox-docs"
$tmpBuildDir = Join-Path $Root ".tmpbuild"

if ($Refresh) {
    if (-not (Test-Path -LiteralPath $tmpBuildDir)) {
        New-Item -ItemType Directory -Force -Path $tmpBuildDir | Out-Null
    }

    if (Test-Path -LiteralPath $snapshotDir) {
        if (-not (Test-Path -LiteralPath (Join-Path $snapshotDir ".git"))) {
            Add-AgentIssue $issues "Error" "S&Box Docs Source" ".tmpbuild/sbox-docs" "Existing docs snapshot is not a git checkout." "Remove or rename the local folder, then rerun with -Refresh."
        }
        else {
            if (Invoke-GitCommand -GitArgs @("-C", $snapshotDir, "fetch", "--depth=1", "origin", $Ref) -FailurePath ".tmpbuild/sbox-docs" -FailureMessage "Failed to fetch Facepunch/sbox-docs.") {
                [void](Invoke-GitCommand -GitArgs @("-C", $snapshotDir, "reset", "--hard", "FETCH_HEAD") -FailurePath ".tmpbuild/sbox-docs" -FailureMessage "Failed to reset docs snapshot to fetched ref.")
            }
        }
    }
    else {
        [void](Invoke-GitCommand -GitArgs @("clone", "--depth", "1", "--branch", $Ref, $RepoUrl, $snapshotDir) -FailurePath ".tmpbuild/sbox-docs" -FailureMessage "Failed to clone Facepunch/sbox-docs.")
    }
}

$snapshotExists = Test-Path -LiteralPath (Join-Path $snapshotDir ".git")
if (-not $snapshotExists) {
    $severity = if ($RequireLocalSnapshot) { "Error" } else { "Info" }
    Add-AgentIssue $issues $severity "S&Box Docs Source" ".tmpbuild/sbox-docs" "No local Facepunch/sbox-docs snapshot is available for content inspection." "Run sbox_docs_source_audit.ps1 -Refresh before broad official-docs research."
}
else {
    $docsDir = Join-Path $snapshotDir "docs"
    if (-not (Test-Path -LiteralPath $docsDir)) {
        Add-AgentIssue $issues "Error" "S&Box Docs Source" ".tmpbuild/sbox-docs/docs" "Docs snapshot has no docs directory." "Refresh the official docs source checkout."
    }
    else {
        function Get-DocsSourceTitle {
            param([string]$Text)

            $titleMatch = [regex]::Match($Text, '(?m)^title:\s*"?([^"\r\n]+)"?')
            if ($titleMatch.Success) {
                return $titleMatch.Groups[1].Value.Trim()
            }

            $headingMatch = [regex]::Match($Text, '(?m)^#\s+(.+)$')
            if ($headingMatch.Success) {
                return $headingMatch.Groups[1].Value.Trim()
            }

            return ""
        }

        function Get-DocsSourceHeadings {
            param([string]$Text)

            $matches = [regex]::Matches($Text, '(?m)^#{1,3}\s+(.+)$')
            $headings = @()
            foreach ($match in $matches) {
                $headings += $match.Groups[1].Value.Trim()
                if ($headings.Count -ge 8) {
                    break
                }
            }

            return $headings
        }

        $expectedDirs = @(
            "actiongraph",
            "assets",
            "code",
            "editor",
            "gameplay",
            "networking",
            "physics",
            "rendering",
            "scene",
            "sound",
            "ui"
        )

        foreach ($dir in $expectedDirs) {
            if (-not (Test-Path -LiteralPath (Join-Path $docsDir $dir))) {
                Add-AgentIssue $issues "Warning" "S&Box Docs Source" "docs/$dir" "Expected official docs section '$dir' is missing from the local snapshot." "Check whether upstream reorganized the docs and update routing guidance."
            }
        }

        $gitProbe = Invoke-GitCapture -GitArgs @("-C", $snapshotDir, "rev-parse", "--is-inside-work-tree")
        $gitMetadataAvailable = $gitProbe.ExitCode -eq 0
        if (-not $gitMetadataAvailable) {
            $detail = if ([string]::IsNullOrWhiteSpace($gitProbe.Details)) { "git metadata probe exited $($gitProbe.ExitCode)." } else { $gitProbe.Details }
            Add-AgentIssue $issues "Warning" "S&Box Docs Source" ".tmpbuild/sbox-docs" "Could not read git metadata from the local docs snapshot." "Run sbox_docs_source_audit.ps1 -Refresh, or mark the cache safe with git config if the checkout is trusted. Details: $detail"
        }

        $head = if ($gitMetadataAvailable) { @((Invoke-GitCapture -GitArgs @("-C", $snapshotDir, "log", "-1", "--format=%H")).Text) } else { @("unknown") }
        $date = if ($gitMetadataAvailable) { @((Invoke-GitCapture -GitArgs @("-C", $snapshotDir, "log", "-1", "--format=%cI")).Text) } else { @("unknown") }
        $subject = if ($gitMetadataAvailable) { @((Invoke-GitCapture -GitArgs @("-C", $snapshotDir, "log", "-1", "--format=%s")).Text) } else { @("unknown") }
        $markdownFiles = @(Get-ChildItem -LiteralPath $docsDir -Recurse -File -Filter "*.md" | Sort-Object FullName)
        $markdownCount = $markdownFiles.Count
        $tocCount = @(Get-ChildItem -LiteralPath $docsDir -Recurse -File -Filter "toc.yml").Count
        $mediaCount = @(Get-ChildItem -LiteralPath $docsDir -Recurse -File | Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|svg|webp|mp4)$' }).Count
        $topDirs = @(Get-ChildItem -LiteralPath $docsDir -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
        $pageRecords = @()

        foreach ($file in $markdownFiles) {
            $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $docsDir
            $section = ($relative -split "/")[0]
            if ($relative -eq "index.md") {
                $section = "root"
            }

            $text = Get-Content -LiteralPath $file.FullName -Raw
            $pageRecords += [pscustomobject]@{
                Section = $section
                Path = $relative
                Title = Get-DocsSourceTitle -Text $text
                Headings = @(Get-DocsSourceHeadings -Text $text)
            }
        }

        $sectionCounts = @($pageRecords | Group-Object Section | Sort-Object Name)

        Add-AgentIssue $issues "Info" "S&Box Docs Source" ".tmpbuild/sbox-docs" "Snapshot commit $($head -join '') has $markdownCount markdown docs, $tocCount toc files, and $mediaCount media files." "Reviewed ref '$Ref' from $RepoUrl."

        $reportLines = @(
            "# S&Box Docs Source Snapshot",
            "",
            "Repository: $RepoUrl",
            "Ref: $Ref",
            "Commit: $($head -join '')",
            "Date: $($date -join '')",
            "Subject: $($subject -join '')",
            "Markdown docs: $markdownCount",
            "TOC files: $tocCount",
            "Media files: $mediaCount",
            "",
            "Top-level docs sections:",
            ($topDirs | ForEach-Object { "- $_" })
        )
        $reportPath = Join-Path $tmpBuildDir "sbox-docs-source-report.md"
        $reportLines | Set-Content -LiteralPath $reportPath -Encoding UTF8
        Write-Host "Docs source report written: $reportPath"

        $indexLines = New-Object System.Collections.Generic.List[string]
        $indexLines.Add("# S&Box Docs Source Page Index")
        $indexLines.Add("")
        $indexLines.Add("Repository: $RepoUrl")
        $indexLines.Add("Commit: $($head -join '')")
        $indexLines.Add("Date: $($date -join '')")
        $indexLines.Add("Markdown docs: $markdownCount")
        $indexLines.Add("")
        $indexLines.Add("## Section Counts")
        foreach ($group in $sectionCounts) {
            $indexLines.Add("- $($group.Name): $($group.Count)")
        }
        $indexLines.Add("")
        $indexLines.Add("## Pages")
        foreach ($page in $pageRecords) {
            $title = if ([string]::IsNullOrWhiteSpace($page.Title)) { "(untitled)" } else { $page.Title }
            $indexLines.Add("- ``$($page.Path)`` - $title")
            if ($page.Headings.Count -gt 0) {
                $indexLines.Add("  headings: $($page.Headings -join '; ')")
            }
        }

        $indexPath = Join-Path $tmpBuildDir "sbox-docs-source-index.md"
        $indexLines | Set-Content -LiteralPath $indexPath -Encoding UTF8
        Write-Host "Docs source index written: $indexPath"
    }
}

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "S&Box Docs Source" "" "Official docs source workflow, local snapshot, agent routing, suite, self-test, and hook wiring passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
