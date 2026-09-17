#!/usr/bin/env python3
"""
check_gitmodules.py  —  100% librería estándar (sin pip install)
================================================================

Audita repositorios de GitHub para saber si tienen (o no) el archivo `.gitmodules`.

Flujo:
  1. Lee el Excel (.xlsx) o CSV con las columnas: CSI, BB Repo (url de Bitbucket) y,
     opcionalmente, Github Repo (la url ya escrita a mano).
     El .xlsx se lee con zipfile + ElementTree (un .xlsx es un zip de XML), así que
     NO hace falta openpyxl ni pandas.

  2. Construye la URL de GitHub con la regla:
         https://github.com/<ORG>/<CSI>.<PROJECT_KEY>.<REPO_SLUG>.git

     donde PROJECT_KEY y REPO_SLUG salen de la url de Bitbucket:
         https://cedt-gct-bitbucket.nam.nsroot.net/bitbucket/scm/sbs/mx.local.oneeclipse.balance.git
                                                              ^^^  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                              key            slug
     CSI = 163950  ->  BnmxInternal/163950.sbs.mx.local.oneeclipse.balance

  3. Contra la API de GitHub (urllib) valida, por cada repo:
        - si el repo EXISTE
        - si está VACÍO / archivado
        - si tiene `.gitmodules` en la rama por defecto (o en TODAS con --all-branches)
        - qué submódulos declara ese archivo (path + url)
        - si hay "gitlinks" (entradas modo 160000 = submódulos reales en el árbol)
          aunque NO exista `.gitmodules`   <- el caso realmente roto
        - si la url construida no coincide con la del Excel (posible mal nombrado)
        - sugerencias de nombres parecidos cuando el repo no existe (--index-org)

  4. Genera en la carpeta de salida:
        - resultados.csv    (una fila por repo, todo el detalle)
        - resultados.xlsx   (lo mismo, escrito a mano sin librerías)
        - reporte.md        (resumen ejecutivo + listas para revisión manual)

Requisitos: Python 3.6+. Nada más (sin pip install).

Uso típico:
    export GITHUB_TOKEN=xxxxx
    python3 check_gitmodules.py --input repos.xlsx --dry-run          # solo ver las URLs
    python3 check_gitmodules.py --input repos.xlsx --org BnmxInternal \
            --out ./salida --index-org --all-branches

GitHub Enterprise:
    --api-base https://github.nam.nsroot.net/api/v3 --web-base https://github.nam.nsroot.net
"""

import argparse
import base64
import csv
import json
import os
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from difflib import get_close_matches
from urllib.parse import urlparse


# --------------------------------------------------------------------------- #
# Constantes
# --------------------------------------------------------------------------- #

GITMODULES = ".gitmodules"          # nombre real del archivo en git
GITLINK_MODE = "160000"             # modo de un submódulo dentro del árbol
DEFAULT_ORG = "BnmxInternal"
DEFAULT_API = "https://api.github.com"
DEFAULT_WEB = "https://github.com"

ST_OK_CON = "CON_GITMODULES"
ST_OK_SIN = "SIN_GITMODULES"
ST_NO_REPO = "REPO_NO_EXISTE"
ST_VACIO = "REPO_VACIO"
ST_SIN_URL = "URL_NO_PARSEABLE"
ST_ERROR = "ERROR"
ST_SIN_PERMISO = "SIN_PERMISO"


# --------------------------------------------------------------------------- #
# Cliente HTTP de GitHub (urllib, sin requests)
# --------------------------------------------------------------------------- #

