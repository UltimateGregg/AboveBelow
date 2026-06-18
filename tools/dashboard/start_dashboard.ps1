# Launch the ABOVE / BELOW ops dashboard and open it in the default browser.
# PowerShell 5.1 compatible. Re-running while the server is up just opens the browser.

param([int]$Port = 8723)

$ErrorActionPreference = "Stop"

$serverPy = Join-Path $PSScriptRoot "server.py"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$url = "http://127.0.0.1:$Port/"

function Test-DashboardAlive {
    try {
        $response = Invoke-WebRequest -Uri ($url + "api/health") -UseBasicParsing -TimeoutSec 2
        return ($response.Content -match '"app"\s*:\s*"sbox-dashboard"')
    } catch {
        return $false
    }
}

if (-not (Test-DashboardAlive)) {
    $pyCmd = "python"
    $pyArgs = @()
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $pyCmd = "py"
        $pyArgs = @("-3")
    }
    # Quote the script path: the repo path contains '&'.
    $pyArgs += @("`"$serverPy`"", "--port", "$Port")
    Start-Process -FilePath $pyCmd -ArgumentList $pyArgs -WorkingDirectory $repoRoot

    $alive = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-DashboardAlive) { $alive = $true; break }
    }
    if (-not $alive) {
        Write-Host "[Error] Dashboard did not come up on port $Port. Run manually to see the error:"
        Write-Host "        python `"$serverPy`" --port $Port"
        exit 1
    }
    Write-Host "Dashboard started on $url"
} else {
    Write-Host "Dashboard already running on $url"
}

Start-Process $url
