# Codebase Audit

Before doing any DevOps work, I audited the codebase to understand the active code path, identify dead code, and establish the architectural boundary between the 2-tier and 3-tier variants.

> I used **AI-assisted analysis (Perplexity Pro)** to audit the codebase structure, identify the dead code paths, and understand the architectural boundary between 2-tier and 3-tier. This architectural clarity is what makes the DevOps work — pipelines and deployment configs — reproducible and understandable.

---

## Active Code Path

The original codebase has all CRUD routes and raw SQL queries written inline inside `server.js` — no separation between routing, business logic, and data access. This is the defining characteristic of the 2-tier structure: one backend process handles everything end to end.

The `server/` directory also contains orphaned MVC files (`app.js`, `config/db.js`, `routes/`, `controllers/`, `models/`) that are not wired into `server.js`. These represent an incomplete refactor attempt. The active code path is `server.js` only.

---

## Dependency Analysis

### `server/package.json`

| Package | Version | Notes |
|---|---|---|
| `express` | `^4.21.2` | Latest 4.x with security patches |
| `mysql2` | `^3.11.3` | v3 connection pool with async support |
| `dotenv` | `^16.4.7` | Env var loading |
| `cors` | `^2.8.5` | Cross-origin support |
| `body-parser` | Absent | Correctly omitted — bundled in Express since v4.16 |

### `client/package.json`

The client still uses `react@17` and `axios@0.21.1`. These are not upgraded here — this repo intentionally preserves the original 2-tier codebase as-is for architectural comparison purposes.

> **Note:** This is the 2-tier variant of the Node monolith. The [3-tier variant](https://github.com/ibtisam-iq/node-monolith-3tier-app) refactors this same application into a clean MVC structure — separating routes, controllers, models, and a connection pool into dedicated files. The architecture distinction is the whole point of having both repos.