class GitHubClient:
    """Cliente mínimo con reintentos, manejo de rate limit y paginación por Link."""

    def __init__(self, token, api_base, timeout=30, max_retries=4, verify_ssl=True):
        self.api_base = api_base.rstrip("/")
        self.timeout = timeout
        self.max_retries = max_retries
        self.headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "gitmodules-audit/2.0",
        }
        if token:
            self.headers["Authorization"] = "Bearer " + token

        if verify_ssl:
            self._ctx = ssl.create_default_context()
        else:
            self._ctx = ssl._create_unverified_context()

        self._local = threading.local()     # un opener por hilo
        self._lock = threading.Lock()
        self.calls = 0

    # -- opener por hilo (respeta HTTP_PROXY / HTTPS_PROXY del entorno) -------
    @property
    def _opener(self):
        op = getattr(self._local, "opener", None)
        if op is None:
            op = urllib.request.build_opener(
                urllib.request.HTTPSHandler(context=self._ctx),
                urllib.request.ProxyHandler(),      # toma HTTP(S)_PROXY del entorno
            )
            self._local.opener = op
        return op

    # -- núcleo --------------------------------------------------------------
    def get(self, path, params=None):
        """Devuelve (data|None, status, headers). Nunca lanza por 4xx."""
        url = path if path.startswith("http") else self.api_base + path
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)

        last_err = None
        for attempt in range(self.max_retries + 1):
            req = urllib.request.Request(url, headers=self.headers, method="GET")
            try:
                with self._opener.open(req, timeout=self.timeout) as resp:
                    status, hdrs, body = resp.status, dict(resp.headers), resp.read()
            except urllib.error.HTTPError as err:
                status, hdrs, body = err.code, dict(err.headers), err.read()
            except Exception as exc:                      # red, DNS, TLS, timeout
                last_err = exc
                time.sleep(min(2 ** attempt, 20))
                continue

            with self._lock:
                self.calls += 1

            if status == 404:
                return None, 404, hdrs
            if self._is_rate_limited(status, hdrs, body):
                if attempt >= self.max_retries:
                    return None, 429, hdrs          # se acabaron los reintentos
                self._sleep_until_reset(hdrs)
                continue
            if status in (401, 403):
                return None, status, hdrs
            if status >= 500:
                time.sleep(min(2 ** attempt, 20))
                continue
            if status >= 400:
                return None, status, hdrs

            try:
                return json.loads(body.decode("utf-8")), status, hdrs
            except Exception:                              # noqa: BLE001
                return None, status, hdrs

        raise RuntimeError("Sin respuesta útil de %s (último error: %s)" % (url, last_err))

    def get_paginated(self, path, params=None, max_pages=50):
        out, url, page = [], path, 0
        params = dict(params or {})
        params.setdefault("per_page", 100)
        while url and page < max_pages:
            data, status, hdrs = self.get(url, params if page == 0 else None)
            if status >= 400 or data is None:
                break
            out.extend(data if isinstance(data, list) else [data])
            url = self._next_link(hdrs)
            page += 1
        return out

    # -- helpers -------------------------------------------------------------
    @staticmethod
    def _next_link(hdrs):
        link = hdrs.get("Link") or hdrs.get("link") or ""
        for part in link.split(","):
            if 'rel="next"' in part:
                return part.split(";")[0].strip().strip("<>")
        return None

    @staticmethod
    def _is_rate_limited(status, hdrs, body):
        if status not in (403, 429):
            return False
        if hdrs.get("X-RateLimit-Remaining") == "0" or hdrs.get("Retry-After"):
            return True
        try:
            return "rate limit" in body.decode("utf-8", "replace").lower()
        except Exception:                                  # noqa: BLE001
            return False

    def _sleep_until_reset(self, hdrs):
        retry_after = hdrs.get("Retry-After")
        if retry_after:
            wait = int(float(retry_after))
        else:
            reset = int(hdrs.get("X-RateLimit-Reset") or 0)
            wait = max(reset - int(time.time()), 1) if reset else 60
        wait = min(wait + 2, 900)
        with self._lock:
            sys.stderr.write("  [rate-limit] esperando %ds ...\n" % wait)
            sys.stderr.flush()
        time.sleep(wait)


# --------------------------------------------------------------------------- #
# Lector de .xlsx sin librerías (un xlsx es un zip de XML)
# --------------------------------------------------------------------------- #

NS_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NS_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"


def _col_index(ref):
    """'BC12' -> 54 (índice 0-based de la columna)."""
    letters = "".join(ch for ch in ref if ch.isalpha())
    n = 0
    for ch in letters.upper():
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def _xml(z, name):
    try:
        return ET.fromstring(z.read(name))
    except KeyError:
        return None


def _shared_strings(z):
    root = _xml(z, "xl/sharedStrings.xml")
    if root is None:
        return []
    out = []
    for si in root.findall(NS_MAIN + "si"):
        # ignora los bloques de fonética (rPh) que Excel mete en algunos archivos
        txt = "".join(t.text or "" for t in si.iter(NS_MAIN + "t"))
        out.append(txt)
    return out


def _sheet_targets(z):
    """[(nombre_hoja, ruta_xml), ...] en el orden del libro."""
    wb = _xml(z, "xl/workbook.xml")
    rels = _xml(z, "xl/_rels/workbook.xml.rels")
    if wb is None or rels is None:
        return []
    relmap = {r.get("Id"): r.get("Target") for r in rels}
    out = []
    for sh in wb.iter(NS_MAIN + "sheet"):
        target = relmap.get(sh.get(NS_REL + "id"), "")
        if target.startswith("/"):
            target = target[1:]
        elif not target.startswith("xl/"):
            target = "xl/" + target
        out.append((sh.get("name"), target))
    return out


def _hyperlinks(z, sheet_path, sheet_root):
    """{ 'E2': 'https://...' } combinando <hyperlinks> + el .rels de la hoja."""
    out = {}
    node = sheet_root.find(NS_MAIN + "hyperlinks")
    if node is None:
        return out
    base = os.path.basename(sheet_path)
    rels = _xml(z, os.path.dirname(sheet_path) + "/_rels/" + base + ".rels")
    relmap = {r.get("Id"): r.get("Target") for r in rels} if rels is not None else {}
    for h in node:
        ref = (h.get("ref") or "").split(":")[0]
        target = relmap.get(h.get(NS_REL + "id")) or h.get("location") or ""
        if ref and target:
            out[ref] = target
    return out


