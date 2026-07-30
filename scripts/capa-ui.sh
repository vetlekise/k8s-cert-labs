#!/usr/bin/env bash
# Open all three Argo UIs at once and tear every port-forward down on Ctrl-C.
# Run with real bash (not Task's embedded shell) so `trap` and process-group
# signalling work reliably. Invoked by the `capa:ui` task.
set -euo pipefail

echo "Argo Workflows UI: http://localhost:2746"
echo "Argo CD UI:        https://localhost:8080 (user: admin, password: task capa:password)"
echo "Argo Rollouts:     http://localhost:3100/rollouts"

# Kill the whole process group (this script + all child kubectl forwards) on exit
# or interrupt. `kill 0` targets the current process group.
trap 'kill 0' EXIT INT TERM

kubectl -n argo port-forward svc/argo-server 2746:2746 &
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
kubectl argo rollouts dashboard &

wait
