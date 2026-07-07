# Phase 3 — Dockerfiles: Complete Code Explanation

> **Target Audience:** Junior DevOps Team (assumes basic terminal knowledge, but NO Docker experience)
>
> **Goal:** Understand what Docker is, why we use multi-stage builds, what every line in both Dockerfiles means, and how DockerHub works — so you can explain it to instructors and understand the CI/CD pipeline in Phase 4.

---

## Table of Contents

1. [What is Docker?](#1-what-is-docker)
2. [What is a Dockerfile?](#2-what-is-a-dockerfile)
3. [Why multi-stage builds?](#3-why-multi-stage-builds)
4. [Frontend Dockerfile](#4-frontend-dockerfile-inventory-frontend)
   - [Line-by-line breakdown](#41-frontend-dockerfile-line-by-line)
   - [The nginx.conf file](#42-the-nginxconf-file)
5. [Backend Dockerfile](#5-backend-dockerfile-inventory-backend)
   - [Line-by-line breakdown](#51-backend-dockerfile-line-by-line)
6. [docker-compose.yml explained](#6-docker-composeyml-explained)
7. [How DockerHub fits in](#7-how-dockerhub-fits-in)
8. [From Phase 3 to Phase 4 (CI/CD)](#8-from-phase-3-to-phase-4-cicd)

---

## 1. What is Docker?

### The problem Docker solves

Imagine you wrote a Python app on your Windows laptop. It works perfectly. You send it to your friend who uses a Mac. It crashes. Why? Maybe your friend doesn't have Python installed. Or has a different version. Or a different library.

**Docker solves "it works on my machine" by packaging your application with EVERYTHING it needs to run:**

```
┌─────────────────────────────────┐
│        Docker Container         │
│  ┌───────────────────────────┐  │
│  │   Your Application        │  │
│  │   (compiled code, files)  │  │
│  ├───────────────────────────┤  │
│  │   Runtime                 │  │
│  │   (Node.js, .NET, etc.)   │  │
│  ├───────────────────────────┤  │
│  │   Operating System        │  │
│  │   (Alpine Linux, Ubuntu)  │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**Key terms:**

| Term | What it is | Analogy |
|---|---|---|
| **Dockerfile** | A recipe for building an image | A cooking recipe |
| **Docker Image** | The built, ready-to-run package | A frozen pizza |
| **Docker Container** | A running instance of an image | The pizza after you bake it |
| **DockerHub** | A website to share images | A supermarket for frozen pizzas |

### Our two images:

| Image | What's inside | Runs when deployed |
|---|---|---|
| `inventory-frontend` | Angular compiled files + Nginx web server | Serves the web app to users |
| `inventory-backend` | .NET 8 compiled DLLs + ASP.NET runtime | Handles API requests, talks to SQL Server |

---

## 2. What is a Dockerfile?

A **Dockerfile** is a text file with instructions for building a Docker image. Each instruction creates a "layer" in the image. Think of it like building a sandwich layer by layer.

### Common Dockerfile instructions:

| Instruction | What it does | Sandwich analogy |
|---|---|---|
| `FROM` | Start from an existing base image | Start with a slice of bread |
| `WORKDIR` | Set the working directory (like `cd`) | Clear your workspace |
| `COPY` | Copy files from your computer into the image | Add ingredients |
| `RUN` | Run a command during build (install packages, compile code) | Toast the bread |
| `EXPOSE` | Document which port the app will use | Put a label on the box |
| `CMD` or `ENTRYPOINT` | Command to run when the container starts | "Turn on the oven" |

---

## 3. Why multi-stage builds?

### The problem

Building applications requires **build tools** that you DON'T need at runtime:

| Stage | Needs | Example size |
|---|---|---|
| **Build** | Node.js, npm, TypeScript compiler, all source code | ~1.5 GB |
| **Runtime** | Just Nginx and compiled HTML/CSS/JS files | ~50 MB |

If you used only one stage, your Docker image would be **huge** because it would include:
- The Node.js SDK
- Source code (proprietary!)
- Npm packages (thousands of files)
- Build artifacts

### The solution: Multi-stage

A multi-stage build has **two FROM instructions**. The first stage builds the app, the second stage copies ONLY the compiled output:

```
┌─ Stage 1: "build" ──────────────────────────────┐
│                                                  │
│  FROM node:20-alpine AS build                    │
│  WORKDIR /app                                    │
│  COPY package*.json ./                           │
│  RUN npm install                                 │
│  COPY . .                                        │
│  RUN npm run build                               │
│                                                  │
│  Output: /app/dist/inventory-app/browser/        │
│  (compiled HTML/CSS/JS files)                    │
└──────────────────────────────────────────────────┘
                         │
                         │ COPY --from=build
                         ▼
┌─ Stage 2: "final" ───────────────────────────────┐
│                                                   │
│  FROM nginx:alpine                                │
│  COPY --from=build ... /usr/share/nginx/html      │
│                                                   │
│  Only Nginx + static files = ~50 MB               │
└───────────────────────────────────────────────────┘
```

**Result:** The final image is tiny because it only contains what's needed to RUN the app, not to BUILD it.

---

## 4. Frontend Dockerfile (`Frontend/Dockerfile`)

```dockerfile
# Build stage
FROM node:20-alpine AS build
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of the application code
COPY . .

# Build the Angular application
RUN npm run build -- --configuration=production

# Production stage using Nginx
FROM nginx:alpine
COPY --from=build /app/dist/inventory-app/browser /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### 4.1 Frontend Dockerfile line-by-line:

#### Stage 1: Build

```dockerfile
FROM node:20-alpine AS build
```

| Part | What it does |
|---|---|
| `FROM` | Start building FROM a base image |
| `node:20-alpine` | Official Node.js version 20 on Alpine Linux (a tiny Linux distro, ~50MB) |
| `AS build` | Name this stage "build" so we can reference it later with `--from=build` |

**Why Alpine?** Alpine Linux is extremely small (~5MB) compared to Ubuntu (~200MB). Every megabyte matters when you're pulling images across the internet.

---

```dockerfile
WORKDIR /app
```

| Part | What it does |
|---|---|
| `WORKDIR` | Create and change to this directory |
| `/app` | All subsequent commands run inside `/app` inside the container |

Equivalent to `mkdir /app && cd /app`. This keeps everything organized.

---

```dockerfile
COPY package*.json ./
```

| Part | What it does |
|---|---|
| `COPY` | Copy files from your HOST machine into the container |
| `package*.json` | Copy files matching the pattern: `package.json` and `package-lock.json` |
| `./` | Copy them to the current WORKDIR (`/app`) |

**Why copy these files FIRST, before the source code?**

This is a **Docker layer caching optimization**. Docker builds images in layers. Each `COPY` or `RUN` creates a layer. If you change a file, only layers AFTER that file need to be rebuilt.

```
Option A (inefficient):           Option B (efficient):
COPY . .      ← changes often     COPY package*.json ./   ← rarely changes
RUN npm install  ← SLOW rebuild   RUN npm install         ← cached! Uses layer cache
                                  COPY . .                ← changes often, fast copy
```

By copying `package.json` first and running `npm install`, Docker caches that layer. As long as you don't add/remove dependencies, `npm install` is skipped on future builds, saving **minutes** each time.

---

```dockerfile
RUN npm install
```

| Part | What it does |
|---|---|
| `RUN` | Execute a shell command during the image build |
| `npm install` | Install all dependencies listed in `package.json` into `node_modules/` |

This downloads hundreds of JavaScript packages from npm registry. They include Angular, TypeScript, etc. (all the build tools, not needed at runtime).

---

```dockerfile
COPY . .
```

Now copy the rest of the application source code (components, templates, styles, etc.). This runs fast because `npm install` is already cached.

**Note:** The `.dockerignore` file (if it exists in the project) tells Docker which files to SKIP when copying. `node_modules` should be in `.dockerignore` since we already installed them via `npm install`.

---

```dockerfile
RUN npm run build -- --configuration=production
```

| Part | What it does |
|---|---|
| `npm run build` | Execute the "build" script defined in Angular's `package.json` |
| `--configuration=production` | Build for production (minifies code, removes debug info, enables optimizations) |
| Output: `/app/dist/inventory-app/browser/` | Compiled HTML, CSS, JS files ready to be served |

This is the **core build step** — TypeScript is compiled to JavaScript, Angular templates are compiled to HTML, CSS is minified, and all files are bundled together.

#### Stage 2: Runtime (the actual image we'll deploy)

```dockerfile
FROM nginx:alpine
```

Start a NEW stage from `nginx:alpine` — the official Nginx web server on Alpine Linux. This is a clean slate; nothing from the build stage carries over unless we explicitly copy it.

---

```dockerfile
COPY --from=build /app/dist/inventory-app/browser /usr/share/nginx/html
```

| Part | What it does |
|---|---|
| `COPY --from=build` | Copy FROM the stage called "build" (not from the host machine) |
| `/app/dist/inventory-app/browser` | The compiled output from the build stage |
| `/usr/share/nginx/html` | Nginx's default directory for serving web files |

**This is the KEY line of the multi-stage build.** We take only the compiled output (no Node.js, no npm, no source code) and put it where Nginx can serve it.

---

```dockerfile
COPY nginx.conf /etc/nginx/conf.d/default.conf
```

| Part | What it does |
|---|---|
| `COPY nginx.conf` | Copy our custom Nginx config from the host |
| `/etc/nginx/conf.d/default.conf` | Nginx's configuration directory. This file REPLACES the default config |

We need a custom config because Angular is a **Single Page Application (SPA)**. When a user refreshes on `/products`, the browser sends a request to Nginx for `/products`, but the file doesn't exist (Angular handles routing client-side). The `try_files` directive in `nginx.conf` tells Nginx: "If the file doesn't exist, fall back to `index.html` and let Angular handle the routing."

---

```dockerfile
EXPOSE 80
```

| Part | What it does |
|---|---|
| `EXPOSE` | Documentation only — tells humans and tools that this container listens on port 80 |
| `80` | Port 80 is the default HTTP port |

**Note:** `EXPOSE` does NOT actually publish the port. It's metadata. To actually make the port accessible, you need to run the container with `-p 8080:80` (maps host port 8080 to container port 80) — or in Kubernetes, the Service handles this.

---

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

| Part | What it does |
|---|---|
| `CMD` | The command to run when the container starts |
| `["nginx", "-g", "daemon off;"]` | Start Nginx in the foreground (daemon off = don't run in background) |

**Why "daemon off"?** Docker containers stop when the main process exits. If Nginx runs as a daemon (background), it "exits" immediately and the container dies. By running in the foreground, Nginx stays alive and so does the container.

---

### 4.2 The `nginx.conf` file

```nginx
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files $uri $uri/ /index.html;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
```

| Line | What it does |
|---|---|
| `server {` | Define a virtual server block |
| `listen 80;` | Listen on port 80 for HTTP traffic |
| `server_name localhost;` | Respond to requests for "localhost" (this will be overridden by the LoadBalancer) |
| `location / {` | Configuration for the root path (`/`) |
| `root /usr/share/nginx/html;` | Serve files from this directory (where we copied our Angular build) |
| `index index.html index.htm;` | When someone visits `/`, serve `index.html` |
| `try_files $uri $uri/ /index.html;` | **Angular SPA magic**: If the request is for `/products` and that file doesn't exist, serve `/index.html` instead. Angular reads the URL and shows the products page |
| `error_page 500 502 503 504 /50x.html;` | Show a friendly error page for server errors |

---

## 5. Backend Dockerfile (`Backend/Dockerfile`)

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy csproj files and restore dependencies
COPY ["InventoryManagement.API/InventoryManagement.API.csproj", "InventoryManagement.API/"]
COPY ["InventoryManagement.Repository/InventoryManagement.Repository.csproj", "InventoryManagement.Repository/"]
COPY ["InventoryManagement.Service/InventoryManagement.Service.csproj", "InventoryManagement.Service/"]
RUN dotnet restore "InventoryManagement.API/InventoryManagement.API.csproj"

# Copy the remaining files
COPY . .

# Build and publish
WORKDIR "/src/InventoryManagement.API"
RUN dotnet publish "InventoryManagement.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
COPY --from=build /app/publish .

# Expose port 5097
ENV ASPNETCORE_URLS=http://+:5097
EXPOSE 5097

ENTRYPOINT ["dotnet", "InventoryManagement.API.dll"]
```

### 5.1 Backend Dockerfile line-by-line:

#### Stage 1: Build

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
```

| Part | What it does |
|---|---|
| `mcr.microsoft.com/` | Microsoft's container registry (MCR is Microsoft's DockerHub-equivalent) |
| `dotnet/sdk:8.0` | The .NET 8 SDK — includes compilers, MSBuild, NuGet — everything needed to BUILD .NET apps |

**Why `mcr.microsoft.com`?** Microsoft hosts their official .NET images on their own registry, not DockerHub. `mcr.microsoft.com/dotnet/sdk` is the same as `dotnet/sdk` on DockerHub.

---

```dockerfile
WORKDIR /src
```

Set the working directory to `/src` inside the container. All subsequent commands will run here.

---

```dockerfile
COPY ["InventoryManagement.API/InventoryManagement.API.csproj", "InventoryManagement.API/"]
COPY ["InventoryManagement.Repository/InventoryManagement.Repository.csproj", "InventoryManagement.Repository/"]
COPY ["InventoryManagement.Service/InventoryManagement.Service.csproj", "InventoryManagement.Service/"]
```

| Part | What it does |
|---|---|
| `COPY` with brackets | Dockerfile syntax using `["source", "destination"]` — needed when paths have spaces (though ours don't) |
| `InventoryManagement.API.csproj` | The project file that lists dependencies (NuGet packages) |
| Destination `InventoryManagement.API/` | Creates the directory structure matching the source |

**Why copy `.csproj` files individually?** Same caching optimization as the frontend. By copying only the project files first and running `dotnet restore`, we cache the NuGet package downloads. If only source code changes (not dependencies), the restore step is skipped.

---

```dockerfile
RUN dotnet restore "InventoryManagement.API/InventoryManagement.API.csproj"
```

| Part | What it does |
|---|---|
| `dotnet restore` | Downloads all NuGet packages referenced in the `.csproj` files |
| It's like `npm install` but for .NET |

Running restore on just the API project also transitively restores the Repository and Service projects since they're dependencies.

---

```dockerfile
COPY . .
```

Now copy ALL the remaining source code (`.cs`, `.json`, etc.). This layer changes frequently but is small, so it's fast to rebuild.

---

```dockerfile
WORKDIR "/src/InventoryManagement.API"
RUN dotnet publish "InventoryManagement.API.csproj" -c Release -o /app/publish /p:UseAppHost=false
```

| Part | What it does |
|---|---|
| `WORKDIR "/src/InventoryManagement.API"` | Change to the API project directory |
| `dotnet publish` | Compile and package the application |
| `-c Release` | Build in Release mode (optimized, no debug symbols) |
| `-o /app/publish` | Output the published files to `/app/publish` |
| `/p:UseAppHost=false` | Don't create a native executable; just output DLL files (needed for `dotnet run`) |

The output is a set of `.dll` files (compiled C#) and a `.json` config file that the .NET runtime can execute.

#### Stage 2: Runtime

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
```

| Part | What it does |
|---|---|
| `dotnet/aspnet:8.0` | The ASP.NET Core runtime — includes everything needed to RUN a .NET web app, but NOT the SDK (no compilers, no build tools). Much smaller (~200MB vs ~1.2GB for the SDK) |

---

```dockerfile
WORKDIR /app
COPY --from=build /app/publish .
```

Set the working directory to `/app` and copy the published output from the build stage. The `.` means "copy into `/app`" (the current WORKDIR).

---

```dockerfile
ENV ASPNETCORE_URLS=http://+:5097
EXPOSE 5097
```

| Part | What it does |
|---|---|
| `ENV` | Set an environment variable inside the container |
| `ASPNETCORE_URLS=http://+:5097` | Tell ASP.NET Core to listen on port 5097 on ALL network interfaces (`+` means "all IPs") |
| `EXPOSE 5097` | Document that this container uses port 5097 |

**Why `+`?** Without this, ASP.NET Core only listens on `localhost`, which means the container would be unreachable from outside. The `+` binds to `0.0.0.0` (all interfaces), making it accessible via the container's IP.

---

```dockerfile
ENTRYPOINT ["dotnet", "InventoryManagement.API.dll"]
```

| Part | What it does |
|---|---|
| `ENTRYPOINT` | The command that ALWAYS runs when the container starts (cannot be overridden like `CMD`) |
| `["dotnet", "InventoryManagement.API.dll"]` | Run `dotnet InventoryManagement.API.dll` — this starts the ASP.NET Core web server |

**Difference between `CMD` and `ENTRYPOINT`:**

| Instruction | Can be overridden? | Use case |
|---|---|---|
| `CMD ["nginx", "-g", "daemon off;"]` | Yes (by `docker run` args) | Default command, easy to replace |
| `ENTRYPOINT ["dotnet", "InventoryManagement.API.dll"]` | No (harder to override) | Always run the app, possibly with extra arguments |

---

## 6. docker-compose.yml explained

```yaml
services:
  db:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: inventory_db
    restart: always
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=YourSecurePassword123!
    ports:
      - "1433:1433"
    volumes:
      - mssql_data:/var/opt/mssql

  backend:
    image: inventory_backend:latest
    container_name: inventory_backend
    build:
      context: ./Backend
      dockerfile: Dockerfile
    restart: always
    environment:
      - ConnectionStrings__DefaultConnection=Server=db;Database=InventoryManagementDb;User Id=sa;Password=YourSecurePassword123!;MultipleActiveResultSets=true;TrustServerCertificate=True;
      - ASPNETCORE_ENVIRONMENT=Development
    ports:
      - "5097:5097"
    depends_on:
      - db

  frontend:
    image: inventory_frontend:latest
    container_name: inventory_frontend
    build:
      context: ./Frontend
      dockerfile: Dockerfile
    restart: always
    ports:
      - "4200:80"
    depends_on:
      - backend

volumes:
  mssql_data:
```

| Line | What it does |
|---|---|
| `services:` | Define all the applications that make up this project |
| `db:` | Service name (other services can reach it as hostname `db`) |
| `image: mcr.microsoft.com/mssql/server:2022-latest` | Use Microsoft's official SQL Server 2022 image |
| `build: context: ./Backend` | Build the Dockerfile in `./Backend` directory |
| `image: inventory_backend:latest` | Tag the built image as `inventory_backend:latest` |
| `ConnectionStrings__DefaultConnection=Server=db;...` | The connection string uses `Server=db` (the service name) to reach SQL Server. The double underscore `__` is how .NET maps environment variables to nested config sections (`ConnectionStrings:DefaultConnection`) |
| `depends_on: - db` | Start order: don't start backend before the database service starts. **Not a health check** — just container start order |
| `ports: "4200:80"` | Map host port 4200 to container port 80 (Nginx) |
| `volumes: mssql_data` | Persistent storage for SQL Server data files — survives container restarts |

**Connection string format:**
`Server=db;Database=InventoryManagementDb;User Id=sa;Password=xxxx;...`

| Part | Meaning |
|---|---|
| `Server=db` | The hostname `db` resolves to the SQL Server container (Docker's internal DNS) |
| `Database=InventoryManagementDb` | The database name to use |
| `User Id=sa` | SQL Server's system admin account |
| `Password=...` | The SA password |

### How docker-compose builds images:

```bash
docker compose up --build -d
```

1. Docker reads `docker-compose.yml`
2. Sees `build: context: ./Backend` → builds the Dockerfile in Backend/ → tags it as `inventory_backend:latest`
3. Sees `build: context: ./Frontend` → builds the Dockerfile in Frontend/ → tags it as `inventory_frontend:latest`
4. Sees `image: mcr.microsoft.com/mssql/server:2022-latest` → pulls it from Microsoft's registry
5. Starts all three containers in the order specified by `depends_on`

---

## 7. How DockerHub fits in

### What is DockerHub?

DockerHub is like GitHub but for Docker images. It's a registry where you can:
- **Push** your images (upload)
- **Pull** your images (download from anywhere)

### Image naming convention:

```
your-dockerhub-username / image-name : tag
─────────────────────   ───────────   ───
mohamedelshahaby      / inventory-frontend : latest
mohamedelshahaby      / inventory-backend  : v1.0.0
```

| Part | Meaning |
|---|---|
| `mohamedelshahaby` | Your DockerHub username (like a GitHub username) |
| `inventory-frontend` | The image name (like a repository name) |
| `latest` | A tag/label (like a Git tag). `latest` is the default |

### From local development to DockerHub:

**Local development (docker-compose):**
```
inventory_frontend:latest      ← simple name, only exists on your machine
inventory_backend:latest
```

**For Kubernetes deployment (CI/CD):**
```
mohamedelshahaby/inventory-frontend:latest   ← pushed to DockerHub
mohamedelshahaby/inventory-backend:latest     ← accessible from any server
```

### The commands you ran earlier:

```bash
# STEP 1: Tag the local image with your DockerHub username
docker tag inventory_frontend:latest mohamedelshahaby/inventory-frontend:latest

# STEP 2: Push to DockerHub
docker push mohamedelshahaby/inventory-frontend:latest
```

| Step | What happens |
|---|---|
| `docker tag` | Creates a new alias/reference to the existing image. The original `inventory_frontend:latest` still exists |
| `docker push` | Uploads the image layers to DockerHub. Anyone with the name can now `docker pull mohamedelshahaby/inventory-frontend:latest` |

### Step-by-step: Setting up DockerHub for your project

If you're setting up DockerHub for the first time (new team member or new account), follow these steps:

#### Step 1: Create a DockerHub Access Token
**Why not use your password?** Your password gives full access to your DockerHub account. An Access Token can be limited to specific permissions and can be revoked individually.

1. Go to https://hub.docker.com and sign in
2. Click your profile picture → **Account Settings**
3. Go to the **Security** tab
4. Click **New Access Token**
5. Give it a name: `jenkins-pipeline`
6. Select permissions: **Read, Write, Delete** (Jenkins needs all three to push new images)
7. Click **Generate**
8. **Copy the token immediately** — DockerHub will show it only once. If you lose it, you'll have to generate a new one.

#### Step 2: Login locally to test
```bash
docker login -u mohamedelshahaby
# Password: paste your ACCESS TOKEN, NOT your account password
```
Expected output: `Login Succeeded`

#### Step 3: Tag both images for DockerHub
```bash
docker tag inventory_frontend:latest mohamedelshahaby/inventory-frontend:latest
docker tag inventory_backend:latest  mohamedelshahaby/inventory-backend:latest
```

#### Step 4: Push both images
```bash
docker push mohamedelshahaby/inventory-frontend:latest
docker push mohamedelshahaby/inventory-backend:latest
```

#### Step 5: Verify on DockerHub
Open https://hub.docker.com/u/mohamedelshahaby in your browser — you should see two new repositories:
- `inventory-frontend`
- `inventory-backend`

#### Using the Access Token in Jenkins (Phase 4)
In the Jenkins pipeline, you won't use `docker login` with a password. Instead, Jenkins will use the **Access Token** as a secret credential:

```groovy
withCredentials([string(credentialsId: 'dockerhub-token', variable: 'DOCKER_TOKEN')]) {
    sh "docker login -u mohamedelshahaby -p $DOCKER_TOKEN"
    sh "docker push mohamedelshahaby/inventory-frontend:${BUILD_NUMBER}"
}
```

This way, the token is stored securely in Jenkins and never hardcoded in the pipeline script.

### Why we need DockerHub for EKS:

Your Kubernetes cluster runs on AWS. The nodes are in private subnets. They can't access your local machine's Docker images. By pushing to DockerHub, you make the images available from anywhere — including your EKS cluster.

In Phase 4 (CI/CD), Jenkins will:
1. Build the images from the source code
2. Tag them as `mohamedelshahaby/inventory-frontend:BUILD_NUMBER`
3. Push them to DockerHub
4. Update the Kubernetes deployment files with the new image tag
5. Run `kubectl apply` — which pulls the images from DockerHub

---

## 8. From Phase 3 to Phase 4 (CI/CD)

### What Jenkins will do with these Dockerfiles:

```
Jenkins Pipeline
       │
       ├── 1. Check out code from GitHub
       │
       ├── 2. Build Frontend image
       │       docker build -t mohamedelshahaby/inventory-frontend:${BUILD_NUMBER} ./Frontend
       │
       ├── 3. Build Backend image
       │       docker build -t mohamedelshahaby/inventory-backend:${BUILD_NUMBER} ./Backend
       │
       ├── 4. Push both images to DockerHub
       │       docker push mohamedelshahaby/inventory-frontend:${BUILD_NUMBER}
       │       docker push mohamedelshahaby/inventory-backend:${BUILD_NUMBER}
       │
       ├── 5. Update Kubernetes deployment files with new image tags
       │       sed 's|image:.*frontend.*|image: mohamedelshahaby/inventory-frontend:${BUILD_NUMBER}|'
       │
       └── 6. Deploy to EKS
               kubectl apply -f k8s/application/
```

### Improvements we'll need for CI/CD:

The existing Dockerfiles are production-ready. The only change for CI/CD is:
- **Backend**: The connection string will change from the docker-compose one to point to RDS (`inventory-mgmt-sqlserver.c2fc20q44515.us-east-1.rds.amazonaws.com,1433`). This will be injected via Kubernetes Secrets (Phase 5), not hardcoded.

---

## 9. Other useful files in the project

These files live in the Backend and Frontend folders and play a role in the DevOps pipeline. Here's what each one does and when you'll care about it.

| File | Location | What it does | Relevant in Phase(s) |
|---|---|---|---|
| `.dockerignore` | `/Frontend/.dockerignore` | Tells Docker which files to **skip** when running `COPY . .` (e.g., `node_modules`, `.git`, local configs). Without it, Docker would copy the entire source tree including the 500MB+ `node_modules` folder, making builds slow and images bloated | Phase 3 (Docker build) |
| `package.json` | `/Frontend/package.json` | Lists npm dependencies, defines build scripts like `"build": "ng build"`, and holds the app version. The Dockerfile runs `npm install` and `npm run build` based on this file | Phase 3 (Docker), Phase 4 (version tagging) |
| `angular.json` | `/Frontend/angular.json` | Angular project configuration — defines the output path for the build. The Dockerfile references this path: `COPY --from=build /app/dist/inventory-app/browser /usr/share/nginx/html`. If this path changes in `angular.json`, the Dockerfile must be updated too | Phase 3 (Docker) |
| `nginx.conf` | `/Frontend/nginx.conf` | Custom Nginx configuration that handles **Angular SPA routing** (see detailed explanation below) | Phase 3 (Docker), Phase 5 (ConfigMap) |
| `appsettings.json` | `/Backend/InventoryManagement.API/appsettings.json` | .NET configuration file with connection strings, JWT keys, etc. In the Docker image, this file is read at runtime. For Kubernetes deployment, these values will be **overridden** by environment variables from Kubernetes Secrets (Phase 5) | Phase 5 (K8s Secrets) |
| `.csproj` files | `/Backend/*/*.csproj` | .NET project files that list NuGet dependencies. The Dockerfile copies them early (`COPY *.csproj`) to leverage Docker layer caching for `dotnet restore` | Phase 3 (Docker layer caching) |

### Deep dive: Why `nginx.conf` matters for DevOps

The `nginx.conf` file is the **frontend's server configuration**. It tells Nginx how to serve your Angular application. Let's look at the critical line:

```nginx
location / {
    root /usr/share/nginx/html;
    index index.html index.htm;
    try_files $uri $uri/ /index.html;
}
```

#### The `try_files` rule — Angular SPA routing explained

Angular is a **Single Page Application (SPA)**. This means:
- The user loads `index.html` once
- Angular handles navigation inside the browser (changing the URL without asking the server)
- But if the user **refreshes the page** on `/products` — the browser sends a real request to Nginx: "Give me the file at `/products`"

Since there is no file called `products.html`, Nginx would normally return a **404 Not Found** error. The `try_files` directive fixes this:

```
try_files $uri $uri/ /index.html;
```

| Check | What it tries | Example |
|---|---|---|
| `$uri` | Does a file with this exact name exist? | `/products.html` → no |
| `$uri/` | Does a directory with this name exist? | `/products/` → no |
| `/index.html` | Fallback: serve `index.html` | ✅ Found! Angular reads the URL and shows the products page |

**Without this rule, refreshing any page in your app would give a 404 error.**

#### How nginx.conf flows through the phases:

```
┌─ Phase 3 (Docker build) ─────────────────────────────────────────┐
│                                                                  │
│  Frontend/Dockerfile:                                            │
│  COPY nginx.conf /etc/nginx/conf.d/default.conf                  │
│                                                                  │
│  → The nginx.conf becomes part of the Docker image               │
│  → Every container runs with this config                         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─ Phase 4 (CI/CD) ────────────────────────────────────────────────┐
│                                                                  │
│  The pipeline builds the image. nginx.conf is baked in —         │
│  no special handling needed.                                     │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─ Phase 5 (Kubernetes Deployment) ────────────────────────────────┐
│                                                                  │
│  If you need different routing per environment (staging vs       │
│  production), you can REPLACE the nginx.conf at runtime using     │
│  a Kubernetes ConfigMap:                                          │
│                                                                  │
│  kubectl create configmap nginx-config --from-file=nginx.conf    │
│                                                                  │
│  Then mount it in the pod, overriding the file in the image:      │
│  volumeMounts:                                                    │
│    - name: nginx-config                                           │
│      mountPath: /etc/nginx/conf.d/default.conf                    │
│      subPath: default.conf                                        │
│                                                                  │
│  → This allows environment-specific config WITHOUT rebuilding    │
│    the Docker image                                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

#### Summary for each phase:

| Phase | What happens with nginx.conf |
|---|---|
| **Phase 1 (Terraform)** | Not relevant — nginx.conf is application-level, not infrastructure |
| **Phase 2 (K8s Jenkins)** | Not relevant |
| **Phase 3 (Docker)** | ✅ Bundled into the image via `COPY nginx.conf` |
| **Phase 4 (CI/CD)** | ✅ Already inside the image — pipeline doesn't touch it |
| **Phase 5 (K8s App)** | ✅ Can be overridden per environment using ConfigMap |

---

## Summary of Phase 3 Learning Objectives

After studying this file, you should be able to answer:

1. **What does `FROM node:20-alpine AS build` do?** (Starts a build stage from the Node.js 20 Alpine image)
2. **Why copy `package*.json` before source code?** (Docker layer caching — `npm install` is cached until dependencies change)
3. **What does `--from=build` mean in `COPY --from=build`?** (Copy from a previous stage instead of the host machine)
4. **Why does the frontend have 2 stages?** (Build stage has Node.js + build tools; runtime stage has only Nginx + compiled files)
5. **What does `try_files $uri $uri/ /index.html;` do?** (Angular SPA routing — fall back to index.html for client-side routes)
6. **Why does the backend copy `.csproj` files individually?** (Layer caching — `dotnet restore` is cached until dependencies change)
7. **What is the difference between `CMD` and `ENTRYPOINT`?** (CMD can be overridden, ENTRYPOINT is fixed)
8. **Why `ENV ASPNETCORE_URLS=http://+:5097`?** (Without `+`, the app only listens on localhost inside the container)
9. **What is DockerHub and why do we need it?** (A registry to share images — needed because EKS nodes can't access your local images)
10. **What does `docker tag` do?** (Creates an alias for an existing local image)
11. **What does `docker push` do?** (Uploads the image to DockerHub)
12. **How will Jenkins use these Dockerfiles?** (Build → Tag → Push → Update Kubernetes manifests → Apply)

---

**Next phase:** Phase 4 — Jenkins Pipeline (Declarative Jenkinsfile that builds, pushes, and deploys)