def read_xlsx_rows(path, sheet=None):
    """Devuelve (filas, links) donde filas = [(nro_fila, {col_idx: valor}), ...]."""
    with zipfile.ZipFile(path) as z:
        shared = _shared_strings(z)
        hojas = _sheet_targets(z)
        if not hojas:
            raise RuntimeError("No pude leer las hojas del archivo.")
        if sheet:
            elegida = next((h for h in hojas if h[0] == sheet), None)
            if elegida is None:
                raise RuntimeError("No existe la hoja %r. Hojas: %s"
                                   % (sheet, [h[0] for h in hojas]))
        else:
            elegida = hojas[0]
        nombre, ruta = elegida
        root = _xml(z, ruta)
        if root is None:
            raise RuntimeError("No pude leer la hoja %s" % nombre)
        links = _hyperlinks(z, ruta, root)

        filas = []
        for row in root.iter(NS_MAIN + "row"):
            rnum = int(row.get("r") or (len(filas) + 1))
            celdas = {}
            for c in row.findall(NS_MAIN + "c"):
                ref = c.get("r") or ""
                idx = _col_index(ref) if ref else len(celdas)
                t = c.get("t")
                if t == "s":
                    v = c.find(NS_MAIN + "v")
                    val = shared[int(v.text)] if (v is not None and v.text) else ""
                elif t == "inlineStr":
                    is_ = c.find(NS_MAIN + "is")
                    val = "".join(x.text or "" for x in is_.iter(NS_MAIN + "t")) if is_ is not None else ""
                else:
                    v = c.find(NS_MAIN + "v")
                    val = v.text if (v is not None and v.text) else ""
                celdas[idx] = (val or "").strip(), ref
            filas.append((rnum, celdas))
        return filas, links


# --------------------------------------------------------------------------- #
# Escritor de .xlsx sin librerías
# --------------------------------------------------------------------------- #

def _esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def _col_letter(i):
    s = ""
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def write_xlsx(path, headers, rows, sheet_name="auditoria"):
    """xlsx mínimo (todo texto en inlineStr) con encabezado en negrita, filtro y panel fijo."""
    def fila_xml(n, valores, style=None):
        cs = []
        for i, v in enumerate(valores):
            v = "" if v is None else str(v)
            if len(v) > 32000:
                v = v[:32000] + "…"
            st = ' s="%d"' % style if style else ""
            cs.append('<c r="%s%d" t="inlineStr"%s><is><t xml:space="preserve">%s</t></is></c>'
                      % (_col_letter(i), n, st, _esc(v)))
        return '<row r="%d">%s</row>' % (n, "".join(cs))

    ncols = len(headers)
    dim = "A1:%s%d" % (_col_letter(ncols - 1), len(rows) + 1)
    cuerpo = [fila_xml(1, headers, style=1)]
    for n, r in enumerate(rows, start=2):
        cuerpo.append(fila_xml(n, r))

    sheet = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<dimension ref="%s"/>'
        '<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>'
        '<sheetFormatPr defaultRowHeight="15"/>'
        '<sheetData>%s</sheetData>'
        '<autoFilter ref="%s"/>'
        '</worksheet>' % (dim, "".join(cuerpo), dim)
    )
    styles = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF305496"/>'
        '<bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border/></borders>'
        '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
        '<cellXfs count="2"><xf xfId="0"/>'
        '<xf fontId="1" fillId="2" applyFont="1" applyFill="1" xfId="0"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '<dxfs count="0"/>'
        '</styleSheet>'
    )
    content_types = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>'
    )
    root_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>'
    )
    workbook = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="%s" sheetId="1" r:id="rId1"/></sheets></workbook>' % _esc(sheet_name)
    )
    wb_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>'
    )
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", root_rels)
        z.writestr("xl/workbook.xml", workbook)
        z.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        z.writestr("xl/styles.xml", styles)
        z.writestr("xl/worksheets/sheet1.xml", sheet)


# --------------------------------------------------------------------------- #
# Modelo
# --------------------------------------------------------------------------- #

class RepoInput(object):
    """Una fila de la hoja de entrada."""

    __slots__ = ("fila", "number", "csi", "owner", "soid", "bb_url", "gh_url_excel")

    def __init__(self, fila, number="", csi="", owner="", soid="", bb_url="", gh_url_excel=""):
        self.fila = fila
        self.number = number
        self.csi = csi
        self.owner = owner
        self.soid = soid
        self.bb_url = bb_url
        self.gh_url_excel = gh_url_excel


