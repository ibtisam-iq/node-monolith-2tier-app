# Local Setup Troubleshooting

While building and running this application locally, I ran into two MySQL-related errors. I have documented them here — along with the exact fixes I applied — so anyone reviewing this project understands what issues came up during local development and how they were resolved. Since I have already fixed both of these in the codebase, you should not encounter them when running the project as-is.

---

## Issue 1 — `ER_NOT_SUPPORTED_AUTH_MODE`

### What I saw

```
Database connection failed: Error: ER_NOT_SUPPORTED_AUTH_MODE: Client does not support
authentication protocol requested by server; consider upgrading MySQL client
```

### What caused it

The original `server/server.js` was using the legacy `mysql` npm package at version `2.3.3`. MySQL 8+ changed its default authentication plugin from `mysql_native_password` to `caching_sha2_password`. The old `mysql` package does not support this newer protocol, so the connection handshake failed immediately.

### What I did to fix it

I replaced the legacy `mysql` package with `mysql2`, which fully supports MySQL 8+ authentication.

**In `server/server.js`, I changed:**

```diff
- const mysql = require('mysql');
+ const mysql = require('mysql2');
```

`mysql2` is a drop-in replacement — no other code changes were needed. The `.createConnection()`, `.connect()`, and `.query()` calls all stayed the same.

**In `server/package.json`, I updated the dependency:**

```diff
- "mysql": "2.3.3"
+ "mysql2": "3.11.3"
```

Then I ran:

```bash
cd server
npm install
```

---

## Issue 2 — `ER_ACCESS_DENIED_ERROR` (Empty Username)

### What I saw

```
Database connection failed: Error: Access denied for user ''@'localhost' (using password: NO)
```

### What caused it

I had placed the `.env` file in the **project root**, but I was running the server from inside the `server/` subdirectory:

```bash
cd server
node server.js
```

Because `dotenv` resolves `.env` relative to the current working directory, running from `server/` meant the `.env` in the root was never found. All environment variables (`MYSQL_USER`, `MYSQL_PASSWORD`, etc.) resolved to `undefined`, which is why MySQL received an empty username `''`.

### What I did to fix it

I started running the server from the **project root** instead, pointing to the server file by its relative path:

```bash
# From the project root (where .env lives):
cd ~/node-monolith-2tier-app
node server/server.js
```

This way, `require('dotenv').config()` finds the `.env` in the root and all credentials are loaded correctly before the database connection is attempted.

### The `.env` file I used (in project root)

```env
DB_HOST=localhost
MYSQL_USER=your_username
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=test_db
PORT=5000
```

> **Note:** `.env` is listed in `.gitignore` and is not committed to the repo. You will need to create it manually on your machine.

---

## Summary

| Issue | Error Code | Root Cause | Fix Applied |
|---|---|---|---|
| Legacy `mysql` package | `ER_NOT_SUPPORTED_AUTH_MODE` | `mysql@2.3.3` incompatible with MySQL 8 auth | Replaced with `mysql2@3.11.3` |
| `.env` not found | `ER_ACCESS_DENIED` (user `''`) | Running server from `server/` instead of root | Run `node server/server.js` from project root |

---

## Final Working Setup

- **Node.js**: v18+
- **MySQL**: 8.x
- **mysql2**: `3.11.3`
- **Start command**: `node server/server.js` (run from project root)
