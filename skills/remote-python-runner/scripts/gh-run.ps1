#Requires -Version 5.1
<#
.SYNOPSIS
    Fallback REST del skill remote-python-runner: dispara el workflow, hace
    polling y descarga los artefactos.

.DESCRIPTION
    Canal alternativo cuando el servidor MCP no esta disponible. Obtiene el PAT
    desde cline_mcp_settings.json (nunca desde un parametro de CLI) y NUNCA lo
    imprime.

.EXAMPLE
    .\gh-run.ps1 -Owner adiazdelcastillo-commits -Repo rpr-lab
    .\gh-run.ps1 -Owner mi-user -Repo mi-repo -Suite fast -PytestArgs '-k vacio'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Owner,
    [Parameter(Mandatory)][string] $Repo,
    [string] $Workflow    = 'run-tests.yml',
    [string] $Branch      = 'main',
    [string] $Suite       = 'all',
    [string] $PytestArgs  = '-q',
    [string] $OutDir      = '',
    [int]    $TimeoutSec  = 900,
    [int]    $PollSec     = 10
)

$ErrorActionPreference = 'Stop'

# --- Token desde la config MCP (nunca desde la CLI) --------------------------
$mcpFile = Join-Path $env:USERPROFILE '.cline\data\settings\cline_mcp_settings.json'
if (-not (Test-Path $mcpFile)) { throw "No existe la config MCP: $mcpFile" }
$cfg = Get-Content $mcpFile -Raw | ConvertFrom-Json
if (-not ($cfg.PSObject.Properties.Name -contains 'mcpServers')) { throw 'Config MCP sin mcpServers' }
if (-not ($cfg.mcpServers.PSObject.Properties.Name -contains 'github')) { throw 'Config MCP sin entrada github' }
$auth = [string]$cfg.mcpServers.github.headers.Authorization
$tok  = ($auth -replace '^Bearer\s+', '').Trim()
if ([string]::IsNullOrWhiteSpace($tok) -or $tok -match 'PEGAR_AQUI') {
    throw 'El PAT sigue sin pegar en la config MCP.'
}

$h = @{ Authorization = "Bearer $tok"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'RPR-gh-run' }

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path (Get-Location) '.rpr\reports' }
$base = "https://api.github.com/repos/$Owner/$Repo"

# --- 1. Disparar (devuelve 204 SIN run_id) ----------------------------------
$body = @{ ref = $Branch
           inputs = @{ suite = $Suite; pytest_args = $PytestArgs } } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Post -Headers $h -ContentType 'application/json' `
    -Uri "$base/actions/workflows/$Workflow/dispatches" -Body $body | Out-Null
Write-Host "Workflow disparado: $Workflow @ $Branch"

# --- 2. Localizar la corrida (el dispatch no devuelve el id) ----------------
Start-Sleep -Seconds 5
$runs = Invoke-RestMethod -Headers $h -Uri "$base/actions/workflows/$Workflow/runs?per_page=1"
if (-not $runs.workflow_runs) { throw 'No se encontro ninguna corrida del workflow.' }
$runId = $runs.workflow_runs[0].id
Write-Host "Run encolado: $runId"

# --- 3. Polling con timeout --------------------------------------------------
$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
    Start-Sleep -Seconds $PollSec
    $run = Invoke-RestMethod -Headers $h -Uri "$base/actions/runs/$runId"
    Write-Host ("  estado: {0} / {1}" -f $run.status, $run.conclusion)
} until ($run.status -eq 'completed' -or (Get-Date) -gt $deadline)

if ($run.status -ne 'completed') {
    Invoke-RestMethod -Method Post -Headers $h -Uri "$base/actions/runs/$runId/cancel" | Out-Null
    throw "Timeout: la corrida $runId no termino en $TimeoutSec s"
}

# --- 4. Descargar artefactos -------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$runDir = Join-Path $OutDir "$runId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$arts = Invoke-RestMethod -Headers $h -Uri "$base/actions/runs/$runId/artifacts"
$count = 0
foreach ($a in @($arts.artifacts)) {
    if ($null -eq $a) { continue }
    $zip = Join-Path $runDir "$($a.name).zip"
    Invoke-WebRequest -Headers @{ Authorization = "Bearer $tok" } `
        -Uri $a.archive_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $runDir -Force
    Remove-Item $zip -Force
    $count++
}

# --- 5. Resultado ------------------------------------------------------------
Write-Host ''
Write-Host "Run URL  : $($run.html_url)"
Write-Host "Conclusion: $($run.conclusion)"
Write-Host "Artefactos: $count (en $runDir)"

[pscustomobject]@{
    runId      = $runId
    conclusion = $run.conclusion
    status     = $run.status
    url        = $run.html_url
    artifacts  = $count
    dir        = $runDir
} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $OutDir 'last-run.json')

if ($run.conclusion -ne 'success') { exit 1 } else { exit 0 }