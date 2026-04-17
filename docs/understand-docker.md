# How to Dockerize a Node.js 2-Tier Application

This document explains **every decision** behind the `Dockerfile` and `compose.yml` in this project — not just what each line does, but **why it was written that way**, what the alternatives were, why they were rejected, and what breaks if you get it wrong.

This is also a **reusable framework** for writing Docker files for any Node.js application that has a build step (Webpack, Vite, etc.) before the runtime server.

---

## Step 0 — Read the Project Before Writing a Single Line

The biggest mistake developers make is opening a blank `Dockerfile` and starting to type. The correct approach is to interrogate the project first. Every answer below was extracted from `server/package.json`, `client/package.json`, `client/webpack.config.js`, `server/server.js`, and `.env.example` in this repo **before** any Docker file was written.

| Question to Answer | Where to Look | Answer for This Project |
|---|---|---|
| What language/runtime? | Root structure — `package.json` files | **Node.js** |
| What Node version to use? | `server/package.json` → `engines` field (if present), or latest LTS | **Node 18 LTS** (Alpine) |
| Does the frontend need a build step? | `client/package.json` → `scripts.build` | **Yes** — `webpack --mode production` produces `bundle.js` |
| Where does the frontend build output go? | `client/webpack.config.js` → `output.path` | `client/public/` — Express serves this as static files |
| What is the server entry point? | `server/package.json` → `main` or `scripts.start` | `node server.js` |
| What port does the server listen on? | `server/server.js` → `process.env.PORT \|\| 5000` | **5000** |
| What database does the app use? | `server/server.js` → `require('mysql2')` | **MySQL** |
| How does the server connect to DB? | `server/server.js` → `mysql.createConnection({...})` | Via env vars: `DB_HOST`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` |
| Is there a health endpoint? | `server/server.js` — search for `/health` route | **No** — must use TCP check or custom endpoint |
| Are credentials hardcoded or env vars? | `server/server.js` → `process.env.*` | **All env vars** — nothing hardcoded |
| What Linux tools are available? | Base image choice (Alpine vs Debian) | **Alpine** — `wget` available, `curl` is NOT |

Only after answering all of these did the Docker files get written. This is the real skill — not syntax, but **reading the project before writing the containers**.

---

## Architecture Recap — What Makes This App Special for Docker

This is a **2-tier monolith** — one Node.js process does two jobs simultaneously:

```
Browser
  │
  ▼
Express Server (Port 5000)
  ├── Serves React frontend → client/public/index.html + bundle.js (static files)
  ├── GET  /api/users  → queries MySQL → returns JSON
  ├── POST /api/users  → inserts into MySQL → returns JSON
  ├── PUT  /api/users/:id → updates MySQL → returns JSON
  └── DELETE /api/users/:id → deletes from MySQL → returns JSON
         │
         ▼
       MySQL (Port 3306)
