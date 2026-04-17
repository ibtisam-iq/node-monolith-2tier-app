# =============================================================
# Stage 1 — Client Build
# Compile React frontend with Webpack into client/public/
# =============================================================
FROM node:18-alpine AS client-build

WORKDIR /app/client

# Copy package.json first to leverage Docker layer caching
# Layer invalidated only when dependencies change — not on every source change
COPY client/package.json ./
RUN npm install

# Copy source after installing dependencies
COPY client/ ./

# Webpack compiles src/index.js → client/public/bundle.js
RUN npm run build


# =============================================================
# Stage 2 — Server Dependencies
# Install production-only Node.js dependencies for the server
# =============================================================
FROM node:18-alpine AS server-deps

WORKDIR /app/server

COPY server/package.json ./

# --omit=dev excludes devDependencies — only runtime packages (express, mysql2, cors, dotenv)
RUN npm install --omit=dev


# =============================================================
# Stage 3 — Runtime
# Assemble final lean image from outputs of Stage 1 and Stage 2
# No Webpack, no Babel, no devDependencies in production
# =============================================================
FROM node:18-alpine AS runtime

# OCI standard image labels
LABEL org.opencontainers.image.title="NodeApp" \
      org.opencontainers.image.description="Node.js + React 2-Tier User Management Application" \
      org.opencontainers.image.authors="Muhammad Ibtisam Iqbal <github.com/ibtisam-iq>" \
      org.opencontainers.image.source="https://github.com/ibtisam-iq/node-monolith-2tier-app" \
      org.opencontainers.image.licenses="MIT"

# Security hardening: run as non-root user
# Running as root inside a container is a critical vulnerability flagged by Trivy
# and rejected by Kubernetes PodSecurityAdmission (restricted policy)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy production server node_modules from Stage 2 (no re-download, no devDeps)
COPY --from=server-deps /app/server/node_modules ./server/node_modules

# Copy server source code from host
COPY server/ ./server/

# Copy ONLY the compiled frontend output from Stage 1
# client/src/, webpack.config.js, .babelrc, client/node_modules/ are intentionally excluded
# — they have no purpose at runtime
COPY --from=client-build /app/client/public ./client/public

# Set ownership before switching user
# chown MUST run as root (before USER) — appuser cannot change file ownership
# Recursive is correct here: we have a directory tree under /app
RUN chown -R appuser:appgroup /app
USER appuser

EXPOSE 5000

# Health check using GET / — the Express wildcard route serves index.html (HTTP 200)
# when the server is fully running. No dedicated /health endpoint exists in server.js.
# start-period=40s: Node.js boots fast but MySQL connection initialization adds time
# wget is used (not curl) — curl is NOT in Alpine base image by default
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:5000/ || exit 1

# Exec form: node runs as PID 1 — receives SIGTERM directly for graceful shutdown
# Shell form would make /bin/sh PID 1 which does NOT forward signals to Node.js
ENTRYPOINT ["node", "server/server.js"]
