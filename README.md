# Prerequisites
Golang
Docker
kubectl
helm
argocli
k9s


# Setup kind
go install sigs.k8s.io/kind@v0.32.0
kind create cluster --name dev
kubectl config use-context kind-dev

# Get password 
htpasswd -nbBC 10 "" adminadmin1 | tr -d ':\n' | sed 's/$2y/$2a/'

# Setup argo
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  -n argocd \
  -f argocd-values.yaml

# Setup gitea
kubectl create namespace gitea
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update
helm install gitea gitea-charts/gitea \
  -n gitea \
  -f gitea-values.yaml

# Get kind cluster IP
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dev-control-plane

# Optional(setup git)
git init
git add
git commit -am 'feature: update manifest'
git remote add origin http://172.18.0.3:30030/admin/local-nginx.git
git push -u origin master

# Create app
argocd login 172.18.0.3:30080 \
  --username admin \
  --password adminadmin1 \
  --insecure

argocd repo add http://gitea-http.gitea.svc.cluster.local:3000/admin/local-nginx.git \
  --username admin \
  --password adminadmin1

argocd app create nginx-app \
  --repo http://gitea-http.gitea.svc.cluster.local:3000/admin/local-nginx.git \
  --path nginx \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace local-nginx

argocd app sync nginx-app