```

**The Docker implication:** Before `node server.js` can serve the frontend, the React app must be **compiled**. `client/src/index.js` (raw React + JSX) must be transformed by Webpack into `client/public/bundle.js` (browser-ready JavaScript). Without this build step, the server starts but `GET /` returns a page with no UI.

This is the key insight that drives the multi-stage Dockerfile design.

---

## The Dockerfile — Every Decision Explained

### Why Multi-Stage? Why 3 Stages?

A naive single-stage Dockerfile would:
1. Copy everything
2. Run `npm install` (both client and server)
3. Run `npm run build` (Webpack)
4. Start `node server.js`

The problem: The final image would contain **Webpack, Babel, all devDependencies, and all build tooling** — none of which are needed at runtime. This produces a bloated, insecure image.

The multi-stage approach splits responsibilities cleanly:

| Stage | Name | Base Image | Job | What It Produces |
|---|---|---|---|---|
| 1 | `client-build` | `node:18-alpine` | Install client deps + run Webpack | `client/public/bundle.js` |
| 2 | `server-deps` | `node:18-alpine` | Install **production-only** server deps | `server/node_modules/` (no devDeps) |
| 3 | `runtime` | `node:18-alpine` | Copy outputs from stages 1 & 2, run server | Final lean image |

The final image contains **zero Webpack, zero Babel, zero devDependencies**. Only Express, mysql2, cors, dotenv, and the compiled `bundle.js`.

| What's in the image | Without multi-stage | With multi-stage |
|---|---|---|
| Webpack + plugins | ✅ Yes | ❌ No |
| Babel + presets | ✅ Yes | ❌ No |
| React source (`src/`) | ✅ Yes | ❌ No |
| `bundle.js` | ✅ Yes | ✅ Yes |
| Server `node_modules/` | All (dev + prod) | Production only |
| Approximate image size | ~600MB+ | ~180MB |

---

### Stage 1 — Client Build

```dockerfile
FROM node:18-alpine AS client-build
WORKDIR /app/client
COPY client/package.json ./
RUN npm install
COPY client/ ./
RUN npm run build
```

**`node:18-alpine`** — Node 18 is the LTS version that covers both Webpack 5 and React 17 compatibility. Alpine keeps the build container small and fast. This stage is only used to produce `bundle.js` — its size does not affect the final image.

**`WORKDIR /app/client`** — All client files live under `/app/client/` inside this stage. The path structure mirrors the repo structure, making `COPY` instructions intuitive.

**Copy `package.json` first, then `npm install`, then copy source — layer caching:**

```
Layer 1: FROM node:18-alpine          ← cached forever
Layer 2: WORKDIR                      ← cached forever
Layer 3: COPY client/package.json .   ← invalidated only if package.json changes
Layer 4: RUN npm install              ← invalidated only if package.json changes (~1-2 min)
Layer 5: COPY client/ ./              ← invalidated on ANY client source change
Layer 6: RUN npm run build            ← invalidated on ANY client source change (~10-15s)
```

**Result:** When you change React component code (the common case), only Layers 5 and 6 re-run. All `node_modules` are served from cache. Build time drops from **2+ minutes to ~15 seconds**.

> **What if you did `COPY client/ ./` before `npm install`?** Every single React code change would invalidate Layer 3, re-running `npm install` (downloading all Webpack/Babel packages) on every build. Catastrophic for CI pipelines.

**`RUN npm run build`** — This executes `webpack --mode production` from `client/package.json`. Webpack reads `webpack.config.js`, processes `src/index.js` through Babel and CSS loaders, and writes the output to `client/public/bundle.js`. After this step, `client/public/` contains everything the browser needs to run the React app.

> **Note:** `client/public/index.html` and `client/public/style.css` are hand-written files committed to the repo (not generated by Webpack — see `understand-architecture.md` Section 4 for the full explanation). They are included in `COPY client/ ./` and are already present in `client/public/` alongside the Webpack output.

---

### Stage 2 — Server Dependencies

```dockerfile
FROM node:18-alpine AS server-deps
WORKDIR /app/server
COPY server/package.json ./
RUN npm install --omit=dev
```

**Why a separate stage for server dependencies?**

This stage exists to install **only production dependencies** for the server in isolation. The `--omit=dev` flag (equivalent to `--production` in older npm) skips devDependencies. For the server, `package.json` has no devDependencies — but the pattern is correct and future-proof.

**`--omit=dev`** — Explicitly excludes any packages listed under `devDependencies`. The server runtime only needs: `express`, `mysql2`, `cors`, `dotenv`, `body-parser`. It does not need test frameworks, linters, or type checkers.

**Why not install server deps in the runtime stage?** Installing in a separate stage keeps the cache clean and independent. If you later add a devDependency to `server/package.json`, it does not affect the runtime stage's node_modules layer.

---

### Stage 3 — Runtime

```dockerfile
FROM node:18-alpine AS runtime
```

Fresh Alpine start. No build tools. No Webpack. No Babel. This stage assembles the final image from the outputs of Stages 1 and 2.

---

```dockerfile
LABEL org.opencontainers.image.title="NodeApp" \
      org.opencontainers.image.description="Node.js + React 2-Tier User Management Application" \
      org.opencontainers.image.authors="Muhammad Ibtisam Iqbal <github.com/ibtisam-iq>" \
      org.opencontainers.image.source="https://github.com/ibtisam-iq/node-monolith-2tier-app" \
      org.opencontainers.image.licenses="MIT"
