## Para qué sirve cada paso del CI

| Fase | Paso | Estado | Qué hace | Se conecta a | En GitHub Actions |
|---|---|---|---|---|---|
| 1. Inicio | **Checkout del repo** | ✅ Habilitado | Descarga el repo de la app (la rama que dispara el build). | Repo de la app (hoy Bitbucket: cedt-gct-bitbucket.nam.nsroot.net) | **Sí**: actions/checkout (repo migrado a GitHub) |
| 1. Inicio | **Descarga Unify CI** | ✅ Habilitado | Descarga los scripts de Unify que orquestan el pipeline (launchPipeline.sh). | https://cedt-gct-bitbucket.nam.nsroot.net/bitbucket/scm/cicd/cicd.git (rama master) | **No**: El workflow reemplaza a Unify |
| 1. Inicio | **Initialize Pipeline** | ✅ Habilitado | Lee de la base de Unify los datos fijos de la app. | Base de datos de Unify (interna) | **No**: Pasan a variables del repo |
| 2. Validaciones de Unify | **CD Gate** | ✅ Habilitado | Pregunta al servicio central si la app cumple las políticas. Salió WARN: Checkmarx sin resultados. Solo avisa. | https://gatingservice.citigroup.net/cd/results/‹id› | **Sí**: Si Citi lo exige |
| 2. Validaciones de Unify | **API Governance** | No aplica | Se salta en el workflow copy. | — | **No**: No aplica |
| 2. Validaciones de Unify | **Unify Patterns** | ✅ Habilitado | Detecta workflow copy (no Java) y usa el assembly.xml por defecto. | Local | **No**: El workflow define qué empaquetar |
| 2. Validaciones de Unify | **Integrity check** | ✅ Habilitado | Verifica que el pipeline.yml cumpla el estándar. | Unify (interno) | **No**: Propio de Unify |
| 2. Validaciones de Unify | **SCM info** | ✅ Habilitado | Arma el change log y busca el PR asociado. | Repo de la app | **Opcional**: GitHub ya lo muestra |
| 3. Configuración | **Configure THOR** | ✅ Habilitado | Configura Maven, Java y Artifactory. | https://www.artifactrepository.citigroup.net/artifactory/maven-gcg-prod | **No**: Para bash no hace falta |
| 3. Configuración | **Pipeline config** | ✅ Habilitado | Workflow copy, escaneos, umbrales y Template de RLM de la app. | pipeline.yml del repo | **Reemplazar**: YAML del workflow |
| 4. Build en EB | **Build** | ✅ Habilitado | Corre Maven en un agente de EB. No compila nada: solo junta los scripts. | https://ebjenkins01.nam.nsroot.net/job/MEXICO/‹app›/… | **Reemplazar**: Un zip simple |
| 4. Build en EB | **Golden archive** | ✅ Habilitado | Copia del código fuente para auditoría. | https://swdc-obj-wip1.wlb.nam.nsroot.net/eb.repo/…/SrcArc | **Opcional**: Si auditoría lo exige |
| 4. Build en EB | **Empaqueta** | ✅ Habilitado | Zip con los scripts según assembly.xml. | Local | **Sí**: Paso de zip |
| 4. Build en EB | **Archiva el paquete** | ✅ Habilitado | Sube el zip a EB (retención 45 días). | https://swdc-obj-wip1.wlb.nam.nsroot.net/eb.repo/…/PkgArc | **Reemplazar**: Subir a Artifactory |
| 5. Calidad y seguridad | **ShellCheck** | 💡 Propuesto | Detecta errores comunes en scripts bash. | — | **Sí**: Propuesto |
| 5. Calidad y seguridad | **Secret scanning** | 💡 Propuesto | Evita que se suban credenciales en los scripts. | — | **Sí**: Propuesto |
| 5. Calidad y seguridad | **SonarQube** | ✅ Habilitado | Corre, pero casi no tiene qué analizar en scripts. | https://sonarqube04.nam.nsroot.net | **Opcional**: Poco valor para bash |
| 5. Calidad y seguridad | **Quality Gate** | ✅ Habilitado | Revisa bugs y vulnerabilidades bloqueantes. Pasó. | https://proactv2-ecs.nam.nsroot.net/proact/ | **Opcional**: Si se mantiene Sonar |
| 5. Calidad y seguridad | **Checkmarx / BlackDuck** | ⛔ Sin resultados | Los pasos corren en EB pero sin resultados ni scan habilitado. | — | **A necesidad**: Si seguridad lo pide |
| 5. Calidad y seguridad | **GEM report** | ✅ Habilitado | Revisa vulnerabilidades GEM. Sin hallazgos. | Gating service | **Opcional**: Ligado al CD Gate |
| 5. Calidad y seguridad | **Snyk** | ✅ Habilitado | Sin vulnerabilidades críticas. | Snyk (interno) | **No**: Bash no tiene dependencias |
| 6. Despliegue | **RLM Integration** | ✅ Habilitado | Template FILECOPY de la app, ENVIRONMENT=DEV. | RLM (interno) | **Reemplazar**: Jobs por GitHub Environment |
| 6. Despliegue | **Crea request en RLM** | ✅ Habilitado | Crea y ejecuta el request (EXECUTE_NOW). | https://releaseorchestrationdeployment.citigroup.net/brpm/requests/‹id› | **Reemplazar**: Job de deploy en runner con acceso al server |
| 7. Cierre | **Post build** | ✅ Habilitado | Actualiza buildinfo y la integración de Sonar. | Unify (interno) | **No**: Propio de Unify |
| 7. Cierre | **Tag del repo** | ✅ Habilitado | Tag snapshot.‹build› y push al repo. | Repo de la app | **Sí**: git tag en el workflow |
| 7. Cierre | **Logs a Splunk** | ✅ Habilitado | Manda el resultado de Sonar a Splunk. | Splunk (interno) | **Opcional**: Si observabilidad lo requiere |

