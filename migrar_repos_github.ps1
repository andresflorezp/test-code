<#
  Migra repos archivados (.tar.gz) a GitHub usando SOLO git (sin API de GitHub).

  Entrada: uno o varios archivos pegados desde Excel (coma, punto y coma o tab; encabezado opcional).
           Se leen dos tipos de URL, en cualquier orden, mezcladas o en archivos separados:
             - Bitbucket: .../projects/<PROYECTO>/repos/<nombre_repo>/browse
             - Descarga : .../<PROYECTO>/<nombre_repo>-<build>.tar.gz
           Se cruzan por <nombre_repo>. El destino en GitHub SIEMPRE se deriva de Bitbucket:
             https://github.com/<Org>/<appId>.<PROYECTO>.<nombre_repo>.git
             (appId = prefijo del nombre del repo; se puede fijar con -AppId)
           Si no hay URL de Bitbucket para un repo, se usa el proyecto/nombre del .tar.gz.

  Por cada repo:
    1. Descarga y extrae el .tar.gz
    2. Encuentra el repo git adentro
    3. Mirror local + convierte remotes/origin/* en ramas
    4. Renombra master -> main
    5. Verifica acceso al repo de GitHub (git ls-remote)
    6. Sube main primero (para que GitHub la tome como default en repos vacios), luego todas las ramas y todos los tags
    7. Verifica con git ls-remote cual quedo como default
  Si una falla, sigue con la siguiente y al final dice por que.

  Uso:
    .\migrar_repos_github.ps1 -DryRun                                  # analiza, no sube nada
    .\migrar_repos_github.ps1 -ListaRepos .\bitbucket.txt,.\urls.txt   # listas separadas
    .\migrar_repos_github.ps1                                          # migra
#>
param(
    [string[]]$ListaRepos = @(".\repos.csv"),
    [string]$Destino    = ".\descargas",
    [string]$Org        = "BnmxInternal",   # org de GitHub para las URLs derivadas
    [string]$GitHubHost = "github.com",
    [string]$AppId      = "",               # vacio = usar el prefijo del nombre del repo
    [switch]$DryRun,
    [switch]$BorrarMasterRemoto   # borra 'master' en GitHub si ya existia y el default quedo en main
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "No encuentro git en el PATH." }
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) { throw "No encuentro tar.exe (viene con Windows 10/11)." }
foreach ($f in $ListaRepos) { if (-not (Test-Path $f)) { throw "No encuentro $f" } }

New-Item -ItemType Directory -Force -Path $Destino | Out-Null
$MirrorDir = Join-Path $Destino "_mirrors"
New-Item -ItemType Directory -Force -Path $MirrorDir | Out-Null

$GitGlobal = @('-c', 'safe.directory=*', '-c', 'http.postBuffer=524288000')

# ---------- Helpers ----------
function Invoke-Git {
    param([string[]]$GitArgs)
    $out = & git @GitGlobal @GitArgs 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Out = ($out -join "`n") }
}

function Short([string]$texto) {
    (($texto -split "`n") | Where-Object { $_.Trim() } | Select-Object -Last 4) -join ' | '
}

function Test-Ref([string]$repo, [string]$ref) {
    (Invoke-Git @('-C', $repo, 'show-ref', '--verify', '--quiet', $ref)).Ok
}

function Get-Refs([string]$repo, [string]$prefijo) {
    @((Invoke-Git @('-C', $repo, 'for-each-ref', '--format=%(refname)', $prefijo)).Out -split "`n" |
        Where-Object { $_.Trim() })
}

function Find-GitRepo([string]$carpeta) {
    $dotgit = Get-ChildItem $carpeta -Recurse -Force -Directory -Filter '.git' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($dotgit) { return $dotgit.Parent.FullName }
    $candidatos = @(Get-Item $carpeta) + @(Get-ChildItem $carpeta -Recurse -Force -Directory -ErrorAction SilentlyContinue)
    foreach ($d in $candidatos) {
        $p = $d.FullName
        if ((Test-Path "$p\HEAD") -and (Test-Path "$p\objects") -and (Test-Path "$p\refs")) { return $p }
    }
    return $null
}

function Get-RemoteDefault([string]$gh) {
    $g = Invoke-Git @('ls-remote', '--symref', $gh, 'HEAD')
    if ($g.Ok -and $g.Out -match 'ref: refs/heads/(\S+)\s+HEAD') { return $Matches[1] }
    return $null
}

# ---------- Leer la lista ----------
function New-GitHubUrl([string]$proyecto, [string]$repo) {
    # appId.proyecto.nombre_repo  (nombre_repo tal cual viene en Bitbucket)
    $app = if ($AppId) { $AppId } else { ($repo -split '_')[0] }
    "https://$GitHubHost/$Org/$app.$proyecto.$repo.git"
}

# Junta todos los tokens de todos los archivos
$tokens = foreach ($f in $ListaRepos) {
    foreach ($linea in Get-Content $f) {
        $linea -split '[;,\t]' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }
    }
}

# Indice nombre_repo -> URL de descarga  (.../<PROYECTO>/<nombre_repo>-<build>.tar.gz)
$descargas = @{}
foreach ($t in $tokens) {
    if ($t -match '/([^/]+)/([^/]+?)-\d+\.tar\.gz$' -or $t -match '/([^/]+)/([^/]+?)\.tar\.gz$') {
        $repo = $Matches[2]
        if (-not $descargas.ContainsKey($repo)) {
            $descargas[$repo] = [pscustomobject]@{ Url = $t; Proyecto = $Matches[1] }
        }
    }
}

# Repos segun Bitbucket  (.../projects/<PROYECTO>/repos/<nombre_repo>[/browse])
$repos = New-Object System.Collections.Generic.List[object]
$vistos = @{}
foreach ($t in $tokens) {
    if ($t -match '/projects/([^/]+)/repos/([^/]+?)(/|$)') {
        $repo = $Matches[2]
        if (-not $vistos.ContainsKey($repo)) {
            $vistos[$repo] = $true
            $repos.Add([pscustomobject]@{ Repo = $repo; Proyecto = $Matches[1]; Origen = 'bitbucket' })
        }
    }
}

# Descargas sin su URL de Bitbucket: igual se procesan, con el proyecto del .tar.gz
foreach ($k in $descargas.Keys) {
    if (-not $vistos.ContainsKey($k)) {
        $repos.Add([pscustomobject]@{ Repo = $k; Proyecto = $descargas[$k].Proyecto; Origen = 'tar.gz' })
    }
}

$filas = foreach ($x in $repos) {
    [pscustomobject]@{
        Repo     = $x.Repo
        Descarga = $(if ($descargas.ContainsKey($x.Repo)) { $descargas[$x.Repo].Url } else { $null })
        GitHub   = New-GitHubUrl $x.Proyecto $x.Repo
    }
}
$filas = @($filas)
if ($filas.Count -eq 0) { throw "No encontre URLs de Bitbucket ni de .tar.gz en: $($ListaRepos -join ', ')" }

$sinDescarga = @($filas | Where-Object { -not $_.Descarga }).Count
Write-Host "Repos detectados: $($filas.Count)$(if ($sinDescarga) { " ($sinDescarga sin .tar.gz)" })" -ForegroundColor DarkGray

# ---------- Proceso ----------
$resultados = New-Object System.Collections.Generic.List[object]
$i = 0

foreach ($fila in $filas) {
    $i++
    $url     = $fila.Descarga
    $gh      = $fila.GitHub
    $archivo = if ($url) { Split-Path $url -Leaf } else { "" }
    $nombre  = if ($url) { $archivo -replace '\.tar\.gz$', '' } else { $fila.Repo }

    Write-Host "`n[$i/$($filas.Count)] $($fila.Repo)  ->  $gh" -ForegroundColor Cyan

    $r = [ordered]@{
        Repo    = $fila.Repo
        Archivo = $nombre
        GitHub  = $gh
        Estado  = 'OK'
        Ramas   = 0
        Tags    = 0
        Default = ''
        Detalle = ''
    }
    $avisos = New-Object System.Collections.Generic.List[string]
    $work = Join-Path $MirrorDir "$nombre.git"

    try {
        if (-not $url) { throw "No encontre el .tar.gz de este repo en las listas (falta la fila de descarga)" }

        # 1. Descargar
        $tgz = Join-Path $Destino $archivo
        if (-not (Test-Path $tgz)) {
            Write-Host "  Descargando..."
            try {
                Invoke-WebRequest -Uri $url -OutFile $tgz -UseDefaultCredentials -ErrorAction Stop
            } catch {
                if (Test-Path $tgz) { Remove-Item $tgz -Force }
                throw "Descarga fallo: $($_.Exception.Message)"
            }
        } else { Write-Host "  Ya descargado, lo reuso" }

        # 2. Extraer
        $carpeta = Join-Path $Destino $nombre
        if (-not (Test-Path $carpeta)) {
            Write-Host "  Extrayendo..."
            New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
            $tarOut = & tar -xzf $tgz -C $carpeta 2>&1 | ForEach-Object { "$_" }
            if ($LASTEXITCODE -ne 0) {
                Remove-Item $carpeta -Recurse -Force -ErrorAction SilentlyContinue
                throw "tar no pudo extraer (archivo corrupto, incompleto o rutas muy largas): $(Short ($tarOut -join "`n"))"
            }
        } else { Write-Host "  Ya extraido, lo reuso" }

        # 3. Encontrar el repo
        $origen = Find-GitRepo $carpeta
        if (-not $origen) { throw "No encontre un repo git dentro del .tar.gz" }

        # 4. Mirror limpio
        if (Test-Path $work) { Remove-Item $work -Recurse -Force }
        $g = Invoke-Git @('clone', '--mirror', '--quiet', $origen, $work)
        if (-not $g.Ok) { throw "git clone --mirror fallo (repo corrupto?): $(Short $g.Out)" }

        # 5. remotes/origin/* -> ramas
        foreach ($ref in Get-Refs $work 'refs/remotes') {
            if ($ref -match '/HEAD$') { continue }
            $rama = ($ref -split '/', 4)[3]
            if (-not (Test-Ref $work "refs/heads/$rama")) {
                Invoke-Git @('-C', $work, 'update-ref', "refs/heads/$rama", $ref) | Out-Null
            }
        }

        # 6. master -> main
        $tieneMaster = Test-Ref $work 'refs/heads/master'
        $tieneMain   = Test-Ref $work 'refs/heads/main'
        $ambas       = $tieneMaster -and $tieneMain
        if ($ambas) {
            $avisos.Add("Tiene master y main a la vez: no renombre, se suben ambas")
        } elseif ($tieneMaster) {
            $g = Invoke-Git @('-C', $work, 'branch', '-m', 'master', 'main')
            if (-not $g.Ok) { throw "No pude renombrar master a main: $(Short $g.Out)" }
            $tieneMain = $true
        }
        if (-not $tieneMain) { $avisos.Add("No tiene master ni main") }

        $r.Ramas = (Get-Refs $work 'refs/heads').Count
        $r.Tags  = (Get-Refs $work 'refs/tags').Count
        if ($r.Ramas -eq 0) { throw "El repo no tiene ninguna rama (vacio)" }
        Write-Host "  $($r.Ramas) ramas, $($r.Tags) tags"

        # 7. Acceso y estado del repo en GitHub
        $lr = Invoke-Git @('ls-remote', '--heads', $gh)
        if (-not $lr.Ok) {
            throw "No hay acceso al repo en GitHub (no existe, sin permisos o sin SSO autorizado): $(Short $lr.Out)"
        }
        $remotoVacio      = -not ($lr.Out -match 'refs/heads/')
        $remotoTieneMaster = $lr.Out -match 'refs/heads/master(\s|$)'
        if (-not $remotoVacio) { $avisos.Add("El repo en GitHub ya tenia ramas") }

        if ($DryRun) {
            $r.Estado = 'DRYRUN'
            $avisos.Add($(if ($remotoVacio) { "Acceso OK, repo vacio" } else { "Acceso OK" }))
        } else {
            # 8. main primero -> en un repo vacio GitHub la toma como default
            if ($tieneMain) {
                Write-Host "  Subiendo main..."
                $g = Invoke-Git @('-C', $work, 'push', $gh, 'refs/heads/main:refs/heads/main')
                if (-not $g.Ok) { throw "Push de main fallo: $(Short $g.Out)" }
            }

            # 9. Resto de ramas
            Write-Host "  Subiendo todas las ramas..."
            $g = Invoke-Git @('-C', $work, 'push', $gh, 'refs/heads/*:refs/heads/*')
            if (-not $g.Ok) { throw "Push de ramas fallo: $(Short $g.Out)" }

            # 10. Tags
            if ($r.Tags -gt 0) {
                Write-Host "  Subiendo tags..."
                $g = Invoke-Git @('-C', $work, 'push', $gh, 'refs/tags/*:refs/tags/*')
                if (-not $g.Ok) {
                    $r.Estado = 'PARCIAL'
                    $avisos.Add("Ramas OK pero push de tags fallo: $(Short $g.Out)")
                }
            }

            # 11. Verificar default
            $def = Get-RemoteDefault $gh
            $r.Default = $def
            if ($tieneMain -and $def -ne 'main') {
                $r.Estado = 'PARCIAL'
                $avisos.Add("Default en GitHub quedo '$def', no main. Con git puro no se puede cambiar: hacerlo en Settings > General > Default branch")
            }

            # 12. (Opcional) borrar master remoto
            if ($BorrarMasterRemoto -and $remotoTieneMaster -and -not $ambas) {
                if ($def -eq 'main') {
                    $g = Invoke-Git @('-C', $work, 'push', $gh, '--delete', 'master')
                    if ($g.Ok) { $avisos.Add("Se borro 'master' en GitHub") }
                    else { $avisos.Add("No pude borrar 'master' en GitHub: $(Short $g.Out)") }
                } else {
                    $avisos.Add("No borre 'master' en GitHub porque sigue siendo el default")
                }
            }
        }
    }
    catch {
        $r.Estado = 'ERROR'
        $avisos.Add("$_")
    }
    finally {
        if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $r.Detalle = $avisos -join '; '
    $color = switch ($r.Estado) { 'OK' { 'Green' } 'DRYRUN' { 'Gray' } 'PARCIAL' { 'Yellow' } default { 'Red' } }
    Write-Host "  => $($r.Estado)  $($r.Detalle)" -ForegroundColor $color
    $resultados.Add([pscustomobject]$r)
}

# ---------- Resumen ----------
$reporte = Join-Path $Destino "reporte_migracion.csv"
$resultados | Export-Csv $reporte -NoTypeInformation -Encoding UTF8

Write-Host "`n================ RESUMEN ================" -ForegroundColor Cyan
$resultados | Format-Table Repo, Estado, Ramas, Tags, Default -AutoSize

$problemas = $resultados | Where-Object { $_.Estado -in 'ERROR', 'PARCIAL' }
if ($problemas) {
    Write-Host "Los que NO pasaron completos y por que:" -ForegroundColor Red
    foreach ($p in $problemas) {
        Write-Host "  - $($p.Repo) [$($p.Estado)]: $($p.Detalle)" -ForegroundColor Red
    }
}

$ok = @($resultados | Where-Object { $_.Estado -eq 'OK' }).Count
Write-Host "`nOK: $ok / $($resultados.Count)   Reporte: $(Resolve-Path $reporte)"
