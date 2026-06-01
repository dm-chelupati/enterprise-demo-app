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
