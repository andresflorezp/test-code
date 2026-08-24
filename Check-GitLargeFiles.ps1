<#
.SYNOPSIS
    Audita archivos grandes en TODO el historial de un repo Git antes de migrar a GitHub.

.DESCRIPTION
    GitHub bloquea el push de cualquier blob > 100 MB, advierte sobre > 50 MB y
    topa el push completo en 2 GB. Estos limites aplican sobre el HISTORIAL COMPLETO,
    no solo sobre el working tree: un archivo borrado hace anios sigue viviendo en los
    objetos del repo y sigue rompiendo el push.

    Este script recorre todos los objetos alcanzables desde todas las refs
    (ramas, tags, notes) y reporta los blobs que superan el umbral.

.PARAMETER RepoPath
    Ruta al repo local (clon completo, NO shallow). Default: directorio actual.

.PARAMETER ThresholdMB
    Umbral minimo para reportar. Default: 50.

.PARAMETER Top
    Cuantos archivos mostrar en consola. Default: 30.

.PARAMETER OutputCsv
    Ruta del CSV de salida. Default: .\reporte-archivos-grandes.csv

.EXAMPLE
    .\Check-GitLargeFiles.ps1 -RepoPath C:\repos\mi-repo

.EXAMPLE
    .\Check-GitLargeFiles.ps1 -RepoPath C:\repos\mi-repo -ThresholdMB 10 -Top 50

.NOTES
    IMPORTANTE: clona con --mirror para garantizar que ves TODO:
        git clone --mirror https://bitbucket.org/org/repo.git
#>

[CmdletBinding()]
param(
    [string]$RepoPath    = ".",
    [int]   $ThresholdMB = 50,
    [int]   $Top         = 30,
    [string]$OutputCsv   = ".\reporte-archivos-grandes.csv"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Limites de GitHub (en MB)
# ---------------------------------------------------------------------------
$GH_BLOCK   = 100    # push rechazado
$GH_WARN    = 50     # advertencia
$GH_PUSH    = 2048   # limite por push
$GH_REPO_OK = 5120   # tamanio de repo "fuertemente recomendado"

$thresholdBytes = $ThresholdMB * 1MB

function Write-Section($text) {
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Validaciones previas
# ---------------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "No encuentro 'git' en el PATH."
}

$RepoPath = (Resolve-Path $RepoPath).Path
$isRepo = & git -C $RepoPath rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) {
    $isBare = & git -C $RepoPath rev-parse --is-bare-repository 2>$null
    if ($LASTEXITCODE -ne 0) { throw "'$RepoPath' no es un repositorio Git." }
}

