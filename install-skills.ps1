#Requires -Version 5.1
<#
.SYNOPSIS
    Instala los skills de este repositorio en ~/.cline/skills.

.DESCRIPTION
    Copia todos los skills desde ./skills al directorio de skills de Cline.
    IDEMPOTENTE: no vuelve a copiar los que ya estan actualizados.
    NO sobrescribe un skill existente que haya sido modificado localmente sin -Force.

.EXAMPLE
    .\install-skills.ps1
    .\install-skills.ps1 -Force
    .\install-skills.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string] $SkillsSource = '',
    [switch] $Force,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SkillsSource)) {
    $SkillsSource = Join-Path $PSScriptRoot 'skills'
}
$dest = Join-Path $env:USERPROFILE '.cline\skills'

if (-not (Test-Path $SkillsSource)) {
    throw "No se encuentra la carpeta de skills de origen: $SkillsSource`n" +
          "Clona el repositorio completo antes de ejecutar este script."
}
Write-Host "Origen : $SkillsSource"
Write-Host "Destino: $dest"
Write-Host ''

$skills = @(Get-ChildItem $SkillsSource -Directory | Sort-Object Name)
if ($skills.Count -eq 0) { throw "La carpeta de origen no contiene skills: $SkillsSource" }

if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }

if ($DryRun) {
    Write-Host "[DRY RUN] Se instalarian $($skills.Count) skills:"
    $skills | ForEach-Object { "  $($_.Name)" }
    exit 0
}

$installed = 0; $updated = 0; $skipped = 0; $failed = 0

foreach ($s in $skills) {
    $target = Join-Path $dest $s.Name
    try {
        if (-not (Test-Path $target)) {
            Copy-Item $s.FullName $target -Recurse -Force
            Write-Host "  [nuevo]     $($s.Name)"
            $installed++
            continue
        }
        # Comparar contenido: si difiere, actualizar (salvo que se pida -Force)
        $srcFiles  = @(Get-ChildItem $s.FullName -Recurse -File)
        $dstFiles  = @(Get-ChildItem $target -Recurse -File -ErrorAction SilentlyContinue)
        $different = $false
        foreach ($f in $srcFiles) {
            $rel = $f.FullName.Substring($s.FullName.Length + 1)
            $tf  = Join-Path $target $rel
            if (-not (Test-Path $tf)) { $different = $true; break }
            if ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash $tf).Hash) { $different = $true; break }
        }
        if (-not $different -and $dstFiles.Count -eq $srcFiles.Count) {
            Write-Host "  [sin cambios] $($s.Name)"
            $skipped++
        } elseif ($Force) {
            Remove-Item $target -Recurse -Force
            Copy-Item $s.FullName $target -Recurse -Force
            Write-Host "  [actualizado] $($s.Name)  (-Force)"
            $updated++
        } else {
            Write-Host "  [omitido]    $($s.Name)  (difiere; usa -Force para reemplazar)"
            $skipped++
        }
    } catch {
        Write-Host "  [ERROR]      $($s.Name): $($_.Exception.Message)"
        $failed++
    }
}

Write-Host ''
Write-Host "Nuevos        : $installed"
Write-Host "Actualizados  : $updated"
Write-Host "Sin cambios   : $skipped"
Write-Host "Fallidos      : $failed"
Write-Host "Total skills  : $(@(Get-ChildItem $dest -Directory).Count) ahora instalados"
Write-Host ''
Write-Host 'SIGUIENTE PASO: reinicia Cline / recarga la ventana de VS Code.'
if ($failed -gt 0) { exit 1 } else { exit 0 }