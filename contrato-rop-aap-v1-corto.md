# Contrato ROP → AAP v1

El ROP hace **una llamada por cada unidad desplegable, en una instancia y un ambiente**. AAP resuelve servidores, credenciales y secretos, y devuelve el número del job. Los valores de los ejemplos son inventados.

## La llamada

```http
POST https://<gateway-del-ambiente>/api/controller/v2/job_templates/<job-template>++<Organización>/launch/
Authorization: Bearer <token>
Content-Type: application/json
```

- **Job Template:** uno por plataforma. `deploy-openshift`, `deploy-linux`, `deploy-api` o `deploy-windows`.
- **Ambiente:** cada uno tiene su propio AAP (versión 2.6). El ROP llama al del ambiente destino.
- **Token:** de un usuario de servicio del ROP en ese AAP.

## El cuerpo

Es igual para las cuatro plataformas. Los comentarios son solo explicación: el JSON real va sin ellos.

```jsonc
{
  "extra_vars": {

    // --- Obligatorios ---
    "contract_version": 1,                  // versión de este contrato
    "deploy_type": "java_container",        // tipo de despliegue, según el catálogo
    "environment": "uat",                   // dev | sit | uat | perf | prod
    "app_id": "payments_api",               // la unidad que se despliega
    "instance_id": "payments_api_uat1",     // en cuál de sus instancias
    "deploy_action": "deploy",              // deploy | rollback
    "artifact_url": "artifactory.banamex.com/docker-release/payments-api:1.8.3",  // ruta completa en Artifactory; la arma el ROP
    "artifact_version": "1.8.3",            // versión a desplegar, para el registro
    "artifact_digest": "sha256:8f31c4a2e7d8...",  // huella del artefacto
    "release_id": "PRM-2026-4002",          // release en el ROP
    "requested_by": "aflorez",              // quién lanzó el despliegue

    // --- Opcionales: si no aplican, se omiten (no se manda null) ---
    "change_id": "CHG0012345",              // ticket de ServiceNow; obligatorio en ambientes con ticket
    "workflow_run_id": 8723918821,          // build de GitHub que produjo el artefacto

    "config_artifact": {                    // scripts y archivos que la app necesita para funcionar
      "url": "artifactory.banamex.com/config-release/payments-api/uat/payments-api-config-2.1.0.zip",  // ruta completa, la del ambiente destino
      "version": "2.1.0",                   // si viene el bloque, los tres datos son obligatorios
      "digest": "sha256:5b1e9c07a3f2..."
    },

    "app_vars": {                           // variables de la app para ese ambiente
      "JAVA_OPTS": "-Xms512m -Xmx1g",
      "DB_PASSWORD": "vault:secret/apps/payments_api/db#password"  // secretos: solo la referencia a Vault
    }
  }
}
```

## La respuesta

```json
{ "job": 4471, "ignored_fields": {}, "status": "pending" }
```

- El ROP guarda `job` junto al `release_id`.
- `ignored_fields` debe venir vacío. Si trae algo, AAP descartó ese dato y lanzó el job sin él.
- Si falta un obligatorio o un valor no es válido, AAP responde `400` y no crea job.
- El resultado se consulta en `GET .../api/controller/v2/jobs/<job>/`. El campo `status` termina en `successful`, `failed` o `canceled`.

## Reglas

- **Una llamada despliega una unidad en una instancia.** Para varias instancias, una llamada por cada una.
- **`app_id` e `instance_id` no cambian** y deben ser los mismos en el ROP y en AAP.
- **Rollback:** la misma llamada con `deploy_action: rollback` y los datos del artefacto (y de la configuración) de la versión a la que se vuelve.
- **Secretos:** nunca en claro, ni en `app_vars` ni en el paquete de configuración.
- **No viajan:** servidores, rutas, usuarios, inventario ni credenciales. Eso vive en AAP.
