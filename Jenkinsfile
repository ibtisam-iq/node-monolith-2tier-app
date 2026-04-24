// ============================================================
// DevSecOps CI Pipeline — Node.js 2-Tier App
// Tool: Jenkins Declarative Pipeline
// Stack: Node.js 22 LTS · React 17 · Webpack 5 · Express 4 · MySQL 8.4
//        SonarQube · Trivy · Nexus · Docker Hub · GHCR
// Credentials: sonarqube-token · github-creds · docker-creds
//              nexus-creds · ghcr-creds
// SonarQube server: sonar-server  |  Scanner: sonar-scanner
//
// ── REQUIRED JENKINS PLUGINS ──────────────────────────────────────────────────
//   - SonarQube Scanner Plugin    → provides withSonarQubeEnv()
//   - AnsiColor Plugin            → provides ansiColor() option
//   - Coverage Plugin             → provides recordCoverage() DSL
//                                   (replaces deprecated Cobertura Plugin)
//   - JUnit Plugin                → provides junit() DSL for Jest XML reports
//
// NOTE: No NodeJS Plugin needed — Node.js 22 is installed system-wide on
//       the Jenkins OS and available on OS PATH.
//       Verified: node -v → v22.22.2 on jenkins-server.
//       Same pattern as Python 3.12 in python-monolith Jenkinsfile.
//
// ──────────────────────────────────────────────────────────────────────────────
//
// ── NODE.JS TOOLCHAIN NOTE ────────────────────────────────────────────────────
// Node.js 22, npm, trivy, and docker are installed system-wide on the
// Jenkins OS and are available on OS PATH.
//   node -v  → v22.22.2  (verified on jenkins-server)
//   npm -v   → resolves automatically with node
// sonar-scanner is NOT installed system-wide — it is registered in
// Manage Jenkins → Tools → SonarQube Scanner as 'sonar-scanner'.
// SCANNER_HOME = tool 'sonar-scanner' in environment{} resolves its
// install path at runtime; $SCANNER_HOME/bin/sonar-scanner invokes it.
// ──────────────────────────────────────────────────────────────────────────────
//
// ── APP STRUCTURE ─────────────────────────────────────────────────────────────
// Two independent package.json files — NO workspace root package.json:
//   client/package.json  → React 17 + Webpack 5 (devDeps needed at build time)
//   server/package.json  → Express 4 + mysql2 + cors + dotenv (prod only)
// Both are installed independently via npm ci in Stage 4.
// Client is compiled (Webpack → client/public/) before Docker build.
// ──────────────────────────────────────────────────────────────────────────────
//
// ── VERSIONING STRATEGY ───────────────────────────────────────────────────────
// Image tag: <version>-<short-git-sha>-<build-number>
// e.g.  1.0.0-ab3f12c-42
//
// Version is read from server/package.json at runtime:
//   node -p "require('./server/package.json').version"
// This is the Node.js equivalent of:
//   Java:   mvn help:evaluate -Dexpression=project.version
//   Python: cat VERSION
// server/package.json is the canonical version source — the server IS
// the deployable unit. Client version follows the server version.
// ──────────────────────────────────────────────────────────────────────────────
//
// ── KNOWN CVE NOTE ────────────────────────────────────────────────────────────
// client/package.json declares axios: ^0.21.1 — SSRF CVE (CVE-2023-45857).
// Stage 6 npm audit (client, Pass B) will WARN in the pipeline.
// Fix: upgrade to axios >=1.6.0 in client/package.json.
// ──────────────────────────────────────────────────────────────────────────────
//
// ── MIGRATION NOTE ────────────────────────────────────────────────────────────
// This Jenkinsfile lives at the application source repository root:
//   Repo:        ibtisam-iq/node-monolith-2tier-app
//   Script Path: Jenkinsfile
// APP_DIR = '.' — workspace root is the application root.
// ──────────────────────────────────────────────────────────────────────────────

// ── STAGE MAP ─────────────────────────────────────────────────────────────────
//  1 → Checkout
//  2 → Trivy FS Scan          (pre-build, 2-pass: CRITICAL exit1 + HIGH/MED advisory)
//  3 → Versioning             (server/package.json + git SHA + build number)
//  4 → Install Dependencies   (client npm ci + server npm ci --omit=dev, parallel)
//  5 → Build Client           (Webpack 5 production bundle → client/public/)
//  6 → npm audit              (client + server, 2-pass per package)
//  7 → ESLint SAST — Server   (eslint-plugin-security, SARIF + human output)
//  8 → ESLint SAST — Client   (+ eslint-plugin-react, react-hooks)
//  9 → Build & Test           (Jest --ci --coverage --runInBand --passWithNoTests)
// 10 → SonarQube Analysis     (sonar-scanner CLI, LCOV + JUnit ingestion)
// 11 → Quality Gate           (waitForQualityGate, 5 min timeout, abortPipeline)
// 12 → Docker Build           (--pull, OCI labels, 3-registry tags in one pass)
// 13 → Trivy Image Scan       (3-pass: OS advisory + lib CRITICAL exit1 + full JSON)
// 14 → Push to Docker Hub     (main branch only)
// 15 → Push to GHCR           (main branch only)
// 16 → Push to Nexus          (main branch only)
// 17 → Update CD Manifest     (GitOps handoff → ArgoCD)
// post → Cleanup + Notifications
// ============================================================

