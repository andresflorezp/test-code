# Contrato ROP → AAP v1

El ROP hace **una llamada por cada unidad desplegable, en una instancia y un ambiente**. Le dice a AAP qué desplegar, dónde y bajo qué release. AAP resuelve lo demás (servidores, rutas, credenciales, secretos) y devuelve el número del job.

Es una propuesta para acordar con el equipo del ROP. Los valores de los ejemplos son inventados.

## La llamada

Aplica para AAP 2.6. Cada ambiente tiene su propio AAP, así que el ROP elige a cuál llamar según el ambiente.

| Qué | Valor |
| --- | --- |
| Método y ruta | `POST https://<gateway-del-ambiente>/api/controller/v2/job_templates/<job-template>++<Organización>/launch/` |
| Job Template | Uno por plataforma: `deploy-openshift`, `deploy-linux`, `deploy-api` o `deploy-windows`. La plataforma de cada tech stack sale de Self Service |
| Autenticación | `Authorization: Bearer <token>`. El token se crea una vez en `/api/gateway/v1/tokens/` con el usuario de servicio del ROP |
| Tipo de contenido | `Content-Type: application/json` |

La barra final de `/launch/` es obligatoria. El cuerpo es igual para las cuatro plataformas:

```json
{
  "extra_vars": {
    "contract_version": 1,
    "deploy_type": "java_container",
    "environment": "uat",
    "app_id": "payments_api",
    "instance_id": "payments_api_uat1",
    "deploy_action": "deploy",
    "artifact_name": "payments-api",
    "artifact_version": "1.8.3",
    "artifact_url": "artifactory.banamex.com/docker-release/payments-api:1.8.3",
    "artifact_digest": "sha256:8f31c4a2e7d8...",
    "release_id": "PRM-2026-4002",
    "change_id": "CHG0012345",
    "requested_by": "aflorez",
    "workflow_run_id": 8723918821,
    "app_vars": {
      "API_BASE_URL": "https://api-uat.banamex.internal",
      "JAVA_OPTS": "-Xms512m -Xmx1g",
      "DB_PASSWORD": "vault:secret/apps/payments_api/db#password"
    }
  }
}
```

Todo va dentro de `extra_vars`. El ROP no manda inventario ni credenciales: quedan fijos en AAP.

## Campos

Son 15: 12 obligatorios y 3 opcionales.

| Campo | Tipo | Obligatorio | Qué es | Formato |
| --- | --- | --- | --- | --- |
| `contract_version` | número | Sí | Versión de este contrato | `1` |
| `deploy_type` | texto | Sí | Tipo de despliegue. Elige los pasos que ejecuta AAP | Valor del catálogo, con guion bajo: `java_container` |
| `environment` | texto | Sí | Ambiente destino | `dev`, `sit`, `uat`, `perf` o `prod` |
| `app_id` | texto | Sí | La unidad que se despliega. Una aplicación puede tener varias (imagen, configuración, base de datos) | Minúsculas, números y guion bajo |
| `instance_id` | texto | Sí | En cuál instancia de esa unidad se despliega | Minúsculas, números y guion bajo |
| `deploy_action` | texto | Sí | Qué hacer | `deploy` o `rollback` |
| `artifact_name` | texto | Sí | Nombre del artefacto | No vacío |
| `artifact_version` | texto | Sí | Versión a desplegar | `1.2.3` |
| `artifact_url` | texto | Sí | Dónde está el artefacto | Ruta del Artifactory del banco |
| `artifact_digest` | texto | Sí | Huella del artefacto | `sha256:` + 64 caracteres hexadecimales |
| `release_id` | texto | Sí | Identificador del release en el ROP | No vacío |
| `requested_by` | texto | Sí | Quién lanzó el despliegue | Usuario |
| `change_id` | texto | En ambientes con ticket | Ticket de ServiceNow ya validado por el ROP | `CHG` + 7 dígitos |
| `workflow_run_id` | número | No | Build de GitHub que produjo el artefacto | Número |
| `app_vars` | objeto | No | Variables de la app para ese ambiente | Clave y valor. Los secretos solo como referencia: `vault:ruta#campo` |

Un campo opcional que no aplica **se omite**. La API no acepta `null` ni conviene mandarlo vacío.

## Respuesta y resultado

AAP responde de inmediato con el número del job. El despliegue sigue corriendo.

```json
{
  "job": 4471,
  "ignored_fields": {},
  "status": "pending",
  "url": "/api/controller/v2/jobs/4471/"
}
```

| Código | Qué significa | Qué hace el ROP |
| --- | --- | --- |
| `201` | El job se creó | Guarda `job` junto al `release_id` y revisa `ignored_fields` |
| `400` | Falta un campo obligatorio o un valor no es válido. No se creó job | Corrige y reintenta. La respuesta dice qué campo falló |
| `401` / `403` | Token inválido o sin permiso sobre ese Job Template | Revisa el token y los permisos |
| `404` | El Job Template no existe con ese nombre | Revisa plataforma y organización en la ruta |

**`ignored_fields` debe venir vacío.** Si el ROP manda algo que AAP no permite, AAP no rechaza la llamada: lanza el job sin ese dato y lo lista ahí. Si no viene vacío, el despliegue corrió con menos información de la enviada.

Para conocer el resultado, el ROP consulta el job:

```http
GET https://<gateway-del-ambiente>/api/controller/v2/jobs/4471/
Authorization: Bearer <token>
```

El campo `status` pasa por `pending`, `waiting` y `running`, y termina en `successful`, `failed` o `canceled`. El log completo está en `/jobs/4471/stdout/?format=txt`.

Un job puede terminar en `failed` antes de desplegar nada: AAP valida el contrato al inicio (formatos, que la instancia pertenezca a la unidad, que el tipo corresponda a la plataforma) y se detiene si algo no cuadra.

## Reglas

- **Una llamada despliega una unidad en una instancia.** Para varias instancias, el ROP hace una llamada por cada una.
- **Los identificadores no cambian.** `app_id` e `instance_id` se asignan una vez y deben ser los mismos en el ROP y en el inventario de AAP. El nombre visible de la app es aparte y sí puede cambiar.
- **Rollback:** misma llamada con `deploy_action: rollback`, y en `artifact_version`, `artifact_url` y `artifact_digest` los datos de la versión a la que se vuelve.
- **Secretos:** nunca viajan en claro. En `app_vars` solo va la referencia a Vault.
- **Lo que no viaja:** servidores, namespaces, rutas, usuarios, inventario y credenciales. Eso vive en AAP.
- **Cambios al contrato:** `contract_version` sube solo si un ROP sin actualizar dejaría de funcionar (campo obligatorio nuevo, campo renombrado o eliminado, cambio de formato). Agregar un campo opcional no la sube.

## Quién hace qué

| El ROP | AAP |
| --- | --- |
| Sabe qué unidades e instancias tiene cada aplicación en cada ambiente | Sabe dónde vive cada instancia y cómo conectarse |
| Valida el ticket de ServiceNow | Exige que el ticket venga donde aplica y lo deja registrado |
| Lanza las instancias una por una y decide qué hacer si una falla | Despliega una instancia por llamada y reporta el resultado |
| Mantiene el orden entre unidades (por ejemplo, configuración antes que imagen) | No conoce dependencias entre unidades |
| Consulta el estado del job | Guarda el job, el log y los datos recibidos |
