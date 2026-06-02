#!/bin/bash
# Deploy the Zava storefront + API to AKS
# Uses az acr build (cloud build — no local Docker needed)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_DIR"

RG=$(azd env get-value RESOURCE_GROUP)
AKS=$(azd env get-value AKS_CLUSTER_NAME)
ACR=$(azd env get-value ACR_LOGIN_SERVER)
ACR_NAME=$(azd env get-value ACR_NAME)
PG_FQDN=$(azd env get-value PG_FQDN)
PG_NAME=$(azd env get-value PG_SERVER_NAME)
AI_CONN=$(azd env get-value AI_CONNECTION_STRING)

echo "Deploying Zava app to AKS"
echo "  RG=$RG  AKS=$AKS  ACR=$ACR  PG=$PG_FQDN"

# Build images in the cloud (no Docker required)
echo "Building API image (cloud build)..."
az acr build -r "$ACR_NAME" -t zava-api:latest src/zava-api/ --no-logs 2>/dev/null || \
  az acr build -r "$ACR_NAME" -t zava-api:latest src/zava-api/

echo "Building storefront image (cloud build)..."
az acr build -r "$ACR_NAME" -t zava-storefront:latest src/storefront/ --no-logs 2>/dev/null || \
  az acr build -r "$ACR_NAME" -t zava-storefront:latest src/storefront/

# Generate k8s manifests with actual values
echo "Generating k8s manifests..."

# Reset any previous sed replacements in tracked files
git checkout -- k8s/api-deployment.yaml k8s/storefront-deployment.yaml 2>/dev/null || true

# Apply ACR substitution — template uses ${ACR_NAME}.azurecr.io
sed -i '' "s|\${ACR_NAME}.azurecr.io|$ACR|g" k8s/api-deployment.yaml k8s/storefront-deployment.yaml 2>/dev/null || \
sed -i "s|\${ACR_NAME}.azurecr.io|$ACR|g" k8s/api-deployment.yaml k8s/storefront-deployment.yaml

# Generate configmap
cat > k8s/configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: zava-config
  namespace: zava
data:
  PG_HOST: "$PG_FQDN"
  PG_DATABASE: "postgres"
  PG_PORT: "5432"
  PG_USER: "appadmin"
  PG_PASSWORD: "DemoP@ss2026!"
  APPLICATIONINSIGHTS_CONNECTION_STRING: "$AI_CONN"
  API_URL: "http://zava-api:3001"
EOF

# Generate secret with actual App Insights connection string
cat > k8s/secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: zava-secrets
  namespace: zava
type: Opaque
stringData:
  APPLICATIONINSIGHTS_CONNECTION_STRING: "$AI_CONN"
EOF

# Generate service account with actual identity client ID
APP_CLIENT_ID=$(az identity list -g "$RG" --query "[?starts_with(name,'id-Zava-app')].clientId" -o tsv 2>/dev/null)
cat > k8s/service-account.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: zava-workload-identity
  namespace: zava
  annotations:
    azure.workload.identity/client-id: "$APP_CLIENT_ID"
EOF

# Generate storefront service as LoadBalancer for external access
cat > k8s/storefront-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: zava-storefront
  namespace: zava
spec:
  selector:
    app: zava-storefront
  ports:
    - port: 80
      targetPort: 3000
  type: LoadBalancer
EOF

# Deploy to AKS (private cluster — use command invoke)
echo "Deploying to AKS (private cluster)..."

# Grant deploying user AKS RBAC Cluster Admin (needed because enableAzureRBAC: true)
DEPLOYER_OID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
if [[ -n "$DEPLOYER_OID" ]]; then
  echo "  Granting AKS RBAC Cluster Admin to deploying user..."
  AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
  az role assignment create \
    --role "Azure Kubernetes Service RBAC Cluster Admin" \
    --assignee-object-id "$DEPLOYER_OID" \
    --assignee-principal-type User \
    --scope "$AKS_ID" \
    --output none 2>/dev/null || true
  echo "  Waiting 30s for RBAC propagation..."
  sleep 30
fi

# Create namespace
az aks command invoke -g "$RG" -n "$AKS" \
  --command "kubectl create namespace zava --dry-run=client -o yaml | kubectl apply -f -" \
  2>/dev/null || true

# Apply manifests one by one
for f in k8s/configmap.yaml k8s/service-account.yaml k8s/secret.yaml k8s/api-deployment.yaml k8s/api-service.yaml k8s/storefront-deployment.yaml k8s/storefront-service.yaml; do
  if [[ -f "$f" ]]; then
    echo "  Applying $f..."
    az aks command invoke -g "$RG" -n "$AKS" \
      --command "kubectl apply -f $(basename $f) -n zava" \
      --file "$f" 2>/dev/null || echo "  WARN: $f may need manual apply"
  fi
done

# Wait for pods
echo "  Waiting for pods..."
sleep 10
az aks command invoke -g "$RG" -n "$AKS" \
  --command "kubectl get pods -n zava -o wide" 2>/dev/null || true

# Get service IPs
echo ""
echo "Getting service endpoints..."
SVC_OUTPUT=$(az aks command invoke -g "$RG" -n "$AKS" \
  --command "kubectl get svc zava-storefront -n zava -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" 2>/dev/null || true)
STOREFRONT_IP=$(echo "$SVC_OUTPUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [[ -n "$STOREFRONT_IP" ]]; then
  azd env set STOREFRONT_IP "$STOREFRONT_IP" 2>/dev/null || true
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  App deployment complete"
echo "════════════════════════════════════════════════════════"
echo "  Resource Group:  $RG"
echo "  AKS Cluster:     $AKS"
echo "  ACR:             $ACR"
echo "  PostgreSQL:      $PG_FQDN"
if [[ -n "$STOREFRONT_IP" ]]; then
  echo "  Storefront URL:  http://$STOREFRONT_IP"
else
  echo "  Storefront URL:  (LoadBalancer IP pending — check in 1-2 min)"
  echo "    az aks command invoke -g $RG -n $AKS --command 'kubectl get svc -n zava'"
fi
echo "════════════════════════════════════════════════════════"