> **Sí**: se mantiene igual · **Reemplazar**: misma función, otra forma · **No**: propio de Unify o no aplica a bash · **Opcional / A necesidad**: según seguridad o auditoría.

## Variables de entorno del Template (valores de ejemplo)

| Variable | DEV | SIT | UAT | Qué es |
|---|---|---|---|---|
| `CITI_DEST_DIR` | /opt/c730/060 | /opt/c730/060 | /opt/c730/060 | Carpeta del server donde se copia el paquete y desde donde corre el script. |
| `CITI_DEST_USER` | c730060 | c730060 | c730060 | Usuario del server con el que se copian los archivos y se ejecuta el script. |
| `CITI_DEST_GROUP` | c730 | c730 | c730 | Grupo que se asigna a los archivos copiados. |
| `CITI_DEST_PERMS` | 775 | 775 | 775 | Permisos de los archivos copiados: dueño y grupo leen, escriben y ejecutan; el resto solo lee y ejecuta. |
| `CITI_DEST_SCRIPT` | postinstall.sh | postinstall.sh | postinstall.sh | Script que RLM ejecuta en el 2.5. Puede tener cualquier nombre y hacer lo que la app necesite. |
| `RLM_TECH_STACKS` | FILECOPY | FILECOPY | FILECOPY | Tipo de despliegue en RLM: copiar archivos al server. |
| `tmp_tech_stack_FILECOPY` | yes | yes | yes | Activa el flujo FILECOPY en el proceso de RLM. *(inferido)* |
| `CITI_EXTRACT_FLAG` | FALSE | FALSE | FALSE | No impide descomprimir el zip (en el 2.4 sí se descomprime). Controla otra extracción, por confirmar. |
| `CITI_BMA_TOKEN_SERVER_NAME` | sd-ijjd-vtx0.nam.nsroot.net | sd-f8b6-beac.nam.nsroot.net | sd-kdix-h5gq.nam.nsroot.net | Server destino del ambiente. *(inferido)* |
| `CITI_APPID` | 163973 | 163973 | 163973 | ID de la aplicación (CSI). |
| `CITI_COMPONENT` | — | — | — | Componente de la app. Vacío en este Template. |
| `CITI_SNOW_SYSTEM` | SAAS | SAAS | SAAS | Instancia de ServiceNow. |
| `CITI_SNOW_TEMPLATE_ID` | — | CTMP0000084327 | CTMP0000084539 | Plantilla con la que se crea el CR. DEV no tiene: no pide CR. SIT y UAT sí. |
| `CITI_UAT_CHANGE` | — | — | — | CR de UAT si aplica. Vacío. |

## Pasos del despliegue en RLM

| Paso | Nombre | Qué hace | Aplica |
|---|---|---|---|
| 1.0 | Cargar variables | Carga las variables del Template para el ambiente: carpeta, usuario, permisos, script y server destino. | Todos |
| CR | Validación en ServiceNow | Si el ambiente tiene `CITI_SNOW_TEMPLATE_ID`, se valida el CR. En DEV se salta. | Según ambiente |
| 2.4 | Deploy Package to Application Base Directory | Acción `citi_copy_pkg_to_dest`: copia el zip del build al server, lo descomprime, pone dueño `CITI_DEST_USER:CITI_DEST_GROUP` y permisos `CITI_DEST_PERMS`, y copia todo a `CITI_DEST_DIR`. | Todos |
| 2.5 | Execute Script On Target | Acción `citi_execute_script_onTarget`: valida `CITI_DEST_DIR`, `CITI_DEST_USER` y `CITI_DEST_SCRIPT`, y ejecuta `su ‹CITI_DEST_USER› -c ‹CITI_DEST_DIR›/‹CITI_DEST_SCRIPT›`. Éxito si sale con código 0. | Todos |
| 3.0 | ¿Se promueve? | El usuario decide si promueve: DEV → SIT → UAT → PROD. | Todos |
| 5.0 | CR del siguiente ambiente | Si el ambiente destino lo pide, se crea el CR con su plantilla. | Según ambiente |

## Ejemplo: servidores por ambiente

| Server | Ambiente | Host Oracle (ORAAS) |
|---|---|---|
| `sd-ijjd-vtx0` | DEV | `oraas-gt-d10-02` |
| `sd-f8b6-beac` | SIT | `oraas-gt-d67-01` |
| `sd-kdix-h5gq` | UAT | `oraasgtp49` |
| `sd-e96f-9fc5` | ¿COB o UAT 2? *(inferido)* | `oraasqru003` |
| `sd-1758-1f7a` · `sd-zpnb-t3h4` | PROD *(inferido)* | `oraasqrp015` |