pipeline {

    // Restrict to Linux agents — sh/trivy/docker all require Linux.
    // Same rationale as java-monolith and python-monolith: prevents
    // accidental Windows agent dispatch where sh steps would immediately fail.
    agent { label 'built-in || linux' }

    // ── tools block is NOT used here.
    // Node.js 22, npm, trivy, and docker are installed system-wide on the
    // Jenkins OS and are available on OS PATH.
    // sonar-scanner is NOT installed system-wide — it is registered in
    // Manage Jenkins → Tools → SonarQube Scanner as 'sonar-scanner'.
    // SCANNER_HOME = tool 'sonar-scanner' in environment{} resolves its
    // install path at runtime; $SCANNER_HOME/bin/sonar-scanner invokes it.

    environment {
        // ── App metadata
        APP_NAME    = 'node-monolith-2tier-app'
        // IMAGE_TAG is intentionally NOT defined here.
        // It is read at runtime from server/package.json in Stage 3 (Versioning).
        // This ensures the image tag always matches the committed version without
        // manual sync here — same pattern as java-monolith pom.xml version.

        // ── Docker Hub
        DOCKER_USER = 'mibtisam'
        IMAGE_NAME  = "${DOCKER_USER}/${APP_NAME}"
        // IMAGE_TAG set dynamically in Versioning stage

        // ── GitHub Container Registry
        GHCR_USER   = 'ibtisam-iq'
        GHCR_IMAGE  = "ghcr.io/${GHCR_USER}/${APP_NAME}"

        // ── AWS ECR  [uncomment once ECR repo is provisioned]
        // AWS_REGION     = 'us-east-1'
        // AWS_ACCOUNT_ID = '123456789012'
        // ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        // ECR_IMAGE      = "${ECR_REGISTRY}/${APP_NAME}"

        // ── Nexus Docker Registry — path-based routing
        // Image format: nexus.ibtisam-iq.com/docker-hosted/node-monolith-2tier-app:<tag>
        // Same Nexus instance as java-monolith and python-monolith.
        // NEXUS_URL: web UI link only — used in success{} echo for clickable link.
        // NEXUS_DOCKER: bare hostname without https:// as required by Docker CLI.
        NEXUS_URL         = 'https://nexus.ibtisam-iq.com'
        NEXUS_DOCKER      = 'nexus.ibtisam-iq.com'
        NEXUS_DOCKER_REPO = 'docker-hosted'

        // ── Source directory
        // APP_DIR = '.' — this Jenkinsfile lives at the repo root.
        // All dir(APP_DIR) blocks resolve to workspace root.
        APP_DIR = '.'

        // ── Application port (matches Dockerfile ARG and compose.yml)
        APP_PORT = '5000'

        // ── CD GitOps repo coordinates
        CD_REPO          = 'ibtisam-iq/platform-engineering-systems'
        CD_MANIFEST_PATH = 'systems/node-monolith/2tier/image.env'

        // ── Trivy DB cache — reused across stages, avoids repeated DB downloads
        TRIVY_CACHE_DIR = '/var/cache/trivy'

        // ── sonar-scanner installed via Jenkins Tools, not OS PATH
        SCANNER_HOME = tool 'sonar-scanner'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
        timeout(time: 60, unit: 'MINUTES')
        // abortPrevious: true — explicit, version-resilient across Jenkins LTS upgrades.
        // Without it, behavior depends on Pipeline Plugin version.
        disableConcurrentBuilds(abortPrevious: true)
        timestamps()
        ansiColor('xterm')
    }

    stages {

        // ────────────────────────────────────────────────────────────────────
        // STAGE 1 — Checkout
        //
        // checkout scm uses Jenkins-injected SCM object from job config.
        // Guarantees GIT_COMMIT and GIT_BRANCH match the triggering commit —
        // critical for image tag traceability and the main-branch when{} guard.
        // ────────────────────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo '📥 Checking out source...'
                checkout scm
                echo "✅ Branch: ${env.GIT_BRANCH} @ ${env.GIT_COMMIT?.take(7)}"
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 2 — Trivy Filesystem Scan
        //
        // Scans source tree BEFORE any install — fail-fast on declared CVEs.
        // Targets: client/package.json + server/package.json (npm CVEs),
        //          Dockerfile (misconfig), source files (hardcoded secrets).
        //
        // Two-pass strategy (matches java-monolith + python-monolith pattern):
        //   Pass 1 — CRITICAL only, --exit-code 1 → FAILS build on finding
        //   Pass 2 — HIGH,MEDIUM only, --exit-code 0 → advisory table only
        //
        // LOW excluded from FS scan (noise). LOW IS included in image scan.
        // --skip-dirs .git: avoids false-positive secrets in git pack files.
        // ────────────────────────────────────────────────────────────────────
        stage('Trivy Filesystem Scan') {
            steps {
                dir(APP_DIR) {
                    echo '🔎 Running Trivy filesystem scan on source tree...'
                    sh """
                        mkdir -p ${TRIVY_CACHE_DIR}

                        echo "=== Pass 1: CRITICAL (enforced — exit 1 on finding) ==="
                        trivy fs \\
                            --cache-dir ${TRIVY_CACHE_DIR} \\
                            --skip-dirs .git \\
                            --scanners secret,vuln,misconfig \\
                            --exit-code 1 \\
                            --severity CRITICAL \\
                            --no-progress \\
                            --format json \\
                            --output trivy-fs-critical.json \\
                            .

                        echo "=== Pass 2: HIGH,MEDIUM (advisory — exit 0) ==="
                        trivy fs \\
                            --cache-dir ${TRIVY_CACHE_DIR} \\
                            --skip-dirs .git \\
                            --scanners secret,vuln,misconfig \\
                            --exit-code 0 \\
                            --severity HIGH,MEDIUM \\
                            --no-progress \\
                            --format table \\
                            .
                    """
                    archiveArtifacts artifacts: 'trivy-fs-critical.json', allowEmptyArchive: true
                }
            }
            post {
                failure {
                    echo '❌ Trivy FS found CRITICAL vulnerabilities — review trivy-fs-critical.json'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 3 — Versioning
        //
        // Builds a unique, traceable image tag:
        //   <version>-<short-git-sha>-<build-number>   e.g. 1.0.0-ab3f12c-42
        //
        // VERSION SOURCE — server/package.json:
        //   node -p "require('./server/package.json').version"
        //   Node.js equivalent of: Java → mvn help:evaluate, Python → cat VERSION
        //
        // VERSION GUARD: errors loudly if version field is missing or empty.
        //
        // --short=7: pins SHA to exactly 7 chars — without explicit length,
        //   git auto-abbreviation grows as repo accumulates commits.
        // -C ${WORKSPACE}: reads SHA from workspace root regardless of CWD.
        //   Safe even if APP_DIR is ever a git submodule.
        // ────────────────────────────────────────────────────────────────────
        stage('Versioning') {
            steps {
                dir(APP_DIR) {
                    script {
                        def appVersion = ''

                        if (fileExists('server/package.json')) {
                            appVersion = sh(
                                script: "node -p \"require('./server/package.json').version\"",
                                returnStdout: true
                            ).trim()
                        }

                        if (!appVersion || appVersion.isEmpty()) {
                            error("❌ Could not read version from server/package.json. " +
                                  "Ensure server/package.json exists and contains a valid \"version\" field.")
                        }

                        // --short=7: pin SHA length — grows without explicit value as repo ages
                        // -C ${WORKSPACE}: always read from workspace root, not CWD — safe even if APP_DIR is a git submodule
                        def shortSha    = sh(script: 'git -C ${WORKSPACE} rev-parse --short=7 HEAD', returnStdout: true).trim()
                        env.IMAGE_TAG   = "${appVersion}-${shortSha}-${BUILD_NUMBER}"
                        env.APP_VERSION = appVersion
                        env.GIT_SHORT_SHA = shortSha

                        echo """
╔══════════════════════════════════════════════╗
║  App:     ${APP_NAME}
║  Version: ${env.APP_VERSION}
║  SHA:     ${env.GIT_SHORT_SHA}
║  Tag:     ${env.IMAGE_TAG}
║  Branch:  ${env.GIT_BRANCH}
║  Build:   #${BUILD_NUMBER}
╚══════════════════════════════════════════════╝
"""
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 4 — Install Dependencies (Parallel)
        //
        // Two package.json files — no workspace root manifest — installs run
        // independently and concurrently to save pipeline time.
        //
        // Client: full install (devDeps required for Webpack + Babel at build time)
        // Server: production-only (--omit=dev) — matches Docker image Stage 2
        //
        // npm ci vs npm install:
        //   npm ci reads package-lock.json exactly — reproducible, faster,
        //   no version drift. Both lockfiles must be committed to the repo.
        //   Using npm install - lockfiles are not committed intentionally.
        //
        // --prefer-offline: uses npm cache on cache hit, falls back to registry. ────────────────────────────────────────────────────────────────────
        stage('Install Dependencies') {
            parallel {

                stage('Client — npm install') {
                    steps {
                        dir('client') {
                            echo '📦 Installing client dependencies (devDeps included for Webpack/Babel)...'
                            sh '''
                                npm install --prefer-offline
                                echo "✅ Client deps: $(npm list --depth=0 2>/dev/null | wc -l) packages"
                            '''
                        }
                    }
                }

                stage('Server — npm install (prod)') {
                    steps {
                        dir('server') {
                            echo '📦 Installing server dependencies (--omit=dev)...'
                            sh '''
                                npm install --prefer-offline --omit=dev
                                echo "✅ Server deps: $(npm list --depth=0 --omit=dev 2>/dev/null | wc -l) packages"
                            '''
                        }
                    }
                }

            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 5 — Install Dependencies (Parallel)
        //
        // Two package.json files — no workspace root manifest — installs run
        // independently and concurrently to save pipeline time.
        //
        // Client: full install (devDeps required for Webpack + Babel at build time)
        // Server: production-only (--omit=dev) — matches Docker image Stage 2
        //
        // npm ci vs npm install:
        //   npm ci reads package-lock.json exactly — reproducible, faster,
        //   no version drift. Both lockfiles must be committed to the repo.
        //
        // --prefer-offline: uses npm cache on cache hit, falls back to registry. ────────────────────────────────────────────────────────────────────
        stage('Build Client') {
            steps {
                dir(APP_DIR) {
                    echo '🔨 Compiling React 17 frontend with Webpack 5...'
                    sh """
                        cd client
                        NODE_ENV=production npm run build
                        echo "✅ Client build complete — output:"
                        ls -lh public/
                    """
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'client/public/**', allowEmptyArchive: true
                }
                failure {
                    echo '❌ Webpack build failed — check client/webpack.config.js and src/ for compile errors'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 6 — npm audit (Dependency CVE Scan)
        //
        // WHY npm audit IN ADDITION TO TRIVY FS (Stage 2):
        //   Trivy scans package.json (declared versions).
        //   npm audit scans package-lock.json (fully resolved transitive tree).
        //   The resolved tree can expose vulnerable transitive deps not visible
        //   in direct declarations. Defense in depth — two advisory sources.
        //
        // Two-pass strategy per package (client + server):
        //   Pass A — CRITICAL only, --audit-level=critical, exit 1 → FAILS build
        //   Pass B — HIGH+MEDIUM, --audit-level=high, exit 0 → advisory only
        //
        // Server audit uses --omit=dev: only prod deps ship to production.
        // KNOWN: client axios ^0.21.1 (SSRF CVE) will appear in Pass B.
        // ────────────────────────────────────────────────────────────────────
        stage('npm audit') {
            steps {
                dir(APP_DIR) {
                    echo '🔐 Running npm audit on client and server...'
                    sh """
                        echo "── Client audit ──"
                        cd client

                        # Pass A — CRITICAL: fail build
                        npm audit --audit-level=critical --json > ../npm-audit-client.json 2>&1 || {
                            echo '❌ npm audit found CRITICAL vulnerabilities in client.'
                            cat ../npm-audit-client.json
                            exit 1
                        }

                        # Pass B — HIGH+MEDIUM: advisory only
                        npm audit --audit-level=high || true

                        cd ..
                        echo "── Server audit ──"
                        cd server

                        # Pass A — CRITICAL: fail build
                        npm audit --omit=dev --audit-level=critical --json > ../npm-audit-server.json 2>&1 || {
                            echo '❌ npm audit found CRITICAL vulnerabilities in server.'
                            cat ../npm-audit-server.json
                            exit 1
                        }

                        # Pass B — HIGH+MEDIUM: advisory only
                        npm audit --omit=dev --audit-level=high || true

                        cd ..
                        echo '✅ npm audit complete'
                    """
                    archiveArtifacts artifacts: 'npm-audit-client.json,npm-audit-server.json', allowEmptyArchive: true
                }
            }
            post {
                failure {
                    echo '❌ npm audit: CRITICAL CVEs found — see archived JSON reports. Client: upgrade axios to >=1.6.0'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 7 — ESLint SAST — Server
        //
        // ESLint + eslint-plugin-security is the standard JS SAST tool (2026).
        // Flat config (eslint.config.mjs) — ESLint v9+ format.
        // .eslintrc.* format deprecated in ESLint v9 (released 2024).
        //
        // OWASP-aligned rules from eslint-plugin-security:
        //   detect-non-literal-fs-filename, detect-child-process,
        //   detect-unsafe-regex, detect-object-injection,
        //   detect-possible-timing-attacks
        //
        // SARIF output → archivable for GitHub Advanced Security / audit trail.
        // Human-readable (stylish) output for Jenkins console.
        // Enforced pass — exits 1 if any ERROR-level rule fires.
        //
        // Plugins installed per-build (CI-only, not committed to server/):
        //   eslint, eslint-plugin-security, @microsoft/eslint-formatter-sarif
        // Temp config cleaned in post{} always{}.
        // ────────────────────────────────────────────────────────────────────
        stage('ESLint SAST — Server') {
            steps {
                dir('server') {
                    echo '🔍 Running ESLint SAST on server (Node.js/Express)...'
                    sh '''
                        echo "=== Installing ESLint + security plugin (CI-only) ==="
                        npm install --save-dev \
                            eslint@^9 \
                            eslint-plugin-security@^3 \
                            @microsoft/eslint-formatter-sarif@^3 \
                            2>/dev/null

                        echo "=== Writing ESLint flat config ==="
                        cat > eslint.config.mjs << 'ESLINT_EOF'
import security from 'eslint-plugin-security';

export default [
  {
    files: ['**/*.js'],
    plugins: { security },
    rules: {
      ...security.configs.recommended.rules,
      'no-eval':                                        'error',
      'no-implied-eval':                                'error',
      'no-new-func':                                    'error',
      'no-console':                                     'warn',
      'no-process-exit':                                'warn',
      'security/detect-non-literal-fs-filename':        'warn',
      'security/detect-child-process':                  'error',
      'security/detect-unsafe-regex':                   'error',
      'security/detect-object-injection':               'warn',
      'security/detect-possible-timing-attacks':        'warn',
    },
  },
];
ESLINT_EOF

                        echo "=== ESLint — SARIF output ==="
                        npx eslint \
                            --format @microsoft/eslint-formatter-sarif \
                            --output-file ../eslint-server.sarif \
                            . || true

                        echo "=== ESLint — Human-readable (advisory) ==="
                        npx eslint --format stylish . 2>&1 | tee ../eslint-server.txt || true

                        echo "=== ESLint — Enforced (errors only, exits 1 on violation) ==="
                        npx eslint \
                            --format stylish \
                            --max-warnings=0 \
                            --rule '{"no-eval": "error", "no-implied-eval": "error", "security/detect-child-process": "error", "security/detect-unsafe-regex": "error"}' \
                            .
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'eslint-server.sarif,eslint-server.txt', allowEmptyArchive: true
                    sh 'rm -f server/eslint.config.mjs || true'
                }
                failure {
                    echo '❌ ESLint SAST (server): ERROR-level security rules fired — review eslint-server.txt'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 8 — ESLint SAST — Client
        //
        // Extends server SAST config with React-specific rules:
        //   eslint-plugin-react   → JSX rules, dangerouslySetInnerHTML guard
        //   eslint-plugin-react-hooks → hooks rules (exhaustive-deps, etc.)
        //
        // react/no-danger: 'error' — prevents XSS via raw HTML injection.
        // react/jsx-no-script-url: 'error' — prevents javascript: href XSS.
        //
        // Client node_modules already installed (Stage 4) — adds devDeps only.
        // ────────────────────────────────────────────────────────────────────
        stage('ESLint SAST — Client') {
            steps {
                dir('client') {
                    echo '🔍 Running ESLint SAST on client (React 17)...'
                    sh '''
                        echo "=== Installing ESLint + React + security plugins (CI-only) ==="
                        npm install --save-dev \
                            eslint@^9 \
                            eslint-plugin-security@^3 \
                            eslint-plugin-react@^7 \
                            eslint-plugin-react-hooks@^4 \
                            @microsoft/eslint-formatter-sarif@^3 \
                            2>/dev/null

                        echo "=== Writing ESLint flat config for client ==="
                        cat > eslint.config.mjs << 'ESLINT_EOF'
import security   from 'eslint-plugin-security';
import react      from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  {
    files: ['src/**/*.{js,jsx}'],
    plugins: { security, react, 'react-hooks': reactHooks },
    settings: { react: { version: 'detect' } },
    rules: {
      ...security.configs.recommended.rules,
      ...react.configs.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      'no-eval':                          'error',
      'no-implied-eval':                  'error',
      'react/no-danger':                  'error',
      'react/jsx-no-script-url':          'error',
      'security/detect-unsafe-regex':     'error',
    },
  },
];
ESLINT_EOF

                        echo "=== ESLint — SARIF output ==="
                        npx eslint \
                            --format @microsoft/eslint-formatter-sarif \
                            --output-file ../eslint-client.sarif \
                            src/ || true

                        echo "=== ESLint — Human-readable ==="
                        npx eslint --format stylish src/ 2>&1 | tee ../eslint-client.txt || true

                        echo "=== ESLint — Enforced ==="
                        npx eslint \
                            --format stylish \
                            --max-warnings=0 \
                            src/
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'eslint-client.sarif,eslint-client.txt', allowEmptyArchive: true
                    sh 'rm -f client/eslint.config.mjs || true'
                }
                failure {
                    echo '❌ ESLint SAST (client): ERROR-level rules fired — review eslint-client.txt'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 9 — Build & Test (Jest)
        //
        // WHY JEST: de-facto standard for React + Node.js projects (2026).
        //   Covers both client (component tests) and server (route/unit tests).
        //
        // SERVER TESTS:
        //   DB calls mocked via jest.mock(). CI_TEST=true signals app to skip
        //   real MySQL connection at startup (no DB container needed in CI).
        //
        // JEST FLAGS:
        //   --ci           → fail on new snapshots, disable interactive mode
        //   --coverage     → LCOV + Cobertura XML coverage reports
        //   --forceExit    → prevents Jest hanging on open DB handles
        //   --runInBand    → serial execution (avoids port conflicts on CI)
        //   --passWithNoTests → passes when no test files exist yet (no tests
        //                      committed — team adds tests without breaking CI)
        //
        // Coverage written to:
        //   coverage/lcov.info              → SonarQube ingestion (Stage 10)
        //   coverage/cobertura-coverage.xml → Jenkins recordCoverage()
        //   coverage/lcov-report/           → HTML artifact
        //
        // junit() + recordCoverage() publishers in post{} always{},
        // guarded by fileExists — prevents publisher failure when no tests run.
        //
        // WHY NO --coverageThreshold: enforcement belongs in SonarQube Gate.
        // ────────────────────────────────────────────────────────────────────
        stage('Build & Test') {
            steps {
                dir(APP_DIR) {
                    echo '🧪 Running Jest tests with coverage...'
                    sh """
                        # Install Jest + Supertest (CI-only, server scope)
                        cd server
                        npm install --save-dev \
                            jest@^29 \
                            supertest@^7 \
                            jest-junit@^16 \
                            2>/dev/null

                        # Write Jest config
                        cat > jest.config.js << 'JEST_EOF'
module.exports = {
  testEnvironment: 'node',
  coverageReporters: ['text', 'lcov', 'cobertura'],
  coverageDirectory: '../coverage',
  collectCoverageFrom: [
    '**/*.js',
    '!node_modules/**',
    '!jest.config.js',
    '!eslint.config.mjs',
  ],
  reporters: [
    'default',
    ['jest-junit', {
      outputDirectory: '..',
      outputName: 'jest-results.xml',
      classNameTemplate: '{classname}',
      titleTemplate:     '{title}',
    }],
  ],
};
JEST_EOF

                        cd ..

                        CI_TEST=true npx --prefix server jest \
                            --ci \
                            --coverage \
                            --forceExit \
                            --runInBand \
                            --passWithNoTests \
                            2>&1 | tee jest-output.txt
                    """
                }
            }
            post {
                always {
                    // Publish JUnit test results to Jenkins UI
                    script {
                        if (fileExists('jest-results.xml')) {
                            junit(
                                testResults: 'jest-results.xml',
                                allowEmptyResults: true,
                                skipPublishingChecks: false
                            )
                        }
                        // Publish coverage to Jenkins Coverage Plugin UI
                        if (fileExists('coverage/cobertura-coverage.xml')) {
                            recordCoverage(
                                tools: [[parser: 'COBERTURA', pattern: 'coverage/cobertura-coverage.xml']],
                                id: 'jest-coverage',
                                name: 'Jest Coverage'
                            )
                        }
                    }
                    archiveArtifacts artifacts: 'jest-results.xml,jest-output.txt,coverage/**', allowEmptyArchive: true
                    sh 'rm -f server/jest.config.js || true'
                }
                failure {
                    echo '❌ Jest tests failed — review jest-output.txt and jest-results.xml'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 10 — SonarQube Analysis
        //
        // Uses sonar-scanner CLI (same as python-monolith — not Maven plugin).
        // Injected via withSonarQubeEnv('sonar-server').
        //
        // KEY PROPERTIES:
        //   sonar.sources=client/src,server  — both tiers
        //   sonar.tests=client/src,server    — Jest tests co-located with src
        //   sonar.test.inclusions            — matches *.test.js / *.spec.js
        //   sonar.javascript.lcov.reportPaths → LCOV from Jest (Stage 9)
        //   sonar.exclusions                 → node_modules, built output, coverage
        //   sonar.working.directory          → pins report-task.txt location
        //                                      (required for waitForQualityGate)
        //
        // SONAR_HOST_URL and SONAR_AUTH_TOKEN injected by withSonarQubeEnv().
        // ────────────────────────────────────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                dir(APP_DIR) {
                    echo '📊 Running SonarQube static analysis...'
                    withSonarQubeEnv('sonar-server') {
                        sh """
                            \$SCANNER_HOME/bin/sonar-scanner \\
                                -Dsonar.projectKey=IbtisamIQnodemonolith \\
                                -Dsonar.projectName=IbtisamIQnodemonolith \\
                                -Dsonar.projectVersion=${IMAGE_TAG} \\
                                -Dsonar.sources=client/src,server \\
                                -Dsonar.tests=client/src,server \\
                                -Dsonar.test.inclusions="**/*.test.js,**/*.spec.js" \\
                                -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \\
                                -Dsonar.testExecutionReportPaths=jest-results.xml \\
                                -Dsonar.exclusions="**/node_modules/**,client/public/**,coverage/**,**/*.min.js,**/jest.config.js,**/eslint.config.mjs,**/webpack.config.js" \\
                                -Dsonar.sourceEncoding=UTF-8 \\
                                -Dsonar.working.directory=${WORKSPACE}/.scannerwork
                        """
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 11 — Quality Gate
        //
        // Blocks pipeline until SonarQube webhook fires with pass/fail result.
        // abortPipeline: true → build FAILS on gate failure.
        // timeout(5 min): sufficient for this codebase; extend if analysis grows.
        // ────────────────────────────────────────────────────────────────────
        stage('Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarQube Quality Gate...'
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                failure {
                    echo '❌ SonarQube Quality Gate FAILED — fix code smells, coverage, or security hotspots'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 12 — Docker Build
        //
        // 3-stage Dockerfile:
        //   Stage 1 (client-build): node:22-alpine, Webpack → client/public/
        //   Stage 2 (server-deps):  node:22-alpine, npm ci --omit=dev
        //   Stage 3 (runtime):      node:22-alpine, lean final image
        //
        // --pull: forces Docker to check registry for newer base image digest.
        //   Without --pull, stale base images with known CVEs are silently reused.
        //
        // Tags for ALL registries in ONE build pass — avoids rebuilding per registry.
        //   Docker Hub:  mibtisam/node-monolith-2tier-app:<tag>
        //   GHCR:        ghcr.io/ibtisam-iq/node-monolith-2tier-app:<tag>
        //   (Nexus tagged separately in Stage 16 — path-based routing)
        //
        // OCI labels: version, revision, created, source (build-time injection).
        // APP_PORT build-arg: passes to Dockerfile EXPOSE + startup (port 5000).
        // ────────────────────────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                dir(APP_DIR) {
                    echo "🐳 Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
                    sh """
                        docker build --pull \\
                            --build-arg APP_PORT=${APP_PORT} \\
                            --label "org.opencontainers.image.version=${IMAGE_TAG}" \\
                            --label "org.opencontainers.image.revision=${GIT_COMMIT}" \\
                            --label "org.opencontainers.image.created=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
                            --label "org.opencontainers.image.source=https://github.com/ibtisam-iq/node-monolith-2tier-app" \\
                            -t ${IMAGE_NAME}:${IMAGE_TAG} \\
                            -t ${IMAGE_NAME}:latest \\
                            -t ${GHCR_IMAGE}:${IMAGE_TAG} \\
                            -t ${GHCR_IMAGE}:latest \\
                            .

                        # Uncomment once ECR variables are set:
                        # docker tag ${IMAGE_NAME}:${IMAGE_TAG} \${ECR_IMAGE}:${IMAGE_TAG}
                        # docker tag ${IMAGE_NAME}:latest       \${ECR_IMAGE}:latest

                        echo "=== Image size ==="
                        docker image inspect ${IMAGE_NAME}:${IMAGE_TAG} \\
                            --format='{{.Size}}' | \\
                            awk '{printf "Image size: %.1f MB\\n", \$1/1024/1024}'

                        echo "=== Image layers ==="
                        docker history ${IMAGE_NAME}:${IMAGE_TAG}

                        echo "✅ Docker build complete — ${IMAGE_NAME}:${IMAGE_TAG}"
                    """
                }
            }
            post {
                failure {
                    echo '❌ Docker build failed — check Dockerfile and client/public/ output from Stage 5'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 13 — Trivy Image Scan
        //
        // Scans the freshly built image for CVEs BEFORE pushing to any registry.
        // Three-pass strategy:
        //
        //   Pass A — OS packages (Alpine Linux base):
        //            --vuln-type os, CRITICAL+HIGH, --exit-code 0 → warn only.
        //            Alpine OS CVEs are maintainer responsibility; we track but
        //            don't block (no fix available most of the time).
        //
        //   Pass B — Library (npm packages from node_modules):
        //            --vuln-type library, CRITICAL only, --exit-code 1 → FAILS.
        //            These are YOUR deps — fix = bump version in package.json.
        //
        //   Pass B (cont.) — Library HIGH+MEDIUM:
        //            --exit-code 0 → advisory table, never blocks.
        //
        //   Pass C — Full audit report (all types + severities incl. LOW):
        //            --exit-code 0, JSON format → archived artifact.
        //            LOW intentionally INCLUDED for image scan (excluded FS scan).
        //
        // --ignore-unfixed: skip CVEs with no available fix (reduces noise).
        // ────────────────────────────────────────────────────────────────────
        stage('Trivy Image Scan') {
            steps {
                dir(APP_DIR) {
                    echo "🛡️  Scanning image with Trivy: ${IMAGE_NAME}:${IMAGE_TAG}"
                    sh """
                        echo "=== Pass A: OS packages CRITICAL+HIGH (advisory) ==="
                        trivy image \\
                            --cache-dir ${TRIVY_CACHE_DIR} \\
                            --vuln-type os \\
                            --exit-code 0 \\
                            --severity CRITICAL,HIGH \\
                            --ignore-unfixed \\
                            --no-progress \\
                            --format table \\
                            ${IMAGE_NAME}:${IMAGE_TAG}

                        echo "=== Pass B: Library CRITICAL (enforced — exit 1 on finding) ==="
                        trivy image \\
                            --cache-dir ${TRIVY_CACHE_DIR} \\
                            --vuln-type library \\
                            --exit-code 1 \\
                            --severity CRITICAL \\
                            --ignore-unfixed \\
                            --no-progress \\
                            --format table \\
                            ${IMAGE_NAME}:${IMAGE_TAG}

                        echo "=== Pass B (cont.): Library HIGH,MEDIUM (advisory) ==="
                        trivy image \\
                            --cache-dir ${TRIVY_CACHE_DIR} \\
                            --vuln-type library \\
                            --exit-code 0 \\
                            --severity HIGH,MEDIUM \\
                            --ignore-unfixed \\
                            --no-progress \\
                            --format table \\
                            ${IMAGE_NAME}:${IMAGE_TAG}

                        echo "=== Pass C: Full report incl. LOW (archived artifact) ==="
                        trivy image \\
                            --cache-dir ${TRIVY_CACHE_DIR} \\
                            --exit-code 0 \\
                            --severity CRITICAL,HIGH,MEDIUM,LOW \\
                            --ignore-unfixed \\
                            --no-progress \\
                            --format json \\
                            --output trivy-image-report.json \\
                            ${IMAGE_NAME}:${IMAGE_TAG}

                        echo "✅ Trivy image scan complete"
                    """
                    archiveArtifacts artifacts: 'trivy-image-report.json', allowEmptyArchive: true
                }
            }
            post {
                failure {
                    echo '❌ Trivy: CRITICAL library CVEs found in image — review trivy-image-report.json'
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGES 14–17 — Publish (main branch only)
        //
        // WHY expression{} INSTEAD OF when { branch 'main' }:
        //   branch{} requires Multibranch Pipeline; on standard Pipeline jobs
        //   BRANCH_NAME is never set and branch{} silently evaluates false.
        //   GIT_BRANCH is set by checkout scm: "origin/main" (standard job)
        //   or "main" (Multibranch). Anchored regex matches both.
        //
        // WHY NULL GUARD (env.GIT_BRANCH != null):
        //   REST API-triggered builds may not populate GIT_BRANCH.
        //   null ==~ /regex/ throws NPE crashing when{} evaluation.
        // ────────────────────────────────────────────────────────────────────
        stage('Publish') {
            when {
                expression {
                    env.GIT_BRANCH != null &&
                    (env.GIT_BRANCH ==~ /^(origin\/)?main$/)
                }
            }
            stages {

                // ────────────────────────────────────────────────────────────
                // STAGE 14 — Push to Docker Hub
                //
                // docker logout registry-1.docker.io — explicit registry arg.
                // Bare `docker logout` on some Docker Engine versions clears ALL
                // credentials from ~/.docker/config.json, wiping GHCR/Nexus creds.
                // ────────────────────────────────────────────────────────────
                stage('Push to Docker Hub') {
                    steps {
                        echo "🚀 Pushing to Docker Hub: ${IMAGE_NAME}:${IMAGE_TAG}"
                        withCredentials([usernamePassword(
                            credentialsId: 'docker-creds',
                            usernameVariable: 'DOCKER_USERNAME',
                            passwordVariable: 'DOCKER_PASSWORD'
                        )]) {
                            sh """
                                echo "\${DOCKER_PASSWORD}" | docker login -u "\${DOCKER_USERNAME}" --password-stdin
                                docker push ${IMAGE_NAME}:${IMAGE_TAG}
                                docker push ${IMAGE_NAME}:latest
                                docker logout registry-1.docker.io
                                echo "✅ Docker Hub push complete"
                            """
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // STAGE 15 — Push to GitHub Container Registry (GHCR)
                //
                // Credential: ghcr-creds (GitHub PAT with write:packages scope).
                // Image already tagged for GHCR in Stage 12 (Docker Build).
                // ────────────────────────────────────────────────────────────
                stage('Push to GHCR') {
                    steps {
                        echo "🐙 Pushing to GHCR: ${GHCR_IMAGE}:${IMAGE_TAG}"
                        withCredentials([usernamePassword(
                            credentialsId: 'ghcr-creds',
                            usernameVariable: 'GHCR_USERNAME',
                            passwordVariable: 'GHCR_TOKEN'
                        )]) {
                            sh """
                                echo "\${GHCR_TOKEN}" | docker login ghcr.io -u "\${GHCR_USERNAME}" --password-stdin
                                docker push ${GHCR_IMAGE}:${IMAGE_TAG}
                                docker push ${GHCR_IMAGE}:latest
                                docker logout ghcr.io
                                echo "✅ GHCR push complete"
                            """
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // STAGE 16 — Push to Nexus Docker Registry
                //
                // Path-based routing — no dedicated Docker port needed.
                // Image: nexus.ibtisam-iq.com/docker-hosted/node-monolith-2tier-app:<tag>
                //
                // Pre-requisites:
                //   1. Hosted Docker repo with "Path based routing" selected
                //   2. Security → Realms → Docker Bearer Token Realm active
                // ────────────────────────────────────────────────────────────
                stage('Push to Nexus Registry') {
                    steps {
                        echo "📤 Pushing to Nexus: ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG}"
                        withCredentials([usernamePassword(
                            credentialsId: 'nexus-creds',
                            usernameVariable: 'NEXUS_USER',
                            passwordVariable: 'NEXUS_PASS'
                        )]) {
                            sh """
                                echo "\${NEXUS_PASS}" | docker login ${NEXUS_DOCKER} -u "\${NEXUS_USER}" --password-stdin
                                docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG}
                                docker tag ${IMAGE_NAME}:latest       ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:latest
                                docker push ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG}
                                docker push ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:latest
                                docker logout ${NEXUS_DOCKER}
                                echo "✅ Nexus push complete"
                            """
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // [COMMENTED] Push to AWS ECR
                // Uncomment once AWS credentials and ECR repo are provisioned.
                //
                // Pre-requisites:
                //   1. aws ecr create-repository --repository-name node-monolith-2tier-app
                //   2. Add AWS credentials to Jenkins (CloudBees AWS Credentials plugin, ID: aws-creds)
                //   3. Set ECR variables in environment{} block above
                //   4. Uncomment docker tag lines in Stage 12
                // ────────────────────────────────────────────────────────────
                // stage('Push to AWS ECR') {
                //     steps {
                //         withCredentials([[
                //             $class:            'AmazonWebServicesCredentialsBinding',
                //             credentialsId:     'aws-creds',
                //             accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                //             secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                //         ]]) {
                //             sh """
                //                 aws ecr get-login-password --region ${AWS_REGION} \
                //                     | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                //                 docker push ${ECR_IMAGE}:${IMAGE_TAG}
                //                 docker push ${ECR_IMAGE}:latest
                //                 docker logout ${ECR_REGISTRY}
                //             """
                //         }
                //     }
                // }

                // ────────────────────────────────────────────────────────────
                // STAGE 17 — Update CD Repo (GitOps handoff)
                //
                // Writes the new image tag into platform-engineering-systems
                // so ArgoCD detects the change and triggers a rolling deployment.
                //
                // ALL hardening from java-monolith Stage 14 and
                // python-monolith Stage 16 carried over identically:
                //
                //   TOKEN OFF ARGV:
                //     Clone with public URL → set authenticated remote after clone
                //     → clear token from remote URL after push.
                //
                //   IMAGE_TAG GUARD:
                //     \${IMAGE_TAG} escaped → shell evaluates at runtime.
                //
                //   UNIQUE TMP DIR:
                //     _cd_repo_tmp — distinct from any app source directory name.
                //
                //   GIT DIFF GUARD:
                //     git diff --cached --quiet — precise "nothing staged" detection.
                //
                //   HEAD PUSH:
                //     git push origin HEAD — resilient to CD repo branch renames.
                //
                //   GROOVY vs SHELL INTERPOLATION:
                //     \${GIT_USER}, \${GIT_TOKEN}, \${IMAGE_TAG} — escaped → shell expands.
                //     ${CD_REPO}, ${CD_MANIFEST_PATH} — Groovy interpolates at parse time.
                //
                // image.env format:
                //   IMAGE_TAG=1.0.0-ab3f12c-42
                //   UPDATED_AT=2026-04-24T10:00:00Z
                //   UPDATED_BY=jenkins-build-42
                //   GIT_COMMIT=abc1234...
                //   GIT_BRANCH=main
                // ────────────────────────────────────────────────────────────
                stage('Update CD Repo') {
                    steps {
                        echo '🔄 Updating image tag in CD repo (platform-engineering-systems)...'
                        withCredentials([usernamePassword(
                            credentialsId: 'github-creds',
                            usernameVariable: 'GIT_USER',
                            passwordVariable: 'GIT_TOKEN'
                        )]) {
                            sh """
                                # IMAGE_TAG GUARD — escaped: shell evaluates at runtime
                                if [ -z "\${IMAGE_TAG}" ]; then
                                    echo '❌ IMAGE_TAG is empty — aborting CD repo update'
                                    exit 1
                                fi

                                # Unique tmp dir — no collision with app source directories
                                rm -rf _cd_repo_tmp

                                # TOKEN OFF ARGV — clone public URL; token never in argv
                                git clone https://github.com/${CD_REPO}.git _cd_repo_tmp

                                cd _cd_repo_tmp

                                # Clear token-bearing URL immediately after clone
                                git remote set-url origin ""

                                # Restore bare HTTPS URL for credential helper
                                git remote set-url origin "https://github.com/${CD_REPO}.git"

                                git config --local user.email "jenkins@ibtisam-iq.com"
                                git config --local user.name  "Jenkins CI"

                                mkdir -p "\$(dirname "${CD_MANIFEST_PATH}")"

                                # Once K8s/Helm manifests exist, replace with:
                                # sed -i "s|image: mibtisam/node-monolith-2tier-app:.*|image: mibtisam/node-monolith-2tier-app:\${IMAGE_TAG}|g" \\
                                #     deployments/node-monolith/deployment.yaml

                                echo "=== Current manifest ==="
                                cat ${CD_MANIFEST_PATH} 2>/dev/null || echo "(file does not exist yet)"

                                echo "=== Writing new manifest ==="
                                cat > ${CD_MANIFEST_PATH} << EOF
IMAGE_TAG=${IMAGE_TAG}
UPDATED_AT=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
UPDATED_BY=jenkins-build-${BUILD_NUMBER}
GIT_COMMIT=${GIT_COMMIT}
GIT_BRANCH=${GIT_BRANCH}
EOF

                                git add "${CD_MANIFEST_PATH}"

                                # PRECISE "nothing staged" detection
                                git diff --cached --quiet \\
                                    && echo "ℹ️  Nothing to commit — image tag unchanged" \\
                                    || git commit -m "ci: update node-monolith image tag to \${IMAGE_TAG} [skip ci]"

                                # TOKEN OFF ARGV — push via credential helper
                                git -c credential.helper='!f() { printf "username=%s\\n" "\${GIT_USER}"; printf "password=%s\\n" "\${GIT_TOKEN}"; }; f' \\
                                    push origin HEAD

                                # Clear token from remote URL
                                git remote set-url origin "https://github.com/${CD_REPO}.git"
                            """
                        }
                    }
                }

            } // end stages (Publish)
        } // end stage('Publish')

    } // end stages

    // ────────────────────────────────────────────────────────────────────────
    // POST — Publishers, Cleanup & Notifications
    //
    // ORDERING (intentional — do not reorder):
    //   1. Jest JUnit XML publisher      — must run BEFORE cleanWs() removes files
    //   2. Coverage publisher            — must run BEFORE cleanWs() removes files
    //   3. Docker cleanup                — named rmi + dangling prune
    //   4. CD tmp dir cleanup            — rm _cd_repo_tmp if Stage 16 ran
    //   5. cleanWs()                     — always last
    //
    // FILEEXISTS GUARDS (equivalent of java-monolith FIX #8):
    //   If the pipeline fails before Stage 7 (Build & Test), jest-results.xml
    //   and coverage/lcov.info do not exist. Without the guard:
    //     - junit() would fail the post block (no XML found)
    //     - recordCoverage() would write a zero-coverage data point to the trend
    //       graph for every Trivy/Versioning/npm-audit failure — same false-negative
    //       problem as Java pipeline.
    //
    // COVERAGE PUBLISHER:
    //   recordCoverage() with COBERTURA parser reads
    //   coverage/cobertura-coverage.xml generated by Jest + jest-coverage-reporter.
    //   Requires the Coverage Plugin (Jenkins Update Center: id = "coverage").
    //   The old Cobertura Plugin is deprecated — do NOT install it.
    // ────────────────────────────────────────────────────────────────────────
    post {
        always {
            // ── 1. Jest JUnit XML publisher — guarded by fileExists
            script {
                if (fileExists("${APP_DIR}/jest-results.xml")) {
                    junit testResults: "${APP_DIR}/jest-results.xml",
                          allowEmptyResults: true
                } else {
                    echo '⏭️  Skipping junit — jest-results.xml not found (pipeline failed before Build & Test stage).'
                }
            }

            // ── 2. Coverage publisher (Coverage Plugin — COBERTURA parser)
            //       Install: Jenkins Update Center → "Coverage" (id: coverage)
            //       Do NOT install the old "Cobertura" plugin — it is deprecated.
            script {
                if (fileExists("${APP_DIR}/coverage/cobertura-coverage.xml")) {
                    recordCoverage(
                        tools: [[
                            parser:  'COBERTURA',
                            pattern: "${APP_DIR}/coverage/cobertura-coverage.xml"
                        ]],
                        sourceCodeRetention: 'EVERY_BUILD'
                    )
                } else {
                    echo '⏭️  Skipping recordCoverage — coverage/cobertura-coverage.xml not found (pipeline failed before Build & Test stage).'
                }
            }

            // ── 3. Docker cleanup — named rmi + dangling layer prune
            script {
                if (env.IMAGE_TAG) {
                    echo '🧹 Cleaning up local Docker images...'
                    sh """
                        docker rmi ${IMAGE_NAME}:${IMAGE_TAG}                                          || true
                        docker rmi ${IMAGE_NAME}:latest                                                || true
                        docker rmi ${GHCR_IMAGE}:${IMAGE_TAG}                                         || true
                        docker rmi ${GHCR_IMAGE}:latest                                               || true
                        docker rmi ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG}      || true
                        docker rmi ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:latest            || true
                        # docker rmi \${ECR_IMAGE}:${IMAGE_TAG}                                       || true
                        # docker rmi \${ECR_IMAGE}:latest                                             || true
                    """
                } else {
                    echo '⏭️  Skipping docker rmi — IMAGE_TAG not set (pipeline failed before Versioning stage).'
                }

                // Prune dangling (<none>:<none>) image layers — always safe
                sh 'docker image prune -f || true'
            }

            // ── 4. CD tmp dir cleanup
            sh 'rm -rf _cd_repo_tmp || true'

            // ── 5. Workspace cleanup — always last
            cleanWs()
        }

        success {
            script {
                def published = (env.GIT_BRANCH != null && env.GIT_BRANCH ==~ /^(origin\/)?main$/)
                    ? 'PUBLISHED to all registries ✅'
                    : 'NOT PUBLISHED — non-main branch (build + scan only)'
                echo """
            ╔══════════════════════════════════════════════════════════╗
            ║  ✅  PIPELINE SUCCEEDED
            ╠══════════════════════════════════════════════════════════╣
            ║  Branch : ${env.GIT_BRANCH}
            ║  Status : ${published}
            ║  Image  : ${IMAGE_NAME}:${IMAGE_TAG}
            ║  GHCR   : ${GHCR_IMAGE}:${IMAGE_TAG}
            ║  Nexus  : ${NEXUS_URL}
            ╚══════════════════════════════════════════════════════════╝
                """
            }
        }

        failure {
            echo """
            ╔══════════════════════════════════════════════════════════╗
            ║  ❌  PIPELINE FAILED                                     ║
            ║  Check console output for details                        ║
            ╚══════════════════════════════════════════════════════════╝
            """
        }

        unstable {
            echo '⚠️  Pipeline is UNSTABLE — test failures or quality issues detected.'
        }
    }
}
