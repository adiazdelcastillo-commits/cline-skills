#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostico del canal MCP: realiza un handshake JSON-RPC real contra
    api.githubcopilot.com/mcp/ y lista las tools que el servidor expone.

.DESCRIPTION
    Comprueba, paso a paso, si el problema es del SERVIDOR (no responde /
    devuelve 401 / sin tools) o de la CONEXION de Cline (el servidor funciona
    pero Cline no le inyecta las tools al agente).

    Nunca imprime el PAT.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $env:USERPROFILE '.cline\data\settings\cline_mcp_settings.json'
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$tok  = ($cfg.mcpServers.github.headers.Authorization -replace '^Bearer\s+','').Trim()
$url  = [string]$cfg.mcpServers.github.url
$type = [string]$cfg.mcpServers.github.type

Write-Host '=== 1. Configuracion local ==='
Write-Host "  url        : $url"
Write-Host "  type       : $type"
Write-Host "  disabled   : $($cfg.mcpServers.github.disabled)"
Write-Host "  autoApprove: $(@($cfg.mcpServers.github.autoApprove).Count) entradas"
Write-Host "  toolsets   : $($cfg.mcpServers.github.headers.'X-MCP-Toolsets')"
Write-Host "  token      : github...$($tok.Substring($tok.Length-4)) (enmascarado)"
Write-Host ''

$baseH = @{
    Authorization         = "Bearer $tok"
    'Content-Type'        = 'application/json'
    'Accept'              = 'application/json, text/event-stream'
    'MCP-Protocol-Version' = '2025-06-18'
    'User-Agent'          = 'RPR-mcp-diag'
}

function Invoke-Mcp {
    param([hashtable]$Headers, [string]$Body, [string]$Uri)
    try {
        $r = Invoke-WebRequest -Method Post -Headers $Headers -Uri $Uri `
             -Body $Body -TimeoutSec 30 -UseBasicParsing
        return @{ Code = [int]$r.StatusCode; Body = $r.Content; Headers = $r.Headers }
    } catch {
        $code = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $code = [int]$_.Exception.Response.StatusCode }
        return @{ Code = $code; Body = $_.Exception.Message; Headers = @{} }
    }
}

# --- 2. initialize ----------------------------------------------------------
Write-Host '=== 2. Handshake: initialize ==='
$init = @{
    jsonrpc = '2.0'; id = 1; method = 'initialize'
    params = @{
        protocolVersion = '2025-06-18'
        capabilities    = @{}
        clientInfo      = @{ name = 'rpr-diagnostic'; version = '1.0' }
    }
} | ConvertTo-Json -Depth 8 -Compress

$res = Invoke-Mcp -Headers $baseH -Body $init -Uri $url
Write-Host "  HTTP : $($res.Code)"
if ($res.Code -ne 200) {
    Write-Host "  BODY : $($res.Body)"
    Write-Host ''
    Write-Host 'DIAGNOSTICO: el SERVIDOR MCP no responde correctamente.'
    exit 1
}

$sessionId = $res.Headers['mcp-session-id']
Write-Host "  session-id: $(if($sessionId){$sessionId}else{'(ninguno)'})"

# El cuerpo puede ser JSON o SSE
$raw = [string]$res.Body
if ($raw -match 'data:\s*(\{.*\})') { $raw = $Matches[1] }
try {
    $initResp = $raw | ConvertFrom-Json
    $sv = $initResp.result.serverInfo
    Write-Host "  servidor: $($sv.name) $($sv.version)"
    Write-Host "  protocolo: $($initResp.result.protocolVersion)"
} catch {
    Write-Host "  (respuesta no JSON: $($raw.Substring(0,[Math]::Min(200,$raw.Length))))"
}
Write-Host ''

# --- 3. notifications/initialized ------------------------------------------
$h2 = $baseH.Clone()
if ($sessionId) { $h2['mcp-session-id'] = $sessionId }
$notif = @{ jsonrpc = '2.0'; method = 'notifications/initialized'; params = @{} } |
         ConvertTo-Json -Depth 5 -Compress
$null = Invoke-Mcp -Headers $h2 -Body $notif -Uri $url
Write-Host '=== 3. notifications/initialized enviado ==='

# --- 4. tools/list ----------------------------------------------------------
Write-Host ''
Write-Host '=== 4. tools/list ==='
$tl = @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} } |
      ConvertTo-Json -Depth 5 -Compress
$r2 = Invoke-Mcp -Headers $h2 -Body $tl -Uri $url
Write-Host "  HTTP : $($r2.Code)"

$body2 = [string]$r2.Body
if ($body2 -match 'data:\s*(\{.*\})') { $body2 = $Matches[1] }

try {
    $tools = ($body2 | ConvertFrom-Json).result.tools
    $names = @($tools | ForEach-Object { $_.name } | Sort-Object)
    Write-Host "  TOTAL DE TOOLS: $($names.Count)"
    Write-Host ''
    $names | ForEach-Object { Write-Host "    - $_" }
    Write-Host ''
    $actions = @($names | Where-Object { $_ -like 'actions*' })
    if ($actions.Count -gt 0) {
        Write-Host '  Tools de Actions disponibles:'
        $actions | ForEach-Object { Write-Host "    * $_" }
    } else {
        Write-Host '  ATENCION: no hay tools de actions_* en la lista.'
    }
} catch {
    Write-Host "  No se pudo parsear: $($body2.Substring(0,[Math]::Min(300,$body2.Length)))"
}