# columnas del reporte, en orden
FIELDS = [
    "fila", "number", "csi", "owner", "soid", "bb_url",
    "project_key", "repo_slug", "gh_org", "gh_repo",
    "gh_url_construida", "gh_url_excel", "url_coincide",
    "estado", "repo_existe", "default_branch", "ramas_revisadas",
    "tiene_gitmodules", "ramas_con_gitmodules", "submodulos", "n_submodulos",
    "gitlinks_sin_declarar", "archivado", "ultimo_push",
    "sugerencias", "detalle", "accion",
]

_DEFAULTS = {"fila": 0, "ramas_revisadas": 0, "n_submodulos": 0}


class RepoResult(object):
    """El resultado del análisis de un repo (una fila del reporte)."""

    __slots__ = tuple(FIELDS)

    def __init__(self, **kw):
        for f in FIELDS:
            setattr(self, f, kw.get(f, _DEFAULTS.get(f, "")))

    def to_dict(self):
        return dict((f, getattr(self, f)) for f in FIELDS)

    def row(self):
        return [getattr(self, f) for f in FIELDS]


# --------------------------------------------------------------------------- #
# Construcción de la URL de GitHub
# --------------------------------------------------------------------------- #

def parse_bitbucket(url):
    """(project_key, repo_slug) desde .../scm/<KEY>/<slug>.git o .../projects/<KEY>/repos/<slug>/browse"""
    if not url:
        return None, None
    url = " ".join(str(url).split())          # junta urls partidas en varias líneas
    path = urlparse(url).path if "://" in url else url
    parts = [p for p in path.split("/") if p]
    lower = [p.lower() for p in parts]

    key = slug = None
    if "scm" in lower:
        i = lower.index("scm")
        if len(parts) > i + 2:
            key, slug = parts[i + 1], parts[i + 2]
    elif "projects" in lower and "repos" in lower:
        i, j = lower.index("projects"), lower.index("repos")
        if len(parts) > i + 1:
            key = parts[i + 1]
        if len(parts) > j + 1:
            slug = parts[j + 1]

    if slug and slug.lower().endswith(".git"):
        slug = slug[:-4]
    return key, slug


def build_github_name(csi, key, slug, key_case="lower"):
    key = {"lower": key.lower(), "upper": key.upper()}.get(key_case, key)
    return "%s.%s.%s" % (csi, key, slug)


def normalize_repo_url(url):
    """Normaliza a 'org/repo' en minúsculas para poder comparar."""
    if not url:
        return ""
    url = " ".join(str(url).split()).rstrip("/")
    if url.lower().endswith(".git"):
        url = url[:-4]
    path = urlparse(url).path if "://" in url else url
    parts = [p for p in path.split("/") if p]
    return "/".join(parts[-2:]).lower() if len(parts) >= 2 else url.lower()


def parse_gitmodules(text):
    """Contenido de .gitmodules -> [{'name','path','url','branch'}, ...]"""
    mods, current = [], None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        m = re.match(r'^\[submodule\s+"?(.*?)"?\]$', line)
        if m:
            current = {"name": m.group(1), "path": "", "url": "", "branch": ""}
            mods.append(current)
            continue
        if current is None or "=" not in line:
            continue
        k, v = (p.strip() for p in line.split("=", 1))
        if k.lower() in current:
            current[k.lower()] = v
    return mods


# --------------------------------------------------------------------------- #
# Análisis de un repo
# --------------------------------------------------------------------------- #

