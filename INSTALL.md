# 🚀 Local GitOps Platform (kind + Argo CD + Gitea)

This project bootstraps a full local platform engineering environment with:
- 2 Kubernetes clusters (dev + prod) using kind
- GitOps with Argo CD
- Git server with Gitea
- True multi-cluster deployments (ApplicationSet)
- Ingress with real local domains
- RBAC simulation (Argo CD + Kubernetes)
- Locked toolchain using mise

---

# 🧱 Architecture

```
Git (Gitea)
↓
Argo CD (dev cluster)
↓
ApplicationSet
↓
| |
dev cluster prod cluster
```

---

# ⚙️ Requirements

## System dependencies
- Docker
- curl
- git
- sudo privileges

---

# 🚀 Installation

## 1. Run full installer

```bash
chmod +x install.sh
./install.sh
```

This single script will:
- Detect your OS (Debian / Arch / Fedora / macOS)
- Install missing dependencies
- Install mise (tool version manager)
- Install pinned toolchain
- Create Kubernetes clusters (dev + prod)
- Install ingress controller
- Install Argo CD + Gitea
- Register clusters in Argo CD
- Apply GitOps + RBAC manifests
- Configure local DNS (/etc/hosts)

---

# 📦 Installed components

### Kubernetes clusters
- kind-dev
- kind-prod

### Platform services
- Argo CD (GitOps engine)
- Gitea (Git server)

### Networking
- NGINX Ingress Controller
- Local DNS via /etc/hosts

### GitOps
- ApplicationSet (multi-cluster automation)

---

# 🌐 Access URLs

After installation, open:

| Service | URL |
|---------|-----|
| Argo CD | http://argocd.dev.local |
| Gitea | http://gitea.dev.local |
| Dev App | http://app.dev.local |
| Prod App | http://app.prod.local |

---

# 🔐 Default credentials

### Argo CD
- admin / adminadmin1

### Gitea
- admin / adminadmin1

---

# 📌 Toolchain (locked via mise)

This project uses a pinned toolchain to ensure reproducibility.

Example .mise.toml:

```toml
[tools]
go = "1.22"
kubectl = "1.30.0"
helm = "3.15.4"
argocd = "2.11.3"
kind = "0.23.0"
```

Install exact versions:

```bash
mise install
```

---

# 🔄 GitOps flow

Any change in Git repository triggers:
1. Argo CD detects change
2. ApplicationSet reconciles state
3. Deployment happens automatically to:
   - dev cluster
   - prod cluster

---

# 🔐 RBAC model

### Argo CD roles

| Role | Permissions |
|------|-------------|
| admin | full access |
| dev-user | dev cluster apps only |
| prod-user | read-only production |

### Kubernetes namespaces

| Namespace | Access |
|-----------|--------|
| dev-app | full control |
| prod-app | restricted (read-only style) |

---

# 🧪 Useful commands

### Switch contexts
```bash
kubectl config use-context admin-dev
kubectl config use-context admin-prod
```

### Check clusters
```bash
kubectl get nodes
```

### Check Argo CD apps
```bash
kubectl get applications -n argocd
```

---

# 🧠 What you built

You now have a full local platform:
- Multi-cluster Kubernetes (dev + prod)
- GitOps automation (Argo CD + ApplicationSet)
- Reproducible toolchain (mise locked versions)
- Ingress-based routing with real domains
- RBAC security simulation
- Production-like architecture locally

---

# 🚀 Next possible upgrades

If you want to extend this lab:
- HTTPS with cert-manager (local CA)
- CI pipeline (Git push → auto deploy dev → promote prod)
- Service mesh (Istio / Linkerd)
- Policy enforcement (Kyverno / OPA)
- Progressive delivery (Argo Rollouts)