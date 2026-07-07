# Phase 1 — Terraform Infrastructure: Complete Code Explanation

> **Target Audience:** Junior DevOps Team (assumes basic AWS and terminal knowledge, but NO Terraform or Kubernetes experience)
>
> **Goal:** Understand what each file does, why it exists, and what every single line means — so you can explain it to instructors and feel confident discussing the architecture.

---

## Table of Contents

1. [What is Terraform and why are we using it?](#1-what-is-terraform-and-why-are-we-using-it)
2. [File-by-file breakdown](#2-file-by-file-breakdown)
   - [main.tf](#21-maintf---entry-point-and-provider-configuration)
   - [variables.tf](#22-variablestf---making-the-code-reusable)
   - [terraform.tfvars](#23-terraformtfvars---supplying-real-values)
   - [vpc.tf](#24-vpctf---networking-foundation)
   - [security-groups.tf](#25-security-groupstf---firewall-rules)
   - [eks.tf](#26-ekstf---kubernetes-cluster)
   - [rds.tf](#27-rdstf---sql-server-database)
   - [outputs.tf](#28-outputstf---getting-information-back)
3. [The Big Picture: How everything connects](#3-the-big-picture)
4. [How to run this code](#4-how-to-run-this-code)

---

## 1. What is Terraform and why are we using it?

Imagine you need to build a house. You could:
- **Click-by-click in the AWS Console** (like building the house manually brick by brick) — slow, error-prone, impossible to repeat exactly.
- **Terraform** (like giving an architect a detailed blueprint) — you write the plan once, and Terraform builds it exactly the same way every time.

**Terraform is an "Infrastructure as Code" (IaC) tool.** You write `.tf` files describing what AWS resources you want (VPC, servers, databases), and Terraform talks to the AWS API to create them.

**Why we chose Terraform for this project:**
- **Repeatable** — run it once, run it 100 times, same result.
- **Version-controlled** — the infrastructure blueprint lives in Git alongside your application code.
- **Self-documenting** — anyone can read the `.tf` files to understand the architecture.
- **Destroyable** — `terraform destroy` removes everything cleanly (saves money when learning).

---

## 2. File-by-file breakdown

### 2.1 `main.tf` — Entry point and provider configuration

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

#### What is this file for?

This is the **entry point** of your Terraform project. When you run `terraform init`, Terraform reads this file first to know:
- What language version to use
- What "providers" (plugins to talk to cloud services) to download
- Which cloud region to deploy into

#### Line-by-line:

| Line(s) | What it does | Why it exists |
|---|---|---|
| `terraform {` | Opens a block that configures Terraform itself | Terraform needs to know about itself before it can create resources |
| `required_version = ">= 1.5"` | Says "this code needs Terraform version 1.5 or newer" | Newer versions have bug fixes and features. If someone runs an older version, Terraform will show a clear error instead of mysterious failures |
| `required_providers {` | Opens a block listing which plugins Terraform needs to download | Terraform itself is generic — it uses plugins ("providers") to talk to each cloud |
| `aws = {` | We're declaring we need the AWS provider | This tells Terraform to download the plugin that can talk to AWS APIs |
| `source = "hashicorp/aws"` | The official AWS provider maintained by HashiCorp (the company behind Terraform) | There are community providers too, but the official one is trusted and well-maintained |
| `version = "~> 5.0"` | "Use version 5.x, but not 6.0" (the `~>` means "any version in the 5.x range") | Pins to a major version so that an unexpected breaking change doesn't break your code |
| `provider "aws" {` | Tells Terraform which AWS provider configuration to use | You could have multiple provider blocks (e.g., different regions), but we just need one |
| `region = var.aws_region` | Sets the AWS region from a variable | Instead of hard-coding `us-east-1` here, we use a variable so it can be changed without editing the file |

#### 💡 Key learning point: Variables vs hard-coded values

Hard-coding: `region = "us-east-1"` ← Bad, because if you want to change region you must edit the file.

Using a variable: `region = var.aws_region` ← Good, because the value comes from `variables.tf`, and you can override it at runtime.

---

### 2.2 `variables.tf` — Making the code reusable

```hcl
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "inventory-mgmt"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "rds_master_username" {
  description = "Master username for RDS SQL Server"
  type        = string
  default     = "admin"
}

variable "rds_master_password" {
  description = "Master password for RDS SQL Server"
  type        = string
  sensitive   = true
}
```

#### What is this file for?

This file **declares all the knobs and dials** of your infrastructure. Think of it like the settings panel of a microwave — you don't hard-code the cooking time inside the microwave's brain; you put it on a dial so the user can change it.

#### Line-by-line for the first variable:

| Line | What it does |
|---|---|
| `variable "aws_region" {` | Declares a new variable named `aws_region`. The name is how other files reference it (e.g., `var.aws_region`) |
| `description = "AWS region to deploy resources"` | A human-readable explanation. Terraform shows this when someone runs `terraform plan` and asks about variables |
| `type = string` | The data type — `string`, `number`, `bool`, `list(string)`, `map(string)`, etc. This provides validation. If someone tries to pass a number here, Terraform rejects it |
| `default = "us-east-1"` | The value to use if the user doesn't provide one. Making `us-east-1` the default is convenient but overridable |

#### Variable types explained:

| Type | Example | Meaning |
|---|---|---|
| `string` | `"us-east-1"` | A single text value |
| `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` | An ordered list of text values |
| `number` | `2` | A numeric value |
| `bool` | `true` | True or false |
| `map(string)` | `{Env = "dev", Team = "platform"}` | Key-value pairs |

#### The special `sensitive` attribute:

```hcl
variable "rds_master_password" {
  ...
  sensitive = true
}
```

This tells Terraform: **"Never print this value in logs or console output."** If you mark a variable as `sensitive`, Terraform will show `(sensitive value)` instead of the actual password. This is a security best practice — you don't want passwords appearing in CI/CD logs.

#### 💡 Key learning point: Why no default for `rds_master_password`?

Some variables **must not** have defaults for security reasons. The password is something the user must provide explicitly when running Terraform (via `-var="rds_master_password=..."` or an environment variable). This prevents accidentally deploying with a weak default password.

---

### 2.3 `terraform.tfvars` — Supplying real values

```hcl
aws_region = "us-east-1"
project_name = "inventory-mgmt"
vpc_cidr = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
availability_zones = ["us-east-1a", "us-east-1b"]
rds_master_username = "admin"
# rds_master_password = "YourStrong!Pass123"  # Uncomment and set your password
```

#### What is this file for?

While `variables.tf` **declares** what variables exist, `terraform.tfvars` **assigns values** to them. When you run `terraform apply`, Terraform automatically reads this file and uses these values.

#### Why separate files?

Think of it like a restaurant menu:
- `variables.tf` = the menu items (Steak, Salad, Pasta — the what)
- `terraform.tfvars` = the chef's choices (Ribeye, Caesar, Carbonara — the specifics)

This separation lets you have:
- `terraform.tfvars` → development settings
- `terraform.tfvars.prod` → production settings (loaded with `-var-file=terraform.tfvars.prod`)

#### The commented-out password line:

```
# rds_master_password = "YourStrong!Pass123"
```

The `# ` (hash + space) makes this a **comment** — Terraform ignores it. We deliberately commented it out because:
1. It's bad practice to store passwords in plain text in your repository.
2. Beginners might accidentally commit real passwords.
3. The password should be provided at runtime: `terraform apply -var="rds_master_password=MyRealPass123!"`

---

### 2.4 `vpc.tf` — Networking Foundation

This is the longest file. Let's understand why networking is important.

#### Analogy: A gated community

A **VPC** is like a gated community for your cloud resources:
- **Internet Gateway (IGW)** = the main gate that connects the community to the outside world (internet)
- **Public subnet** = houses with front doors facing the street (things that need direct internet access)
- **Private subnet** = houses behind a security checkpoint (things that should NOT be directly reachable from the internet)
- **NAT Gateway** = a secure mailroom. People in private houses can SEND mail out, but nobody can mail them directly
- **Route table** = a map that tells traffic which direction to go

---

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}
```

| Line | What it does |
|---|---|
| `resource "aws_vpc" "main" {` | Tells Terraform: "I want to create an **AWS VPC** resource, and I'll refer to it internally as `main`" |
| `cidr_block = var.vpc_cidr` | Sets the IP address range for the entire VPC (default: `10.0.0.0/16` = 65,536 possible IPs) |
| `enable_dns_support = true` | Allows resources inside the VPC to resolve DNS names (e.g., `google.com` → IP address) |
| `enable_dns_hostnames = true` | Assigns friendly DNS names to EC2 instances automatically (e.g., `ip-10-0-1-5.ec2.internal`) |
| `tags = { Name = "${var.project_name}-vpc" }` | A label so you can identify this VPC in the AWS Console. `${var.project_name}` inserts the variable value, resulting in `inventory-mgmt-vpc` |

#### 💡 Key learning point: The `resource` block

```hcl
resource "TYPE" "LOCAL_NAME" {
  # configuration
}
```

- **TYPE**: The kind of AWS resource (`aws_vpc`, `aws_subnet`, `aws_db_instance`, etc.)
- **LOCAL_NAME**: A name YOU choose to reference this resource in OTHER `.tf` files. For example, elsewhere you'll write `aws_vpc.main.id` to get this VPC's ID.

---

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}
```

| Line | What it does |
|---|---|
| `vpc_id = aws_vpc.main.id` | Attaches this Internet Gateway to the VPC we created above. `aws_vpc.main.id` means "get the `id` attribute of the `aws_vpc` resource named `main`" |
| Without an IGW, traffic cannot leave or enter the VPC from the internet |

---

```hcl
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}
```

**Elastic IP (EIP):** A static, public IP address that doesn't change. The NAT Gateway needs a fixed public IP so it can communicate with the internet. Think of it as the mailing address for the mailroom.

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat-gw"
  }
}
```

| Line | What it does |
|---|---|
| `allocation_id = aws_eip.nat.id` | Assigns the Elastic IP we just created to this NAT Gateway |
| `subnet_id = aws_subnet.public[0].id` | Places the NAT Gateway in the first public subnet. `aws_subnet.public[0]` means "the first element of the public subnets list" (index 0 = first item) |

#### Why do we need a NAT Gateway?

Resources in **private subnets** (like our EKS worker nodes and RDS database) have no direct internet access. But they sometimes NEED internet access (e.g., to download Docker images, security patches, etc.).

The NAT Gateway solves this: it sits in a public subnet and **translates** outbound traffic from private subnets so it looks like it's coming from the NAT Gateway's public IP. The key point: **it only allows outbound traffic, not inbound**. Nobody from the internet can initiate a connection to your private resources.

---

```hcl
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}
```

#### What is `count`?

`count` is a Terraform meta-argument that creates MULTIPLE copies of a resource. If `count = 2`, Terraform creates 2 subnets.

#### Breaking down the `count` logic:

| Expression | Value | Meaning |
|---|---|---|
| `length(var.public_subnet_cidrs)` | `2` | There are 2 CIDR blocks in the list |
| `count.index` | `0` then `1` | Terraform loops: first iteration index=0, second index=1 |
| `var.public_subnet_cidrs[count.index]` | `"10.0.1.0/24"` then `"10.0.2.0/24"` | Gets the first, then the second CIDR from the list |
| `${count.index + 1}` | `1` then `2` | Human-friendly naming (people count from 1, computers from 0) |

#### What does each subnet become?

After Terraform runs, you'll have:

| Subnet | CIDR | AZ | Name tag |
|---|---|---|---|
| `aws_subnet.public[0]` | `10.0.1.0/24` | `us-east-1a` | `inventory-mgmt-public-subnet-1` |
| `aws_subnet.public[1]` | `10.0.2.0/24` | `us-east-1b` | `inventory-mgmt-public-subnet-2` |

#### Why `map_public_ip_on_launch = true`?

Any resource launched in a public subnet automatically gets a public IP address. This is needed for things like the NAT Gateway and (in later phases) the Load Balancer.

---

```hcl
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  }
}
```

Private subnets are nearly identical to public subnets, except:
- **No `map_public_ip_on_launch`** — resources inside private subnets do NOT get public IPs.
- **Different CIDR ranges** — `10.0.10.0/24` and `10.0.20.0/24` are in the "10" and "20" range, making them visually distinct from public subnets (which are "1" and "2").

---

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}
```

#### What is a Route Table?

A route table is a set of rules that says "if traffic is destined for X, send it to Y."

| Setting | Meaning |
|---|---|
| `cidr_block = "0.0.0.0/0"` | "Any IP address" (all traffic, 0.0.0.0/0 means "the entire internet") |
| `gateway_id = aws_internet_gateway.main.id` | "Send it to the Internet Gateway" |

**Translation:** "Any traffic going to the internet should go through the Internet Gateway." This is what makes a subnet "public" — it has a route to the internet.

```hcl
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

This **connects** the public route table to each public subnet. Without this association, the route table is just a document that nobody follows.

---

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}
```

The private route table is similar, but instead of sending internet traffic to the IGW, it sends it to the **NAT Gateway**. This means:
- Outbound internet traffic ✅ (goes through NAT)
- Inbound internet traffic ❌ (no direct route from the internet)

This is the **security boundary** — your database and application servers can download updates but cannot be directly accessed from the internet.

---

#### The IP addressing scheme visualized:

```
VPC: 10.0.0.0/16 (65,536 addresses)
│
├── Public Subnet 1: 10.0.1.0/24 (254 addresses, us-east-1a)
├── Public Subnet 2: 10.0.2.0/24 (254 addresses, us-east-1b)
│
├── Private Subnet 1: 10.0.10.0/24 (254 addresses, us-east-1a)
├── Private Subnet 2: 10.0.20.0/24 (254 addresses, us-east-1b)
│
└── Rest of VPC: 10.0.3.0 - 10.0.255.255 (unused, for future expansion)
```

Why 2 subnets of each type? **High Availability (HA)**. We deploy across 2 Availability Zones so that if one AWS data center goes down, our application survives in the other zone.

---

### 2.5 `security-groups.tf` — Firewall Rules

A **Security Group (SG)** is a virtual firewall that controls traffic to AWS resources. Think of it as a bouncer at a club:
- **Inbound rules** = "Who can come in?"
- **Outbound rules** = "Who can leave?"

> Security groups are **stateful**: if you allow inbound traffic on port 80, the outbound response is automatically allowed. You don't need a separate outbound rule for reply traffic.

---

```hcl
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}
```

| Line | What it does |
|---|---|
| `name = "${var.project_name}-eks-cluster-sg"` | The name that appears in AWS Console |
| `description = "Security group for EKS cluster"` | A note for humans |
| `vpc_id = aws_vpc.main.id` | This SG lives inside our VPC |

**The `egress` block:**
| Setting | Meaning |
|---|---|
| `from_port = 0` and `to_port = 0` | "All ports" (when protocol is `-1`, port range is ignored) |
| `protocol = "-1"` | Special value meaning "all protocols" (TCP, UDP, ICMP, etc.) |
| `cidr_blocks = ["0.0.0.0/0"]` | "To anywhere on the internet" |

**Translation:** The EKS cluster can send traffic anywhere (outbound fully open).

> Notice there's **no `ingress` block** here. The EKS cluster doesn't need inbound rules directly — it communicates with worker nodes through a different mechanism (we'll see that next).

---

```hcl
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-nodes-sg"
  }
}
```

Similar to the cluster SG — worker nodes can also reach the internet (they need to pull Docker images from DockerHub, etc.).

---

```hcl
resource "aws_vpc_security_group_egress_rule" "cluster_to_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
}
```

#### What are these "rule" resources?

AWS allows you to define rules **separately** from the security group itself (using `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule`). This is the modern way to do it.

| Line | What it does |
|---|---|
| `security_group_id = aws_security_group.eks_cluster.id` | "This rule applies to the EKS cluster's SG" |
| `referenced_security_group_id = aws_security_group.eks_nodes.id` | "The destination is the EKS nodes' SG" (instead of a CIDR block) |
| `from_port = 0` / `to_port = 65535` / `ip_protocol = "tcp"` | "Allow all TCP ports" |

**Translation:** The EKS cluster can send traffic to the worker nodes on any TCP port.

#### 💡 Key learning point: Security group referencing

Instead of writing `cidr_blocks = ["10.0.10.0/24"]`, we wrote `referenced_security_group_id = ...`. This is **dynamic referencing**: if the node SG changes (e.g., you add more subnets), you don't need to update the CIDR everywhere. AWS automatically resolves which resources have that SG attached.

---

```hcl
resource "aws_vpc_security_group_ingress_rule" "nodes_from_cluster" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
}
```

The reverse of the previous rule — **nodes can receive traffic from the cluster** on any TCP port. Together, these two rules enable bidirectional communication between the EKS control plane and worker nodes:

```
Cluster ──── TCP any port ────> Nodes
Cluster <─── TCP any port ──── Nodes
```

---

```hcl
resource "aws_vpc_security_group_ingress_rule" "nodes_to_nodes" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  node_id                      = aws_security_group.eks_nodes.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "-1"
}
```

Wait — this references the **same** security group (`eks_nodes` references itself). This means nodes can talk to each other on all ports and all protocols. This is required for:
- Kubernetes pods communicating across nodes
- Internal cluster networking (CNI plugin)

---

```hcl
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS SQL Server"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}
```

The RDS security group starts with NO rules. We add one inbound rule next.

---

```hcl
resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 1433
  to_port                      = 1433
  ip_protocol                  = "tcp"
}
```

| Setting | Meaning |
|---|---|
| `from_port = 1433` / `to_port = 1433` | Only port 1433 (SQL Server default) |
| `referenced_security_group_id = aws_security_group.eks_nodes.id` | Only from resources that have the EKS nodes SG attached |

**Translation:** Only the EKS worker nodes can talk to the database, and only on port 1433. No other resource in the VPC (or outside) can access the database. This is our **defense in depth** — even if someone gains access to the VPC, they still can't reach the database unless they're running inside an EKS node.

---

### 2.6 `eks.tf` — Kubernetes Cluster

This file creates the Kubernetes cluster and its worker nodes. Let's understand the pieces.

#### IAM Roles — Identity and Access Management

Before we create the EKS cluster, we need to tell AWS **who** is allowed to create and manage it. This is done through IAM Roles.

**Analogy:** An IAM Role is like a security badge. You wear the badge, and it gives you specific permissions. The badge is not tied to a specific person — anyone wearing it gets those permissions.

---

```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
```

| Line | What it does |
|---|---|
| `name = "${var.project_name}-eks-cluster-role"` | The role's name in AWS |
| `assume_role_policy = jsonencode({...})` | "Who is allowed to wear this badge?" — this policy says the EKS service (`eks.amazonaws.com`) can assume this role |
| `jsonencode({...})` | Converts the Terraform map into JSON format (IAM policies are JSON) |

**Translation:** This creates a role that the EKS service itself can use. When AWS needs to create resources on behalf of EKS (like load balancers), it uses this role.

---

```hcl
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}
```

This **attaches** a predefined AWS-managed policy to the role. `AmazonEKSClusterPolicy` contains all the permissions EKS needs (create ELBs, manage ENIs, etc.).

Think of it as: "Here's the badge (role), and here's the list of doors it unlocks (policy)."

Similarly, `AmazonEKSServicePolicy` provides additional permissions needed by the EKS service.

---

```hcl
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
```

This role is for **EC2 instances** (the worker nodes), not the EKS service. The principal is `ec2.amazonaws.com` because EC2 instances will assume this role.

Three policies are attached to this role:

| Policy | Purpose |
|---|---|
| `AmazonEKSWorkerNodePolicy` | Allow nodes to connect to the EKS cluster |
| `AmazonEKS_CNI_Policy` | Allow nodes to manage Elastic Network Interfaces (for pod networking) |
| `AmazonEC2ContainerRegistryReadOnly` | Allow nodes to pull images from ECR (though we're using DockerHub, this is a standard attachment) |

---

```hcl
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy
  ]
}
```

#### Creating the actual EKS cluster:

| Line | What it does |
|---|---|
| `name = "${var.project_name}-cluster"` | Cluster name: `inventory-mgmt-cluster` |
| `role_arn = aws_iam_role.eks_cluster.arn` | The IAM role the cluster will use (the one we created above) |
| `version = "1.31"` | Kubernetes version 1.31 (latest stable at time of writing) |

**The `vpc_config` block:**
| Setting | Meaning |
|---|---|
| `subnet_ids = aws_subnet.private[*].id` | The cluster will launch in our private subnets. The `[*]` syntax means "all elements of the list" (equivalent to `aws_subnet.private[0].id, aws_subnet.private[1].id`) |
| `endpoint_private_access = true` | The Kubernetes API is accessible from within the VPC (private) |
| `endpoint_public_access = true` | The Kubernetes API is also accessible from the internet (public) — needed for Jenkins to connect from outside |
| `security_group_ids = [aws_security_group.eks_cluster.id]` | The cluster's security group |

**The `depends_on` block:**
```hcl
depends_on = [
  aws_iam_role_policy_attachment.eks_cluster_policy,
  aws_iam_role_policy_attachment.eks_service_policy
]
```

This is Terraform's way of saying: **"Don't create the cluster until the IAM policies are attached."** Without this, Terraform might try to create the cluster before the permissions are ready, causing a failure.

---

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  version         = aws_eks_cluster.main.version

  subnet_ids = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  instance_types = ["t3.medium"]

  launch_template {
    name    = aws_launch_template.eks_nodes.name
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    Name = "${var.project_name}-node-group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry
  ]
}
```

#### Creating the worker nodes (the actual EC2 instances):

| Line | What it does |
|---|---|
| `cluster_name = aws_eks_cluster.main.name` | Which cluster to join |
| `node_group_name = "${var.project_name}-node-group"` | Name of the node group |
| `node_role_arn = aws_iam_role.eks_nodes.arn` | IAM role for the EC2 instances |
| `version = aws_eks_cluster.main.version` | Use the same K8s version as the cluster |

**The `scaling_config` block:**
```hcl
scaling_config {
  desired_size = 2
  min_size     = 2
  max_size     = 4
}
```

- `desired_size = 2`: Start with exactly 2 nodes
- `min_size = 2`: Never scale below 2 (we need one for tools, one for production)
- `max_size = 4`: Allow scaling up to 4 if needed (e.g., during deployments)

**Instance type:** `t3.medium` — a general-purpose instance with 2 vCPUs and 4 GB RAM. This is the "Goldilocks" choice for learning: not too expensive, not too weak.

**The `launch_template` block:** Links to a launch template that defines how each node is configured (we'll look at it next).

---

```hcl
resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "${var.project_name}-node-template-"
  instance_type = "t3.medium"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-worker-node"
    }
  }
}
```

| Line | What it does |
|---|---|
| `name_prefix = "${var.project_name}-node-template-"` | Starts the name with this prefix (Terraform adds a random suffix to avoid conflicts) |
| `instance_type = "t3.medium"` | Override the instance type (though it matches the node group) |

**The `user_data` section:** This is a script that runs when each EC2 instance boots. Currently it's a minimal placeholder. In future phases, we'll modify this to automatically label nodes (e.g., "Node 1 = tools, Node 2 = production").

`base64encode(<<-EOF ... EOF)` — User data must be base64-encoded. `<<-EOF` is a heredoc syntax that lets us write multi-line text cleanly.

---

#### 💡 Key learning point: How will we separate Tools vs Production on the 2 nodes?

Our architecture requires:
- **Node 1** → Jenkins pod (tools)
- **Node 2** → Frontend + Backend pods (production)

We can't control which pod goes where just by having 2 nodes. We need **node labels** and **nodeSelector**:
1. After the nodes join the cluster, we label one as `role=tools` and the other as `role=production`
2. In Kubernetes deployment files, we add `nodeSelector: { role: tools }` to the Jenkins pod and `nodeSelector: { role: production }` to the app pods
3. This "pins" each pod to the correct node

We'll implement the labeling in Phase 2.

---

### 2.7 `rds.tf` — SQL Server Database

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}
```

#### What is a DB Subnet Group?

RDS needs to know which subnets it can place the database in. We tell it: "Use both private subnets" (`aws_subnet.private[*].id`). This gives RDS high availability options — if one subnet's AZ goes down, the database can failover to the other.

```hcl
resource "aws_db_instance" "sql_server" {
  identifier = "${var.project_name}-sqlserver"

  engine         = "sqlserver-ex"
  engine_version = "15.00.4375.1.v1"
  instance_class = "db.t3.small"

  db_name  = "InventoryManagementDb"
  username = var.rds_master_username
  password = var.rds_master_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot = true

  license_model = "license-included"

  tags = {
    Name = "${var.project_name}-sqlserver"
  }
}
```

| Line | What it does |
|---|---|
| `engine = "sqlserver-ex"` | SQL Server Express Edition (free tier, limited to 10GB DB size — fine for learning) |
| `engine_version = "15.00.4375.1.v1"` | Specific version of SQL Server 2019 |
| `instance_class = "db.t3.small"` | The hardware: 2 vCPUs, 2 GB RAM (~$30/month — cheapest option for SQL Server) |
| `db_name = "InventoryManagementDb"` | The initial database name that RDS creates when provisioning |
| `username` / `password` | SQL Server admin credentials (from variables) |
| `publicly_accessible = false` | **Crucial security setting** — the database is ONLY accessible from within the VPC. No public endpoint |
| `skip_final_snapshot = true` | When you delete this database, don't take a final backup (we're learning, not running production) |
| `license_model = "license-included"` | The license cost is included in the instance price (for SQL Server Express, this is free) |

#### 💡 Key learning point: Why RDS and not running SQL Server in a container?

Your original setup used SQL Server in a Docker container (`mcr.microsoft.com/mssql/server:2022-latest`). In our production-like AWS architecture, we're switching to **Amazon RDS** for good reasons:

| Local Docker SQL Server | AWS RDS SQL Server |
|---|---|
| You manage everything (backups, patches, storage) | AWS manages backups, patches, replication |
| Data disappears if container is destroyed | Data persists independently |
| Manual backups required | Automated backups enabled by default |
| Single instance, no HA | Multi-AZ failover available |
| You must secure it yourself | VPC security groups + encryption built in |

The application code doesn't care — it just needs a SQL Server connection string. The connection string will change from:
```
Server=db;Database=InventoryManagementDb;User Id=sa;Password=...
```
to:
```
Server=<rds-endpoint>.us-east-1.rds.amazonaws.com,1433;Database=InventoryManagementDb;User Id=admin;Password=...
```

---

### 2.8 `outputs.tf` — Getting Information Back

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster API"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_certificate" {
  description = "Certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "rds_endpoint" {
  description = "Connection endpoint for RDS SQL Server"
  value       = aws_db_instance.sql_server.address
}

output "rds_port" {
  description = "Port for RDS SQL Server"
  value       = aws_db_instance.sql_server.port
}

output "rds_db_name" {
  description = "Database name"
  value       = aws_db_instance.sql_server.db_name
}
```

#### What are Outputs for?

After Terraform finishes creating everything, it prints these values to the console. They serve several purposes:

1. **Information sharing** — You need the RDS endpoint to configure your application's connection string
2. **Input to other tools** — The EKS cluster name and endpoint are needed to configure `kubectl`
3. **Reference documentation** — Anyone can run `terraform output` later to get these values

#### The `sensitive` output:

```hcl
output "eks_cluster_certificate" {
  ...
  sensitive = true
}
```

The cluster's TLS certificate is sensitive information (it's used to establish trusted communication). Marking it as `sensitive` prevents it from appearing in plain text in logs or CI/CD output.

#### After deployment, you'll see something like:

```
Outputs:

eks_cluster_endpoint = "https://ABC123DEF456.gr7.us-east-1.eks.amazonaws.com"
eks_cluster_name = "inventory-mgmt-cluster"
private_subnet_ids = [
  "subnet-0a1b2c3d4e5f6g7h8",
  "subnet-1i2j3k4l5m6n7o8p9",
]
public_subnet_ids = [
  "subnet-9q8r7s6t5u4v3w2x1y",
  "subnet-0z1y2x3w4v5u6t7s8r",
]
rds_endpoint = "inventory-mgmt-sqlserver.c9abc8defg7h.us-east-1.rds.amazonaws.com"
rds_port = 1433
vpc_id = "vpc-0a1b2c3d4e5f6g7h8"
```

The RDS endpoint (`rds_endpoint`) is what your backend application will use as the SQL Server hostname in its connection string.

---

## 3. The Big Picture

### How all the pieces connect:

```
                    Internet
                       │
                       ▼
              ┌─────────────────┐
              │  Internet GW    │
              │  (main gate)    │
              └────────┬────────┘
                       │
              ┌────────┴────────┐
              │  Public Subnets │
              │  (10.0.1.0/24,  │
              │   10.0.2.0/24)  │
              │                 │
              │  ┌───────────┐  │
              │  │NAT Gateway│  │
              │  └─────┬─────┘  │
              └────────┼────────┘
                       │ (outbound only)
              ┌────────┴────────┐
              │ Private Subnets │
              │ (10.0.10.0/24,  │
              │  10.0.20.0/24)  │
              │                 │
              │  ┌──────────┐   │
              │  │EKS Nodes  │   │
              │  │(t3.medium)│   │
              │  │Node 1:    │   │  ┌──────────────────┐
              │  │  Jenkins  │   │  │  RDS SQL Server  │
              │  │Node 2:    │   │  │  (db.t3.small)   │
              │  │  App Pods │   │  │  Port 1433       │
              │  └──────────┘   │  │                  │
              │       │         │  │  Private, no     │
              │       │(port    │  │  public access   │
              │       │ 1433)   │  └──────────────────┘
              │       └─────────┼─────────┘
              └─────────────────┘
```

### Traffic Flows:

| From | To | Route | Security |
|---|---|---|---|
| User's browser | EKS API (kubectl) | Internet → IGW → Public subnets → NAT → Private → EKS API | TLS certificate authentication |
| Jenkins (inside cluster) | DockerHub | Node → NAT → IGW → Internet | Outbound only |
| Jenkins (inside cluster) | EKS API | Node → kubelet → API | RBAC (ServiceAccount) |
| Frontend pod | Backend pod | Cluster internal (ClusterIP) | Kubernetes network policy |
| Backend pod | RDS SQL Server | Pod → Node → RDS SG (port 1433) | Only from EKS node SG |
| User's browser | Frontend (via LB) | Internet → IGW → Load Balancer → Frontend Pod | Load Balancer SG |

---

## 4. How to Run This Code

### Prerequisites

| Tool | Purpose | How to install |
|---|---|---|
| **Terraform** | Apply infrastructure | `choco install terraform` (Windows) or `brew install terraform` (Mac) |
| **AWS CLI** | Authenticate with AWS | `choco install awscli` or `brew install awscli` |
| **AWS credentials** | Allow Terraform to act on your behalf | Run `aws configure` and enter your Access Key ID + Secret Access Key |

### Step-by-step execution:

#### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

What happens:
- Downloads the AWS provider plugin
- Sets up the `.terraform` directory (like a cache)
- Validates that your files have correct syntax

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.xx.x...
- Installed hashicorp/aws v5.xx.x...
Terraform has been successfully initialized!
```

#### Step 2: Preview the changes (safety check)

```bash
terraform plan -var="rds_master_password=YourStr0ngPass123!"
```

What happens:
- Terraform reads all `.tf` files
- Contacts AWS to check current state
- Shows a detailed diff of what will be created, modified, or deleted
- **Does NOT make any changes** — it's read-only

Read the plan output carefully. It should show:
```
Plan: 24 to add, 0 to change, 0 to destroy.
```

24 resources total (VPC, 2 public subnets, 2 private subnets, IGW, NAT, EIP, 2 route tables, 4 route table associations, 3 security groups, 6 SG rules, 2 IAM roles, 5 IAM policy attachments, 1 EKS cluster, 1 node group, 1 launch template, 1 DB subnet group, 1 RDS instance).

#### Step 3: Apply the changes

```bash
terraform apply -var="rds_master_password=YourStr0ngPass123!"
```

Terraform will show the plan again and ask: `Do you want to perform these actions?`

Type `yes` and press Enter.

This takes **15-25 minutes** because:
- EKS cluster creation: ~10 minutes
- EKS node group creation: ~5 minutes
- RDS instance creation: ~10 minutes

#### Step 4: Configure kubectl (after apply completes)

```bash
aws eks update-kubeconfig --region us-east-1 --name inventory-mgmt-cluster
```

This downloads the cluster's certificate and configures `kubectl` so you can run `kubectl get nodes` and see your 2 nodes.

#### Step 5: Destroy (when done learning)

```bash
terraform destroy -var="rds_master_password=YourStr0ngPass123!"
```

**IMPORTANT:** Always destroy resources when you're done to avoid ongoing AWS charges. The EKS cluster + RDS instance + NAT Gateway cost approximately **$150-200/month** if left running.

---

## Summary of Phase 1 Learning Objectives

After studying this file, you should be able to answer:

1. **Why do we need 2 public and 2 private subnets?** (High Availability across AZs)
2. **What is the difference between a public and private subnet?** (Route to IGW vs NAT)
3. **Why does the RDS database live in a private subnet?** (Security — no public access)
4. **What does a Security Group do?** (Acts as a firewall for AWS resources)
5. **What is the NAT Gateway for?** (Allows outbound internet from private subnets)
6. **What does the EKS node group define?** (How many worker nodes, what instance type)
7. **What is an IAM role and why do we need one for EKS?** (Grants permissions to AWS services)
8. **What is Terraform's `count` used for?** (Creating multiple copies of a resource)
9. **What is `depends_on`?** (Ensures resources are created in the correct order)
10. **How will we separate Jenkins from App pods on different nodes?** (node labels + nodeSelector)

---

**Next phase:** Phase 2 — Kubernetes Jenkins Deployment + RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
