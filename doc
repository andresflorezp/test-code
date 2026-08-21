# Guía de Uso de GitHub — Organización Banamex

> **Versión:** 1.0 (borrador)
> **Última actualización:** _(fecha)_
> **Responsable / Owner:** _(equipo DevOps – Plataforma)_
> **Audiencia:** desarrolladores, QA, DevOps, líderes técnicos y cualquier persona que necesite versionar código en la organización.

---

## Tabla de contenido

1. [Propósito y alcance](#1-propósito-y-alcance)
2. [Fundamentos: Git, GitHub y Bitbucket](#2-fundamentos-git-github-y-bitbucket)
3. [Conceptos base que debes conocer](#3-conceptos-base-que-debes-conocer)
4. [Estructura organizacional en GitHub](#4-estructura-organizacional-en-github)
5. [Roles y permisos](#5-roles-y-permisos)
6. [Convención de nombres de repositorios](#6-convención-de-nombres-de-repositorios)
7. [Creación de repositorios (flujo con Jira)](#7-creación-de-repositorios-flujo-con-jira)
8. [Estrategia de ramas (Branching Strategy)](#8-estrategia-de-ramas-branching-strategy)
9. [Convención de nombres de ramas](#9-convención-de-nombres-de-ramas)
10. [Protección de ramas (Branch Protection Rules)](#10-protección-de-ramas-branch-protection-rules)
11. [Convención de commits](#11-convención-de-commits)
12. [Pull Requests: estándar de trabajo](#12-pull-requests-estándar-de-trabajo)
13. [Labels estándar](#13-labels-estándar)
14. [Versionamiento, tags y releases](#14-versionamiento-tags-y-releases)
15. [Integración GitHub ↔ Jira](#15-integración-github--jira)
16. [Seguridad y manejo de información sensible](#16-seguridad-y-manejo-de-información-sensible)
17. [Flujo de trabajo diario (paso a paso)](#17-flujo-de-trabajo-diario-paso-a-paso)
18. [Comandos Git más utilizados](#18-comandos-git-más-utilizados)
19. [Buenas prácticas (resumen)](#19-buenas-prácticas-resumen)
20. [Preguntas frecuentes](#20-preguntas-frecuentes)
21. [Glosario](#21-glosario)

---

## 1. Propósito y alcance

### 1.1 ¿Para qué sirve este documento?

Este documento define **cómo trabajamos con GitHub dentro de la organización**: cómo se crean los repositorios, cómo se nombran, quién tiene acceso a qué, cómo se ramifica el código y cómo se integra un cambio a producción.

El objetivo es que **cualquier persona que se una al equipo pueda leer este documento y trabajar igual que el resto**, sin depender de que alguien le explique "cómo se hace acá".

### 1.2 ¿A quién aplica?

| Perfil | Aplica |
|---|---|
| Desarrolladores | ✅ Obligatorio |
| QA / Automatización | ✅ Obligatorio |
| DevOps / SRE | ✅ Obligatorio |
| Líderes técnicos / Arquitectos | ✅ Obligatorio |
| Product Owners / Managers | 🔶 Secciones 1, 3, 7, 15 |

### 1.3 Qué NO cubre este documento

- Configuración de pipelines de CI/CD (ver documento `CI-CD-Standards`).
- Estándares de código por lenguaje (ver guías específicas de cada stack).
- Gestión de infraestructura como código (ver documento `IaC-Standards`).

---

## 2. Fundamentos: Git, GitHub y Bitbucket

### 2.1 La diferencia en una frase

| Herramienta | Qué es | Analogía |
|---|---|---|
| **Git** | El sistema de control de versiones. Un programa que corre en tu máquina y registra los cambios del código. | El motor |
| **GitHub** | Una plataforma web que **aloja** repositorios Git y agrega colaboración, permisos, automatización y seguridad. | El carro completo |
| **Bitbucket** | Otra plataforma web que también aloja repositorios Git. | Otro carro, mismo motor |

**Idea clave:** Git es la herramienta, GitHub es la plataforma. Si sabes Git, ya sabes el 80% de GitHub. Lo que cambia entre GitHub y Bitbucket es la interfaz y algunas funcionalidades, **no los comandos**.

```
Git      = Control de versiones (comandos: git add, git commit, git push...)
GitHub   = Plataforma basada en Git
Bitbucket = Plataforma basada en Git
```

### 2.2 Equivalencias Bitbucket → GitHub

Si vienes de Bitbucket, esta tabla es tu traductor:

| Bitbucket | GitHub | Notas |
|---|---|---|
| Repository | Repository | Idéntico |
| Branch | Branch | Idéntico |
| Pull Request | Pull Request | Idéntico |
| Reviewer | Reviewer | En GitHub se pueden asignar por **CODEOWNERS** |
| Merge | Merge | GitHub ofrece 3 estrategias (merge, squash, rebase) |
| Commit | Commit | Idéntico |
| Project | Organization / Repository | Bitbucket agrupa por *Project*; GitHub agrupa por *Organization* y *Teams* |
| Pipelines | GitHub Actions | Cambia la sintaxis del YAML |
| Branch permissions | Branch protection rules / Rulesets | Concepto equivalente |
| Default reviewers | CODEOWNERS | En GitHub es un archivo dentro del repo |
| Workspace | Enterprise / Organization | — |

> 🖼️ **Espacio para imagen sugerida #1:** captura lado a lado de la interfaz de Bitbucket vs GitHub, señalando dónde queda cada elemento (repos, ramas, PRs). Muy útil para quienes están migrando.

---

## 3. Conceptos base que debes conocer

Si ya manejas Git, puedes saltar a la sección 4.

| Concepto | Qué es | Para qué sirve |
|---|---|---|
| **Repositorio (repo)** | Carpeta del proyecto con todo su historial de cambios. | Es la unidad mínima de trabajo. |
| **Clone** | Copia del repositorio remoto en tu máquina. | Para trabajar localmente. |
| **Commit** | Una "foto" de tus cambios con un mensaje que los describe. | Registrar avance de forma atómica. |
| **Branch (rama)** | Una línea de trabajo paralela e independiente. | Trabajar sin afectar el código estable. |
| **Merge** | Integrar los cambios de una rama en otra. | Llevar tu trabajo al código principal. |
| **Pull Request (PR)** | Solicitud formal para integrar una rama en otra, con revisión. | Control de calidad y trazabilidad. |
| **Reviewer** | Persona que revisa y aprueba (o rechaza) un PR. | Asegurar calidad y compartir conocimiento. |
| **Conflict (conflicto)** | Dos personas modificaron la misma línea. Git no sabe cuál dejar. | Se resuelve manualmente. |
| **Tag** | Marca fija sobre un commit específico. | Identificar versiones liberadas. |
| **Release** | Empaquetado de un tag con notas y artefactos. | Publicar versiones formales. |
| **Fork** | Copia completa del repo bajo otra cuenta. | Poco usado internamente; común en open source. |
| **`.gitignore`** | Archivo que le dice a Git qué NO versionar. | Evitar subir binarios, secretos, `node_modules`, etc. |
| **CODEOWNERS** | Archivo que define revisores automáticos por ruta. | Asignación automática de revisores. |

> 🖼️ **Espacio para imagen sugerida #2:** diagrama del ciclo de vida de un cambio: *Working Directory → Staging Area → Local Repository → Remote Repository*, con los comandos `git add`, `git commit`, `git push` sobre cada flecha. Es la imagen que más ayuda a los perfiles junior.

---

## 4. Estructura organizacional en GitHub

### 4.1 Jerarquía

```
Enterprise (Banamex)
│
├── Organization: banamex-<dominio-1>
│   ├── Team: <dominio>-developers
│   ├── Team: <dominio>-devops
│   ├── Team: <dominio>-qa
│   └── Repositories
│       ├── repo-a
│       └── repo-b
│
└── Organization: banamex-<dominio-2>
    └── ...
```

| Nivel | Qué agrupa | Quién lo administra |
|---|---|---|
| **Enterprise** | Todas las organizaciones de la compañía. Define políticas globales (SSO, 2FA, retención). | Gobierno de plataforma / Seguridad |
| **Organization** | Repositorios de un dominio, célula o línea de negocio. | Org Owners (equipo de plataforma) |
| **Team** | Conjunto de personas con un mismo nivel de acceso. | Team Maintainers |
| **Repository** | Un servicio, librería, aplicación o componente. | Repo Maintainers |

### 4.2 Regla de oro: los permisos se dan a **Teams**, nunca a personas

❌ **Incorrecto:** darle acceso `Write` a Juan Pérez directamente sobre el repo `banamex-core-payments-api`.

✅ **Correcto:** agregar a Juan Pérez al team `payments-developers`, y ese team tiene `Write` sobre el repo.

**Por qué:** cuando alguien entra o sale del proyecto, se toca un solo lugar (el team). Con accesos individuales, el offboarding se vuelve imposible de auditar.

### 4.3 Estructura de Teams recomendada

| Team | Propósito | Permiso típico |
|---|---|---|
| `<dominio>-owners` | Líderes técnicos y arquitectos del dominio. | `Admin` |
| `<dominio>-devops` | Configuración de pipelines, secretos, infraestructura. | `Maintain` |
| `<dominio>-developers` | Equipo de desarrollo del dominio. | `Write` |
| `<dominio>-qa` | Automatización de pruebas y validaciones. | `Write` (o `Triage`) |
| `<dominio>-readonly` | Consulta, auditoría, stakeholders. | `Read` |

> 🖼️ **Espacio para imagen sugerida #3:** diagrama de la jerarquía Enterprise → Organization → Teams → Repositories, con nombres reales (anonimizados) de la organización.

---

## 5. Roles y permisos

### 5.1 Niveles de permiso en un repositorio

GitHub define 5 niveles. De menor a mayor:

| Nivel | Puede hacer | Perfil típico |
|---|---|---|
| **Read** | Ver el código, clonar, comentar en issues y PRs. | Stakeholders, auditoría, equipos externos |
| **Triage** | Todo lo de Read + gestionar issues y PRs (asignar, etiquetar, cerrar). **No puede escribir código.** | QA, soporte, coordinadores |
| **Write** | Todo lo de Triage + hacer push a ramas, crear PRs, ejecutar Actions. | Desarrolladores |
| **Maintain** | Todo lo de Write + administrar configuraciones del repo (no las críticas de seguridad). | Tech leads, DevOps |
| **Admin** | Control total: borrar el repo, cambiar visibilidad, gestionar accesos. | Org owners, plataforma |

### 5.2 Matriz de permisos por acción

| Acción | Read | Triage | Write | Maintain | Admin |
|---|:---:|:---:|:---:|:---:|:---:|
| Clonar y leer código | ✅ | ✅ | ✅ | ✅ | ✅ |
| Comentar en PRs / issues | ✅ | ✅ | ✅ | ✅ | ✅ |
| Asignar labels y revisores | ❌ | ✅ | ✅ | ✅ | ✅ |
| Push a ramas de feature | ❌ | ❌ | ✅ | ✅ | ✅ |
| Crear Pull Request | ❌ | ❌ | ✅ | ✅ | ✅ |
| Aprobar Pull Request | ❌ | ❌ | ✅ | ✅ | ✅ |
| Hacer merge a `main` | ❌ | ❌ | 🔶* | ✅ | ✅ |
| Editar branch protection | ❌ | ❌ | ❌ | 🔶* | ✅ |
| Gestionar secrets del repo | ❌ | ❌ | ❌ | ✅ | ✅ |
| Cambiar visibilidad / borrar repo | ❌ | ❌ | ❌ | ❌ | ✅ |
| Agregar/quitar colaboradores | ❌ | ❌ | ❌ | ❌ | ✅ |

\* Sujeto a las reglas de protección de rama definidas en la sección 10.

### 5.3 Principios de asignación

1. **Mínimo privilegio.** Se otorga el permiso más bajo que permita hacer el trabajo.
2. **Permisos vía Team, siempre.** (Ver 4.2)
3. **`Admin` es excepcional.** Máximo 2–3 personas por organización.
4. **Revisión trimestral de accesos.** Se audita quién tiene acceso a qué y se retiran los inactivos.
5. **Toda solicitud de acceso pasa por Jira.** Sin ticket no hay acceso (ver sección 7).

### 5.4 Requisitos obligatorios de cuenta

- ✅ Autenticación de dos factores (2FA) **habilitada**. Sin excepciones.
- ✅ Acceso vía **SSO corporativo**.
- ✅ Nombre completo real y correo corporativo en el perfil.
- ✅ Uso de **Personal Access Tokens (PAT) de tipo fine-grained** con expiración máxima de 90 días, o SSH keys registradas.
- ❌ Prohibido compartir credenciales o tokens entre personas.

> 🖼️ **Espacio para imagen sugerida #4:** captura de la pantalla `Settings → Collaborators and teams` de un repo mostrando cómo se ven los teams asignados con su nivel de permiso.

---

## 6. Convención de nombres de repositorios

### 6.1 Estructura

```
<dominio>-<producto/servicio>-<tipo>
```

Todo en **minúsculas**, separado por **guiones medios** (`kebab-case`).

### 6.2 Componentes

| Componente | Descripción | Ejemplos |
|---|---|---|
| `<dominio>` | Área de negocio o célula dueña del repo. | `payments`, `cards`, `onboarding`, `channels`, `core` |
| `<producto/servicio>` | Nombre funcional, claro y corto. | `customer-search`, `login`, `transfers` |
| `<tipo>` | Naturaleza técnica del repositorio. | Ver tabla 6.3 |

### 6.3 Sufijos de tipo permitidos

| Sufijo | Se usa para | Ejemplo |
|---|---|---|
| `-api` | Servicios REST/GraphQL expuestos. | `payments-transfers-api` |
| `-service` | Microservicios internos sin exposición directa. | `cards-fraud-service` |
| `-web` | Aplicaciones frontend web. | `onboarding-portal-web` |
| `-mobile` | Aplicaciones móviles. | `channels-wallet-mobile` |
| `-lib` | Librerías reutilizables. | `core-logging-lib` |
| `-infra` | Infraestructura como código (Terraform, CloudFormation). | `payments-platform-infra` |
| `-pipeline` | Definiciones de CI/CD compartidas. | `core-shared-pipeline` |
| `-docs` | Documentación técnica. | `payments-architecture-docs` |
| `-tools` | Utilidades internas, scripts. | `devops-automation-tools` |
| `-poc` | Pruebas de concepto (temporales, con fecha de expiración). | `cards-tokenization-poc` |

### 6.4 Reglas

✅ **Sí:**
- Solo minúsculas, números y guiones medios.
- Máximo 50 caracteres.
- Nombre en **inglés** (estándar técnico).
- Debe ser autoexplicativo: alguien externo debe entender qué hay adentro sin abrirlo.

❌ **No:**
- Espacios, guiones bajos (`_`), puntos, `CamelCase`, `MAYÚSCULAS`.
- Acrónimos internos no documentados (`prj-x-v2`, `sys-4421`).
- Nombres de personas o de equipos (`repo-de-juan`, `equipo-alpha`).
- Sufijos de versión en el nombre (`-v2`, `-new`, `-final`, `-old`). Para eso están los tags y las ramas.
- Números de ticket como nombre (`abcd-1234`).

### 6.5 Ejemplos

| ❌ Mal | ✅ Bien | Por qué |
|---|---|---|
| `API_Pagos_Nueva` | `payments-transfers-api` | Mayúsculas, guion bajo, español, "nueva" no dice nada |
| `proyecto-juan` | `cards-fraud-service` | Nombre de persona, no describe el contenido |
| `backend2` | `onboarding-identity-api` | Genérico, no identifica dominio ni función |
| `MiLibreriaUtils` | `core-utils-lib` | CamelCase, no sigue estructura |
| `test` | `devops-automation-tools` | Ambiguo, invita al desorden |

---

## 7. Creación de repositorios (flujo con Jira)

> ⚠️ **Sección a completar con el detalle operativo del proyecto.** Abajo queda la estructura propuesta; hay que llenar los campos marcados con `_____` con los datos reales del board y del proyecto de Jira.

### 7.1 Principio

**Ningún repositorio se crea manualmente desde la interfaz de GitHub.** Toda creación nace de una solicitud en Jira, para asegurar trazabilidad, aprobación y aplicación automática de estándares (branch protection, labels, CODEOWNERS, plantillas).

### 7.2 Flujo general

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  1. Solicitud│ →  │ 2. Aprobación│ →  │ 3. Creación  │ →  │ 4. Entrega   │
│   en Jira    │    │  Tech Lead   │    │  automatizada│    │  al equipo   │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

### 7.3 Paso 1 — Crear la solicitud en Jira

| Campo | Valor |
|---|---|
| Proyecto Jira | `_____` |
| Tipo de issue | `_____` (ej. *Service Request* / *Task*) |
| Componente / Label | `_____` (ej. `github-repo-request`) |
| Asignado a | `_____` (equipo DevOps / Plataforma) |
| SLA de atención | `_____` (ej. 2 días hábiles) |

**Información obligatoria en la descripción del ticket:**

- [ ] Nombre propuesto del repositorio (según convención sección 6).
- [ ] Dominio / célula dueña.
- [ ] Descripción funcional (2–3 líneas: qué va a contener y para qué).
- [ ] Tipo de repositorio (`-api`, `-lib`, `-infra`, ...).
- [ ] Visibilidad: `private` (por defecto) / `internal`.
- [ ] Teams que requieren acceso y nivel solicitado (ver sección 5).
- [ ] Tech Lead responsable (aprobador).
- [ ] Lenguaje / stack principal (define el template a aplicar).
- [ ] ¿Requiere pipeline de CI/CD desde el inicio? Sí / No.
- [ ] ¿Maneja datos sensibles o regulados? Sí / No.

### 7.4 Paso 2 — Aprobación

El Tech Lead del dominio valida:
1. Que el repositorio realmente sea necesario (no duplica uno existente).
2. Que el nombre cumpla la convención.
3. Que los accesos solicitados sigan el principio de mínimo privilegio.

Aprueba cambiando el estado del ticket a `_____`.

### 7.5 Paso 3 — Creación

El equipo de Plataforma ejecuta el proceso `_____` (automatización / Terraform / GitHub Actions), que aplica:

- ✅ Repositorio creado con visibilidad `private`.
- ✅ Rama `main` como default y protegida.
- ✅ Archivo `README.md` con la plantilla estándar.
- ✅ Archivo `.gitignore` según el stack.
- ✅ Archivo `CODEOWNERS`.
- ✅ Plantillas de PR e Issues (`.github/`).
- ✅ Labels estándar (sección 13).
- ✅ Teams asignados con sus permisos.
- ✅ Secret scanning y Dependabot habilitados.

### 7.6 Paso 4 — Entrega

Se cierra el ticket de Jira con:
- URL del repositorio.
- Lista de accesos otorgados.
- Enlace a esta guía.

### 7.7 Contenido mínimo de todo repositorio

| Archivo | Obligatorio | Contenido |
|---|:---:|---|
| `README.md` | ✅ | Qué es, cómo levantarlo local, cómo probarlo, dueño, enlaces |
| `.gitignore` | ✅ | Según el stack |
| `CODEOWNERS` | ✅ | Revisores automáticos por ruta |
| `.github/pull_request_template.md` | ✅ | Plantilla de PR |
| `.github/workflows/` | ✅ | Pipelines de CI |
| `CHANGELOG.md` | 🔶 | Recomendado en librerías y APIs versionadas |
| `CONTRIBUTING.md` | 🔶 | Recomendado en repos con múltiples equipos |

> 🖼️ **Espacio para imagen sugerida #5:** captura del formulario real de Jira para solicitud de repositorio, con los campos señalados. Es la imagen de mayor valor práctico de todo el documento.

> 🖼️ **Espacio para imagen sugerida #6:** diagrama de flujo (BPMN simple o flowchart) del proceso Jira → aprobación → creación → entrega, con roles en carriles.

---

## 8. Estrategia de ramas (Branching Strategy)

### 8.1 Estrategia adoptada: **Trunk-Based con ramas de corta duración**

**En una frase:** `main` es la única fuente de verdad; todo cambio nace de `main` en una rama corta y vuelve a `main` mediante Pull Request.

### 8.2 Tipos de rama

| Rama | Duración | Nace de | Se integra a | Protegida |
|---|---|---|---|:---:|
| `main` | Permanente | — | — | ✅ |
| `develop` * | Permanente | `main` | `main` | ✅ |
| `feature/*` | Días (máx. 5 días hábiles) | `main` / `develop` | `main` / `develop` | ❌ |
| `bugfix/*` | Días | `main` / `develop` | `main` / `develop` | ❌ |
| `hotfix/*` | Horas | `main` | `main` (+ back-merge) | ❌ |
| `release/*` * | Días | `develop` | `main` | ✅ |

\* `develop` y `release/*` solo aplican si el equipo usa el modelo con rama de integración (ver 8.4).

### 8.3 Modelo A — Trunk-Based (recomendado por defecto)

```
main ────●────────●────────●────────●────────●──────▶
          \      /          \      /
           ●────●            ●────●
        feature/JIRA-123   bugfix/JIRA-456
```

**Cuándo usarlo:** servicios con despliegue continuo, equipos con buena cobertura de pruebas automatizadas.

**Ventajas:** menos conflictos, integración rápida, historial simple.

### 8.4 Modelo B — Con rama de integración (`develop`)

```
main ──────●──────────────────────────●──────────▶
            \                        /
develop ─────●──────●──────●────────●─────────────▶
              \    /        \      /
               ●──●          ●────●
          feature/JIRA-123  feature/JIRA-789
```

**Cuándo usarlo:** cuando hay ventanas de despliegue fijas, certificación previa obligatoria o múltiples equipos integrando hacia una misma liberación (escenario común en banca).

### 8.5 Flujo de hotfix

```
main ────●──────────────●────▶
          \            /
           ●──────────●
        hotfix/JIRA-999
```

1. Nace **directamente de `main`**.
2. PR con revisión acelerada (mínimo 1 aprobador + Tech Lead).
3. Merge a `main` + tag de versión patch.
4. **Back-merge obligatorio a `develop`** (si aplica el Modelo B), para no perder el fix.

### 8.6 Reglas transversales

1. 🚫 **Nunca se trabaja directamente sobre `main`.**
2. ⏱️ **Ramas cortas.** Si una rama vive más de 5 días hábiles, el alcance está mal dimensionado. Divídelo.
3. 🔄 **Sincroniza a diario** tu rama con la rama base (`git pull origin main --rebase`).
4. 1️⃣ **Una rama = un ticket de Jira = un propósito.**
5. 🧹 **Borra la rama después del merge.** GitHub lo hace automático si está configurado.
6. 📦 **Sin ramas personales de larga vida** (`juan/mis-cambios`).

> 🖼️ **Espacio para imagen sugerida #7:** diagrama de la estrategia de ramas adoptada (git graph). Aquí conviene una imagen limpia y grande — es la sección que más se consulta. Si prefieres, la genero como diagrama.

---

## 9. Convención de nombres de ramas

### 9.1 Estructura

```
<tipo>/<CLAVE-JIRA>-<descripcion-corta>
```

### 9.2 Tipos permitidos

| Tipo | Se usa para | Ejemplo |
|---|---|---|
| `feature/` | Nueva funcionalidad. | `feature/PAY-1234-transfer-limits` |
| `bugfix/` | Corrección de defecto en desarrollo. | `bugfix/PAY-1235-session-timeout` |
| `hotfix/` | Corrección urgente en producción. | `hotfix/PAY-1300-payment-duplication` |
| `refactor/` | Reestructuración sin cambio funcional. | `refactor/PAY-1240-payment-service` |
| `chore/` | Tareas de mantenimiento, dependencias, config. | `chore/PAY-1250-upgrade-spring-boot` |
| `docs/` | Solo documentación. | `docs/PAY-1260-api-readme` |
| `test/` | Solo pruebas. | `test/PAY-1270-integration-coverage` |
| `release/` | Preparación de liberación. | `release/2.4.0` |

### 9.3 Reglas

- ✅ La **clave de Jira en MAYÚSCULAS** e inmediatamente después del tipo. Esto habilita la vinculación automática con Jira (sección 15).
- ✅ Descripción en **inglés**, minúsculas, `kebab-case`, máximo 5 palabras.
- ❌ Sin caracteres especiales, tildes, ñ ni espacios.
- ❌ Sin nombres de personas.

### 9.4 Ejemplos

| ❌ Mal | ✅ Bien |
|---|---|
| `feature/nueva-funcionalidad` | `feature/PAY-1234-transfer-limits` |
| `juan-fix` | `bugfix/PAY-1235-session-timeout` |
| `Feature/Login_V2` | `feature/ONB-4410-login-mfa` |
| `arreglos` | `bugfix/CRD-2201-card-status-sync` |
| `PAY-1234` | `feature/PAY-1234-transfer-limits` |

---

## 10. Protección de ramas (Branch Protection Rules)

Se aplican mediante **Rulesets** a nivel de organización, para que ningún repositorio quede sin protección.

### 10.1 Reglas sobre `main` (y `develop` si aplica)

| Regla | Configuración | Por qué |
|---|---|---|
| Require a pull request before merging | ✅ Activado | Nadie hace push directo |
| Required approvals | **2** (mínimo 1 en repos de bajo riesgo) | Cuatro ojos |
| Dismiss stale approvals on new commits | ✅ Activado | Se revisa el código final, no una versión vieja |
| Require review from Code Owners | ✅ Activado | El dueño del módulo debe aprobar |
| Require status checks to pass | ✅ Activado (build, tests, SAST, lint) | No entra código roto |
| Require branches to be up to date | ✅ Activado | Se prueba contra el estado actual de `main` |
| Require conversation resolution | ✅ Activado | No quedan comentarios sin atender |
| Require signed commits | 🔶 Recomendado | Trazabilidad de autoría |
| Require linear history | ✅ Activado | Historial legible |
| Block force pushes | ✅ Activado | Protege el historial |
| Restrict deletions | ✅ Activado | Nadie borra `main` |
| Include administrators | ✅ Activado | Las reglas aplican para todos |

### 10.2 Estrategia de merge permitida

| Estrategia | Estado | Uso |
|---|:---:|---|
| **Squash and merge** | ✅ **Por defecto** | Un PR = un commit en `main`. Historial limpio. |
| **Rebase and merge** | 🔶 Caso a caso | Cuando cada commit del PR tiene valor independiente. |
| **Create a merge commit** | ❌ Deshabilitado | Genera historial ruidoso. |

> 🖼️ **Espacio para imagen sugerida #8:** captura de la configuración de Branch Protection / Rulesets aplicada en la organización, para que el equipo reconozca la pantalla.

---

## 11. Convención de commits

Se adopta el estándar **Conventional Commits**.

### 11.1 Estructura

```
<tipo>(<alcance opcional>): <descripción en imperativo>

[cuerpo opcional]

[footer opcional — refs, breaking changes]
```

### 11.2 Tipos

| Tipo | Uso |
|---|---|
| `feat` | Nueva funcionalidad |
| `fix` | Corrección de defecto |
| `refactor` | Cambio interno sin alterar comportamiento |
| `perf` | Mejora de rendimiento |
| `test` | Agregar o corregir pruebas |
| `docs` | Documentación |
| `build` | Build system, dependencias |
| `ci` | Pipelines y automatización |
| `chore` | Tareas varias sin impacto en producción |
| `revert` | Reversión de un commit previo |

### 11.3 Reglas

- Descripción en **inglés**, imperativo, minúscula inicial, sin punto final.
- Máximo **72 caracteres** en la primera línea.
- Un commit = un cambio lógico. Nada de "cambios varios".
- Incluir la clave de Jira en el cuerpo o footer: `Refs: PAY-1234`.

### 11.4 Ejemplos

```bash
# ✅ Bien
git commit -m "feat(transfers): add daily limit validation"
git commit -m "fix(auth): prevent session timeout on refresh"
git commit -m "refactor(payments): extract fee calculator to service"

# ❌ Mal
git commit -m "cambios"
git commit -m "arreglos varios y ajustes finales v2"
git commit -m "WIP"
git commit -m "Fixed the bug that was breaking everything."
```

---

## 12. Pull Requests: estándar de trabajo

### 12.1 Antes de abrir el PR

- [ ] La rama está sincronizada con la rama base.
- [ ] El build local pasa.
- [ ] Las pruebas unitarias pasan.
- [ ] No hay credenciales, tokens ni datos sensibles.
- [ ] Se eliminaron `console.log`, `System.out.println` y código comentado.
- [ ] El código sigue la guía de estilo del lenguaje.

### 12.2 Título del PR

Mismo formato que los commits, más la clave de Jira:

```
[PAY-1234] feat(transfers): add daily limit validation
```

### 12.3 Plantilla de descripción (`.github/pull_request_template.md`)

```markdown
## 🎫 Ticket
PAY-1234

## 📝 Descripción
_¿Qué cambia y por qué? En 3–5 líneas._

## 🔧 Tipo de cambio
- [ ] Nueva funcionalidad (feature)
- [ ] Corrección de defecto (bugfix)
- [ ] Corrección urgente (hotfix)
- [ ] Refactor
- [ ] Documentación
- [ ] Configuración / infraestructura

## ✅ Checklist
- [ ] Probado localmente
- [ ] Pruebas unitarias agregadas o actualizadas
- [ ] Documentación actualizada
- [ ] Sin credenciales ni datos sensibles
- [ ] Sin cambios de contrato (breaking changes) o están documentados
- [ ] Variables de entorno nuevas documentadas

## 🧪 Cómo probar
1.
2.
3.

## 📸 Evidencia
_Capturas, logs o resultados de pruebas._

## ⚠️ Impacto y riesgos
_Servicios afectados, plan de rollback._
```

### 12.4 Tamaño del PR

| Líneas modificadas | Estado |
|---|---|
| < 200 | ✅ Ideal |
| 200 – 400 | 🔶 Aceptable |
| > 400 | ❌ Divídelo |

**Un PR grande no se revisa: se aprueba.** Y ese es exactamente el riesgo que queremos evitar.

### 12.5 Revisión

| Aspecto | Estándar |
|---|---|
| Revisores mínimos | 2 (1 en repos de bajo riesgo) |
| Code Owner | Obligatorio si el PR toca su ruta |
| SLA de revisión | 24 horas hábiles |
| Auto-aprobación | ❌ Prohibida |

**Al revisar:** sé específico, comenta sobre el código y no sobre la persona, y distingue lo bloqueante de la sugerencia opcional (usa el prefijo `nit:` para lo menor).

### 12.6 Después del merge

- ✅ La rama se borra automáticamente.
- ✅ El ticket de Jira pasa al siguiente estado (automático vía integración).
- ✅ El pipeline de despliegue se dispara según el ambiente.

---

## 13. Labels estándar

Todos los repositorios de la organización se crean con el mismo set de labels. Esto permite filtrar y reportar de forma homogénea.

### 13.1 Por tipo

| Label | Color | Descripción |
|---|---|---|
| `type: feature` | `#0E8A16` | Nueva funcionalidad |
| `type: bug` | `#D73A4A` | Defecto |
| `type: hotfix` | `#B60205` | Corrección urgente en producción |
| `type: refactor` | `#1D76DB` | Reestructuración interna |
| `type: docs` | `#0075CA` | Documentación |
| `type: chore` | `#CFD3D7` | Mantenimiento |
| `type: test` | `#BFD4F2` | Pruebas |

### 13.2 Por prioridad

| Label | Color | Descripción |
|---|---|---|
| `priority: critical` | `#B60205` | Bloquea producción. Atención inmediata. |
| `priority: high` | `#D93F0B` | Sprint actual |
| `priority: medium` | `#FBCA04` | Siguiente sprint |
| `priority: low` | `#C2E0C6` | Backlog |

### 13.3 Por estado

| Label | Color | Descripción |
|---|---|---|
| `status: wip` | `#FEF2C0` | En progreso, no revisar aún |
| `status: ready for review` | `#0E8A16` | Listo para revisión |
| `status: changes requested` | `#D93F0B` | Requiere ajustes |
| `status: blocked` | `#B60205` | Bloqueado por dependencia externa |
| `status: on hold` | `#CFD3D7` | Pausado |

### 13.4 Por área

| Label | Color | Descripción |
|---|---|---|
| `area: backend` | `#5319E7` | Servicios y APIs |
| `area: frontend` | `#006B75` | Interfaces |
| `area: infra` | `#1D76DB` | Infraestructura / IaC |
| `area: ci-cd` | `#0052CC` | Pipelines |
| `area: security` | `#B60205` | Seguridad |
| `area: database` | `#5319E7` | Base de datos |

### 13.5 Especiales

| Label | Color | Descripción |
|---|---|---|
| `breaking change` | `#B60205` | Rompe compatibilidad. Requiere comunicación previa. |
| `needs discussion` | `#D4C5F9` | Requiere definición técnica o de negocio |
| `dependencies` | `#0366D6` | Actualización de dependencias (Dependabot) |
| `good first issue` | `#7057FF` | Apropiado para alguien que recién ingresa |

### 13.6 Reglas de uso

1. Todo PR e issue debe tener **como mínimo** un label `type:` y uno `priority:`.
2. Los labels **no se crean ad hoc por repositorio**. Si se necesita uno nuevo, se solicita vía Jira para agregarlo al set estándar de la organización.
3. Los labels de `status:` se actualizan durante la vida del PR.

---

## 14. Versionamiento, tags y releases

### 14.1 Versionamiento semántico (SemVer)

```
MAJOR.MINOR.PATCH   →   2.4.1
```

| Componente | Se incrementa cuando | Ejemplo |
|---|---|---|
| **MAJOR** | Hay cambios incompatibles (breaking changes). | `1.9.3` → `2.0.0` |
| **MINOR** | Se agrega funcionalidad compatible. | `2.0.0` → `2.1.0` |
| **PATCH** | Se corrige un defecto sin cambiar el contrato. | `2.1.0` → `2.1.1` |

### 14.2 Tags

Formato: `v<MAJOR>.<MINOR>.<PATCH>` → `v2.4.1`

```bash
git tag -a v2.4.1 -m "Release 2.4.1 - fix transfer limit validation"
git push origin v2.4.1
```

### 14.3 Releases

Cada liberación a producción genera un **Release** en GitHub con:
- Tag asociado.
- Notas de versión (generadas desde los Conventional Commits).
- Lista de tickets de Jira incluidos.
- Artefactos si aplica.

---

## 15. Integración GitHub ↔ Jira

> ⚠️ **Sección a validar con la configuración real del proyecto.**

### 15.1 Qué habilita la integración

Cuando la clave de Jira aparece en el nombre de la rama, en el commit o en el título del PR, Jira muestra automáticamente:
- Las ramas asociadas al ticket.
- Los commits realizados.
- El estado del Pull Request.
- El despliegue asociado.

Esto elimina el reporte manual de avance.

### 15.2 Dónde debe ir la clave de Jira

| Lugar | Formato | Ejemplo |
|---|---|---|
| Nombre de rama | `<tipo>/<CLAVE>-<desc>` | `feature/PAY-1234-transfer-limits` |
| Mensaje de commit | En el footer | `Refs: PAY-1234` |
| Título del PR | Al inicio, entre corchetes | `[PAY-1234] feat(transfers): ...` |

### 15.3 Transiciones automáticas

| Evento en GitHub | Estado en Jira |
|---|---|
| Se crea la rama | `In Progress` |
| Se abre el PR | `In Review` |
| Se aprueba el PR | `Ready to Merge` |
| Se hace merge a `main` | `_____` |
| Despliegue exitoso a producción | `Done` |

_(Confirmar el mapeo real de estados del workflow de Jira del proyecto.)_

> 🖼️ **Espacio para imagen sugerida #9:** captura de un ticket de Jira mostrando el panel de "Development" con ramas, commits y PRs vinculados. Muestra el beneficio concreto de nombrar bien las ramas.

---

## 16. Seguridad y manejo de información sensible

### 16.1 Nunca subir al repositorio

❌ Contraseñas, tokens, API keys, certificados privados.
❌ Archivos `.env` con valores reales.
❌ Cadenas de conexión a bases de datos.
❌ Datos de clientes reales (nombres, cuentas, tarjetas, identificaciones).
❌ Volcados de base de datos productiva.
❌ Llaves privadas SSH o PGP.

> **Recuerda:** borrar un secreto en un commit posterior **no lo elimina**. Queda en el historial. Si se sube un secreto, hay que **rotarlo inmediatamente** y reportarlo al equipo de seguridad.

### 16.2 Cómo manejar secretos correctamente

| Contexto | Mecanismo |
|---|---|
| Local | Archivo `.env` **incluido en `.gitignore`**, con un `.env.example` sin valores reales |
| CI/CD | GitHub Secrets a nivel de organización o repositorio |
| Runtime | Gestor de secretos corporativo (Vault / Secrets Manager) |

### 16.3 Controles habilitados por defecto

| Control | Función |
|---|---|
| **Secret Scanning + Push Protection** | Bloquea el push si detecta un secreto |
| **Dependabot Alerts** | Alerta vulnerabilidades en dependencias |
| **Dependabot Security Updates** | Genera PRs de actualización automáticos |
| **Code Scanning (SAST)** | Análisis estático en cada PR |
| **Audit Log** | Registro de acciones administrativas |

### 16.4 Si subiste un secreto por error

1. 🚨 **Rota la credencial de inmediato.** Es lo primero, antes que cualquier limpieza.
2. Notifica al equipo de Seguridad y a tu Tech Lead.
3. Abre un ticket de Jira para la limpieza del historial.
4. **No intentes reescribir el historial por tu cuenta** en una rama compartida.

---

## 17. Flujo de trabajo diario (paso a paso)

### Paso 1 — Toma el ticket en Jira
Asegúrate de tener la clave (ej. `PAY-1234`) y de que el ticket esté en `In Progress`.

### Paso 2 — Actualiza tu copia local
```bash
git checkout main
git pull origin main
```

### Paso 3 — Crea tu rama
```bash
git checkout -b feature/PAY-1234-transfer-limits
```

### Paso 4 — Trabaja y haz commits pequeños
```bash
git status
git add .
git commit -m "feat(transfers): add daily limit validation"
```

### Paso 5 — Sincroniza con `main` (mínimo una vez al día)
```bash
git fetch origin
git rebase origin/main
```

### Paso 6 — Publica tu rama
```bash
git push -u origin feature/PAY-1234-transfer-limits
```

### Paso 7 — Abre el Pull Request en GitHub
- Título con la clave de Jira.
- Llena la plantilla completa.
- Asigna revisores y labels.

### Paso 8 — Atiende la revisión
- Responde cada comentario.
- Sube los ajustes a la misma rama.
- Resuelve las conversaciones.

### Paso 9 — Merge
Una vez aprobado y con todos los checks en verde: **Squash and merge**.

### Paso 10 — Limpieza
```bash
git checkout main
git pull origin main
git branch -d feature/PAY-1234-transfer-limits
```

> 🖼️ **Espacio para imagen sugerida #10:** capturas de la pantalla de creación de PR en GitHub, señalando dónde va el título, los revisores, los labels y los checks. Ideal para perfiles junior.

---

## 18. Comandos Git más utilizados

### 18.1 Configuración inicial (una sola vez)
```bash
git config --global user.name "Nombre Apellido"
git config --global user.email "nombre.apellido@empresa.com"
git config --global pull.rebase true
git config --global init.defaultBranch main
```

### 18.2 Trabajo diario
```bash
git clone <url>                        # Clonar repositorio
git status                             # Ver estado de los cambios
git branch                             # Listar ramas locales
git branch -a                          # Listar todas las ramas (incl. remotas)
git checkout <rama>                    # Cambiar de rama
git checkout -b <nueva-rama>           # Crear y cambiar a una rama nueva
git pull origin main                   # Descargar cambios
git add .                              # Preparar todos los cambios
git add <archivo>                      # Preparar un archivo específico
git commit -m "mensaje"                # Confirmar cambios
git push origin <rama>                 # Publicar la rama
git log --oneline --graph --decorate   # Ver historial visual
git diff                               # Ver cambios sin preparar
git diff --staged                      # Ver cambios preparados
```

### 18.3 Sincronización y limpieza
```bash
git fetch origin                       # Traer referencias remotas sin mezclar
git rebase origin/main                 # Rebasar tu rama sobre main
git merge origin/main                  # Alternativa al rebase
git branch -d <rama>                   # Borrar rama local
git push origin --delete <rama>        # Borrar rama remota
git remote prune origin                # Limpiar referencias a ramas borradas
```

### 18.4 Guardar trabajo temporalmente
```bash
git stash                              # Guardar cambios sin commitear
git stash list                         # Ver stashes guardados
git stash pop                          # Recuperar el último stash
```

### 18.5 Deshacer (con cuidado)
```bash
git restore <archivo>                  # Descartar cambios locales de un archivo
git restore --staged <archivo>         # Quitar un archivo del staging
git commit --amend                     # Corregir el último commit (solo si NO se ha pusheado)
git revert <hash>                      # Crear un commit que revierte otro (seguro en ramas compartidas)
git reset --soft HEAD~1                # Deshacer el último commit, conservando los cambios
```

> ⚠️ `git reset --hard` y `git push --force` **están prohibidos en ramas compartidas**. Si necesitas forzar en tu propia rama, usa `git push --force-with-lease`.

---

## 19. Buenas prácticas (resumen)

### ✅ Sí

- Crear una rama por cada cambio, vinculada a un ticket de Jira.
- Mantener commits pequeños, atómicos y descriptivos.
- Usar Pull Requests para **toda** modificación.
- Sincronizar tu rama con `main` a diario.
- Solicitar revisión antes de cualquier merge.
- Mantener el `README.md` y la documentación actualizados.
- Borrar las ramas ya integradas.
- Escribir mensajes de commit en imperativo y en inglés.
- Responder los comentarios de revisión en menos de 24 horas.

### ❌ No

- Trabajar directamente sobre `main` o `develop`.
- Subir contraseñas, tokens o información sensible.
- Hacer cambios grandes en un único commit o PR.
- Usar `git push --force` en ramas compartidas.
- Aprobar tu propio Pull Request.
- Dejar ramas vivas por semanas.
- Nombrar ramas o repos con nombres de personas.
- Hacer merge con checks de CI en rojo.
- Commitear código comentado o `console.log` de depuración.

---

## 20. Preguntas frecuentes

**¿Puedo hacer push directo a `main` si es un cambio mínimo?**
No. La rama está protegida y toda modificación requiere PR. No hay excepciones por tamaño.

**Mi rama tiene conflictos con `main`. ¿Qué hago?**
`git fetch origin` → `git rebase origin/main` → resolver los conflictos archivo por archivo → `git add <archivo>` → `git rebase --continue` → `git push --force-with-lease`.

**¿Squash o merge commit?**
Squash por defecto. Un PR se convierte en un commit en `main`.

**¿Qué hago si nadie revisa mi PR?**
El SLA es de 24 horas hábiles. Pasado ese tiempo, escala con tu Tech Lead.

**¿Cuándo uso `hotfix` en lugar de `bugfix`?**
`hotfix` es exclusivamente para defectos que ya están afectando producción y requieren liberación inmediata. Todo lo demás es `bugfix`.

**Necesito acceso a un repositorio. ¿A quién le pido?**
Abre un ticket de Jira solicitando ingreso al Team correspondiente. No se otorgan accesos individuales por mensaje directo.

**¿Puedo crear un repositorio yo mismo?**
No. Toda creación pasa por el flujo de la sección 7.

---

## 21. Glosario

| Término | Definición |
|---|---|
| **Branch protection** | Conjunto de reglas que restringen qué se puede hacer sobre una rama. |
| **CODEOWNERS** | Archivo que asigna revisores obligatorios según la ruta modificada. |
| **Conventional Commits** | Estándar de formato para mensajes de commit. |
| **Fast-forward** | Merge sin commit adicional, posible cuando no hay divergencia. |
| **Force push** | Sobrescribir el historial remoto. Peligroso en ramas compartidas. |
| **Rebase** | Reaplicar tus commits sobre la punta de otra rama. Genera historial lineal. |
| **Ruleset** | Reglas de protección aplicadas a nivel de organización. |
| **SemVer** | Versionamiento semántico (`MAJOR.MINOR.PATCH`). |
| **SLA** | Tiempo máximo comprometido de respuesta. |
| **Squash** | Comprimir varios commits en uno solo. |
| **Trunk-based development** | Modelo donde todo se integra rápido a una única rama principal. |
| **Upstream** | Repositorio o rama de origen desde donde se sincroniza. |

---

## Control de cambios

| Versión | Fecha | Autor | Cambios |
|---|---|---|---|
| 1.0 | _(fecha)_ | _(autor)_ | Versión inicial estructurada |

---

## Referencias

- [Documentación oficial de Git](https://git-scm.com/doc)
- [GitHub Docs](https://docs.github.com)
- [Conventional Commits](https://www.conventionalcommits.org)
- [Semantic Versioning](https://semver.org)