def analyze_repo(gh, item, org, web_base, all_branches, deep, key_case, fetch_content):
    res = RepoResult(fila=item.fila, number=item.number, csi=item.csi, owner=item.owner,
                     soid=item.soid, bb_url=item.bb_url, gh_url_excel=item.gh_url_excel,
                     gh_org=org)

    # 1) armar la url --------------------------------------------------------
    key, slug = parse_bitbucket(item.bb_url)
    if key and slug and item.csi:
        res.project_key, res.repo_slug = key, slug
        res.gh_repo = build_github_name(item.csi, key, slug, key_case)
    else:
        # último recurso: usar la url que ya venía en el Excel
        norm = normalize_repo_url(item.gh_url_excel)
        if "/" in norm:
            res.gh_repo = norm.split("/")[-1]
            res.detalle = "URL tomada de la columna del Excel (Bitbucket no parseable)"
        else:
            res.estado = ST_SIN_URL
            res.detalle = "No pude extraer project key / slug de la url de Bitbucket ni del Excel"
            res.accion = "REVISAR MANUALMENTE: url de Bitbucket vacía o con formato raro"
            return res

    res.gh_url_construida = "%s/%s/%s.git" % (web_base.rstrip("/"), org, res.gh_repo)
    if item.gh_url_excel:
        res.url_coincide = "SI" if normalize_repo_url(res.gh_url_construida) == \
                                   normalize_repo_url(item.gh_url_excel) else "NO"
    else:
        res.url_coincide = "N/A"

    # 2) ¿existe? ------------------------------------------------------------
    data, status, _ = gh.get("/repos/%s/%s" % (org, urllib.parse.quote(res.gh_repo)))
    if status == 404:
        res.estado, res.repo_existe = ST_NO_REPO, "NO"
        res.accion = "REVISAR MANUALMENTE: no existe con ese nombre (mal nombrado o sin migrar)"
        return res
    if status in (401, 403):
        res.estado, res.repo_existe = ST_SIN_PERMISO, "?"
        res.detalle = "HTTP %s — el token no tiene acceso" % status
        res.accion = "REVISAR MANUALMENTE: validar permisos del token / membresía en la org"
        return res
    if status >= 400 or data is None:
        res.estado = ST_ERROR
        res.detalle = ("Rate limit de la API agotado (sin token son 60 req/hora)"
                       if status == 429 else "HTTP %s al consultar el repo" % status)
        res.accion = "REVISAR MANUALMENTE: error consultando la API"
        return res

    res.repo_existe = "SI"
    res.default_branch = data.get("default_branch") or ""
    res.archivado = "SI" if data.get("archived") else "NO"
    res.ultimo_push = (data.get("pushed_at") or "")[:10]

    real = data.get("name") or res.gh_repo
    if real != res.gh_repo:
        res.detalle = ("; ".join(filter(None, [res.detalle,
                       "GitHub resolvió el nombre real como '%s' (difiere en mayúsculas)" % real])))
        res.gh_repo = real

    if not res.default_branch:
        res.estado, res.tiene_gitmodules = ST_VACIO, "NO"
        res.accion = "REVISAR MANUALMENTE: repo vacío (sin commits)"
        return res

    # 3) ramas ---------------------------------------------------------------
    branches = []
    if all_branches:
        raw = gh.get_paginated("/repos/%s/%s/branches" % (org, res.gh_repo))
        branches = [(b["name"], b["commit"]["sha"]) for b in raw
                    if b.get("name") and (b.get("commit") or {}).get("sha")]
    if not branches:
        branches = [(res.default_branch, res.default_branch)]
    res.ramas_revisadas = len(branches)

    # muchas ramas apuntan al mismo commit -> una sola llamada por sha
    por_sha = {}
    for nombre, sha in branches:
        por_sha.setdefault(sha, []).append(nombre)

    ramas_con, submodulos, gitlinks, errores = [], {}, set(), []

    for sha, nombres in por_sha.items():
        tree, status, _ = gh.get(
            "/repos/%s/%s/git/trees/%s" % (org, res.gh_repo, urllib.parse.quote(sha, safe="")),
            {"recursive": "1"} if deep else None,
        )
        if status >= 400 or tree is None:
            errores.append("%s: HTTP %s al leer el árbol" % (nombres[0], status))
            continue
        if tree.get("truncated"):
            errores.append("%s: árbol truncado por GitHub (repo enorme)" % nombres[0])

        blob_sha = None
        for e in tree.get("tree", []) or []:
            p = e.get("path", "")
            if e.get("mode") == GITLINK_MODE or e.get("type") == "commit":
                gitlinks.add(p)
            if p == GITMODULES or (deep and p.endswith("/" + GITMODULES)):
                blob_sha = e.get("sha")
            elif p.lower() == GITMODULES and p != GITMODULES:
                blob_sha = e.get("sha")
                errores.append("%s: archivo '%s' con mayúsculas raras" % (nombres[0], p))

        if blob_sha:
            ramas_con.extend(nombres)
            if fetch_content:
                blob, st, _ = gh.get("/repos/%s/%s/git/blobs/%s" % (org, res.gh_repo, blob_sha))
                if st < 400 and blob and blob.get("encoding") == "base64":
                    try:
                        texto = base64.b64decode(blob["content"]).decode("utf-8", "replace")
                        for m in parse_gitmodules(texto):
                            submodulos[m.get("path") or m.get("name")] = m.get("url", "")
                    except Exception as exc:                      # noqa: BLE001
                        errores.append("%s: no pude decodificar .gitmodules (%s)" % (nombres[0], exc))

    # 4) veredicto -----------------------------------------------------------
    res.ramas_con_gitmodules = ", ".join(sorted(set(ramas_con))[:25])
    res.submodulos = " | ".join("%s -> %s" % (k, v) for k, v in sorted(submodulos.items()))
    res.n_submodulos = len(submodulos)
    res.gitlinks_sin_declarar = ", ".join(sorted(g for g in gitlinks if g not in submodulos))

    if ramas_con:
        res.estado, res.tiene_gitmodules = ST_OK_CON, "SI"
        res.accion = "OK: tiene .gitmodules — validar que las urls de los submódulos apunten a GitHub"
    else:
        res.estado, res.tiene_gitmodules = ST_OK_SIN, "NO"
        res.accion = ("ALERTA: hay submódulos en el árbol (gitlinks) pero NO existe .gitmodules"
                      if gitlinks else "OK: no usa submódulos")

    if errores:
        res.detalle = "; ".join(filter(None, [res.detalle] + errores))
    return res


