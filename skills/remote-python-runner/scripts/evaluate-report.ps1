#Requires -Version 5.1
<#
.SYNOPSIS
    Interpreta report.xml de una corrida remota y produce un veredicto.

.DESCRIPTION
    Traduce el reporte JUnit de pytest a un resumen legible, y ADEMAS detecta la
    incoherencia critica: conclusion=success con tests fallados (falso positivo).
    En ese caso el veredicto es FALSO-POSITIVO, nunca OK.

.EXAMPLE
    .\evaluate-report.ps1 -RunDir .rpr\reports\37154257666
    .\evaluate-report.ps1 -ReportXml .rpr\reports\12345\report.xml
#>
[CmdletBinding()]
param(
    [string] $RunDir = '',
    [string] $ReportXml = '',
    [string] $Conclusion = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ReportXml)) {
    if ([string]::IsNullOrWhiteSpace($RunDir)) { throw 'Indica -RunDir o -ReportXml' }
    $ReportXml = Join-Path $RunDir 'report.xml'
}
if (-not (Test-Path $ReportXml)) { throw "No existe el reporte: $ReportXml" }

$summaryPath = Join-Path (Split-Path -Parent $ReportXml) 'summary.md'
if (-not (Test-Path $summaryPath)) { $summaryPath = '' }

[xml]$x = Get-Content $ReportXml -Raw
$suite = $x.testsuites.testsuite
if ($null -eq $suite) { $suite = $x.testsuites }

$total   = [int]$suite.tests
$failN   = [int]$suite.failures
$errN    = [int]$suite.errors
$skipN   = [int]$suite.skipped
$passed  = $total - $failN - $errN - $skipN

'=== Veredicto de la corrida remota ==='
''
"Reporte  : $ReportXml"
"Total    : $total"
"Pasadas  : $passed"
"Fallidas : $failN"
"Errores  : $errN"
"Omitidas : $skipN"

# --- Tests fallidos ----------------------------------------------------------
$failed = @($suite.testcase | Where-Object { $_.failure -or $_.error })
if ($failed.Count -gt 0) {
    ''
    '--- Tests con fallo ---'
    foreach ($t in $failed) {
        "  * $($t.name)"
        if ($t.failure) { "      $($t.failure.InnerText)" }
        if ($t.error)   { "      ERROR: $($t.error.InnerText)" }
    }
}

# --- summary.md --------------------------------------------------------------
if ($summaryPath) {
    ''
    '--- summary.md ---'
    Get-Content $summaryPath | ForEach-Object { "  $_" }
}

# --- Coherencia conclusion vs reporte (control critico) ---------------------
$verdict = 'OK'
$exit = 0
if ([string]::IsNullOrWhiteSpace($Conclusion)) {
    $verdict = 'REPORTE-SOLO'
} elseif ($Conclusion -eq 'success' -and ($failN -gt 0 -or $errN -gt 0)) {
    # T-12: esto NO es un aprobado. Es un bug del pipeline.
    $verdict = 'FALSO-POSITIVO (BUG DEL PIPELINE)'
    $exit = 2
} elseif ($Conclusion -ne 'success') {
    $verdict = "CORRIDA $Conclusion"
    $exit = 1
} elseif ($total -eq 0) {
    $verdict = 'SIN PRUEBAS EJECUTADAS'
    $exit = 3
}

''
"VEREDICTO: $verdict"
switch ($exit) {
    0 { 'Todas las pruebas pasaron y la corrida fue success.' }
    1 { 'La corrida no fue success. Revisa los fallos.' }
    2 { 'ATENCION: conclusion=success pero hay tests fallados. Reportar como BUG, nunca como aprobado.' }
    3 { 'No se ejecuto ninguna prueba: revisa la ruta de tests y el input suite.' }
}
exit $exit