# Database Strategy: RDS SQL Server + EF Core

> **Problem:** RDS SQL Server Express is provisioned, but the `InventoryManagementDb` database does not exist inside it. This documents why, and the production-ready solution.
>
> **Target Audience:** Developers and DevOps team who need to understand how the database lifecycle works across environments.

---

## Table of Contents

1. [The Problem](#1-the-problem)
2. [Why this happened](#2-why-this-happened)
3. [How the current code handles database creation](#3-how-the-current-code-handles-database-creation)
4. [The problem with EnsureCreated in production](#4-the-problem-with-ensurecreated-in-production)
5. [Production solution: EF Core Migrations](#5-production-solution-ef-core-migrations)
6. [What needs to change for production](#6-what-needs-to-change-for-production)
7. [Comparing all approaches](#7-comparing-all-approaches)
8. [FAQ](#8-faq)

---

## 1. The Problem

```
Cannot open database "InventoryManagementDb" requested by the login. The login failed.
Login failed for user 'admin'.
Error Number: 4060, State: 1, Class: 11
```

**SQL Server Error 4060** means:
- ✅ The **login credentials** are correct (`admin` can connect)
- ✅ The **SQL Server instance** is running and reachable
- ❌ The database **`InventoryManagementDb`** does **not exist** inside RDS

This happens at three different points:

| When | Why |
|---|---|
| **After Terraform apply** | RDS creates the server instance, but **no user database** — only system databases (`master`, `model`, `msdb`, `tempdb`) |
| **When backend starts** | `EnsureCreated()` tries to create it, but fails if SQL isn't ready or if the method wasn't called |
| **When user registers** | The app tries to query tables that don't exist yet |

---

## 2. Why this happened

### Root cause 1: Terraform limitation

SQL Server Express on RDS **does not support** the `db_name` parameter:

```hcl
# This does NOT work for sqlserver-ex:
resource "aws_db_instance" "sql_server" {
  db_name = "InventoryManagementDb"  # ❌ AWS returns: "DBName must be null for engine: sqlserver-ex"
}
```

Only the paid SQL Server editions (Standard, Enterprise) support creating a database during provisioning. With Express, RDS creates an empty instance with zero user databases.

### Root cause 2: The backend hasn't been deployed yet

The database creation is supposed to happen at application startup via:

```csharp
// Backend/InventoryManagement.Repository/Data/DbInitializer.cs
public static void Seed(ApplicationDbContext context)
{
    context.Database.EnsureCreated();
}
```

But since we're only at Phase 3, the backend hasn't been deployed to EKS, so this code has never run against RDS.

### Root cause 3: Manual creation was skipped

We ran `terraform apply` and got RDS running, but we never connected to it and ran `CREATE DATABASE`. The database exists only in the connection string — not in actual SQL Server.

---

## 3. How the current code handles database creation

### The DbInitializer flow

```
Program.cs startup (line 128-156)
    │
    ▼
DbInitializer.Seed(context)
    │
    ▼
context.Database.EnsureCreated()
    │
    ├── Does database "InventoryManagementDb" exist?
    │      │
    │      ├── No  → CREATE DATABASE + CREATE ALL TABLES (from DbContext model)
    │      │
    │      └── Yes → Do nothing (assumes schema is up to date)
```

### The code path (from your existing codebase):

**Program.cs** (lines 128-156, with the retry fix we added):
```csharp
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();
    var retryAttempts = 10;
    var delay = TimeSpan.FromSeconds(5);

    for (int attempt = 1; attempt <= retryAttempts; attempt++)
    {
        try
        {
            var context = services.GetRequiredService<ApplicationDbContext>();
            DbInitializer.Seed(context);
            break;
        }
        catch (Exception ex) when (attempt < retryAttempts)
        {
            Thread.Sleep(delay);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Database seeding failed after {MaxAttempts} attempts.", retryAttempts);
        }
    }
}
```

**DbInitializer.cs**:
```csharp
public static void Seed(ApplicationDbContext context)
{
    context.Database.EnsureCreated();
}
```

**ApplicationDbContext.cs** defines the schema via `DbSet<>` properties:
```csharp
public DbSet<Tenant> Tenants { get; set; }
public DbSet<Product> Products { get; set; }
public DbSet<Category> Categories { get; set; }
// ... all other tables
```

### What EnsureCreated does:

1. Connects to SQL Server using the connection string
2. Checks if the database named `InventoryManagementDb` exists
3. If **no**: Creates the database, then creates all tables matching the `DbSet<>` properties in `ApplicationDbContext`
4. If **yes**: Does nothing (assumes schema matches the code)

### The retry fix we added in Phase 1:

The original code tried `EnsureCreated()` **once** and failed if SQL Server wasn't ready. We added a retry loop (10 attempts, 5 seconds apart) so the backend waits for RDS to become available.

---

## 4. The problem with `EnsureCreated` in production

`EnsureCreated()` is convenient for development but has **critical limitations** in production:

| Issue | What happens | Impact |
|---|---|---|
| **No migration history** | Creates tables directly from the code model, not from migration files | You lose the ability to track schema changes over time |
| **Cannot evolve the schema** | If you add a new column, `EnsureCreated()` won't alter the existing table | You'd need to drop and recreate the database (losing all data) |
| **No versioning** | Every deployment recreates based on the current code state | Different team members on different code versions get different schemas |
| **No rollback** | If a deployment introduces a bad schema change, you can't revert | You'd need a manual backup restore |

### Real-world scenario:

```
Month 1: App deployed with Users table (Id, Name, Email)
Month 2: New feature needs PhoneNumber column
         With EnsureCreated ❌ → Can't add column, must drop DB
         With migrations   ✅ → dotnet ef migrations add AddPhoneNumber
```

---

## 5. Production solution: EF Core Migrations

### What are EF Core Migrations?

Migrations are **version-controlled C# files** that describe incremental schema changes. Think of them like Git commits for your database:

```
Migration 1: InitialCreate  ──→ Creates Users, Products, Categories tables
Migration 2: AddPhoneNumber ──→ ALTER TABLE Users ADD PhoneNumber
Migration 3: AddIndexes     ──→ CREATE INDEX on Products.Name
```

Each migration is a **file in your repo** that can be:
- Version-controlled (Git)
- Code-reviewed (PRs)
- Rolled back if needed

### The existing migration in your project

Your project already has an initial migration:

**File:** `Backend/InventoryManagement.Repository/Migrations/20260619123423_InitialCreate.cs`

This was created with:
```bash
dotnet ef migrations add InitialCreate
```

It already contains the complete schema (all tables, indexes, foreign keys).

### How `Database.Migrate()` works

```csharp
context.Database.Migrate();
```

1. Creates the database if it doesn't exist
2. Checks the `__EFMigrationsHistory` table for applied migrations
3. Applies any **pending** migrations in order
4. Records each applied migration in the history table

This means:
- **First run:** Database is created, all migrations applied
- **Subsequent runs:** Only new migrations are applied
- **Rollback:** `dotnet ef migrations remove` reverts the last migration

---

## 6. What needs to change for production

### File 1: `DbInitializer.cs` — Change `EnsureCreated` to `Migrate`

**Current (dev):**
```csharp
public static void Seed(ApplicationDbContext context)
{
    context.Database.EnsureCreated();
}
```

**Production:**
```csharp
public static void Seed(ApplicationDbContext context)
{
    context.Database.Migrate();
}
```

### File 2: `Program.cs` — Already has retry logic, no changes needed

The retry loop we added in Phase 1 already handles database availability. It works for both `EnsureCreated` and `Migrate`.

### File 3: `ApplicationDbContext.cs` — Verify migrations assembly

Current (already correct):
```csharp
options.UseSqlServer(connectionString, b =>
{
    b.MigrationsAssembly("InventoryManagement.Repository");
});
```

This tells EF Core to look for migration files in the `InventoryManagement.Repository` assembly, where they already exist.

### File 4: RDS remains as-is (no changes)

RDS stays as an empty server instance. The migration process will create the database and tables on first deployment. No manual `CREATE DATABASE` is needed.

### File 5: K8s deployment (Phase 5) — Connection string via Secrets

The backend's connection string needs to point to RDS, not localhost. This will be injected via Kubernetes Secrets in Phase 5:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rds-connection
type: Opaque
stringData:
  connection-string: "Server=inventory-mgmt-sqlserver.c2fc20q44515.us-east-1.rds.amazonaws.com,1433;Database=InventoryManagementDb;User Id=admin;Password=YourSecurePassword123!;TrustServerCertificate=True;MultipleActiveResultSets=true"
```

---

## 7. Comparing all approaches

| Approach | Code change | Creates DB? | Creates tables? | Handles updates? | Production-ready? |
|---|---|---|---|---|---|
| **Manual SQL** | None (run sqlcmd) | ✅ Manual | ❌ Manual | ❌ | ❌ |
| **EnsureCreated** (current) | None | ✅ Auto | ✅ Auto | ❌ Destructive | ❌ |
| **Database.Migrate** (recommended) | 1 line change | ✅ Auto | ✅ Auto | ✅ Incremental | ✅ |
| **Azure Pipelines / manual migration** | `dotnet ef database update` in CI | ✅ | ✅ | ✅ | ✅ |

### The production flow (recommended approach):

```
Developer pushes code with new migration
        │
        ▼
Jenkins pipeline (Phase 4)
        │
        ├── Builds Docker images
        ├── Pushes to DockerHub
        │
        ▼
Backend pod restarts (new image)
        │
        ▼
Program.cs → DbInitializer.Seed()
        │
        ▼
context.Database.Migrate()
        │
        ├── First time → Creates DB + applies all migrations
        │
        └── Update   → Applies only new migrations
```

### Migration lifecycle for future features:

```bash
# Step 1: Developer adds a new property to an entity class
public class Product
{
    public string SerialNumber { get; set; }  // New field
}

# Step 2: Generate a migration
dotnet ef migrations add AddSerialNumberToProduct

# Step 3: Review the generated migration file (committed to Git)
# File: Migrations/20260705120000_AddSerialNumberToProduct.cs

# Step 4: Push to GitHub → Jenkins builds → Deploy → Migrate() runs
```

---

## 8. FAQ

### Q1: Can I keep `EnsureCreated` for now and switch later?

Yes. For development/testing, `EnsureCreated()` works fine. Switch to `Database.Migrate()` when you're ready for production. The database schema is the same either way.

### Q2: Will switching to `Migrate()` break my existing data?

**No.** `Migrate()` checks the `__EFMigrationsHistory` table. If it exists (created by `EnsureCreated` or a previous migration), Migrate will skip already-applied migrations. If it doesn't exist, Migrate will apply all pending migrations.

### Q3: What if I have data in the database and switch?

If the database was created by `EnsureCreated()`, the schema already matches the initial migration. When you switch to `Migrate()`:
1. EF Core checks `__EFMigrationsHistory` — table doesn't exist
2. EF Core tries to apply all migrations
3. It detects the tables already exist (from `EnsureCreated`)
4. It records the initial migration as "already applied" in `__EFMigrationsHistory`
5. Future migrations work normally

### Q4: Should I keep the retry loop when switching to `Migrate()`?

**Yes, definitely.** The retry loop handles:
- RDS not being ready yet (still provisioning)
- Network connectivity issues
- Transient SQL Server errors

### Q5: Do I need to manually create `InventoryManagementDb` before deploy?

**No.** `Database.Migrate()` creates the database automatically if it doesn't exist. You only need to create it manually if you want to test the connection before deploying the backend.

### Q6: What's the one-line change to switch to production mode?

```csharp
// Old (development):
context.Database.EnsureCreated();

// New (production):
context.Database.Migrate();
```

That's it. One line change in `DbInitializer.cs`.

---

## Summary

| Question | Answer |
|---|---|
| Why is the database missing? | RDS Express doesn't support `db_name` in Terraform; backend not deployed yet |
| Will the backend create it? | Yes — via `EnsureCreated()` or `Database.Migrate()` on first startup |
| Which approach for production? | **`Database.Migrate()`** — handles schema updates safely |
| What code changes needed? | One line in `DbInitializer.cs`: `EnsureCreated` → `Migrate` |
| Do I need to create the DB manually? | **No** — migrations handle it automatically |
| When will this happen? | Phase 5 when we deploy the backend to EKS |
