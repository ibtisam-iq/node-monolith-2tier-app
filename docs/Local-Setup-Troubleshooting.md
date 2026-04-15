# Local Setup Troubleshooting

This document covers real issues encountered while building and running this application locally, along with their root causes and exact fixes applied. If you are setting up this project on your local machine and hit these errors, this guide will save you time.

---

## Problem 1 — `ER_NOT_SUPPORTED_AUTH_MODE`

### Error

```
Database connection failed: Error: ER_NOT_SUPPORTED_AUTH_MODE: Client does not support
authentication protocol requested by server; consider upgrading MySQL client
```

### Root Cause

The original `server/server.js` used the legacy `mysql` npm package (version `2.3.3`). MySQL 8+ changed its default authentication plugin from `mysql_native_password` to `caching_sha2_password`. The old `mysql` package does not support this newer protocol, causing the handshake to fail at connection time.

### Fix Applied

**1. Replaced the `mysql` package with `mysql2` in `server/server.js`:**

```diff
- const mysql = require('mysql');
+ const mysql = require('mysql2');
```

`mysql2` is a drop-in replacement — the rest of the code (`.createConnection()`, `.connect()`, `.query()`) required no changes.

**2. Updated the version in `server/package.json`:**

```diff
- "mysql": "2.3.3"
+ "mysql2": "3.11.3"
```

Then reinstalled dependencies:

```bash
cd server
npm install
```

---

## Problem 2 — `ER_ACCESS_DENIED_ERROR` (Empty Username)

### Error

```
Database connection failed: Error: Access denied for user ''@'localhost' (using password: NO)
```

### Root Cause

The `.env` file containing the database credentials (`MYSQL_USER`, `MYSQL_PASSWORD`, etc.) was placed in the **project root directory**, but the server was being started from inside the `server/` subdirectory:

```bash
# This was being run:
cd server
node server.js          # ← dotenv looks for .env relative to CWD = server/
                        #   but .env is in the root, so it is not found
                        #   → all env vars resolve to undefined → user = ''
```

Since `dotenv` loads `.env` relative to the current working directory, running from `server/` when `.env` sits in the root means the credentials are never loaded.

### Fix Applied

Run the server from the **project root** instead, pointing to the server file by path:

```bash
# Run from project root (where .env lives):
cd ~/node-monolith-2tier-app
node server/server.js
```

This ensures `require('dotenv').config()` finds the `.env` file in the root and all environment variables (`DB_HOST`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`, `PORT`) are loaded correctly before the database connection is attempted.

### Expected `.env` File (in project root)

```env
DB_HOST=localhost
MYSQL_USER=your_username
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=test_db
PORT=5000
```

> **Note:** The `.env` file is listed in `.gitignore` and is never committed. You must create it manually on every new machine.

---

## Quick Reference

| Problem | Symptom | Fix |
|---|---|---|
| Legacy `mysql` package | `ER_NOT_SUPPORTED_AUTH_MODE` | Replace `mysql` with `mysql2@3.11.3` |
| `.env` in wrong directory | `ER_ACCESS_DENIED` with empty username `''` | Run `node server/server.js` from project root |

---

## Verified Working Setup

- **Node.js**: v18+
- **MySQL**: 8.x
- **mysql2**: `3.11.3`
- **Command to start server**: `node server/server.js` (from project root)
- **Database**: `test_db` with a `users` table (see `README.md` for schema)
