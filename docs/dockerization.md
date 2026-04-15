# Dockerization Deep Dive

I wrote this documentation when I first forked this project and started learning how to understand an unfamiliar codebase, run it locally, and eventually Dockerize it. At that point I had very little experience — I didn't know which files belong in Git and which are generated, I didn't fully understand what `dist/` vs `public/` means, and I didn't know how to read a project's architecture from its files alone. This document is everything I worked through. I am keeping it here so that if I (or anyone else) ever comes back to this repo, the thinking process is preserved.

> **Note on architecture:** The old version of this documentation incorrectly called this a 3-tier application. It is not. This is a **2-tier (monolithic) application**. The frontend (React) is built into static files and served directly by the same Express backend server. There is no separate frontend server or reverse proxy — Express handles everything via `app.use(express.static(...))`. The two tiers are: (1) the Node.js/Express server, and (2) the MySQL database. I later converted this project into a proper 3-tier app in a separate repo.

---

## Table of Contents

1. [How I Approached an Unfamiliar Project](#1-how-i-approached-an-unfamiliar-project)
2. [Project Structure (Current)](#2-project-structure-current)
3. [Understanding the Architecture](#3-understanding-the-architecture)
   - [Why This Is 2-Tier, Not 3-Tier](#why-this-is-2-tier-not-3-tier)
   - [How the Two Tiers Work Together](#how-the-two-tiers-work-together)
4. [Frontend Deep Dive (`client/`)](#4-frontend-deep-dive-client)
   - [src/ — Where You Write Code](#src--where-you-write-code)
   - [webpack.config.js — The Build Tool](#webpackconfigjs--the-build-tool)
   - [.babelrc — The Transpiler Config](#babelrc--the-transpiler-config)
   - [public/ — The Build Output](#public--the-build-output)
   - [The dist/ Folder — Why It Existed and Why I Deleted It](#the-dist-folder--why-it-existed-and-why-i-deleted-it)
5. [Backend Deep Dive (`server/`)](#5-backend-deep-dive-server)
   - [server.js — Entry Point](#serverjs--entry-point)
   - [package.json](#packagejson)
   - [How Express Serves Both API and Frontend](#how-express-serves-both-api-and-frontend)
6. [Database (`database/`)](#6-database-database)
7. [Build Process — What Generates What](#7-build-process--what-generates-what)
8. [The bundle.js.LICENSE.txt File](#8-the-bundlejslicensetxt-file)
9. [Dockerization](#9-dockerization)
   - [Understanding What Needs to Be Containerized](#understanding-what-needs-to-be-containerized)
   - [Single-Stage Dockerfile (Simple)](#single-stage-dockerfile-simple)
   - [Multi-Stage Dockerfile (Efficient)](#multi-stage-dockerfile-efficient)
   - [docker-compose.yml (Full Stack)](#docker-composeyml-full-stack)
10. [Running the Application Locally](#10-running-the-application-locally)

---

## 1. How I Approached an Unfamiliar Project

When I first got this project, I didn't know anything about it. The first thing I had to figure out was: what kind of project is this, and how do I run it? Here is the mental process I followed:

**Step 1: Look at the top-level folders.**
The root contained `client/`, `server/`, `database/`, and `docs/`. That immediately told me:
- There is a frontend (`client/`)
- There is a backend (`server/`)
- There is a database layer (`database/`)

**Step 2: Look at the `package.json` files.**
Each `package.json` tells you the dependencies and scripts. I looked at `client/package.json` and saw Webpack, Babel, and React. That told me the frontend is a React app built with a custom Webpack setup (not Create React App). I looked at `server/package.json` and saw Express, mysql2, dotenv, and cors. That told me the backend is an Express server that connects to MySQL.

**Step 3: Find the entry points.**
Every project has entry points — the files where execution starts. For the frontend, the Webpack entry point is `src/index.js`. For the backend, `server.js` is the main file (it's listed as `"main": "server.js"` in `package.json`).

**Step 4: Read `server.js` carefully.**
This is the most important file for understanding how the whole app works. It revealed that Express serves the React build files as static assets, which told me this is a monolithic 2-tier setup, not a 3-tier one.

**Step 5: Understand what is generated vs what is written.**
Not every file/folder in a project is hand-written. Some are generated automatically by tools. Understanding which is which is critical before Dockerizing or committing to Git.

---

## 2. Project Structure (Current)

This is the current state of the repo after my cleanup (the `dist/` folder has been removed — more on that below):

```plaintext
.
├── .env.example              # Template showing required environment variables
├── .gitignore                # Tells Git what NOT to track
├── README.md
├── client/                   # Frontend (React + Webpack)
│   ├── .babelrc              # Babel transpiler config
│   ├── package.json          # Frontend dependencies and scripts
│   ├── webpack.config.js     # Webpack build configuration
│   ├── public/               # BUILD OUTPUT — generated by `npm run build`
│   │   ├── bundle.js         # All React code compiled into one file
│   │   ├── bundle.js.LICENSE.txt
│   │   ├── index.html        # HTML shell with <div id="root">
│   │   ├── style.css
│   │   └── c592f33a...png    # Hashed asset filename
│   └── src/                  # SOURCE CODE — this is what you write
│       ├── index.js          # React entry point (renders <App/>)
│       ├── App.js            # Root React component
│       ├── App.css
│       ├── Youtube_Banner.png
│       ├── api/
│       │   └── users.js      # API call functions (fetch to backend)
│       └── components/
│           ├── UserItem.js
│           └── UsersList.js
├── database/
│   └── init.sql              # SQL to create the `users` table
├── docs/                     # Documentation
└── server/                   # Backend (Express + MySQL)
    ├── .env                  # NOT committed — you create this manually
    ├── package.json
    └── server.js             # Main entry point — runs the whole app
```

> **Note:** `node_modules/` appears in both `client/` and `server/` after running `npm install`, but it is listed in `.gitignore` and is never committed.

---

## 3. Understanding the Architecture

### Why This Is 2-Tier, Not 3-Tier

A proper 3-tier architecture has three independently running processes:
1. A **frontend server** (e.g., Nginx serving React static files)
2. A **backend API server** (e.g., Express handling business logic)
3. A **database** (e.g., MySQL)

This project has only **two** independently running processes:
1. The **Express server** — which handles BOTH the API routes AND serves the React frontend as static files
2. The **MySQL database**

This is the key line in `server.js` that makes it 2-tier:

```js
// server.js
app.use(express.static(path.join(__dirname, '../client/public')));
```

Express is serving the compiled React files directly. There is no Nginx, no separate frontend container, no separate process. The Express server is a monolith that does everything. This is a **monolithic 2-tier application**.

I later built a proper 3-tier version of this project in a separate repo where the frontend and backend are decoupled.

### How the Two Tiers Work Together

```
Browser
  │
  │  HTTP request to localhost:5000
  ▼
┌─────────────────────────────────────────┐
│           Express Server (Tier 1)        │
│                                         │
│  GET /          → serves index.html      │
│  GET /bundle.js → serves bundle.js       │
│  GET /api/users → queries MySQL          │
│  POST /api/users → inserts into MySQL    │
└─────────────────────────────────────────┘
  │
  │  SQL queries
  ▼
┌─────────────────┐
│  MySQL (Tier 2) │
│  Database: test_db│
│  Table: users   │
└─────────────────┘
```

The React app runs **in the browser**. It is not a separate server. When the browser opens `http://localhost:5000`, Express responds with `index.html`, which loads `bundle.js`, which boots the React UI. The React UI then makes API calls back to the same Express server at `/api/users`.

---

## 4. Frontend Deep Dive (`client/`)

### `src/` — Where You Write Code

This is the only folder you ever manually edit in the frontend. It contains:

- **`index.js`** — The React entry point. Webpack starts here and follows all `import` statements to bundle everything.
  ```js
  import React from 'react';
  import ReactDOM from 'react-dom';
  import App from './App';
  ReactDOM.render(<App />, document.getElementById('root'));
  ```

- **`App.js`** — The root React component. Renders the `UsersList` component.

- **`api/users.js`** — All HTTP calls to the backend live here. Functions like `fetchUsers()`, `createUser()`, `deleteUser()` use the browser's `fetch()` API to call `/api/users` on the Express server.

- **`components/UsersList.js`** and **`components/UserItem.js`** — Reusable UI components. `UsersList` fetches all users and renders a list of `UserItem` components.

### `webpack.config.js` — The Build Tool

This project uses a **custom Webpack setup**, not Create React App. The `webpack.config.js` file is the build instructions:

```js
module.exports = {
  mode: 'production',
  entry: './src/index.js',       // Start here
  output: {
    filename: 'bundle.js',
    path: path.resolve(__dirname, 'public'),  // Output goes to public/
  },
  // ... loaders for CSS, images, JS (via babel-loader)
};
```

The critical line is `path: path.resolve(__dirname, 'public')`. This means when you run `npm run build`, Webpack compiles everything starting from `src/index.js` and writes the result as `client/public/bundle.js`. **The output directory is `public/`, not `dist/`.**

This is why after running the build, `client/public/` contains:
- `bundle.js` — the entire React app compiled into one file
- `bundle.js.LICENSE.txt` — auto-generated license info
- `index.html` — the HTML shell (hand-written, not generated)
- `style.css` — the stylesheet (hand-written)

### `.babelrc` — The Transpiler Config

Babel transpiles modern JavaScript and JSX into browser-compatible JavaScript. The `.babelrc` file tells Babel which rules to use:

```json
{
  "presets": ["@babel/preset-env", "@babel/preset-react"]
}
```

- **`@babel/preset-env`** — Converts modern ES6+ syntax (arrow functions, `const`, etc.) into older syntax that more browsers support.
- **`@babel/preset-react`** — Converts JSX (React's `<Component />` syntax) into plain `React.createElement()` calls that browsers understand.

Without `.babelrc`, Webpack's `babel-loader` would not know how to process `.js` files and the build would fail. This file must not be deleted — it will not auto-regenerate.

### `public/` — The Build Output

The `public/` folder is the **build output directory**. Its contents are generated by running:

```bash
cd client
npm run build
```

I want to be clear about something I was confused about early on: the name `public` or `dist` is not a standard — **the name is whatever the developer wrote in `webpack.config.js`**. In this project, the developer wrote `path.resolve(__dirname, 'public')`, so Webpack outputs to `public/`. Another project might write `path.resolve(__dirname, 'dist')` and output to `dist/` instead. The name is arbitrary. What matters is what the code says.

**What lives in `public/` and why:**

| File | Hand-written or Generated? | Purpose |
|---|---|---|
| `index.html` | Hand-written | HTML shell; has `<div id="root">` where React mounts |
| `style.css` | Hand-written | Global styles |
| `bundle.js` | **Generated** by Webpack | Compiled React app |
| `bundle.js.LICENSE.txt` | **Generated** by Webpack | License info for bundled libraries |
| `*.png` (hashed filename) | **Generated** by Webpack | Image assets processed by url-loader |

The `index.html` and `style.css` in `public/` are source files that you write. The `bundle.js` is generated. You must run `npm run build` before the backend can serve a working frontend.

### The `dist/` Folder — Why It Existed and Why I Deleted It

When I first cloned this repo, there was a `dist/` folder inside `client/` containing `bundle.js`, `bundle.js.LICENSE.txt`, and `index.html`. I was confused because the `webpack.config.js` clearly outputs to `public/`, not `dist/`.

What happened: the original developer had at some point configured Webpack to output to `dist/` (which is a very common convention), ran the build, committed that output to Git, and then later changed the Webpack config to output to `public/` — but never deleted the old `dist/` folder from the repo.

The `dist/` folder was stale build output from an old configuration. It had no effect on the running application since `server.js` serves from `client/public`, not `client/dist`. I deleted it to remove the confusion.

**Key lesson:** Build output folders (`dist/`, `public/bundle.js`, etc.) should generally be in `.gitignore` and not committed to Git. They are generated artifacts, not source code. However, in this project the `public/` folder contains both hand-written files (`index.html`, `style.css`) and generated files (`bundle.js`), which makes it trickier.

---

## 5. Backend Deep Dive (`server/`)

### `server.js` — Entry Point

This is the single most important file in the entire project. Reading it carefully tells you everything about how the app works:

```js
require('dotenv').config();  // Load .env file
const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');
const path = require('path');

const app = express();
const port = process.env.PORT || 5000;

app.use(cors());
app.use(bodyParser.json());

// --- Database connection ---
const db = mysql.createConnection({
  host: process.env.DB_HOST,
  user: process.env.MYSQL_USER,
  password: process.env.MYSQL_PASSWORD,
  database: process.env.MYSQL_DATABASE,
});

db.connect((err) => {
  if (err) { console.error('Database connection failed:', err); process.exit(1); }
  console.log('Database connected.');
});

// --- API Routes ---
app.get('/api/users', (req, res) => { ... });
app.post('/api/users', (req, res) => { ... });
app.put('/api/users/:id', (req, res) => { ... });
app.delete('/api/users/:id', (req, res) => { ... });

// --- Serve React frontend ---
app.use(express.static(path.join(__dirname, '../client/public')));
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../client/public', 'index.html'));
});

app.listen(port, () => console.log(`Server is running on http://localhost:${port}`));
```

Notice there is no separate `app.js` or `config/db.js` in the current version — the original forked code had those files, but in this simplified monolithic version everything lives in `server.js`. The database connection, all four CRUD routes, and the static file serving are all in one place.

### `package.json`

```json
{
  "name": "server",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.21.2",
    "mysql2": "^3.11.3",
    "dotenv": "^16.4.7"
  }
}
```

Note the dependency is `mysql2`, not `mysql`. The old `mysql` package does not support MySQL 8's authentication protocol. I updated it to `mysql2@3.11.3`. See `docs/local-setup-troubleshooting.md` for the full story.

### How Express Serves Both API and Frontend

Express processes routes **in order**. So:
1. A request to `GET /api/users` matches the API route first and returns JSON.
2. A request to `GET /` or any other non-API path falls through to `express.static(...)`, which looks for a matching file in `client/public/`.
3. If no file is found, the catch-all `app.get('*', ...)` sends back `index.html`, which lets React Router handle the navigation client-side.

This ordering is what makes it a monolith — one server handling everything.

---

## 6. Database (`database/`)

The `database/init.sql` file creates the `users` table:

```sql
CREATE TABLE IF NOT EXISTS users (
  id    INT AUTO_INCREMENT PRIMARY KEY,
  name  VARCHAR(100) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  role  VARCHAR(50)
);
```

This file is used in two ways:
- **Locally**: Run it manually in MySQL after creating the database.
- **In Docker**: Mounted as a volume at `/docker-entrypoint-initdb.d/init.sql` so MySQL auto-runs it on first startup.

The backend requires the `test_db` database and `users` table to exist before starting. The credentials are loaded from the `.env` file at the project root.

---

## 7. Build Process — What Generates What

This is the clearest summary of what gets created by which command:

| Folder / File | How It Gets Created | Committed to Git? |
|---|---|---|
| `client/src/` | Written by hand | ✅ Yes |
| `client/public/index.html` | Written by hand | ✅ Yes |
| `client/public/style.css` | Written by hand | ✅ Yes |
| `client/public/bundle.js` | Generated by `npm run build` (Webpack) | ✅ Yes (in this repo) |
| `client/public/*.png` (hashed) | Generated by Webpack's url-loader | ✅ Yes (in this repo) |
| `client/node_modules/` | Generated by `npm install` | ❌ No (in .gitignore) |
| `server/node_modules/` | Generated by `npm install` | ❌ No (in .gitignore) |
| `.env` | Created manually on each machine | ❌ No (in .gitignore) |

The general rule: **if a file is produced by running a command, it should be in `.gitignore`.** However, this project commits the Webpack output (`public/bundle.js`) because the React source requires a build step that not everyone may want to run. This is a tradeoff — it makes cloning and running easier but mixes source and generated files.

---

## 8. The `bundle.js.LICENSE.txt` File

When Webpack bundles JavaScript libraries like React and ReactDOM, it extracts all license headers from those libraries and writes them into a separate file called `bundle.js.LICENSE.txt`. This happens automatically during the build.

It contains text like:
```
/** @license React v18.x
 * MIT License
 * Copyright (c) Meta Platforms, Inc. ...
 */
```

You should not delete this file in production because it satisfies open-source license requirements for the libraries bundled into your app. In development, it doesn't matter. It is safe to add to `.gitignore` if you don't want it in the repo, since it will regenerate on every build.

---

## 9. Dockerization

### Understanding What Needs to Be Containerized

Since this is a 2-tier app, there are only two services to containerize:
1. **The Node.js/Express server** (which also serves the built React frontend)
2. **The MySQL database**

Before building the Docker image for the backend, the React app must be built first (so `client/public/bundle.js` exists). The Express server then serves those static files.

### Single-Stage Dockerfile (Simple)

The simplest approach — one image builds both frontend and backend:

```dockerfile
FROM node:18-alpine

WORKDIR /app

# Install frontend dependencies and build
COPY client/package*.json ./client/
RUN npm install --prefix client
COPY client ./client
RUN npm run build --prefix client

# Install backend dependencies
COPY server/package*.json ./server/
RUN npm install --prefix server
COPY server ./server

EXPOSE 5000

WORKDIR /app/server
CMD ["node", "server.js"]
```

**Pros:** Simple, one Dockerfile.  
**Cons:** Large image (~400MB+); Node.js stays in image even though it's only needed for the build step.

### Multi-Stage Dockerfile (Efficient)

Uses two stages: one to build the React app, one to run the Express server. The Node.js build tools don't end up in the final image:

```dockerfile
# ---- Stage 1: Build React frontend ----
FROM node:18-alpine AS frontend-builder
WORKDIR /app
COPY client/package*.json ./
RUN npm install
COPY client ./
RUN npm run build
# Output is now in /app/public/

# ---- Stage 2: Run Express backend ----
FROM node:18-alpine
WORKDIR /app
COPY server/package*.json ./
RUN npm install --omit=dev
COPY server ./
# Copy the built frontend from Stage 1
COPY --from=frontend-builder /app/public ./client/public

EXPOSE 5000
CMD ["node", "server.js"]
```

**Pros:** Smaller final image; clean separation of build vs runtime.  
**Cons:** Slightly more complex.

### `docker-compose.yml` (Full Stack)

This orchestrates both the backend and MySQL database together:

```yaml
version: '3.8'

services:
  backend:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "5000:5000"
    environment:
      DB_HOST: db
      MYSQL_USER: your_username
      MYSQL_PASSWORD: your_password
      MYSQL_DATABASE: test_db
      PORT: 5000
    depends_on:
      - db

  db:
    image: mysql:8
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_USER: your_username
      MYSQL_PASSWORD: your_password
      MYSQL_DATABASE: test_db
    volumes:
      - db_data:/var/lib/mysql
      - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "3306:3306"

volumes:
  db_data:
```

Key points:
- `DB_HOST: db` — inside Docker Compose, services communicate by their service name, not `localhost`.
- The `init.sql` volume mount means MySQL will automatically create the `users` table on first startup.
- `depends_on` ensures MySQL starts before the backend, though it doesn't wait for MySQL to be fully ready — a health check or retry logic in the app is better practice for production.

**To build and run:**
```bash
docker-compose up --build
```

**Access the app:** `http://localhost:5000`

---

## 10. Running the Application Locally

### Prerequisites
- Node.js v18+
- MySQL 8.x running locally
- A `.env` file in the **project root**

### Step 1: Set up MySQL

```sql
CREATE DATABASE test_db;
CREATE USER 'your_username'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON test_db.* TO 'your_username'@'localhost';
FLUSH PRIVILEGES;
USE test_db;
SOURCE database/init.sql;
```

### Step 2: Create the `.env` file in the project root

```env
DB_HOST=localhost
MYSQL_USER=your_username
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=test_db
PORT=5000
```

### Step 3: Build the frontend

```bash
cd client
npm install
npm run build
cd ..
```

This generates `client/public/bundle.js`.

### Step 4: Install backend dependencies

```bash
cd server
npm install
cd ..
```

### Step 5: Start the server (from project root)

```bash
node server/server.js
```

> **Important:** Run this from the **project root**, not from inside `server/`. The `.env` file is in the root, and `dotenv` looks for it relative to the current working directory. Running from inside `server/` will cause the env vars to not load. See `docs/local-setup-troubleshooting.md` for full details.

**App is now running at:** `http://localhost:5000`