# --------------------------------------------------------------------------- #
# Lectura de la entrada
# --------------------------------------------------------------------------- #

COL_ALIASES = {
    "csi": ["csi"],
    "bb": ["bb repo", "bbrepo", "bitbucket", "bitbucket repo", "repo bb", "url bitbucket"],
    "gh": ["github repo", "githubrepo", "github", "repo github", "url github"],
    "number": ["number", "nro", "no", "#", "id"],
    "owner": ["owner", "dueño", "dueno"],
    "soid": ["soid"],
}


def _match_col(header):
    h = re.sub(r"\s+", " ", str(header or "").strip().lower())
    for canon, alias in COL_ALIASES.items():
        if h in alias:
            return canon
    return None


def _clean_csi(v):
    v = str(v or "").strip()
    if v.endswith(".0"):
        v = v[:-2]
    return v


def read_input(path, sheet, header_row):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".csv", ".tsv", ".txt"):
        return _read_csv(path, header_row, "\t" if ext == ".tsv" else ",")
    return _read_xlsx(path, sheet, header_row)


def _make_item(n, g):
    return RepoInput(n, g("number"), _clean_csi(g("csi")), g("owner"), g("soid"),
                     g("bb"), g("gh"))


def _read_csv(path, header_row, delim):
    with open(path, newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.reader(fh, delimiter=delim))
    if not rows:
        return []
    idx = {}
    for i, h in enumerate(rows[header_row - 1]):
        c = _match_col(h)
        if c and c not in idx:
            idx[c] = i
    out = []
    for n, row in enumerate(rows[header_row:], start=header_row + 1):
        def g(k, row=row):  # noqa: E306
            i = idx.get(k)
            v = row[i].strip() if (i is not None and i < len(row)) else ""
            return re.sub(r"\s+", "", v) if k in ("bb", "gh") else v
        if any(g(k) for k in ("csi", "bb", "gh")):
            out.append(_make_item(n, g))
    return out


def _read_xlsx(path, sheet, header_row):
    filas, links = read_xlsx_rows(path, sheet)
    por_num = {n: celdas for n, celdas in filas}
    cab = por_num.get(header_row, {})
    if not cab:
        raise RuntimeError("La fila %d está vacía. Usa --header-row para indicar la de encabezados."
                           % header_row)

    idx, leidos = {}, []
    for i, (val, _ref) in sorted(cab.items()):
        leidos.append(val)
        c = _match_col(val)
        if c and c not in idx:
            idx[c] = i

    faltan = [k for k in ("csi", "bb") if k not in idx]
    if faltan:
        sys.stderr.write("[!] No encontré las columnas %s en la fila %d. Encabezados: %s\n"
                         % (faltan, header_row, leidos))

    out = []
    for n, celdas in filas:
        if n <= header_row:
            continue

        def g(k, celdas=celdas):
            i = idx.get(k)
            if i is None or i not in celdas:
                return ""
            val, ref = celdas[i]
            if k in ("bb", "gh"):
                # una URL nunca lleva espacios: Excel suele partirla visualmente
                val = re.sub(r"\s+", "", val)
                # si la celda es un hipervínculo, el destino real manda sobre el texto visible
                target = links.get(ref)
                if target and "://" in target:
                    return target.strip()
                return val
            return val

        if any(g(k) for k in ("csi", "bb", "gh")):
            out.append(_make_item(n, g))
    return out


# --------------------------------------------------------------------------- #
# Índice de la organización (sugerencias de nombres)
# --------------------------------------------------------------------------- #

def index_org(gh, org):
    sys.stderr.write("[i] Indexando repos de %s (puede tardar)...\n" % org)
    repos = gh.get_paginated("/orgs/%s/repos" % org, {"type": "all"}, max_pages=300)
    idx = {r["name"].lower(): r["name"] for r in repos if r.get("name")}
    sys.stderr.write("[i] %d repos indexados.\n" % len(idx))
    return idx


def sugerir(nombre, indice, slug=""):
    if not indice:
        return ""
    cands = get_close_matches(nombre.lower(), list(indice), n=3, cutoff=0.72)
    if not cands and slug:
        cands = [k for k in indice if slug.lower() in k][:3]
    return ", ".join(indice[c] for c in cands)


# --------------------------------------------------------------------------- #
# Salidas
# --------------------------------------------------------------------------- #

