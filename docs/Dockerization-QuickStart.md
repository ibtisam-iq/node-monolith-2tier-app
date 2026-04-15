# Dockerization of this Project

## Table of Contents
1. [Project Structure](#project-structure)
2. [Frontend (React)](#frontend-react)
3. [Backend (Node.js with Express)](#backend-nodejs-with-express)
4. [Database (MySQL)](#database-mysql)
5. [Dockerization](#dockerization)
   - [Dockerfile for Frontend](#dockerfile-for-frontend)
   - [Dockerfile for Backend](#dockerfile-for-backend)
   - [Docker Compose Configuration](#docker-compose-configuration)
6. [Running the Application](#running-the-application)

## Project Structure

### `tree -a`
```plaintext
.
├── client
│   ├── .babelrc
│   ├── dist
│   │   ├── bundle.js
│   │   ├── bundle.js.LICENSE.txt
│   │   └── index.html
│   ├── package.json
│   ├── public
│   │   ├── bundle.js
│   │   ├── bundle.js.LICENSE.txt
│   │   ├── c592f33a595971f260033277055bfd43.png
│   │   ├── index.html
│   │   └── style.css
│   ├── src
│   │   ├── api
│   │   │   └── users.js
│   │   ├── App.css
│   │   ├── App.js
│   │   ├── components
│   │   │   ├── UserItem.js
│   │   │   └── UsersList.js
│   │   ├── index.js
│   │   └── Youtube_Banner.png
│   └── webpack.config.js
├── database
│   └── init.sql
└── server
    ├── app.js
    ├── config
    │   └── db.js
    ├── controllers
    │   └── userController.js
    ├── models
    │   └── userModel.js
    ├── package.json
    ├── routes
    │   ├── userRoutes.js
    │   └── users.js
    └── server.js
```

## Analysis of this 3-Tier Application

Your project consists of:

1. **Frontend (React)**
    - Located in the **`client/`** directory.
    - Built using Webpack (`webpack.config.js`).
    - Outputs static files (`dist/bundle.js`).

2. **Backend (Node.js with Express)**
    - Located in the **`server/`** directory.
    - Handles API requests and business logic.

3. **Database (MySQL)**
    - Initialization script located in the **`database/`** directory (`init.sql`).

## Dockerization

### Dockerfile for Frontend

Create a `Dockerfile` in the `client/` directory:

```dockerfile
# Use official Node.js image as the base
FROM node:14-alpine

# Set working directory
WORKDIR /app

# Copy package.json and install dependencies
COPY package.json ./
RUN npm install

# Copy the rest of the application
COPY . .

# Build the React app
RUN npm run build

# Use Nginx to serve the static files
FROM nginx:alpine
COPY --from=0 /app/dist /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
```

### Dockerfile for Backend

Create a `Dockerfile` in the `server/` directory:

```dockerfile
# Use official Node.js image as the base
FROM node:14

# Set working directory
WORKDIR /app

# Copy package.json and install dependencies
COPY package.json ./
RUN npm install

# Copy the rest of the application
COPY . .

# Expose port 3000
EXPOSE 3000

# Start the application
CMD ["node", "server.js"]
```

### Docker Compose Configuration

Create a `docker-compose.yml` file in the root directory:

```yaml
version: '3.8'

services:
  frontend:
    build:
      context: ./client
    ports:
      - "80:80"

  backend:
    build:
      context: ./server
    ports:
      - "3000:3000"
    environment:
      - DB_HOST=db
      - DB_USER=root
      - DB_PASSWORD=password
      - DB_NAME=users_db
    depends_on:
      - db

  db:
    image: mysql:5.7
    environment:
      MYSQL_ROOT_PASSWORD: password
      MYSQL_DATABASE: users_db
    volumes:
      - db_data:/var/lib/mysql

volumes:
  db_data:
```

## Running the Application

### Build and Start the Containers

```bash
docker-compose up --build
```

### Access the Application

- Frontend: `http://localhost`
- Backend: `http://localhost:3000`

### Environment Variables

Ensure sensitive information like database credentials are managed using environment variables.

---

## Summary

- **Frontend**: Dockerized using Node.js and Nginx.
- **Backend**: Dockerized using Node.js.
- **Database**: Managed using MySQL Docker image.
- **Docker Compose**: Used to orchestrate the services.

## Reference

You can find in-depth information [here](Dockerization.md).

