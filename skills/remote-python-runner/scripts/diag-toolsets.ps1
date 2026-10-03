#Requires -Version 5.1
<#
.SYNOPSIS
    Compara el conjunto de tools que devuelve el servidor MCP segun el valor
    del header X-MCP-Toolsets. Sirve para aislar por que Cline no expone actions_*.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$cfgPath = Join-Path $env:USERPROFILE '.cline\data\settings\cline_mcp_settings.json'
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$tok = ($cfg.mcpServers.github.headers.Authorization -replace '^Bearer\s+','').Trim()
$url = [string]$cfg.mcpServers.github.url

function Get-Tools {
    param([string] $ToolsetHeader)
    $h = @{ Authorization = "Bearer $tok"
            'Content-Type' = 'application/json'
            Accept = 'application/json, text/event-stream'
            'MCP-Protocol-Version' = '2025-06-18'
            'User-Agent' = 'RPR-toolset-diag' }
    if ($ToolsetHeader) { $h['X-MCP-Toolsets'] = $ToolsetHeader }

    $init = @{ jsonrpc='2.0'; id=1; method='initialize'
               params=@{ protocolVersion='2025-06-18'; capabilities=@{}
                         clientInfo=@{ name='rpr-diag'; version='1.0' } } } |
             ConvertTo-Json -Depth 8 -Compress
    $r = Invoke-WebRequest -Method Post -Headers $h -Uri $url -Body $init -UseBasicParsing -TimeoutSec 40
    $sid = $r.Headers['mcp-session-id']
    if ($sid) { $h['mcp-session-id'] = $sid }

    $q = @{ jsonrpc='2.0'; id=2; method='tools/list'; params=@{} } | ConvertTo-Json -Compress
    $r2 = Invoke-WebRequest -Method Post -Headers $h -Uri $url -Body $q -UseBasicParsing -TimeoutSec 60
    $b = [string]$r2.Content
    if ($b -match 'data:\s*(\{.*\})') { $b = $Matches[1] }
    $names = @(($b | ConvertFrom-Json).result.tools | ForEach-Object { $_.name })
    return @{ All = $names; Actions = @($names | Where-Object { $_ -like 'actions*' }) }
}

$casos = @(
    @{ Label = 'SIN header (default)';            Header = '' }
    @{ Label = 'X-MCP-Toolsets: actions,repos,context'; Header = 'actions,repos,context' }
    @{ Label = 'X-MCP-Toolsets: actions';          Header = 'actions' }
    @{ Label = 'X-MCP-Toolsets: all';              Header = 'all' }
)

foreach ($c in $casos) {
    $res = Get-Tools -ToolsetHeader $c.Header
    $hdr = if ($c.Header) { $c.Header } else { '(ninguno)' }
    Write-Host ("{0,-42} total={1,3}  actions={2}" -f $c.Label, $res.All.Count, $res.Actions.Count)
    if ($res.Actions.Count -gt 0) {
        Write-Host ("    -> {0}" -f ($res.Actions -join ', '))
    } else {
        Write-Host '    -> SIN tools actions_*'
    }
}

Write-Host ''
Write-Host 'CONCLUSION:'
Write-Host '  El header X-MCP-Toolsets filtra la lista de tools que el servidor entrega.'
Write-Host '  Si Cline no expone actions_*, casi seguro no esta aplicando ese header'