def write_csv(results, path):
    with open(path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        for r in results:
            w.writerow(r.to_dict())


def write_markdown(results, path, org, args):
    total = len(results)
    sel = lambda *e: [r for r in results if r.estado in e]          # noqa: E731
    con, sin = sel(ST_OK_CON), sel(ST_OK_SIN)
    nores = sel(ST_NO_REPO)
    otros = sel(ST_VACIO, ST_SIN_URL, ST_ERROR, ST_SIN_PERMISO)
    rotos = [r for r in results if r.gitlinks_sin_declarar]
    dif = [r for r in results if r.url_coincide == "NO"]

    L = []
    A = L.append
    A("# Auditoría de `.gitmodules` — organización `%s`\n" % org)
    A("Generado: %s  " % datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))
    A("Ramas revisadas: **%s**  " % ("todas" if args.all_branches else "solo la rama por defecto"))
    A("Búsqueda en subdirectorios: **%s**\n" % ("sí" if args.deep else "no (solo la raíz)"))

    A("## Resumen\n")
    A("| Estado | Repos | % |")
    A("|---|---:|---:|")
    for etiqueta, grupo in (("✅ Con `.gitmodules`", con),
                            ("⚪ Sin `.gitmodules`", sin),
                            ("❌ Repo no existe", nores),
                            ("⚠️ Otros (vacío / error / permisos / url mala)", otros)):
        pct = (len(grupo) / total * 100) if total else 0
        A("| %s | %d | %.1f%% |" % (etiqueta, len(grupo), pct))
    A("| **Total** | **%d** | 100%% |\n" % total)

    if rotos:
        A("## 🚨 Prioridad alta — submódulos en el árbol sin `.gitmodules`\n")
        A("Tienen entradas de submódulo (gitlinks, modo `160000`) que el `.gitmodules` no declara. "
          "Un `git clone --recurse-submodules` falla o deja directorios vacíos.\n")
        A("| Fila | Repo | Rutas huérfanas |")
        A("|---:|---|---|")
        for r in rotos:
            A("| %d | `%s` | `%s` |" % (r.fila, r.gh_repo, r.gitlinks_sin_declarar))
        A("")

    if nores:
        A("## ❌ Repos que no existen — revisión manual\n")
        A("O no se han migrado, o el nombre quedó mal armado, o el token no los ve.\n")
        A("| Fila | CSI | Nombre construido | URL Bitbucket | Sugerencias en la org |")
        A("|---:|---|---|---|---|")
        for r in nores:
            A("| %d | %s | `%s` | %s | %s |" % (r.fila, r.csi, r.gh_repo, r.bb_url,
                                                r.sugerencias or "—"))
        A("")

    if dif:
        A("## ⚠️ La URL construida no coincide con la del Excel\n")
        A("| Fila | Construida | En el Excel |")
        A("|---:|---|---|")
        for r in dif:
            A("| %d | `%s` | `%s` |" % (r.fila, r.gh_url_construida, r.gh_url_excel))
        A("")

    if sin:
        A("## ⚪ Repos sin `.gitmodules`\n")
        A("| Fila | CSI | Repo | Rama default | Ramas revisadas | Último push |")
        A("|---:|---|---|---|---:|---|")
        for r in sin:
            A("| %d | %s | `%s` | %s | %d | %s |" % (r.fila, r.csi, r.gh_repo,
                                                     r.default_branch, r.ramas_revisadas,
                                                     r.ultimo_push))
        A("")

    if con:
        A("## ✅ Repos con `.gitmodules`\n")
        A("| Fila | Repo | Ramas donde aparece | # submódulos | Submódulos |")
        A("|---:|---|---|---:|---|")
        for r in con:
            A("| %d | `%s` | %s | %d | %s |" % (r.fila, r.gh_repo,
                                                r.ramas_con_gitmodules or r.default_branch,
                                                r.n_submodulos, r.submodulos or "—"))
        A("")

    if otros:
        A("## ⚠️ Otros casos para revisar a mano\n")
        A("| Fila | Repo | Estado | Detalle |")
        A("|---:|---|---|---|")
        for r in otros:
            A("| %d | `%s` | %s | %s |" % (r.fila, r.gh_repo or r.bb_url, r.estado,
                                           r.detalle or r.accion))
        A("")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #

