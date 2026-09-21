<#
  Migra repos archivados (.tar.gz) de Bitbucket a GitHub usando SOLO git (sin API de GitHub).

  Entrada: uno o varios archivos pegados desde Excel (coma, punto y coma o tab; encabezado opcional).
           Se leen dos tipos de URL, en cualquier orden, mezcladas o en archivos separados:
             - Bitbucket: .../projects/<PROYECTO>/repos/<nombre_repo>/browse
             - Descarga : .../<PROYECTO>/<nombre_repo>-<build>.tar.gz
           Se cruzan por <nombre_repo>. El destino en GitHub se deriva de Bitbucket:
             https://github.com/<Org>/<appId>.<PROYECTO>.<nombre_repo>.git

  Por defecto sube las ramas TAL CUAL vienen de Bitbucket (master, development, release) mas
  todos los tags. No toca 'main', porque suele estar protegida por un ruleset. El cambio de
  master a main se hace despues a mano, y el reporte trae las URLs listas para eso.

  Con -RenombrarAMain hace el flujo completo: renombra master -> main, fusiona el commit
  inicial del repo provisionado y sube main (solo funciona si el ruleset lo permite).

  Uso:
    .\migrar_repos_github.ps1 -DryRun                  # analiza, no sube nada
    .\migrar_repos_github.ps1 -Solo pdmgm003           # prueba con uno
    .\migrar_repos_github.ps1                          # sube master/development/release + tags
    .\migrar_repos_github.ps1 -RenombrarAMain          # ademas renombra a main y fusiona
#>
param(
    [string[]]$ListaRepos = @(".\repos.csv"),
    [string]$Destino      = ".\descargas",
    [string]$Org          = "BnmxInternal",
    [string]$GitHubHost   = "github.com",
    [string]$AppId        = "",            # vacio = prefijo del nombre del repo
    [string]$Solo         = "",            # procesa solo los repos cuyo nombre contenga esto

    [switch]$RenombrarAMain,               # renombra master->main y fusiona el commit inicial
    [string]$RamaSiBloqueo = "",           # si una rama la bloquea el ruleset, sube su contenido aqui

    # Rama extra para el PR hacia main: sale de master y le fusiona lo que ya hay en main,
    # asi el PR queda sin conflictos y master se sube intacto. "" la desactiva.
    [string]$RamaPR = "migracion-main",

    # Que hacer si la rama ya existe en GitHub con otra historia:
    #   fusionar = merge --allow-unrelated-histories, sin --force (sirve con rulesets)  [default]
    #   forzar   = git push --force (falla si el ruleset lo bloquea)
    [ValidateSet('fusionar','forzar')]
    [string]$Estrategia   = 'fusionar',
    [string]$MergeNombre  = 'migracion-bitbucket',
    [string]$MergeEmail   = 'migracion@noreply.local',
    [string]$MergeMensaje = 'Merge del repo provisionado con la historia migrada desde Bitbucket',

    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "No encuentro git en el PATH." }
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) { throw "No encuentro tar.exe (viene con Windows 10/11)." }
foreach ($f in $ListaRepos) { if (-not (Test-Path $f)) { throw "No encuentro $f" } }

New-Item -ItemType Directory -Force -Path $Destino | Out-Null
# Absoluta: git -C cambia de directorio, una ruta relativa se resolveria dentro del mirror
$Destino   = (Resolve-Path $Destino).Path
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