```

OCI (Open Container Initiative) standard metadata labels. Visible in `docker inspect`, Docker Hub, GitHub Container Registry (GHCR), and scanned by Trivy. No runtime impact — pure metadata. Required for professional and portfolio images.

---

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
```

**Why create a non-root user?**

By default, Docker containers run as `root` (UID 0). This is a **critical security vulnerability** for three reasons:

1. **Trivy flags it** as a HIGH or CRITICAL finding in security scans
2. **Kubernetes rejects it** under `PodSecurityAdmission` (restricted policy) — many production clusters enforce `runAsNonRoot: true`
3. **Container escape risk** — if an attacker breaks out of the container, they land as root on the host

`-S` = system account — no home directory, no login shell, no password. Minimal footprint.

> **Alpine vs Debian syntax:** Alpine uses `addgroup` / `adduser`. Debian/Ubuntu images use `groupadd` / `useradd`. This matters when switching base images.

---

```dockerfile
WORKDIR /app
```

Sets the working directory for the runtime container. `/app` is the conventional path for application code in runtime containers (less formal than the builder's `/usr/src/app` — acceptable for the final stage).

---

```dockerfile
COPY --from=server-deps /app/server/node_modules ./server/node_modules
COPY server/ ./server/
COPY --from=client-build /app/client/public ./client/public
```

**The assembly step — pulling outputs from both previous stages:**

```
From server-deps stage:  /app/server/node_modules  →  /app/server/node_modules
From repo (host):        server/                   →  /app/server/
From client-build stage: /app/client/public/       →  /app/client/public/
```

**Order matters for caching:**
- `node_modules` is copied first (large, rarely changes)
- Server source code is copied second (changes frequently — invalidates only layer below)
- Built frontend assets are copied last (changes when React code changes)

**Why copy `node_modules` from `server-deps` instead of running `npm install` again?**

Running `npm install` in the runtime stage would re-download packages from the internet every time the image is rebuilt. Copying from `server-deps` uses the already-installed packages directly — no network, no npm registry, deterministic.

**Why only `client/public/` and not the full `client/` directory?**

`client/src/`, `client/webpack.config.js`, `client/.babelrc`, `client/package.json`, and `client/node_modules/` are all **build-time artifacts**. They served their purpose in Stage 1. The runtime container has no use for React source code, Webpack configs, or Babel presets. Only the compiled output (`client/public/bundle.js`, `client/public/index.html`, `client/public/style.css`) needs to be present at runtime.

---

```dockerfile
RUN chown -R appuser:appgroup /app
USER appuser
```

**The order here is mandatory and cannot be changed:**

```
Step 1: chown — runs as root, sets ownership of all files to appuser
Step 2: USER  — switches to appuser; from here everything runs as appuser
```

If you put `USER appuser` **before** `chown`, the `chown` command runs as `appuser` who has no permission to change file ownership. It fails with `Permission denied`.

**`chown -R`** — Recursive here is correct because we have a directory tree (`/app/server/` and `/app/client/public/`). Unlike the Java project where only one JAR file needed ownership change, here the entire `/app` directory tree must be accessible to `appuser`.

---

```dockerfile
EXPOSE 5000
```

`EXPOSE` is **documentation**, not a firewall rule. It does not publish the port. It tells Docker and tooling (Compose, Kubernetes, `docker run -P`) that the container listens on port 5000.

Port 5000 comes from `process.env.PORT || 5000` in `server/server.js` and `PORT=5000` in `.env.example`.

---

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:5000/ || exit 1
```

**Why `--start-period=40s`?**

Node.js starts much faster than Java Spring Boot. A cold Node.js + Express server is typically ready in 5-10 seconds. However, the startup time includes:
- Node.js process start
- `require('dotenv').config()` — reads `.env`
- `mysql.createConnection()` — establishes DB connection
- `app.listen()` — binds to port 5000

With MySQL starting simultaneously, the DB connection may take 15-30 seconds. `40s` gives ample grace period without being unnecessarily long.

| Parameter | Value | Reason |
|---|---|---|
| `--interval=30s` | Check every 30 seconds | Frequent enough for monitoring |
| `--timeout=10s` | Fail if no response in 10s | Generous for a local HTTP ping |
| `--start-period=40s` | Grace period after start | Node.js + MySQL connection initialization |
| `--retries=3` | 3 consecutive failures = unhealthy | One bad check should not kill the container |

**Why `wget` and not `curl`?** Alpine Linux does not include `curl` in the base image. `wget` is available by default. Using `curl` would require `RUN apk add --no-cache curl` — adding a layer and a package just for a healthcheck is wasteful.

**Why `GET /` and not a dedicated `/health` route?**

`server/server.js` does not define a `/health` endpoint. The `*` wildcard route serves `index.html` for any unmatched GET request — including `GET /`. So `wget --spider http://localhost:5000/` returns HTTP 200 (serving `index.html`) whenever Express is running. This is a pragmatic healthcheck for a server with no dedicated health endpoint.

> **Production note:** Adding a dedicated `app.get('/health', (req, res) => res.json({ status: 'UP' }))` in `server.js` is the correct long-term approach. It decouples health checking from frontend serving and makes the healthcheck semantically accurate.

---

```dockerfile
ENTRYPOINT ["node", "server/server.js"]
```

**`ENTRYPOINT` vs `CMD`:**

| | `ENTRYPOINT` | `CMD` |
|---|---|---|
| Override requires | `--entrypoint` flag (explicit, uncommon) | Passing any argument to `docker run` (easy, accidental) |
| PID 1 in exec form | Yes — Node.js is PID 1 | Yes — Node.js is PID 1 |
| Shell form risk | Shell becomes PID 1 | Shell becomes PID 1 |
| Best for | Single-purpose containers | Containers with switchable default commands |

This container has one job: run the Node.js server. `ENTRYPOINT` enforces that.

**Exec form `["node", "server/server.js"]` vs shell form `node server/server.js`:**

Shell form runs as `/bin/sh -c "node server/server.js"` — the shell becomes PID 1, Node.js becomes PID 2. When Docker sends `SIGTERM` during `docker stop`, it goes to PID 1 (the shell). Alpine's `sh` does not forward signals to child processes. Node.js never receives `SIGTERM` and Docker waits the full 10-second timeout before sending `SIGKILL` — no graceful shutdown, in-flight requests are killed.

Exec form runs `node` directly as PID 1. `SIGTERM` goes directly to Node.js, which handles graceful shutdown.

**`server/server.js` path** — The WORKDIR is `/app`. The entry point is at `/app/server/server.js`. The relative path `server/server.js` is correct from `/app`.

---

## The compose.yml — Every Decision Explained

### `name: nodeapp`

```yaml
name: nodeapp
```

Sets the Compose project name explicitly. Without this, Docker Compose uses the **directory name** as the project prefix — which varies by machine (`node-monolith-2tier-app`, `app`, `nodeapp-main`, etc.). With `name: nodeapp`, all containers, networks, and volumes are always prefixed with `nodeapp-` on any machine.

---

### The `mysql` service

```yaml
mysql:
  image: mysql:8.4
```

**`mysql:8.4` vs `mysql:8`:**

`mysql:8` is a floating tag — it resolves to whatever MySQL 8.x is latest at pull time. In April 2026, MySQL 8.0 reached End of Life. `mysql:8` could resolve to 8.0 (EOL) on some machines. `mysql:8.4` pins to the current LTS release — explicit, reproducible, and future-safe.

---

```yaml
  env_file: .env
  environment:
    MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    MYSQL_DATABASE: ${MYSQL_DATABASE}
    MYSQL_USER: ${MYSQL_USER}
    MYSQL_PASSWORD: ${MYSQL_PASSWORD}
```

**Understanding `env_file` vs `environment`:**

`env_file: .env` loads **every** `KEY=VALUE` line from `.env` and injects all of them into the container's environment automatically. You do not need to re-list them under `environment:`.

The four variables listed under `environment:` are **redundant** — they are already injected by `env_file`. They are kept here **explicitly for documentation purposes only**:

1. **Clarity** — Shows exactly which four variables the official `mysql:8.4` image requires for database initialization
2. **Syntax demonstration** — Shows the `${VAR_NAME}` substitution syntax (reads from `.env` at runtime — no hardcoded values)
3. **Auditability** — Makes it immediately obvious that MySQL receives exactly these four variables and nothing unexpected

In a minimal production compose file you would remove the `environment:` block entirely and keep only `env_file: .env`.

**What MySQL does with these variables on first start:**

| Variable | MySQL action |
|---|---|
| `MYSQL_ROOT_PASSWORD` | Sets the root password |
| `MYSQL_DATABASE` | Creates this database automatically |
| `MYSQL_USER` | Creates this application user |
| `MYSQL_PASSWORD` | Sets the password for `MYSQL_USER` |

> **Important:** MySQL only reads `MYSQL_*` initialization variables on **first startup** when `/var/lib/mysql` is empty. Changing them after the volume is initialized has no effect until you run `docker compose down -v` to destroy the volume.

---

```yaml
  volumes:
    - mysql-data:/var/lib/mysql
    - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
```

**`mysql-data:/var/lib/mysql` — persistent named volume:**

MySQL stores all database files in `/var/lib/mysql` inside the container. Without a volume, **all data is destroyed every time the container is removed** (`docker compose down`). With a named volume, data persists across restarts, rebuilds, and even `docker compose down` — only `docker compose down -v` destroys it.

**`./database/init.sql:/docker-entrypoint-initdb.d/init.sql:ro` — automatic schema initialization:**

The official MySQL Docker image automatically executes any `.sql` files found in `/docker-entrypoint-initdb.d/` on **first startup** (when the data directory is empty). By mounting `database/init.sql` here, the `test_db` database and `users` table are created automatically — no manual `mysql` commands required.

`:ro` (read-only) — The container can read the file but cannot modify it. Correct for initialization scripts.

> **Why only on first startup?** MySQL checks if `/var/lib/mysql` is already initialized. If the named volume already contains data, `docker-entrypoint-initdb.d/` scripts are **skipped**. This prevents accidentally wiping your data on every restart.

---

```yaml
  healthcheck:
    test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-p${MYSQL_ROOT_PASSWORD}"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 30s
```

**The `-h localhost` decision — and the bug it fixes:**

A common mistake is writing `-h mysql` (using the Docker Compose service name) in the MySQL healthcheck. This is wrong. `mysql` is the Docker Compose service name — it resolves to the MySQL container's IP **from other containers on the same network**. But this healthcheck runs **inside the MySQL container itself**. Inside the container, `mysql` is not a valid hostname. The correct hostname for the local MySQL server inside the container is `localhost` or `127.0.0.1`.

With `-h mysql`, the healthcheck always fails with `Unknown MySQL server host 'mysql'`. Because `depends_on: condition: service_healthy` in the `app` service waits for the MySQL healthcheck to pass, **the app container would never start** with the broken hostname.

```
❌ Wrong: -h mysql    (service name — only valid from OTHER containers)
✅ Correct: -h localhost  (valid inside the MySQL container itself)
```

**`-uroot -p${MYSQL_ROOT_PASSWORD}`** — Authenticates as root to run `mysqladmin ping`. The `MYSQL_ROOT_PASSWORD` variable is substituted from `.env` at Compose startup.

---

### The `app` service

```yaml
app:
  build:
    context: .
    dockerfile: Dockerfile
  image: node-monolith-2tier-app
```

**`image: node-monolith-2tier-app`** — Gives the built image an explicit name. Without this, the image is named `nodeapp-app` (project name + service name) by default. With an explicit name, you can push it directly to a registry (`docker push node-monolith-2tier-app`) without re-tagging.

---

```yaml
  env_file: .env
  environment:
    DB_HOST: mysql
```

**This is the single most important override in the entire compose file.**

`env_file: .env` loads all server variables automatically — `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`, `PORT`, and everything else. No need to re-list any of them.

The **only** variable that needs an explicit `environment:` override is `DB_HOST`. Here is why:

The `.env` file contains:
```
DB_HOST=localhost
```

`localhost` is correct when running the app directly on bare metal — MySQL is on the same machine. But in Docker Compose, each service runs in a **separate, isolated container**. Inside the `app` container, `localhost` refers to the `app` container itself — not the `mysql` container. The `app` container has nothing listening on port 3306. The connection fails immediately.

The correct hostname in Docker Compose is the **service name** — `mysql`. Docker's internal DNS resolves `mysql` to the MySQL container's IP on the shared network.

```
Outside Docker:   app → localhost:3306   (MySQL on same machine)
Inside Compose:   app → mysql:3306       (MySQL container by service name)
```

This single `environment:` entry overrides the `localhost` value from `.env` with the correct `mysql` hostname — only for the Docker Compose environment. The `.env` file itself is left unchanged so it still works for bare-metal development.

**The rule:**
- `env_file` loads everything from `.env` automatically
- `environment:` is only needed when a value from `.env` is **wrong** for Docker and needs to be overridden
- Never re-list variables under `environment:` just because they came from `env_file` — that is redundant noise

---

```yaml
  depends_on:
    mysql:
      condition: service_healthy
```

**`condition: service_healthy` vs just `depends_on: mysql`:**

`depends_on: mysql` (no condition) only waits for the `mysql` **container to start**. A MySQL container becomes "started" in ~2 seconds, but MySQL itself takes 15-30 seconds to initialize. The Node.js server will try to connect immediately via `mysql.createConnection()`, fail, and call `process.exit(1)` — crashing the container.

`condition: service_healthy` waits for the `mysql` healthcheck (`mysqladmin ping`) to return success. That only happens when MySQL is **fully initialized and accepting connections** — exactly when the app needs it.

> **Important limitation:** `mysql.createConnection()` in `server.js` connects once at startup. If MySQL restarts after the app is running, the connection is not automatically re-established. A production-grade fix is to use `mysql.createPool()` with `waitForConnections: true` — it retries automatically. This is documented in `docs/understand-architecture.md` Section 5 as a known limitation.

---

```yaml
  healthcheck:
    test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5000/"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s
```

Matches the `HEALTHCHECK` in the Dockerfile. Node.js starts faster than Java, but the DB connection initialization adds time. `40s` is the correct grace period. See the Dockerfile section above for full parameter rationale.

---

```yaml
  ports:
    - "5000:5000"
```

Maps host port 5000 to container port 5000. Format: `"HOST_PORT:CONTAINER_PORT"`. After `docker compose up`, the app is accessible at `http://localhost:5000` on the host machine.

The MySQL service intentionally has **no `ports:` mapping**. Port 3306 is only accessible within the Docker network (between `app` and `mysql` containers). It is not exposed to the host machine — a correct security posture.

---

```yaml
volumes:
  mysql-data:
```

Declares the named volume at the top level of `compose.yml`. Named volumes are managed by Docker and persist beyond container lifecycle. Without this declaration, the `mysql-data:` reference in the `mysql` service would fail with a validation error.

---

## How `env_file` Works — The Complete Mental Model

```
.env file:
  MYSQL_ROOT_PASSWORD=secret
  MYSQL_DATABASE=test_db
  MYSQL_USER=appuser
  MYSQL_PASSWORD=apppass
  DB_HOST=localhost        ← correct for bare metal, WRONG for Docker
  PORT=5000

When env_file: .env is processed:
  → ALL variables injected into container environment automatically
  → No listing required

When environment: is also present:
  → Those entries OVERRIDE the matching values from env_file
  → Variables not in environment: still come from env_file unchanged
  → Variables in environment: that are NOT in env_file are added fresh
```

This is why the `app` service only needs one `environment:` entry — the `DB_HOST` override. Everything else loads correctly from `.env` as-is.

---

## How the Two Files Work Together — End to End

```
docker compose up --build
        │
        ├── Reads compose.yml
        │
        ├── Builds Dockerfile → image: node-monolith-2tier-app
        │       Stage 1 (node:18-alpine AS client-build):
        │         COPY client/package.json → npm install (cached after first run)
        │         COPY client/           → npm run build (Webpack)
        │         Output: client/public/bundle.js
        │
        │       Stage 2 (node:18-alpine AS server-deps):
        │         COPY server/package.json → npm install --omit=dev
        │         Output: server/node_modules/ (production only)
        │
        │       Stage 3 (node:18-alpine AS runtime):
        │         Non-root user created (appuser:appgroup)
        │         server/node_modules/ copied from Stage 2
        │         server/ source code copied from host
        │         client/public/ copied from Stage 1
        │         Node.js serves on port 5000
        │
        ├── Starts mysql (mysql:8.4)
        │       Reads MYSQL_* from .env → creates test_db + appuser on first start
        │       Executes database/init.sql → creates users table
        │       Healthcheck: mysqladmin ping -h localhost
        │       Status: starting → healthy (after ~20-30s)
        │
        ├── Waits for mysql healthcheck to pass (condition: service_healthy)
        │
        └── Starts app (node-monolith-2tier-app)
                Reads ALL variables from .env
                DB_HOST overridden to "mysql" (service name)
                Node.js connects to MySQL via service name "mysql"
                Express serves client/public/ as static files
                API routes handle CRUD on users table
                Healthcheck: wget http://localhost:5000/ → 200 after ~5-10s
                Accessible at http://localhost:5000
```

---

## Decision Log — What Was Decided and Why

This table documents every significant architectural and configuration decision made during Dockerization.

| Area | Decision Made | Alternative Considered | Why This Was Chosen |
|---|---|---|---|
| **Multi-stage build** | 3 stages: client-build, server-deps, runtime | Single stage (copy everything, build, run) | Single stage includes Webpack/Babel/devDeps in production — ~600MB vs ~180MB, more CVEs |
| **Node version** | `node:18-alpine` | `node:20-alpine`, `node:lts-alpine` | Node 18 LTS covers Webpack 5 + React 17 compatibility; Alpine minimizes image size |
| **Client build in separate stage** | Stage 1 dedicated to Webpack build | Build client inside runtime stage | Keeps build tools completely out of the runtime image |
| **`npm install --omit=dev` in server-deps** | Install production deps only in Stage 2 | `npm install` (all deps) in runtime stage | devDependencies not needed at runtime; smaller, more secure image |
| **Copy `client/public/` only (not full `client/`)** | Only compiled output in runtime image | Copy entire `client/` directory | `src/`, `webpack.config.js`, `node_modules/` have no runtime purpose |
| **`chown -R` on `/app`** | Recursive ownership change on full `/app` | Targeted `chown` on individual files | Multiple files/dirs across `server/` and `client/public/` — recursive is correct here |
| **Healthcheck endpoint: `GET /`** | Use `wget --spider http://localhost:5000/` | Dedicated `/health` route | No health endpoint exists in `server.js`; `*` wildcard serves `index.html` returning 200 |
| **`start_period: 40s`** | 40s grace period | 30s (too short), 60s (unnecessary for Node) | Node.js boots in seconds; 40s covers MySQL connection wait comfortably |
| **`DB_HOST: mysql` override** | Override only `DB_HOST` in `environment:` | Hardcode `DB_HOST=mysql` in `.env` | `.env` must stay `localhost` for bare-metal dev; override only in Compose |
| **`mysql:8.4` image tag** | Pin to `mysql:8.4` (LTS) | `mysql:8` (floating tag) | `mysql:8` could resolve to EOL 8.0; `8.4` is explicit and reproducible |
| **MySQL healthcheck `-h localhost`** | `-h localhost` inside container | `-h mysql` (service name) | Service name only resolves from OTHER containers; inside MySQL container use `localhost` |
| **`condition: service_healthy`** | Wait for MySQL healthcheck before starting app | `depends_on: mysql` (no condition) | Without condition, app starts before MySQL is ready and crashes on connection failure |
| **Named volume `mysql-data`** | Persist `/var/lib/mysql` in named volume | Anonymous volume or no volume | Named volumes persist beyond `docker compose down`; anonymous volumes are harder to manage |
| **`init.sql` mounted `:ro`** | Read-only mount of schema file | Read-write mount | Init scripts should never be modified by the container |
| **No MySQL port exposure** | MySQL port 3306 not in `ports:` | Expose 3306 to host | MySQL should only be accessible within the Docker network — not to the host |
| **`name: nodeapp`** | Explicit Compose project name | No name (uses directory name) | Consistent container/network/volume naming across all machines |
| **`image: node-monolith-2tier-app`** | Explicit image name on `app` service | Default `nodeapp-app` naming | Explicit name enables direct registry push without re-tagging |

---

## Common Mistakes Reference

| Mistake | What Breaks | Correct Approach |
|---|---|---|
| Single-stage Dockerfile | 600MB+ image with Webpack, Babel, all devDeps in production | Use multi-stage: client-build → server-deps → runtime |
| `COPY client/ .` before `npm install` in Stage 1 | npm re-installs all packages on every source change | Copy `package.json` first, `npm install`, then `COPY client/ ./` |
| Copying full `client/` to runtime stage | React source, Webpack config, node_modules all in production image | Copy only `client/public/` (compiled output) to runtime stage |
| `npm install` (not `--omit=dev`) in runtime | devDependencies bloat the production image | Use `npm install --omit=dev` in the deps stage |
| Not creating non-root user | Trivy CRITICAL finding, fails Kubernetes `PodSecurityAdmission` | `addgroup` + `adduser` before `USER` |
| `chown` after `USER appuser` | `Permission denied` — non-root cannot change file ownership | Always `chown` before switching `USER` |
| Shell form `CMD node server.js` | Node.js becomes PID 2, `SIGTERM` not forwarded, no graceful shutdown | Use exec form `ENTRYPOINT ["node", "server/server.js"]` |
| `depends_on: mysql` without `condition` | App starts before MySQL is ready, `createConnection()` fails, `process.exit(1)` | Use `condition: service_healthy` |
| `-h mysql` in MySQL healthcheck | Healthcheck always fails, `app` service never starts | Use `-h localhost` — service name is invalid inside the container |
| `DB_HOST=localhost` in Compose | `localhost` inside `app` container = `app` itself — MySQL unreachable | Override `DB_HOST: mysql` in `environment:` |
| Using `curl` in Alpine healthcheck | `curl` not in Alpine base image — command not found | Use `wget --spider` (available by default in Alpine) |
| Floating `mysql:8` tag | May resolve to EOL 8.0 depending on when image is pulled | Pin to `mysql:8.4` (current LTS) |
| No volume for `/var/lib/mysql` | All MySQL data lost on `docker compose down` | Mount `mysql-data:/var/lib/mysql` as a named volume |
| Exposing MySQL port to host | Database accessible from outside Docker network | Remove `ports:` from `mysql` service entirely |
| Re-listing `env_file` variables under `environment:` | Redundant noise — works but misleads about what is being overridden | Only list variables that need to **override** their `env_file` values |