def main():
    p = argparse.ArgumentParser(
        description="Audita .gitmodules en GitHub construyendo la URL desde CSI + Bitbucket. "
                    "Solo librería estándar.")
    p.add_argument("--input", required=True, help="Excel (.xlsx) o CSV con CSI / BB Repo / Github Repo")
    p.add_argument("--sheet", default=None, help="Nombre de la hoja (default: la primera)")
    p.add_argument("--header-row", type=int, default=1, help="Fila de encabezados (default: 1)")
    p.add_argument("--org", default=DEFAULT_ORG, help="Organización de GitHub (default: %s)" % DEFAULT_ORG)
    p.add_argument("--api-base", default=os.environ.get("GITHUB_API", DEFAULT_API),
                   help="Base de la API. GHE: https://tu-github/api/v3")
    p.add_argument("--web-base", default=os.environ.get("GITHUB_WEB", DEFAULT_WEB),
                   help="Base web para armar las urls visibles")
    p.add_argument("--token", default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"),
                   help="Token (o variable GITHUB_TOKEN)")
    p.add_argument("--out", default="./salida", help="Carpeta de salida")
    p.add_argument("--all-branches", action="store_true", help="Revisar TODAS las ramas")
    p.add_argument("--deep", action="store_true", help="Buscar también en subdirectorios (árbol recursivo)")
    p.add_argument("--no-content", action="store_true",
                   help="No descargar el .gitmodules (más rápido, sin lista de submódulos)")
    p.add_argument("--index-org", action="store_true",
                   help="Indexar la org para sugerir nombres cuando el repo no existe")
    p.add_argument("--key-case", choices=["lower", "upper", "asis"], default="lower",
                   help="Cómo escribir el project key (default: lower)")
    p.add_argument("--workers", type=int, default=6, help="Hilos en paralelo (default: 6)")
    p.add_argument("--limit", type=int, default=0, help="Procesar solo las primeras N filas")
    p.add_argument("--dry-run", action="store_true", help="Solo construir e imprimir las URLs")
    p.add_argument("--insecure", action="store_true", help="No verificar TLS (redes corporativas)")
    args = p.parse_args()

    items = read_input(args.input, args.sheet, args.header_row)
    if args.limit:
        items = items[:args.limit]
    if not items:
        sys.exit("No se leyó ninguna fila. Revisa --header-row y los nombres de las columnas.")
    sys.stderr.write("[i] %d filas leídas de %s\n" % (len(items), args.input))

    if args.dry_run:
        print("%5s  %-10s %-9s %s" % ("FILA", "CSI", "COINCIDE", "URL CONSTRUIDA"))
        for it in items:
            key, slug = parse_bitbucket(it.bb_url)
            if key and slug and it.csi:
                url = "%s/%s/%s.git" % (args.web_base.rstrip("/"), args.org,
                                        build_github_name(it.csi, key, slug, args.key_case))
                ok = "-"
                if it.gh_url_excel:
                    ok = "SI" if normalize_repo_url(url) == normalize_repo_url(it.gh_url_excel) else "NO <<<"
                print("%5d  %-10s %-9s %s" % (it.fila, it.csi, ok, url))
            else:
                print("%5d  %-10s %-9s no pude parsear: %r" % (it.fila, it.csi, "ERROR", it.bb_url))
        return

    if not args.token:
        sys.stderr.write("[!] Sin token: vas a chocar con el rate limit y no verás repos privados. "
                         "Exporta GITHUB_TOKEN.\n")

    gh = GitHubClient(args.token, args.api_base, verify_ssl=not args.insecure)
    indice = index_org(gh, args.org) if args.index_org else {}

    results, hechos, total = [], 0, len(items)
    lock = threading.Lock()

    def tarea(it):
        try:
            return analyze_repo(gh, it, args.org, args.web_base, args.all_branches,
                                args.deep, args.key_case, not args.no_content)
        except Exception as exc:                                    # noqa: BLE001
            return RepoResult(fila=it.fila, number=it.number, csi=it.csi, owner=it.owner,
                              soid=it.soid, bb_url=it.bb_url, gh_url_excel=it.gh_url_excel,
                              gh_org=args.org, estado=ST_ERROR,
                              detalle="%s: %s" % (type(exc).__name__, exc),
                              accion="REVISAR MANUALMENTE: excepción durante el análisis")

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        futs = [pool.submit(tarea, it) for it in items]
        for fut in as_completed(futs):
            r = fut.result()
            if r.estado == ST_NO_REPO and indice:
                r.sugerencias = sugerir(r.gh_repo, indice, r.repo_slug)
            results.append(r)
            with lock:
                hechos += 1
                if hechos % 10 == 0 or hechos == total:
                    sys.stderr.write("  [%d/%d] (%d llamadas API)\n" % (hechos, total, gh.calls))
                    sys.stderr.flush()

    results.sort(key=lambda r: r.fila)

    os.makedirs(args.out, exist_ok=True)
    csv_path = os.path.join(args.out, "resultados.csv")
    xlsx_path = os.path.join(args.out, "resultados.xlsx")
    md_path = os.path.join(args.out, "reporte.md")

    write_csv(results, csv_path)
    write_markdown(results, md_path, args.org, args)
    try:
        write_xlsx(xlsx_path, FIELDS, [r.row() for r in results])
        xlsx_ok = True
    except Exception as exc:                                        # noqa: BLE001
        sys.stderr.write("[!] No pude escribir el xlsx (%s). Usa el CSV.\n" % exc)
        xlsx_ok = False

    cnt = {}
    for r in results:
        cnt[r.estado] = cnt.get(r.estado, 0) + 1
    sys.stderr.write("\n=== RESUMEN ===\n")
    for k, v in sorted(cnt.items(), key=lambda x: -x[1]):
        sys.stderr.write("  %-18s %d\n" % (k, v))
    sys.stderr.write("\nArchivos generados:\n  %s\n  %s%s\n"
                     % (csv_path, md_path, ("\n  " + xlsx_path) if xlsx_ok else ""))


if __name__ == "__main__":
    main()