# Traduce los errores de push a algo accionable y rescata el motivo que manda el servidor
function Explain-Push([string]$salida) {
    $remotas = @(($salida -split "`n") |
        Where-Object { $_ -match '^remote:\s*\S' } |
        ForEach-Object { ($_ -replace '^remote:\s*', '').Trim(' -') } |
        Where-Object { $_ -and $_ -notmatch '^(Resolving|Counting|Compressing|Writing|Total)' })

    $causa = switch -Regex ($salida) {
        'rule violations|protected branch|cannot force-push|GH006|GH013' {
            'BLOQUEADO POR UN RULESET de GitHub'; break
        }
        'non-fast-forward|fetch first|behind its remote' {
            'La rama en GitHub tiene commits que no estan en Bitbucket'; break
        }
        'pre-receive hook declined' { 'Un hook del servidor rechazo el push'; break }
        'exceeds.*file size limit|GH001' { 'Hay archivos > 100 MB en la historia: se necesita Git LFS'; break }
        'Permission.*denied|403|Write access to repository not granted' {
            'Sin permisos de escritura (revisa el SSO de la org)'; break
        }
        default { $null }
    }
    $detalle = if ($remotas) { $remotas -join ' | ' } else { Short $salida }
    if ($causa) { "$causa >> $detalle" } else { $detalle }
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

function New-GitHubUrl([string]$proyecto, [string]$repo) {
    $app = if ($AppId) { $AppId } else { ($repo -split '_')[0] }
    "https://$GitHubHost/$Org/$app.$proyecto.$repo.git"
}

function Get-WebUrl([string]$gh) { $gh -replace '\.git$', '' }

# Fusiona $refOrigen dentro de $rama usando un worktree temporal (el mirror es bare).
# -X ours: ante conflicto gana el contenido de Bitbucket; lo que solo existe del otro lado se conserva.
function Merge-Ref {
    param([string]$repo, [string]$rama, [string]$refOrigen, [string]$wtPath)
    if (Test-Path $wtPath) { Remove-Item $wtPath -Recurse -Force }
    $g = Invoke-Git @('-C', $repo, 'worktree', 'add', '--quiet', $wtPath, $rama)
    if (-not $g.Ok) { return [pscustomobject]@{ Ok = $false; Out = "No pude preparar el worktree: $(Short $g.Out)" } }
    try {
        Invoke-Git @('-C', $wtPath,
            '-c', "user.name=$MergeNombre", '-c', "user.email=$MergeEmail",
            'merge', '--allow-unrelated-histories', '-X', 'ours', '--no-edit',
            '-m', $MergeMensaje, $refOrigen)
    } finally {
        Invoke-Git @('-C', $repo, 'worktree', 'remove', '--force', $wtPath) | Out-Null
    }
}

# ---------- Leer las listas ----------
$tokens = foreach ($f in $ListaRepos) {
    foreach ($linea in Get-Content $f) {
        $linea -split '[;,\t]' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }
    }
}

$descargas = @{}
foreach ($t in $tokens) {
    if ($t -match '/([^/]+)/([^/]+?)-\d+\.tar\.gz$' -or $t -match '/([^/]+)/([^/]+?)\.tar\.gz$') {
        if (-not $descargas.ContainsKey($Matches[2])) {
            $descargas[$Matches[2]] = [pscustomobject]@{ Url = $t; Proyecto = $Matches[1] }
        }
    }
}

