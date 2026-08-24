<#
.SYNOPSIS
    Reporte de migracion Bitbucket -> GitHub: que archivos bloquean, en que ramas estan,
    cuanto pesan, y genera los archivos de entrada para borrarlos con git-filter-repo.

.DESCRIPTION
    Una sola pasada produce:

      1. reporte-migracion.csv   -> tabla completa para analizar
      2. reporte-migracion.html  -> version legible para compartir con el equipo
      3. blobs-a-borrar.txt      -> SHAs para: git filter-repo --strip-blobs-with-ids
      4. rutas-a-borrar.txt      -> paths para: git filter-repo --invert-paths --paths-from-file
      5. comandos-limpieza.txt   -> los comandos exactos, listos para copiar

    El mapeo blob->rama se hace recorriendo cada ref una vez (no blob por blob),
    que es ordenes de magnitud mas rapido que 'git log --find-object'.

.PARAMETER RepoPath
    Ruta al repo. Idealmente un clon --mirror. Default: directorio actual.

.PARAMETER ThresholdMB
    Umbral minimo para incluir en el reporte. Default: 50.

.PARAMETER StripMB
    A partir de que tamanio marcar un archivo para borrado en los .txt de salida.
    Default: 100 (el limite duro de GitHub).

.PARAMETER OutputDir
    Carpeta donde dejar los reportes. Default: .\reporte-migracion

.PARAMETER SkipBranchMapping
    Omite el cruce blob->rama. Mucho mas rapido, pero pierdes la columna Ramas.

.EXAMPLE
    .\New-GitMigrationReport.ps1 -RepoPath .\repo.git -ThresholdMB 20

.NOTES
    Solo lectura. No modifica el repo.
#>

[CmdletBinding()]
param(
    [string]$RepoPath          = ".",
    [int]   $ThresholdMB       = 50,
    [int]   $StripMB           = 100,
    [string]$OutputDir         = ".\reporte-migracion",
    [switch]$SkipBranchMapping,
    [switch]$IncludePullRequestRefs,
    [int]   $MaxRamasMostradas = 8
)

$ErrorActionPreference = "Stop"
$RepoPath = (Resolve-Path $RepoPath).Path
$thresholdBytes = $ThresholdMB * 1MB

$GH_BLOCK = 100
$GH_WARN  = 50

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$OutputDir = (Resolve-Path $OutputDir).Path

function Write-Section($t) {
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkGray
}