$isShallow = & git -C $RepoPath rev-parse --is-shallow-repository 2>$null
if ($isShallow -eq "true") {
    Write-Warning "Este clon es SHALLOW. El historial esta truncado y el reporte sera incompleto."
    Write-Warning "Corre:  git -C `"$RepoPath`" fetch --unshallow   (o vuelve a clonar con --mirror)"
}

Write-Section "Auditoria de archivos grandes  |  $RepoPath"
Write-Host "Umbral de reporte : $ThresholdMB MB"
Write-Host "Escaneando historial completo (esto puede tardar en repos grandes)..." -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# 1. Tamanio total del repo en disco
# ---------------------------------------------------------------------------
$countObjects = & git -C $RepoPath count-objects -vH
$sizePack = ($countObjects | Select-String '^size-pack:').ToString() -replace 'size-pack:\s*',''
$numObjects = ($countObjects | Select-String '^count:').ToString() -replace 'count:\s*',''

# ---------------------------------------------------------------------------
# 2. Set de rutas vivas en HEAD (para separar "vivo" de "solo historial")
# ---------------------------------------------------------------------------
$liveFiles = New-Object 'System.Collections.Generic.HashSet[string]'
$headFiles = & git -C $RepoPath -c core.quotepath=false ls-tree -r HEAD --name-only 2>$null
if ($LASTEXITCODE -eq 0) {
    foreach ($f in $headFiles) { [void]$liveFiles.Add($f) }
}

# ---------------------------------------------------------------------------
# 3. Recorrer todos los blobs del historial
#    rev-list --objects  ->  cat-file --batch-check
# ---------------------------------------------------------------------------
$batch = & git -C $RepoPath -c core.quotepath=false rev-list --objects --all |
         & git -C $RepoPath cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)'

$blobs = [System.Collections.Generic.List[object]]::new()

foreach ($line in $batch) {
    if (-not $line.StartsWith('blob ')) { continue }

    # blob <sha> <size> <path con espacios posibles>
    $parts = $line.Split(' ', 4)
    if ($parts.Count -lt 4) { continue }          # blob sin ruta (raro, se ignora)

    $size = [int64]$parts[2]
    if ($size -lt $thresholdBytes) { continue }

    $blobs.Add([pscustomobject]@{
        Sha  = $parts[1]
        Size = $size
        Path = $parts[3].Trim('"')
    })
}

if ($blobs.Count -eq 0) {
    Write-Host ""
    Write-Host "Limpio: no hay blobs por encima de $ThresholdMB MB en el historial." -ForegroundColor Green
    Write-Host "Tamanio del repo: $sizePack ($numObjects objetos sueltos)"
    return
}

# ---------------------------------------------------------------------------
# 4. Agrupar por ruta: un mismo archivo puede tener N versiones en historial
# ---------------------------------------------------------------------------
$report = $blobs | Group-Object Path | ForEach-Object {
    $maxBlob    = $_.Group | Sort-Object Size -Descending | Select-Object -First 1
    $totalBytes = ($_.Group | Measure-Object Size -Sum).Sum
    $maxMB      = [math]::Round($maxBlob.Size / 1MB, 2)

    $estado = if     ($maxMB -ge $GH_BLOCK) { "BLOQUEA" }
              elseif ($maxMB -ge $GH_WARN)  { "ADVIERTE" }
              else                          { "OK" }

    [pscustomobject]@{
        Estado        = $estado
        MaxMB         = $maxMB
        TotalHistMB   = [math]::Round($totalBytes / 1MB, 2)
        Versiones     = $_.Count
        EnHEAD        = if ($liveFiles.Contains($_.Name)) { "SI" } else { "NO (solo historial)" }
        Extension     = if ([System.IO.Path]::GetExtension($_.Name)) { [System.IO.Path]::GetExtension($_.Name).ToLower() } else { "(sin ext)" }
        Ruta          = $_.Name
        BlobMayor     = $maxBlob.Sha
    }
} | Sort-Object MaxMB -Descending

# ---------------------------------------------------------------------------
# 5. Salida en consola
# ---------------------------------------------------------------------------
Write-Section "TOP $Top archivos mas pesados"

$report | Select-Object -First $Top |
    Format-Table Estado, MaxMB, TotalHistMB, Versiones, EnHEAD, Ruta -AutoSize

# ---------------------------------------------------------------------------
# 6. Resumen por extension (util para decidir que mandar a LFS)
# ---------------------------------------------------------------------------
Write-Section "Peso acumulado por extension"

$report | Group-Object Extension | ForEach-Object {
    [pscustomobject]@{
        Extension   = $_.Name
        Archivos    = $_.Count
        TotalHistMB = [math]::Round(($_.Group | Measure-Object TotalHistMB -Sum).Sum, 2)
    }
} | Sort-Object TotalHistMB -Descending | Format-Table -AutoSize

# ---------------------------------------------------------------------------
# 7. Veredicto
# ---------------------------------------------------------------------------
$bloquean  = @($report | Where-Object Estado -eq "BLOQUEA")
$advierten = @($report | Where-Object Estado -eq "ADVIERTE")
$soloHist  = @($bloquean | Where-Object EnHEAD -like "NO*")

Write-Section "VEREDICTO"

Write-Host "Tamanio del repo (size-pack) : $sizePack"
Write-Host "Archivos > $GH_BLOCK MB (bloquean push) : $($bloquean.Count)" -ForegroundColor $(if ($bloquean.Count) { "Red" } else { "Green" })
Write-Host "Archivos > $GH_WARN MB (advertencia)     : $($advierten.Count)" -ForegroundColor $(if ($advierten.Count) { "Yellow" } else { "Green" })
Write-Host "De los bloqueantes, ya NO estan en HEAD  : $($soloHist.Count)  <- estos exigen reescribir historial"

if ($bloquean.Count -gt 0) {
    Write-Host ""
    Write-Host "La migracion VA A FALLAR tal como esta. Opciones:" -ForegroundColor Red
    Write-Host ""
    Write-Host "  A) Pasar a Git LFS conservando el historial:" -ForegroundColor White
    $exts = ($bloquean | Select-Object -ExpandProperty Extension -Unique) -join '","*'
    Write-Host "     git lfs migrate import --everything --include=`"*$exts`""
    Write-Host ""
    Write-Host "  B) Borrar los blobs del historial (git-filter-repo):" -ForegroundColor White
    Write-Host "     git filter-repo --strip-blobs-bigger-than 100M"
    Write-Host ""
    Write-Host "  Ambas REESCRIBEN los SHA de todos los commits. Coordina con el equipo:" -ForegroundColor Yellow
    Write-Host "  toca congelar el repo en Bitbucket, migrar, y que todos re-clonen." -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "Sin bloqueantes. El repo deberia migrar sin problema." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 8. CSV
# ---------------------------------------------------------------------------
$report | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Reporte completo -> $((Resolve-Path $OutputCsv).Path)" -ForegroundColor Cyan
