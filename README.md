# enterprise-demo-app

Node.js + PostgreSQL app on AKS with full VNet isolation and Azure Monitor Private Link Scope (AMPLS). All telemetry flows through private endpoints — no public access to LAW or App Insights.

## Architecture

```
VNet (10.0.0.0/8)
├── aks-subnet (10.0.0.0/16)
│   └── AKS Cluster (private API server)
│       └── enterprise-api pod → PostgreSQL (private)
├── db-subnet (10.1.0.0/24)
│   └── PostgreSQL Flexible Server (VNet-delegated)
└── ampls-subnet (10.2.0.0/24)
    └── Private Endpoint → AMPLS
        ├── App Insights (private ingestion + query)
        └── Log Analytics (private ingestion + query)
```

## Deploy

```bash
az login && azd auth login
azd init
azd up
```

## What Gets Deployed

| Resource | Access | Purpose |
|---|---|---|
| AKS Cluster | Private API server | Runs the app |
| PostgreSQL 16 | VNet-delegated, no public access | Backend database |
| App Insights | Private via AMPLS | Application telemetry |
| Log Analytics | Private via AMPLS | Platform logs + Activity Logs |
| AMPLS | Private endpoint in VNet | Ties AI + LAW to the VNet |
| ACR | Public (for image pulls) | Container registry |
| Alert Rule | On App Insights | Fires on 5xx errors (auto-mitigate) |

## For SRE Agent Demo

This app is the target workload for the `cg-poc-enterprise` recipe. After deploying:

```bash
cd ~/sre-agent-fresh/sreagent-templates

./bin/new-agent.sh --recipe cg-poc-enterprise --non-interactive \
  --set agentName=cg-poc-enterprise \
  --set resourceGroup=rg-cg-poc \
  --set location=eastus2 \
  --set targetRGs=rg-enterprise-demo \
  --set dtTenant=<dynatrace-env-id> \
  --set dtToken=<token> \
  --set snowInstance=https://<instance>.service-now.com \
  --set lawId=<LAW resource ID from azd output> \
  --set githubRepo=dm-chelupati/enterprise-demo-app \
  -o cg-poc-enterprise/

./bin/deploy.sh cg-poc-enterprise/
```

Then configure VNet integration, GitHub Enterprise, Jira, and granular permissions in the portal.
