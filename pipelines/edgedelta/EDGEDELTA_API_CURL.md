# Edge Delta API – curl commands

Based on [Edge Delta API](https://api.edgedelta.com/swagger/index.html) and [Manage Pipelines with the API](https://docs.edgedelta.com/api-example/).

Replace `<<ORG_ID>>`, `<<API_TOKEN>>`, `<<PIPELINE_ID>>`, and `<<VERSION_ID>>` with your values.

---

## 1. Create a base pipeline

Creates a new pipeline with a base configuration (environment/fleet). Use the returned pipeline `id` as `PIPELINE_ID` for update/save/deploy.

```bash
curl -X POST 'https://api.edgedelta.com/v1/orgs/<<ORG_ID>>/pipelines/base' \
  -H 'X-ED-API-Token: <<API_TOKEN>>' \
  -H 'Content-Type: application/json' \
  -d '{"environment_type": "Kubernetes", "description": "HTTP benchmark pipeline"}'
```

---

## 2. Validate configuration (before save)

Validates the YAML in `pipelines/edgedelta.yaml` without saving.

```bash
curl -X POST 'https://api.edgedelta.com/v1/orgs/<<ORG_ID>>/confs/validate' \
  -H 'X-ED-API-Token: <<API_TOKEN>>' \
  -H 'Content-Type: application/json' \
  -d "{\"content\": $(jq -Rs '.' pipelines/edgedelta.yaml)}"
```

Success: `{"valid": true}`. On error: `{"valid": false, "errors": ["..."]}`.

---

## 3. Update pipeline with `pipelines/edgedelta.yaml`

Saves a new version of the pipeline using the content of `edgedelta.yaml`.

```bash
curl -X POST 'https://api.edgedelta.com/v1/orgs/<<ORG_ID>>/pipelines/<<PIPELINE_ID>>/save' \
  -H 'X-ED-API-Token: <<API_TOKEN>>' \
  -H 'Content-Type: application/json' \
  -d "{\"content\": $(jq -Rs '.' pipelines/edgedelta.yaml)}"
```

---

## 4. Get version history

Returns version history; use the **timestamp** of the latest entry as `<<VERSION_ID>>` for deploy.

```bash
curl -X GET 'https://api.edgedelta.com/v1/orgs/<<ORG_ID>>/pipelines/<<PIPELINE_ID>>/history' \
  -H 'X-ED-API-Token: <<API_TOKEN>>'
```

Example: `[{"timestamp": "1733394600000", "author": "...", "status": "saved"}, ...]` → use `1733394600000` as version.

---

## 5. Deploy a version

Marks that version as active so agents reload the config.

```bash
curl -X POST 'https://api.edgedelta.com/v1/orgs/<<ORG_ID>>/pipelines/<<PIPELINE_ID>>/deploy/<<VERSION_ID>>' \
  -H 'X-ED-API-Token: <<API_TOKEN>>' \
  -H 'Content-Type: application/json'
```

---

## Endpoint summary

| Action              | Method | Endpoint |
|---------------------|--------|----------|
| Create base pipeline | POST   | `/v1/orgs/{org_id}/pipelines/base` |
| Validate config     | POST   | `/v1/orgs/{org_id}/confs/validate` |
| Save (update)       | POST   | `/v1/orgs/{org_id}/pipelines/{conf_id}/save` |
| Get history        | GET    | `/v1/orgs/{org_id}/pipelines/{conf_id}/history` |
| Deploy version     | POST   | `/v1/orgs/{org_id}/pipelines/{conf_id}/deploy/{version}` |

All authenticated requests use header: `X-ED-API-Token: <<API_TOKEN>>`.

---

## Typical workflow

1. **Create base:** Run the “Create a base pipeline” curl; copy the pipeline `id` from the response.
2. **Validate:** Run the validate curl to check `pipelines/edgedelta.yaml`.
3. **Update:** Set `<<PIPELINE_ID>>` to that id and run the save curl.
4. **Deploy:** Run the history curl, take the first `timestamp` as `<<VERSION_ID>>`, then run the deploy curl.

Or use the script from the repo root:

```bash
cd pipelines
export ORG_ID=your-org-id API_TOKEN=your-token
./edgedelta-api-curl.sh create-base   # then set PIPELINE_ID from response
./edgedelta-api-curl.sh full         # validate, save, deploy
```
