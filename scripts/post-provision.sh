#!/bin/bash
# Post-provision: seed database, configure diagnostics
set -euo pipefail

RG=$(azd env get-value RESOURCE_GROUP)
PG=$(azd env get-value PG_SERVER_NAME)
AKS=$(azd env get-value AKS_CLUSTER_NAME)
LAW_ID=$(azd env get-value LAW_ID)
AI_CONN=$(azd env get-value AI_CONNECTION_STRING)

echo "Post-provision for enterprise-demo-app"
echo "  RG: $RG"
echo "  PG: $PG"
echo "  AKS: $AKS"

# Create federated credential for app workload identity → PG Entra auth
OIDC_ISSUER=$(azd env get-value AKS_OIDC_ISSUER 2>/dev/null || echo "")
APP_ID_NAME=$(az identity list -g "$RG" --query "[?starts_with(name,'id-Zava-app')].name" -o tsv 2>/dev/null)
if [[ -n "$OIDC_ISSUER" && -n "$APP_ID_NAME" ]]; then
  echo "Creating federated credential for workload identity..."
  for NS in zava default; do
    az identity federated-credential create \
      --name "zava-fed-$NS" \
      --identity-name "$APP_ID_NAME" \
      -g "$RG" \
      --issuer "$OIDC_ISSUER" \
      --subject "system:serviceaccount:${NS}:zava-workload-identity" \
      --audiences "api://AzureADTokenExchange" 2>/dev/null || echo "  (federated credential for $NS may already exist)"
  done
fi

# Attach ACR to AKS
ACR_NAME=$(azd env get-value ACR_NAME 2>/dev/null || echo "")
if [[ -n "$ACR_NAME" ]]; then
  echo "Attaching ACR to AKS..."
  az aks update -g "$RG" -n "$AKS" --attach-acr "$ACR_NAME" --output none 2>/dev/null || echo "  (ACR may already be attached)"
fi

# Seed database tables
echo "Seeding database..."
az postgres flexible-server execute \
  --name "$PG" -g "$RG" -d enterprise_db \
  --querytext "
    CREATE TABLE IF NOT EXISTS products (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      category VARCHAR(50),
      price DECIMAL(10,2),
      stock INT DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      product_id INT REFERENCES products(id),
      quantity INT DEFAULT 1,
      created_at TIMESTAMP DEFAULT NOW()
    );
    INSERT INTO products (name, category, price, stock) VALUES
      ('Widget A', 'hardware', 29.99, 100),
      ('Widget B', 'hardware', 49.99, 50),
      ('Service Plan', 'subscription', 9.99, 999),
      ('Enterprise License', 'software', 299.99, 25)
    ON CONFLICT DO NOTHING;
  " 2>/dev/null || echo "DB seed may need manual run (private endpoint)"

# Activity Log diagnostic settings
SUB=$(az account show --query id -o tsv)
EXISTING=$(az monitor diagnostic-settings subscription list \
  --query "[?name=='activity-to-law-enterprise'].name" -o tsv 2>/dev/null || echo "")
if [[ -z "$EXISTING" ]]; then
  az monitor diagnostic-settings subscription create \
    --name "activity-to-law-enterprise" \
    --workspace "$LAW_ID" \
    --logs '[{"category":"Administrative","enabled":true},{"category":"Security","enabled":true}]' \
    --output none 2>/dev/null || echo "Diagnostic settings may need elevated permissions"
  echo "Activity Log diagnostic settings created"
fi

echo "Post-provision complete"

# ── GitHub BYO App: store PEM in Key Vault ──
KV_NAME=$(azd env get-value KV_NAME 2>/dev/null || echo "")
PEM_FILE="${GITHUB_APP_PEM_FILE:-}"

if [[ -n "$KV_NAME" && -n "$PEM_FILE" ]]; then
  if [[ -f "$PEM_FILE" ]]; then
    echo "Storing GitHub App private key in Key Vault: $KV_NAME"
    # Grant ourselves Secrets Officer (may already exist)
    MY_OID=$(az ad signed-in-user show --query id -o tsv)
    SUB=$(az account show --query id -o tsv)
    az role assignment create \
      --role "Key Vault Secrets Officer" \
      --assignee-object-id "$MY_OID" \
      --assignee-principal-type User \
      --scope "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
      --output none 2>/dev/null || true
    echo "  Waiting 30s for RBAC propagation..."
    sleep 30
    az keyvault secret set \
      --vault-name "$KV_NAME" \
      --name sre-agent-github-app-key \
      --file "$PEM_FILE" \
      --output none
    SECRET_URI=$(az keyvault secret show \
      --vault-name "$KV_NAME" \
      --name sre-agent-github-app-key \
      --query id -o tsv)
    echo "  PEM stored. Secret URI: $SECRET_URI"
    azd env set KV_SECRET_URI "$SECRET_URI"
  else
    echo "WARNING: GITHUB_APP_PEM_FILE=$PEM_FILE not found — skipping KV upload"
    echo "  Upload manually: az keyvault secret set --vault-name $KV_NAME --name sre-agent-github-app-key --file /path/to/key.pem"
  fi
elif [[ -n "$KV_NAME" && -z "$PEM_FILE" ]]; then
  echo "Key Vault $KV_NAME created. To store your GitHub App PEM:"
  echo "  export GITHUB_APP_PEM_FILE=~/Downloads/your-app.private-key.pem"
  echo "  az keyvault secret set --vault-name $KV_NAME --name sre-agent-github-app-key --file \$GITHUB_APP_PEM_FILE"
fi
