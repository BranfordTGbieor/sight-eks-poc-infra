#!/usr/bin/env bash

set -euo pipefail

# Install Argo CD and seed the root application that fans out the rest of GitOps.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-repo-server -n argocd --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-applicationset-controller -n argocd --timeout=300s
kubectl apply -f "${ROOT_DIR}/gitops/argocd/bootstrap/root-application.yaml"
