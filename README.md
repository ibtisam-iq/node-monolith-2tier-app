# Node Monolith 2-Tier Application

## Overview

This is a Node.js + React-based monolithic user management web application serving as the **source codebase** for two downstream DevOps projects:

- **[DevSecOps Pipelines](https://github.com/ibtisam-iq/devsecops-pipelines)** — CI/CD pipelines that build, scan, and package this application into a secure, deployable artifact using Jenkins, GitHub Actions, Docker, SonarQube, and Trivy.
- **[Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems)** — Deployment workflows that run this artifact across Docker Compose, AWS EC2, EKS (Kubernetes), Terraform, and GitOps-based delivery.

> I did not build this application from scratch. As a DevOps Engineer, my focus is on everything that happens **around the code** — building, securing, packaging, and operating it in production-like environments.

---

## Application Structure

```
node-monolith-2tier-app/
├── client/                         # React frontend (Webpack-bundled)
│   ├── src/                        # React components and Axios API calls
│   ├── public/                     # Static assets served by Express
│   ├── package.json                # React 17, Axios, Webpack, Babel
│   └── webpack.config.js
├── server/                         # Node.js + Express backend
│   ├── server.js                   # Single entry point — DB connection, all CRUD routes, static serving
│   ├── app.js                      # Unused alternate Express config (leftover)
│   ├── config/db.js                # MySQL connection (used by MVC files only)
│   ├── routes/                     # Route definitions (unused in active server.js flow)
│   ├── controllers/                # Controller logic (unused in active server.js flow)
│   ├── models/                     # Model layer (unused in active server.js flow)
│   └── package.json                # Express, MySQL2, dotenv, cors
├── database/
│   └── init.sql                    # Schema bootstrap
├── docs/                           # Architecture notes
├── assets/                         # Project images
├── .env.example                    # Environment variable template
└── compose.yml
```

Two-tier architecture: Presentation (React SPA) + Business Logic + Data Access — all handled by a **single Express process** (`server.js`) that embeds routes and SQL queries inline, with no separate model or controller layer in the active code path.

> **Note:** This is the 2-tier variant of the Node monolith. The [3-tier variant](https://github.com/ibtisam-iq/node-monolith-3tier-app) refactors this same application into a clean MVC structure — separating routes, controllers, models, and a connection pool into dedicated files. The architecture distinction is the whole point of having both repos.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | JavaScript (Node.js) |
| Frontend Framework | React 17 |
| Frontend Bundler | Webpack 5 + Babel |
| HTTP Client | Axios |
| Backend Framework | Express 4 |
| Database Driver | mysql2 |
| Database | MySQL |
| Environment | dotenv |
| Build Tool | npm |

---

## DevOps Implementation Journey

### Step 0 — Codebase Audit

The original codebase has all CRUD routes and raw SQL queries written inline inside `server.js` — no separation between routing, business logic, and data access. This is the defining characteristic of the 2-tier structure: one backend process handles everything end to end.

The `server/` directory also contains orphaned MVC files (`app.js`, `config/db.js`, `routes/`, `controllers/`, `models/`) that are not wired into `server.js`. These represent an incomplete refactor attempt. The active code path is `server.js` only.

> **Note:** I used **AI-assisted analysis (Perplexity Pro)** to audit the codebase structure, identify the dead code paths, and understand the architectural boundary between 2-tier and 3-tier. This architectural clarity is what makes the DevOps work — pipelines and deployment configs — reproducible and understandable.

**Dependency state of `server/package.json`:**

| Package | Version | Notes |
|---|---|---|
| `express` | `^4.21.2` | Latest 4.x with security patches |
| `mysql2` | `^3.11.3` | v3 connection pool with async support |
| `dotenv` | `^16.4.7` | Env var loading |
| `cors` | `^2.8.5` | Cross-origin support |
| `body-parser` | Absent | Correctly omitted — bundled in Express since v4.16 |

**Note on `client/package.json`:** The client still uses `react@17` and `axios@0.21.1`. These are not upgraded here — this repo intentionally preserves the original 2-tier codebase as-is for architectural comparison purposes.

---

### Step 1 — Environment Standardization

All database configuration is read from environment variables via `dotenv`. No credentials are hardcoded in `server.js`.

```bash
# Copy the template and fill in real values
cp .env.example .env
```

Key variables set in `.env`:

```env
MYSQL_ROOT_PASSWORD=your_root_password
MYSQL_DATABASE=test_db
MYSQL_USER=your_username
MYSQL_PASSWORD=your_password
DB_HOST=localhost
PORT=5000
```

> **Note:** For local bare-metal runs, `DB_HOST=localhost` is correct — MySQL is running directly on the same machine. When running via Docker Compose, change `DB_HOST` to match the database service name defined in `compose.yml` (e.g., `db`). Docker resolves that service name as a hostname on the internal container network, so `localhost` will not work there.

---

### Step 2 — Local Build & Validation

Before building any pipeline, I validated the full application lifecycle locally.

**Install and configure MySQL:**

```bash
sudo apt update && sudo apt install -y mysql-server
sudo systemctl start mysql
sudo systemctl enable mysql

# Secure and create DB user
sudo mysql -u root -p
```

```sql
CREATE DATABASE test_db;
CREATE USER 'your_username'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON test_db.* TO 'your_username'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

**Verify MySQL is running and the database exists:**

```bash
sudo systemctl status mysql
mysql -u your_username -p -e "SHOW DATABASES;" | grep test_db
```

**Install dependencies and start the backend:**

```bash
cd server && npm install
node server.js
```

The server printed:

```
Server running at http://localhost:5000
Database connected.
```

**Build the frontend:**

```bash
cd ../client && npm install && npm run build
```

> **Note:** The React app must be built (`npm run build`) before starting the server. Express serves the compiled static files from `client/public/`. Running the server without building first will result in a blank frontend.

**Verify end to end:**

```bash
# Confirm the backend API is up
curl http://localhost:5000/api/test

# Confirm the API returns users
curl http://localhost:5000/api/users

# Confirm the frontend is being served
curl http://localhost:5000
```

App runs at: `http://localhost:5000`

---

### Step 3 — DevSecOps Pipelines (CI/CD)

With the application validated locally, I built automated pipelines to transform this code into a secure, deployable artifact.

Pipelines include: npm build → SonarQube analysis → Trivy vulnerability scan → Docker image build → Nexus artifact management → Jenkins & GitHub Actions automation.

👉 **Pipelines repository:** [DevSecOps Pipelines](https://github.com/ibtisam-iq/devsecops-pipelines/tree/main/pipelines/node-monolith-2tier)

---

### Step 4 — Platform Engineering (Deployment & Operations)

Once the artifact was ready, I deployed it using multiple industry-standard approaches.

Deployment targets: Local bare-metal · Docker Compose · AWS EC2 · EKS (Kubernetes) · Terraform-provisioned infrastructure.

Also covered: monitoring, observability, scaling strategies, and system reliability.

👉 **Platform repository:** [Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/node-monolith-2tier)

---

## Key Idea

> Code = Input. Pipelines secure it. Infrastructure runs it.

| Repository | Role |
|---|---|
| **This repo** | Application source code — the single input to everything below |
| **[DevSecOps Pipelines](https://github.com/ibtisam-iq/devsecops-pipelines)** | CI/CD — builds, scans, and packages the code into a deployable artifact |
| **[Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems)** | Platform — deploys, operates, and scales the artifact across multiple targets |

This separation is intentional: one repo per concern. The source code stays clean, the pipeline logic stays auditable, and the deployment configs stay independently versioned.