# Escape HTML sin depender de System.Web (no existe en PowerShell 7)
function ConvertTo-HtmlSafe([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

# Encoding correcto para paths con tildes.
# Sin esto, PowerShell 5.1 decodifica la salida de git con la code page ANSI
# y los acentos se convierten en '?' - lo que corrompe rutas-a-borrar.txt.
$encodingPrevio = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
& git -C $RepoPath config core.quotepath false 2>$null | Out-Null

Write-Section "Reporte de migracion  |  $RepoPath"

# ===========================================================================
# PASO 1 - Inventario de blobs grandes en todo el historial
# ===========================================================================
Write-Host "[1/4] Escaneando historial completo..." -ForegroundColor Yellow

$batch = & git -C $RepoPath rev-list --objects --all |
         & git -C $RepoPath cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)'

# blobSha -> @{ Size; Paths }
$blobInfo = @{}

foreach ($line in $batch) {
    if (-not $line.StartsWith('blob ')) { continue }
    $p = $line.Split(' ', 4)
    if ($p.Count -lt 4) { continue }

    $size = [int64]$p[2]
    if ($size -lt $thresholdBytes) { continue }

    $sha  = $p[1]
    $path = $p[3].Trim('"')

    if ($blobInfo.ContainsKey($sha)) {
        [void]$blobInfo[$sha].Paths.Add($path)
    } else {
        $set = [System.Collections.Generic.HashSet[string]]::new()
        [void]$set.Add($path)
        $blobInfo[$sha] = @{ Size = $size; Paths = $set }
    }
}

if ($blobInfo.Count -eq 0) {
    Write-Host ""
    Write-Host "Limpio: nada por encima de $ThresholdMB MB. El repo migra sin problema." -ForegroundColor Green
    return
}

Write-Host "      $($blobInfo.Count) blobs encontrados sobre $ThresholdMB MB"

# ===========================================================================
# PASO 2 - Cruce blob -> ramas / tags
# ===========================================================================
$blobRefs = @{}   # sha -> HashSet de refs

if (-not $SkipBranchMapping) {
    $refs = & git -C $RepoPath for-each-ref --format="%(refname)" refs/heads refs/remotes refs/tags |
            Where-Object { $_ -notmatch '/HEAD$' }

    if (-not $IncludePullRequestRefs) {
        $antes = $refs.Count
        $refs = $refs | Where-Object { $_ -notmatch 'pull-requests?/' -and $_ -notmatch 'refs/pull/' }
        $filtradas = $antes - $refs.Count
        if ($filtradas -gt 0) {
            Write-Host "      $filtradas refs de pull-requests excluidas (usa -IncludePullRequestRefs para incluirlas)" -ForegroundColor DarkGray
        }
    }

    Write-Host "[2/4] Cruzando contra $($refs.Count) refs..." -ForegroundColor Yellow

    $n = 0
    foreach ($ref in $refs) {
        $n++
        $nombre = $ref -replace '^refs/heads/','' -replace '^refs/remotes/','' -replace '^refs/tags/','tag:'
        Write-Progress -Activity "Mapeando ramas" -Status "$n/$($refs.Count)  $nombre" `
                       -PercentComplete (($n / $refs.Count) * 100)

        $objs = & git -C $RepoPath rev-list --objects $ref 2>$null
        foreach ($o in $objs) {
            if ($o.Length -lt 40) { continue }
            $sha = $o.Substring(0, 40)
            if (-not $blobInfo.ContainsKey($sha)) { continue }

            if (-not $blobRefs.ContainsKey($sha)) {
                $blobRefs[$sha] = [System.Collections.Generic.HashSet[string]]::new()
            }
            [void]$blobRefs[$sha].Add($nombre)
        }
    }
    Write-Progress -Activity "Mapeando ramas" -Completed
} else {
    Write-Host "[2/4] Mapeo de ramas omitido (-SkipBranchMapping)" -ForegroundColor DarkGray
}

# ===========================================================================
# PASO 3 - Rutas vivas en HEAD
# ===========================================================================
Write-Host "[3/4] Consolidando..." -ForegroundColor Yellow

$liveFiles = [System.Collections.Generic.HashSet[string]]::new()
$headFiles = & git -C $RepoPath ls-tree -r HEAD --name-only 2>$null
if ($LASTEXITCODE -eq 0) { foreach ($f in $headFiles) { [void]$liveFiles.Add($f) } }

# Aplanar blob -> filas por ruta, luego agrupar por ruta
$filas = [System.Collections.Generic.List[object]]::new()

foreach ($sha in $blobInfo.Keys) {
    foreach ($path in $blobInfo[$sha].Paths) {
        $filas.Add([pscustomobject]@{
            Sha  = $sha
            Size = $blobInfo[$sha].Size
            Path = $path
            Refs = if ($blobRefs.ContainsKey($sha)) { $blobRefs[$sha] } else { $null }
        })
    }
}

$reporte = $filas | Group-Object Path | ForEach-Object {
    $grupo   = $_.Group
    $mayor   = $grupo | Sort-Object Size -Descending | Select-Object -First 1
    $maxMB   = [math]::Round($mayor.Size / 1MB, 2)
    $totalMB = [math]::Round((($grupo | Measure-Object Size -Sum).Sum) / 1MB, 2)

    $todasRefs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($g in $grupo) {
        if ($g.Refs) { foreach ($r in $g.Refs) { [void]$todasRefs.Add($r) } }
    }

    $ramas = @($todasRefs | Where-Object { $_ -notlike 'tag:*' } | Sort-Object)
    $tags  = @($todasRefs | Where-Object { $_ -like  'tag:*' } | Sort-Object)

    $ramasTxt = if ($ramas.Count -gt $MaxRamasMostradas) {
        (($ramas | Select-Object -First $MaxRamasMostradas) -join "; ") + " ... (+$($ramas.Count - $MaxRamasMostradas) mas)"
    } else { $ramas -join "; " }

    $tagsLimpios = $tags | ForEach-Object { $_ -replace '^tag:','' }
    $tagsTxt = if ($tagsLimpios.Count -gt $MaxRamasMostradas) {
        (($tagsLimpios | Select-Object -First $MaxRamasMostradas) -join "; ") + " ... (+$($tagsLimpios.Count - $MaxRamasMostradas) mas)"
    } else { $tagsLimpios -join "; " }

    $estado = if     ($maxMB -ge $GH_BLOCK) { "BLOQUEA" }
              elseif ($maxMB -ge $GH_WARN)  { "ADVIERTE" }
              else                          { "REVISAR" }

    $enHead = $liveFiles.Contains($_.Name)

    # Accion sugerida
    $ext = [System.IO.Path]::GetExtension($_.Name).ToLower()
    $accion = if (-not $enHead)            { "BORRAR (muerto, ya no esta en HEAD)" }
              elseif ($maxMB -ge $StripMB) { "BORRAR o mover a LFS (bloquea el push)" }
              else                         { "EVALUAR (pesa pero no bloquea)" }

    [pscustomobject]@{
        Estado       = $estado
        MaxMB        = $maxMB
        TotalHistMB  = $totalMB
        Versiones    = $grupo.Count
        EnHEAD       = if ($enHead) { "SI" } else { "NO" }
        NumRamas     = $ramas.Count
        Ramas        = $ramasTxt
        Tags         = $tagsTxt
        NumTags      = $tags.Count
        Extension    = if ($ext) { $ext } else { "(sin ext)" }
        Archivo      = Split-Path $_.Name -Leaf
        Ruta         = $_.Name
        Accion       = $accion
        Blobs        = (($grupo | Select-Object -ExpandProperty Sha -Unique) -join " ")
    }
} | Sort-Object MaxMB -Descending

# ===========================================================================
# PASO 4 - Salidas
# ===========================================================================
Write-Host "[4/4] Generando archivos..." -ForegroundColor Yellow

$csvPath = Join-Path $OutputDir "reporte-migracion.csv"
$reporte | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# --- Entradas para git-filter-repo -----------------------------------------
$paraBorrar = $reporte | Where-Object { $_.MaxMB -ge $StripMB -or $_.EnHEAD -eq "NO" }

$blobsPath = Join-Path $OutputDir "blobs-a-borrar.txt"
$paraBorrar | ForEach-Object { $_.Blobs -split ' ' } |
    Where-Object { $_ } | Sort-Object -Unique |
    Set-Content -Path $blobsPath -Encoding ascii

$rutasPath = Join-Path $OutputDir "rutas-a-borrar.txt"
$paraBorrar | Select-Object -ExpandProperty Ruta | Sort-Object -Unique |
    Set-Content -Path $rutasPath -Encoding utf8

$numBlobs = @(Get-Content $blobsPath).Count

# --- Comandos listos --------------------------------------------------------
$cmdPath = Join-Path $OutputDir "comandos-limpieza.txt"
@"
# ===========================================================================
# COMANDOS DE LIMPIEZA - repo: $RepoPath
# Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
# ===========================================================================
# Requisito:  pip install git-filter-repo
# Trabaja SIEMPRE sobre un clon --mirror desechable, nunca sobre tu clon de trabajo.

# --- OPCION A: borrar blobs exactos (quirurgico) ---------------------------
# Borra solo esas $numBlobs versiones. Si el archivo tuvo versiones pequenias,
# esas se conservan. Es la opcion mas segura.

git filter-repo --strip-blobs-with-ids "$blobsPath" --force

# --- OPCION B: borrar rutas completas --------------------------------------
# Elimina el archivo entero del historial, todas sus versiones.

git filter-repo --invert-paths --paths-from-file "$rutasPath" --force

# --- OPCION C: cualquier cosa sobre el limite ------------------------------
# La bruta. No necesita listas.

git filter-repo --strip-blobs-bigger-than ${StripMB}M --force

# --- OPCION D: mover a LFS conservando el historial ------------------------
# Los archivos siguen existiendo, pero como punteros LFS.

git lfs migrate import --everything --include="*.zip,*.jar,*.war,*.ear"

# --- Verificar despues -----------------------------------------------------
git count-objects -vH
git gc --prune=now --aggressive

# --- Empujar a GitHub ------------------------------------------------------
# El repo en GitHub debe estar VACIO (sin README, sin .gitignore).
git remote add github https://github.com/TU-ORG/TU-REPO.git
git push --mirror github
"@ | Set-Content -Path $cmdPath -Encoding utf8

# --- HTML -------------------------------------------------------------------
$rows = ($reporte | ForEach-Object {
    $cls = switch ($_.Estado) { "BLOQUEA" { "bloquea" } "ADVIERTE" { "advierte" } default { "" } }
    $ram = if ($SkipBranchMapping) { "<span style='color:#888'>(no mapeado)</span>" }
           elseif ($_.Ramas)      { ConvertTo-HtmlSafe $_.Ramas }
           else                   { "<em>solo historial</em>" }
    $rt  = ConvertTo-HtmlSafe $_.Ruta
    $tg  = ConvertTo-HtmlSafe $_.Tags
    "<tr class='$cls'><td>$($_.Estado)</td><td class='n'>$($_.MaxMB)</td><td class='n'>$($_.TotalHistMB)</td><td class='n'>$($_.Versiones)</td><td>$($_.EnHEAD)</td><td class='r'>$ram</td><td class='r'>$tg</td><td class='p'>$rt</td><td>$($_.Accion)</td></tr>"
}) -join "`n"

$bloquean = @($reporte | Where-Object Estado -eq "BLOQUEA").Count
$muertos  = @($reporte | Where-Object EnHEAD -eq "NO").Count
$pesoTot  = [math]::Round((($reporte | Measure-Object TotalHistMB -Sum).Sum), 2)

$html = @"
<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<title>Reporte de migracion</title>
<style>
 body{font-family:-apple-system,Segoe UI,sans-serif;margin:2rem;background:#fafafa;color:#1a1a1a}
 h1{font-size:1.4rem} .meta{color:#666;font-size:.85rem;margin-bottom:1.5rem}
 .cards{display:flex;gap:1rem;margin-bottom:1.5rem;flex-wrap:wrap}
 .card{background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:1rem 1.25rem;min-width:150px}
 .card .v{font-size:1.6rem;font-weight:600} .card .l{font-size:.8rem;color:#666}
 .card.red .v{color:#c62828} .card.amber .v{color:#e68a00}
 table{border-collapse:collapse;width:100%;background:#fff;font-size:.85rem}
 th{background:#2d2d2d;color:#fff;text-align:left;padding:.5rem;position:sticky;top:0}
 td{padding:.4rem .5rem;border-bottom:1px solid #eee;vertical-align:top}
 td.n{text-align:right;font-variant-numeric:tabular-nums}
 td.p{font-family:ui-monospace,Consolas,monospace;font-size:.78rem;word-break:break-all;max-width:380px}
 td.r{font-size:.78rem;color:#555;max-width:200px}
 tr.bloquea{background:#fff0f0} tr.advierte{background:#fffaf0}
 tr:hover{background:#eef6ff}
 #f{padding:.5rem;width:320px;margin-bottom:.75rem;border:1px solid #ccc;border-radius:6px}
</style></head><body>
<h1>Reporte de migracion &mdash; archivos grandes</h1>
<div class="meta">$RepoPath &middot; $(Get-Date -Format 'yyyy-MM-dd HH:mm') &middot; umbral $ThresholdMB MB</div>
<div class="cards">
 <div class="card red"><div class="v">$bloquean</div><div class="l">bloquean el push</div></div>
 <div class="card amber"><div class="v">$muertos</div><div class="l">ya no estan en HEAD</div></div>
 <div class="card"><div class="v">$pesoTot</div><div class="l">MB en historial</div></div>
 <div class="card"><div class="v">$($reporte.Count)</div><div class="l">archivos listados</div></div>
</div>
<input id="f" placeholder="Filtrar por ruta, rama o extension...">
<table id="t"><thead><tr>
<th>Estado</th><th>Max MB</th><th>Hist MB</th><th>Vers</th><th>HEAD</th><th>Ramas</th><th>Tags</th><th>Ruta</th><th>Accion</th>
</tr></thead><tbody>
$rows
</tbody></table>
<script>
document.getElementById('f').addEventListener('input',function(e){
  var q=e.target.value.toLowerCase();
  document.querySelectorAll('#t tbody tr').forEach(function(r){
    r.style.display = r.textContent.toLowerCase().includes(q) ? '' : 'none';
  });
});
</script>
</body></html>
"@

$htmlPath = Join-Path $OutputDir "reporte-migracion.html"
$html | Set-Content -Path $htmlPath -Encoding utf8

# ===========================================================================
# Resumen en consola
# ===========================================================================
Write-Section "RESUMEN"

$reporte | Select-Object -First 20 |
    Format-Table Estado, MaxMB, Versiones, EnHEAD, NumRamas, Archivo -AutoSize

Write-Host ""
Write-Host "Ramas con archivos grandes:" -ForegroundColor Cyan
$reporte | ForEach-Object { $_.Ramas -split ';\s*' } | Where-Object { $_ } |
    Group-Object | Sort-Object Count -Descending | Select-Object -First 15 |
    Select-Object @{n='Rama';e={$_.Name}}, @{n='Archivos';e={$_.Count}} |
    Format-Table -AutoSize

Write-Host "Bloquean el push : $bloquean" -ForegroundColor $(if($bloquean){"Red"}else{"Green"})
Write-Host "Muertos (no HEAD): $muertos"
Write-Host "Blobs marcados para borrar: $numBlobs"
Write-Host ""
Write-Host "Archivos generados en $OutputDir :" -ForegroundColor Cyan
Write-Host "  reporte-migracion.html   <- abre este primero"
Write-Host "  reporte-migracion.csv"
Write-Host "  blobs-a-borrar.txt       <- para --strip-blobs-with-ids"
Write-Host "  rutas-a-borrar.txt       <- para --paths-from-file"
Write-Host "  comandos-limpieza.txt    <- comandos listos para copiar"

# Verificacion de encoding: si quedaron '?' en las rutas, el borrado fallaria en silencio
$corruptas = @($reporte | Where-Object { $_.Ruta -match '\?' })
if ($corruptas.Count -gt 0) {
    Write-Host ""
    Write-Warning "$($corruptas.Count) rutas contienen '?' - probable problema de encoding."
    Write-Warning "Esas rutas NO coincidiran en git filter-repo. Ejemplo:"
    Write-Warning "  $($corruptas[0].Ruta)"
    Write-Warning "Usa PowerShell 7 (pwsh) o revisa la codepage de tu consola: chcp 65001"
}

[Console]::OutputEncoding = $encodingPrevio
