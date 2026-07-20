#!/usr/bin/env bash
# Instala o ArgoCD via Helm (nunca via Terraform — os finalizers dele
# quebrariam um `terraform destroy`) e aplica a Application raiz
# (app-of-apps) apontada para o overlay do ambiente informado.
#
# Uso:
#   REPO_URL=https://github.com/SEU_USUARIO/hackathon-solidarytech.git \
#     ./install.sh primary   # ou: ./install.sh dr
#
# Pré-requisito: kubectl já configurado para o cluster alvo
# (aws eks update-kubeconfig ...).
set -euo pipefail

ENV="${1:-primary}"
if [[ "$ENV" != "primary" && "$ENV" != "dr" ]]; then
  echo "Uso: $0 [primary|dr]" >&2
  exit 1
fi

: "${REPO_URL:?defina REPO_URL com a URL do repositório GitHub (ex.: https://github.com/SEU_USUARIO/hackathon-solidarytech.git)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Instalando/atualizando ArgoCD (namespace argocd)..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --wait --timeout 10m

echo "==> Aguardando argocd-server ficar pronto..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m

echo "==> Aplicando a Application raiz (env=${ENV})..."
sed -e "s#__REPO_URL__#${REPO_URL}#g" -e "s#__ENV__#${ENV}#g" \
  "${SCRIPT_DIR}/root-app.yaml" | kubectl apply -f -

cat <<EOF

ArgoCD instalado e Application raiz aplicada (env=${ENV}).

Acompanhar o sync:
  kubectl -n argocd get applications

Senha inicial do usuário admin:
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

Acessar a UI (port-forward, sem expor LoadBalancer):
  kubectl -n argocd port-forward svc/argocd-server 8080:443
EOF