$repos  = New-Object System.Collections.Generic.List[object]
$vistos = @{}
foreach ($t in $tokens) {
    if ($t -match '/projects/([^/]+)/repos/([^/]+?)(/|$)') {
        if (-not $vistos.ContainsKey($Matches[2])) {
            $vistos[$Matches[2]] = $true
            $repos.Add([pscustomobject]@{ Repo = $Matches[2]; Proyecto = $Matches[1] })
        }
    }
}
foreach ($k in $descargas.Keys) {
    if (-not $vistos.ContainsKey($k)) {
        $repos.Add([pscustomobject]@{ Repo = $k; Proyecto = $descargas[$k].Proyecto })
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

if ($Solo) {
    $filas = @($filas | Where-Object { $_.Repo -like "*$Solo*" })
    if ($filas.Count -eq 0) { throw "Ningun repo coincide con -Solo '$Solo'" }
    Write-Host "Filtro -Solo '$Solo': $($filas.Count) repo(s)" -ForegroundColor Yellow
}

$sinDescarga = @($filas | Where-Object { -not $_.Descarga }).Count
Write-Host "Repos detectados: $($filas.Count)$(if ($sinDescarga) { " ($sinDescarga sin .tar.gz)" })" -ForegroundColor DarkGray

# ---------- Proceso ----------
$resultados = New-Object System.Collections.Generic.List[object]
$i = 0

foreach ($fila in $filas) {
    $i++
    $url     = $fila.Descarga
    $gh      = $fila.GitHub
    $web     = Get-WebUrl $gh
    $archivo = if ($url) { Split-Path $url -Leaf } else { "" }
    $nombre  = if ($url) { $archivo -replace '\.tar\.gz$', '' } else { $fila.Repo }

    Write-Host "`n[$i/$($filas.Count)] $($fila.Repo)  ->  $gh" -ForegroundColor Cyan

    $r = [ordered]@{
        Repo        = $fila.Repo
        Estado      = 'OK'
        Ramas       = ''
        Tags        = 0
        Default     = ''
        UrlRepo     = $web
        UrlRamas    = "$web/branches"
        UrlDefault  = "$web/settings/branches"
        UrlPR       = ''
        Detalle     = ''
    }
    $avisos = New-Object System.Collections.Generic.List[string]
    $work = Join-Path $MirrorDir "$nombre.git"

    try {
        if (-not $url) { throw "No encontre el .tar.gz de este repo en las listas" }

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
                throw "tar no pudo extraer (corrupto, incompleto o rutas muy largas): $(Short ($tarOut -join "`n"))"
            }
        } else { Write-Host "  Ya extraido, lo reuso" }

        # 3. Encontrar el repo git adentro
        $origen = Find-GitRepo $carpeta
        if (-not $origen) { throw "No encontre un repo git dentro del .tar.gz" }

        # 4. Mirror limpio
        if (Test-Path $work) { Remove-Item $work -Recurse -Force }
        $g = Invoke-Git @('clone', '--mirror', '--quiet', $origen, $work)
        if (-not $g.Ok) { throw "git clone --mirror fallo (repo corrupto?): $(Short $g.Out)" }

        # 5. remotes/origin/* -> ramas locales
        foreach ($ref in Get-Refs $work 'refs/remotes') {
            if ($ref -match '/HEAD$') { continue }
            $rama = ($ref -split '/', 4)[3]
            if (-not (Test-Ref $work "refs/heads/$rama")) {
                Invoke-Git @('-C', $work, 'update-ref', "refs/heads/$rama", $ref) | Out-Null
            }
        }

        # 6. Rama principal
        $tieneMaster = Test-Ref $work 'refs/heads/master'
        $tieneMain   = Test-Ref $work 'refs/heads/main'
        $principal   = ''
        if ($RenombrarAMain) {
            if ($tieneMaster -and $tieneMain) {
                $avisos.Add("Tiene master y main a la vez: no renombre, se suben ambas")
                $principal = 'main'
            } elseif ($tieneMaster) {
                $g = Invoke-Git @('-C', $work, 'branch', '-m', 'master', 'main')
                if (-not $g.Ok) { throw "No pude renombrar master a main: $(Short $g.Out)" }
                $avisos.Add("master renombrada a main")
                $principal = 'main'
            } elseif ($tieneMain) { $principal = 'main' }
        } else {
            $principal = if ($tieneMaster) { 'master' } elseif ($tieneMain) { 'main' } else { '' }
        }

        $ramas = @(Get-Refs $work 'refs/heads' | ForEach-Object { ($_ -split '/', 3)[2] })
        $r.Tags = (Get-Refs $work 'refs/tags').Count
        if ($ramas.Count -eq 0) { throw "El repo no tiene ninguna rama (vacio)" }
        $r.Ramas = $ramas.Count
        Write-Host "  $($ramas.Count) ramas ($($ramas -join ', ')), $($r.Tags) tags"

        # 7. Acceso y estado en GitHub
        $lr = Invoke-Git @('ls-remote', '--heads', $gh)
        if (-not $lr.Ok) {
            throw "No hay acceso al repo en GitHub (no existe, sin permisos o sin SSO): $(Explain-Push $lr.Out)"
        }
        $remotoVacio = -not ($lr.Out -match 'refs/heads/')
        $ramasRemotas = @(($lr.Out -split "`n") | ForEach-Object {
            if ($_ -match 'refs/heads/(\S+)') { $Matches[1] } }) | Where-Object { $_ }
        if (-not $remotoVacio) { $avisos.Add("En GitHub ya existian: $($ramasRemotas -join ', ')") }

        if ($DryRun) {
            if ($RamaPR -and $principal -and $principal -ne 'main' -and $ramasRemotas -contains 'main') {
                $r.UrlPR = "$web/compare/main...${RamaPR}?expand=1"
                $avisos.Add("Se creara la rama '$RamaPR' para el PR")
            }
            $r.Estado = 'DRYRUN'
            $avisos.Add($(if ($remotoVacio) { "Acceso OK, repo vacio" } else { "Acceso OK" }))
        } else {
            # 8. Si la rama principal ya existe en GitHub con otra historia, reconciliar
            if ($Estrategia -eq 'fusionar' -and $principal -and ($ramasRemotas -contains $principal)) {
                $g = Invoke-Git @('-C', $work, 'fetch', '--quiet', $gh, "+refs/heads/${principal}:refs/gh/$principal")
                if ($g.Ok -and (Test-Ref $work "refs/gh/$principal")) {
                    $yaIntegrado = (Invoke-Git @('-C', $work, 'merge-base', '--is-ancestor',
                                    "refs/gh/$principal", "refs/heads/$principal")).Ok
                    if (-not $yaIntegrado) {
                        Write-Host "  Fusionando lo que ya hay en GitHub dentro de $principal..." -ForegroundColor Yellow
                        $g = Merge-Ref $work $principal "refs/gh/$principal" (Join-Path $MirrorDir "$nombre.wt")
                        if (-not $g.Ok) { throw "La fusion fallo: $(Short $g.Out)" }
                        $avisos.Add("$principal fusionada con lo que ya habia en GitHub")
                    }
                }
            }

            $fuerza = if ($Estrategia -eq 'forzar') { @('--force') } else { @() }

            # 9. Push rama por rama: si un ruleset bloquea una, las demas igual suben
            $orden = @($ramas | Where-Object { $_ -eq $principal }) + @($ramas | Where-Object { $_ -ne $principal })
            $okRamas = New-Object System.Collections.Generic.List[string]
            $noRamas = New-Object System.Collections.Generic.List[string]
            foreach ($rama in $orden) {
                Write-Host "  Subiendo $rama..."
                $g = Invoke-Git (@('-C', $work, 'push') + $fuerza + @($gh, "refs/heads/${rama}:refs/heads/$rama"))
                if ($g.Ok) { $okRamas.Add($rama) }
                else {
                    $noRamas.Add($rama)
                    $avisos.Add("Rama '$rama' rechazada: $(Explain-Push $g.Out)")
                    Write-Host "    rechazada" -ForegroundColor Red
                }
            }
            $r.Ramas = "$($okRamas.Count)/$($orden.Count)"

            # 10. Rama de respaldo si la principal quedo bloqueada
            if ($RamaSiBloqueo -and $principal -and ($noRamas -contains $principal)) {
                Write-Host "  $principal bloqueada: subiendo su contenido a '$RamaSiBloqueo'..." -ForegroundColor Yellow
                $g = Invoke-Git (@('-C', $work, 'push') + $fuerza + @($gh, "refs/heads/${principal}:refs/heads/$RamaSiBloqueo"))
                if ($g.Ok) {
                    $r.UrlPR = "$web/compare/${principal}...${RamaSiBloqueo}?expand=1"
                    $avisos.Add("'$principal' esta protegida: el contenido quedo en '$RamaSiBloqueo', abre un PR")
                } else {
                    $avisos.Add("Tampoco pude subir a '$RamaSiBloqueo': $(Explain-Push $g.Out)")
                }
            }

            if ($noRamas.Count -eq $orden.Count) { throw "Ninguna rama se pudo subir. $($avisos[-1])" }
            if ($noRamas.Count -gt 0) { $r.Estado = 'PARCIAL' }

            # 11. Tags
            if ($r.Tags -gt 0) {
                Write-Host "  Subiendo tags..."
                $g = Invoke-Git (@('-C', $work, 'push') + $fuerza + @($gh, 'refs/tags/*:refs/tags/*'))
                if (-not $g.Ok) {
                    $r.Estado = 'PARCIAL'
                    $avisos.Add("Push de tags fallo: $(Explain-Push $g.Out)")
                }
            }

            # 12. Rama lista para el PR: sale de la principal y le fusiona la main de GitHub.
            #     Asi master queda intacto y el PR hacia main no tiene conflictos.
            if ($RamaPR -and $principal -and $principal -ne 'main' -and ($ramasRemotas -contains 'main') `
                -and ($okRamas -contains $principal)) {
                Write-Host "  Preparando '$RamaPR' para el PR hacia main..." -ForegroundColor Yellow
                $g = Invoke-Git @('-C', $work, 'update-ref', "refs/heads/$RamaPR", "refs/heads/$principal")
                if ($g.Ok) {
                    $g = Invoke-Git @('-C', $work, 'fetch', '--quiet', $gh, '+refs/heads/main:refs/gh/main')
                    if ($g.Ok -and (Test-Ref $work 'refs/gh/main')) {
                        $g = Merge-Ref $work $RamaPR 'refs/gh/main' (Join-Path $MirrorDir "$nombre.pr.wt")
                        if ($g.Ok) {
                            $g = Invoke-Git (@('-C', $work, 'push') + $fuerza + @($gh, "refs/heads/${RamaPR}:refs/heads/$RamaPR"))
                            if ($g.Ok) {
                                $r.UrlPR = "$web/compare/main...${RamaPR}?expand=1"
                                $avisos.Add("Rama '$RamaPR' lista: PR hacia main sin conflictos")
                            } else {
                                $r.Estado = 'PARCIAL'
                                $avisos.Add("No pude subir '$RamaPR': $(Explain-Push $g.Out)")
                            }
                        } else {
                            $r.Estado = 'PARCIAL'
                            $avisos.Add("No pude fusionar main en '$RamaPR': $(Short $g.Out)")
                        }
                    }
                }
            }

            # 13. Que rama quedo de default en GitHub
            $r.Default = Get-RemoteDefault $gh
            if ($principal -and $r.Default -ne 'main') {
                $avisos.Add("Default en GitHub: '$($r.Default)'. Cambialo en $web/settings/branches")
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
try {
    $resultados | Export-Csv $reporte -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
} catch {
    $reporte = Join-Path $Destino "reporte_migracion_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $resultados | Export-Csv $reporte -NoTypeInformation -Encoding UTF8
    Write-Host "El reporte anterior estaba abierto (Excel?), guarde en uno nuevo." -ForegroundColor Yellow
}

Write-Host "`n================ RESUMEN ================" -ForegroundColor Cyan
$resultados | Format-Table Repo, Estado, Ramas, Tags, Default -AutoSize

$problemas = @($resultados | Where-Object { $_.Estado -in 'ERROR', 'PARCIAL' })
if ($problemas) {
    Write-Host "Los que NO pasaron completos y por que:" -ForegroundColor Red
    foreach ($p in $problemas) {
        Write-Host "  - $($p.Repo) [$($p.Estado)]: $($p.Detalle)" -ForegroundColor Red
    }
}

Write-Host "`n---------- URLs de los repos en GitHub ----------" -ForegroundColor Cyan
foreach ($x in $resultados) { Write-Host "  $($x.UrlRepo)" }
Write-Host "`nPara cambiar la rama por defecto de cada uno:" -ForegroundColor DarkGray
foreach ($x in $resultados) { Write-Host "  $($x.UrlDefault)" -ForegroundColor DarkGray }

$conPR = @($resultados | Where-Object { $_.UrlPR })
if ($conPR) {
    Write-Host "`nPara abrir el PR hacia main:" -ForegroundColor DarkGray
    foreach ($x in $conPR) { Write-Host "  $($x.UrlPR)" -ForegroundColor DarkGray }
}

$ok = @($resultados | Where-Object { $_.Estado -eq 'OK' }).Count
Write-Host "`nOK: $ok / $($resultados.Count)   Reporte: $reporte"
Write-Host "El CSV trae las columnas UrlRepo, UrlRamas, UrlDefault y UrlPR." -ForegroundColor DarkGray
