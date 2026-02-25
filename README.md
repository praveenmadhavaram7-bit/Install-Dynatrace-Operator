# Dynatrace Kubernetes onboarding via Harness (shell scripts)

This repo implements an end-to-end Harness pipeline flow using **shell scripts**:

1. **PE platform**: `GET /api/v1/login` → `POST /api/v1/tokenapi/create`
   - Creates a Dynatrace **access token** and stores it in Vault (per your org service).
   - Returns `vault_addr`, `vault_namespace`, `secret_path` and (only on first run) `role_id/secret_id`.
2. **Vault**: AppRole login → read Dynatrace access token from the returned Vault `secret_path`.
3. **Dynatrace**: create Kubernetes **Operator token** + **Data ingest token** using Dynatrace `/api/v2/apiTokens`.
4. **Kubernetes (delegate has access)**: install dynatrace-operator (Helm OCI) and apply DynaKube.

---

## Important behavior: PE returns role_id/secret_id only once
Your PE `/tokenapi/create` response returns `role_id/secret_id` **only on the first run**.

So Stage 1 script implements this logic:
- If `role_id/secret_id` returned → use them and output them.
- If not returned (re-run) → fallback to:
  - `VAULT_ROLE_ID_OVERRIDE`
  - `VAULT_SECRET_ID_OVERRIDE`

**Action after bootstrap run:** store the returned ROLE_ID/SECRET_ID into Harness secrets
(`vault_role_id`, `vault_secret_id`) and pass them to Stage 1 as overrides.

---

## Repo layout
```
scripts/
  common.sh
  01_pe_tokenapi_create.sh
  02_vault_fetch_dt_access_token.sh
  03_dynatrace_create_k8s_tokens.sh
  04_k8s_install_operator_and_dynakube.sh
payloads/
  tokenapi_body_example.json
templates/
  dynakube.yaml.tpl
docs/
  harness-pipeline-steps.md
```

---

## Delegate prerequisites
The delegate must have:
- bash, curl, jq
- kubectl, helm (stage 4)
- network access to PE host, Vault, Dynatrace SaaS

---

## Quick local test (dev)
```bash
export PE_HOST_URL="https://pe.example.com"
export PE_CLIENT_ID="..."
export PE_CLIENT_SECRET="..."
export EMAIL_ID="you@fisglobal.com"
export BUSINESS_UNIT="BankingAndPayments"
export LOCATION="US"
export ENVIRONMENT="Development"
export INFRA_TYPE="OCP4"
export APPLICATION_NAME="HarnessAutomation"
export OWNER_ID="HarnessAutomation"
export ACCESS_CATEGORY="dev"
export COMMENT="APIToken"
export START_DATE="2026-02-03T19:30:00.000Z"
export END_DATE="2027-02-02T00:00:00.000Z"
export AUTO_RENEW="true"
export ACCESS_DETAILS_JSON='["InstallerDownload","settings.read","settings.write","activeGateTokenManagement.create","entities.read","DataExport"]'
bash scripts/01_pe_tokenapi_create.sh

export VAULT_ADDR="$VAULT_ADDR"
export VAULT_NAMESPACE="$VAULT_NAMESPACE"
export ROLE_ID="$ROLE_ID"
export SECRET_ID="$SECRET_ID"
export DT_ACCESS_SECRET_PATH="$DT_ACCESS_SECRET_PATH"
bash scripts/02_vault_fetch_dt_access_token.sh

export DT_ENV_URL="https://<env>.live.dynatrace.com"
export CLUSTER_NAME="my-cluster"
export DT_ACCESS_TOKEN="$DT_ACCESS_TOKEN"
bash scripts/03_dynatrace_create_k8s_tokens.sh

export DT_NAMESPACE="dynatrace"
export DYNATRACE_OPERATOR_VERSION="1.7.3"
export NETWORK_ZONE="my-nz"
export DT_API_URL="${DT_ENV_URL}/api"
export DT_OPERATOR_TOKEN="$DT_OPERATOR_TOKEN"
export DT_DATA_INGEST_TOKEN="$DT_DATA_INGEST_TOKEN"
bash scripts/04_k8s_install_operator_and_dynakube.sh
```
