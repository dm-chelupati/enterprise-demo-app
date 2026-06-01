const appInsights = require("applicationinsights");
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights.setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING)
    .setAutoCollectRequests(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .start();
}

const express = require("express");
const { Pool } = require("pg");

const app = express();
app.use(express.json());

const pool = new Pool({
  host: process.env.PG_HOST,
  port: 5432,
  database: process.env.PG_DATABASE || "enterprise_db",
  user: process.env.PG_USER,
  password: process.env.PG_PASSWORD,
  ssl: { rejectUnauthorized: false },
});

// Health check
app.get("/api/health", async (req, res) => {
  try {
    const result = await pool.query("SELECT 1 AS ok");
    res.json({ status: "healthy", db_connected: true, timestamp: new Date().toISOString() });
  } catch (err) {
    res.status(503).json({ status: "unhealthy", db_connected: false, error: err.message });
  }
});

// Orders endpoint
app.get("/api/orders", async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM orders ORDER BY created_at DESC LIMIT 20");
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: "Database query failed", detail: err.message });
  }
});

// Products endpoint
app.get("/api/products", async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM products ORDER BY name LIMIT 50");
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: "Database query failed", detail: err.message });
  }
});

// Create order
app.post("/api/orders", async (req, res) => {
  try {
    const { product_id, quantity } = req.body;
    const result = await pool.query(
      "INSERT INTO orders (product_id, quantity, created_at) VALUES ($1, $2, NOW()) RETURNING *",
      [product_id, quantity || 1]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: "Failed to create order", detail: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Enterprise Demo API listening on port ${PORT}`);
});
