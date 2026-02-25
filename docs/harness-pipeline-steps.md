# Harness pipeline steps (copy/paste friendly)

This is the minimum working setup: **4 Custom stages**, one Shell Script step per stage.

---

## Stage 1: PE token request (bootstrap + rerun safe)
**Shell Script step id:** `pe_create`

### Inputs (env vars in the step)
Use pipeline variables/secrets:

- `PE_HOST_URL` = `<+pipeline.variables.peHostUrl>`
- `PE_CLIENT_ID` = `<+secrets.getValue("pe_client_id")>`
- `PE_CLIENT_SECRET` = `<+secrets.getValue("pe_client_secret")>`
- `EMAIL_ID` = `<+pipeline.variables.emailId>`

Token request fields:
- `BUSINESS_UNIT` = `<+pipeline.variables.businessUnit>`
- `LOCATION` = `<+pipeline.variables.location>`
- `ENVIRONMENT` = `<+pipeline.variables.environment>`
- `INFRA_TYPE` = `<+pipeline.variables.infrastructureType>`
- `APPLICATION_NAME` = `<+pipeline.variables.applicationName>`
- `OWNER_ID` = `<+pipeline.variables.ownerID>`
- `ACCESS_CATEGORY` = `<+pipeline.variables.accessCategory>`
- `COMMENT` = `<+pipeline.variables.comment>`
- `START_DATE` = `<+pipeline.variables.startDate>`
- `END_DATE` = `<+pipeline.variables.endDate>`
- `AUTO_RENEW` = `<+pipeline.variables.autoRenew>`
- `ACCESS_DETAILS_JSON` = `<+pipeline.variables.accessDetailsJson>`

Rerun overrides (store in Harness secrets after bootstrap):
- `VAULT_ROLE_ID_OVERRIDE` = `<+secrets.getValue("vault_role_id")>`
- `VAULT_SECRET_ID_OVERRIDE` = `<+secrets.getValue("vault_secret_id")>`

### Run
```
bash scripts/01_pe_tokenapi_create.sh
```

### Output variables (configure in step)
- `ROLE_ID`
- `SECRET_ID`
- `VAULT_ADDR`
- `VAULT_NAMESPACE`
- `DT_ACCESS_SECRET_PATH`

---

## Stage 2: Vault fetch DT access token
**Step id:** `vault_fetch`

Env vars:
- `VAULT_ADDR` = `<+pipeline.stages.pe_create.spec.execution.steps.pe_create.output.outputVariables.VAULT_ADDR>`
- `VAULT_NAMESPACE` = `<+pipeline.stages.pe_create.spec.execution.steps.pe_create.output.outputVariables.VAULT_NAMESPACE>`
- `DT_ACCESS_SECRET_PATH` = `<+pipeline.stages.pe_create.spec.execution.steps.pe_create.output.outputVariables.DT_ACCESS_SECRET_PATH>`
- `ROLE_ID` = `<+pipeline.stages.pe_create.spec.execution.steps.pe_create.output.outputVariables.ROLE_ID>`
- `SECRET_ID` = `<+pipeline.stages.pe_create.spec.execution.steps.pe_create.output.outputVariables.SECRET_ID>`

Run:
```
bash scripts/02_vault_fetch_dt_access_token.sh
```

Outputs:
- `DT_ACCESS_TOKEN`

---

## Stage 3: Create Dynatrace k8s tokens
**Step id:** `dt_tokens`

Env vars:
- `DT_ENV_URL` = `<+pipeline.variables.dtEnvUrl>`
- `CLUSTER_NAME` = `<+pipeline.variables.clusterName>`
- `DT_ACCESS_TOKEN` = `<+pipeline.stages.vault_fetch.spec.execution.steps.vault_fetch.output.outputVariables.DT_ACCESS_TOKEN>`

Run:
```
bash scripts/03_dynatrace_create_k8s_tokens.sh
```

Outputs:
- `DT_OPERATOR_TOKEN`
- `DT_DATA_INGEST_TOKEN`

---

## Stage 4: Install operator + dynakube
**Step id:** `k8s_deploy`

Env vars:
- `DT_ENV_URL` = `<+pipeline.variables.dtEnvUrl>`
- `CLUSTER_NAME` = `<+pipeline.variables.clusterName>`
- `NETWORK_ZONE` = `<+pipeline.variables.networkZone>`
- `DT_NAMESPACE` = `<+pipeline.variables.dtNamespace>`
- `DYNATRACE_OPERATOR_VERSION` = `<+pipeline.variables.operatorVersion>`

- `DT_OPERATOR_TOKEN` = `<+pipeline.stages.dt_tokens.spec.execution.steps.dt_tokens.output.outputVariables.DT_OPERATOR_TOKEN>`
- `DT_DATA_INGEST_TOKEN` = `<+pipeline.stages.dt_tokens.spec.execution.steps.dt_tokens.output.outputVariables.DT_DATA_INGEST_TOKEN>`

Run:
```
bash scripts/04_k8s_install_operator_and_dynakube.sh
```
