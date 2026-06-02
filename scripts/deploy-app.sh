#!/bin/bash
# Deploy the Zava storefront + API to AKS
# Requires: Docker running, az login done, azd env values set
set -eo pipefail

cd ~/enterprise-demo-app

RG=$(azd env get-value RESOURCE_GROUP)
AKS=$(azd env get-value AKS_CLUSTER_NAME)
ACR=$(azd env get-value ACR_LOGIN_SERVER)
ACR_NAME=$(azd env get-value ACR_NAME)
PG_FQDN=$(azd env get-value PG_FQDN)
PG_NAME=$(azd env get-value PG_SERVER_NAME)
AI_CONN=$(azd env get-value AI_CONNECTION_STRING)

echo "RG=$RG  AKS=$AKS  ACR=$ACR  PG=$PG_FQDN"

# Login to ACR
az acr login -n $ACR_NAME

# Build and push images
echo "Building API image..."
docker build -t $ACR/zava-api:latest src/zava-api/
docker push $ACR/zava-api:latest

echo "Building storefront image..."
docker build -t $ACR/zava-storefront:latest src/storefront/
docker push $ACR/zava-storefront:latest

# Update K8s manifests with actual values
sed -i '' "s|__ACR__|$ACR|g" k8s/api-deployment.yaml k8s/storefront-deployment.yaml 2>/dev/null || \
sed -i "s|__ACR__|$ACR|g" k8s/api-deployment.yaml k8s/storefront-deployment.yaml

# Update configmap with PG connection + App Insights
cat > k8s/configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: zava-config
  namespace: default
data:
  PG_HOST: "$PG_FQDN"
  PG_DATABASE: "postgres"
  PG_PORT: "5432"
  APPLICATIONINSIGHTS_CONNECTION_STRING: "$AI_CONN"
  API_URL: "http://zava-api:3001"
EOF

# Deploy to AKS (private cluster — use command invoke)
echo "Deploying to AKS..."
for f in k8s/configmap.yaml k8s/service-account.yaml k8s/api-deployment.yaml k8s/api-service.yaml k8s/storefront-deployment.yaml k8s/storefront-service.yaml k8s/ingress.yaml; do
  echo "  Applying $f..."
  az aks command invoke -g $RG -n $AKS \
    --command "kubectl apply -f -" \
    --file "$f" --no-wait 2>/dev/null || echo "  Failed: $f"
done

echo ""
echo "Deployed. Get the ingress IP with:"
echo "  az aks command invoke -g $RG -n $AKS --command 'kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath={.status.loadBalancer.ingress[0].ip}'"
