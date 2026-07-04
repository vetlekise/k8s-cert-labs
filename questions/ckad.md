# CKAD Practice Questions

Each lab below is written as an exam-style task. Expand **Hint** for a pointer to the official Kubernetes docs, and expand **Answer** to reveal the solution.

## Table of Contents

1. [Build and Export a Container Image in OCI Format](#1-build-and-export-a-container-image-in-oci-format)
2. [Configure a Security Context for a Deployment](#2-configure-a-security-context-for-a-deployment)
3. [Use Existing Secrets in a Deployment](#3-use-existing-secrets-in-a-deployment)
4. [Resolve ServiceAccount Permissions by Binding a Role](#4-resolve-serviceaccount-permissions-by-binding-a-role)
5. [Create a ServiceAccount and Grant Pod Access](#5-create-a-serviceaccount-and-grant-pod-access)
6. [Scale a Deployment and Expose It via NodePort](#6-scale-a-deployment-and-expose-it-via-nodeport)
7. [Apply Existing NetworkPolicies to Segment Traffic](#7-apply-existing-networkpolicies-to-segment-traffic)
8. [Update, Rollout, and Rollback Deployments](#8-update-rollout-and-rollback-deployments)
9. [Create and Configure a CronJob](#9-create-and-configure-a-cronjob)
10. [Create a Redis Cache Pod](#10-create-a-redis-cache-pod)
11. [Deploy a Pod, Retrieve Logs, and Monitor CPU Usage](#11-deploy-a-pod-retrieve-logs-and-monitor-cpu-usage)
12. [Traffic Splitting Using Native Kubernetes Objects](#12-traffic-splitting-using-native-kubernetes-objects)
13. [Update a Deployment Manifest API Version](#13-update-a-deployment-manifest-api-version)

---

## 1. Build and Export a Container Image in OCI Format

**Task:** Build the image `devmaq:3.0` from the Dockerfile at `~/home/Dockerfile`. Export it in OCI format to `~/human-stork/devmac-3.0.tar`. Do not push or run the image.

<details>
<summary>Hint</summary>

[Kubernetes — Images](https://kubernetes.io/docs/concepts/containers/images/) · [Podman: build](https://docs.podman.io/en/latest/markdown/podman-build.1.html) · [Podman: save](https://docs.podman.io/en/latest/markdown/podman-save.1.html)

</details>

<details>
<summary>Answer</summary>

```bash
podman build -t devmaq:3.0 -f ~/home/Dockerfile ~/home/
mkdir -p ~/human-stork/
podman save --format oci-archive -o ~/human-stork/devmac-3.0.tar devmaq:3.0
```

</details>

---

## 2. Configure a Security Context for a Deployment

**Task:** In the `hotfix-deployment` Deployment (namespace `quetzal`), configure the containers to run as user `30000` and forbid privilege escalation.

<details>
<summary>Hint</summary>

[Configure a Security Context for a Pod or Container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

</details>

<details>
<summary>Answer</summary>

```bash
vi ~/broker-deployment/hotfix-deployment.yaml
```

Add at the container level:

```yaml
securityContext:
  runAsUser: 30000
  allowPrivilegeEscalation: false
```

```bash
kubectl apply -f ~/broker-deployment/hotfix-deployment.yaml
```

</details>

---

## 3. Use Existing Secrets in a Deployment

**Task:** The `db-deployment` Deployment in namespace `secure` currently passes its credentials as clear-text environment variables: `DB_USER=admin`, `DB_PASSWORD=P@ssw0rd123`, and `DB_DATABASE=appdb`. Create a Secret named `db-credentials` that stores these values under the keys `username`, `password`, and `database`. Then edit the Deployment so the same three environment variables source their values from the Secret instead of clear text.

<details>
<summary>Hint</summary>

[Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) · [Using Secrets as environment variables](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-environment-variables)

</details>

<details>
<summary>Answer</summary>

```bash
# Inspect the current clear-text values in the deployment
kubectl get deployment db-deployment -n secure -o yaml | grep -A1 'DB_'

# Create the secret with the required KEYS (username/password/database)
kubectl create secret generic db-credentials -n secure \
  --from-literal=username=admin \
  --from-literal=password='P@ssw0rd123' \
  --from-literal=database=appdb

kubectl edit deployment db-deployment -n secure
```

Replace the clear-text `env` values with `secretKeyRef` entries. The env var **names** stay the same (that's what the app reads); only their **values** now come from the secret keys:

```yaml
env:
- name: DB_USER
  valueFrom:
    secretKeyRef: {name: db-credentials, key: username}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef: {name: db-credentials, key: password}
- name: DB_DATABASE
  valueFrom:
    secretKeyRef: {name: db-credentials, key: database}
```

```bash
# Verify the pod comes up with the values resolved from the secret
kubectl exec deploy/db-deployment -n secure -- env | grep DB_
```

> [!IMPORTANT]
> Watch the mapping: the container env var names (`DB_USER`, `DB_PASSWORD`, `DB_DATABASE`) differ from the secret keys (`username`, `password`, `database`).

</details>

---

## 4. Resolve ServiceAccount Permissions by Binding a Role

**Task:** The `dev-deployment` Deployment in namespace `meta` is logging RBAC permission errors. Two Roles already exist in the namespace. Read the deployment logs to determine which permissions are missing, then bind the correct existing Role to the ServiceAccount the deployment uses so the errors stop. Do not create new Roles.

<details>
<summary>Hint</summary>

[Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) · [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Read the logs to see exactly which action is forbidden
kubectl logs deployment/dev-deployment -n meta

# 2. Find which ServiceAccount the deployment runs as
kubectl get deployment dev-deployment -n meta \
  -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'

# 3. Inspect both existing roles and pick the one matching the error
kubectl get roles -n meta
kubectl describe role <role-1> -n meta
kubectl describe role <role-2> -n meta

# 4. Bind the correct role to that ServiceAccount
kubectl create rolebinding dev-rolebinding \
  --role=<correct-role> \
  --serviceaccount=meta:<sa-name> -n meta

# 5. Restart and re-check the logs
kubectl rollout restart deployment/dev-deployment -n meta
kubectl logs deployment/dev-deployment -n meta
```

</details>

---

## 5. Create a ServiceAccount and Grant Pod Access

**Task:** The `reporter-deployment` Deployment in namespace `audit` is failing because its ServiceAccount cannot `get` or `list` pods (confirm this in the deployment logs). Create a new ServiceAccount, grant it permission to get and list pods via a Role and RoleBinding, and update the Deployment to use the new ServiceAccount.

<details>
<summary>Hint</summary>

[Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) · [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Confirm the error in the logs
kubectl logs deployment/reporter-deployment -n audit   # e.g. "cannot list resource \"pods\""

# 2. Create the ServiceAccount
kubectl create serviceaccount reporter-sa -n audit

# 3. Create a Role granting get/list on pods
kubectl create role pod-reader --verb=get --verb=list --resource=pods -n audit

# 4. Bind the Role to the ServiceAccount
kubectl create rolebinding reporter-binding \
  --role=pod-reader \
  --serviceaccount=audit:reporter-sa -n audit

# 5. Point the deployment at the new ServiceAccount
kubectl set serviceaccount deployment/reporter-deployment reporter-sa -n audit

# 6. Verify the errors are gone
kubectl logs deployment/reporter-deployment -n audit
```

</details>

---

## 6. Scale a Deployment and Expose It via NodePort

**Task:** In namespace `nov2025`: add the label `func: webFrontend` to the pod template of `nov2025-deployment`, add a health check that probes the HTTP path `/healthz` on port 8080, and scale the deployment to 4 replicas. Create a NodePort Service named `Berry` on port 8080 that selects that label.

<details>
<summary>Hint</summary>

[Service — type NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) · [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl edit deployment nov2025-deployment -n nov2025
# Set replicas: 4
# Add under spec.template.metadata.labels: func: webFrontend
# Add the probe(s) under spec.template.spec.containers[]
```

```yaml
# container excerpt in the pod template (spec.template.spec.containers[])
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

```yaml
# svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: Berry
  namespace: nov2025
spec:
  type: NodePort
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    func: webFrontend
```

```bash
kubectl apply -f svc.yaml
```

</details>

---

## 7. Apply Existing NetworkPolicies to Segment Traffic

**Task:** Namespace `kdsn00201` already contains four NetworkPolicies: `allow-all`, `allow-frontend`, `allow-backend`, and `default-deny`. Without modifying any of them, ensure that only frontend pods can reach the frontend pods and only backend pods can reach the backend pods. Do this by applying the correct labels to the pods so the intended policies select them.

<details>
<summary>Hint</summary>

[Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. List the policies and inspect what each one selects and allows
kubectl get networkpolicy -n kdsn00201
kubectl describe networkpolicy allow-frontend -n kdsn00201  # note podSelector + allowed ingress
kubectl describe networkpolicy allow-backend -n kdsn00201

# 2. Label each pod so the matching policy applies
#    (use the label key/value referenced in each policy's podSelector)
kubectl label pod <frontend-pod> role=frontend -n kdsn00201
kubectl label pod <backend-pod>  role=backend  -n kdsn00201

# 3. Verify the labels
kubectl get pods -n kdsn00201 --show-labels
```

> [!NOTE]
> `default-deny` is the baseline that blocks everything not explicitly allowed. `allow-frontend` and `allow-backend` only permit ingress from pods carrying the matching `role` label, so correct labeling is what enforces the segmentation.

</details>

---

## 8. Update, Rollout, and Rollback Deployments

**Task:** Update the `app` deployment in `nov2025` with `maxSurge=5%` and `maxUnavailable=2%`. Update the container image of the `web1` deployment to `nginx:1.13` using a rolling update. Then roll back the `app` deployment to its previous revision.

<details>
<summary>Hint</summary>

[Deployments — Updating & Rolling Back](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl edit deployment app -n nov2025
```

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 5%
      maxUnavailable: 2%
```

```bash
kubectl describe deployment web1 | grep Image  # find container name
kubectl set image deployment/web1 <container-name>=repo/nginx:1.13
kubectl rollout undo deployment/app -n nov2025
```

</details>

---

## 9. Create and Configure a CronJob

**Task:** Create a CronJob `log-cleaner` in namespace `production` that runs `busybox` executing `date` every 30 minutes. The container must be named `log`, and the job must have 2 completions, 3 retries, and terminate after 30 seconds.

<details>
<summary>Hint</summary>

[Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl create cronjob log-cleaner --image=busybox --schedule="*/30 * * * *" \
  -n production --dry-run=client -oyaml -- date > cronjob.yaml
```

Edit `jobTemplate.spec`:

```yaml
completions: 2
backoffLimit: 3
activeDeadlineSeconds: 30
template:
  spec:
    containers:
    - name: log        # rename from busybox
      image: busybox
      command: [date]
    restartPolicy: OnFailure
```

```bash
kubectl apply -f cronjob.yaml
kubectl create job --from=cronjob/log-cleaner test-run -n production  # manual trigger to verify
kubectl logs -l job-name=test-run -n production
```

</details>

---

## 10. Create a Redis Cache Pod

**Task:** Create a Pod named `cache` in the `web` namespace using image `lfccncf/redis:3.2`, exposing port `6379`.

<details>
<summary>Hint</summary>

[kubectl run reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#run)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl run cache --image=lfccncf/redis:3.2 -n web --port=6379
```

</details>

---

## 11. Deploy a Pod, Retrieve Logs, and Monitor CPU Usage

**Task 1:** Deploy the Pod from the manifest and save its logs to a file.

**Task 2:** Find the highest CPU-consuming pod in namespace `cpu-stress` and write its name to a file.

<details>
<summary>Hint</summary>

[kubectl logs](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#logs) · [kubectl top pod](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#top)

</details>

<details>
<summary>Answer</summary>

```bash
# Task 1
kubectl apply -f /opt/ckadnov2025/winter.yaml
kubectl logs winter > /opt/ckadnov2025/log_Output.txt

# Task 2
kubectl top pods -n cpu-stress --sort-by=cpu
echo "<pod-name>" > /opt/ckadnov2025/pod.txt
```

</details>

---

## 12. Traffic Splitting Using Native Kubernetes Objects

**Task:** Route approximately 80% of traffic to `webapp` v1 and 20% to v2 in namespace `production`, using only native Kubernetes objects (no Ingress or Service Mesh). Use a single Service `webapp-svc`.

<details>
<summary>Hint</summary>

[Service — defining a Service](https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service)

</details>

<details>
<summary>Answer</summary>

```bash
# 4:1 replica ratio = 80/20 split
kubectl scale deployment webapp-v1 --replicas=4 -n production
kubectl scale deployment webapp-v2 --replicas=1 -n production
kubectl get pods -n production --show-labels  # verify both share a common label
kubectl edit svc webapp-svc -n production
```

```yaml
# Service selector must match the common label of BOTH versions (e.g. app: webapp)
# Do NOT include version-specific labels in the selector
spec:
  selector:
    app: webapp
```

```bash
kubectl describe svc webapp-svc -n production  # verify 5 endpoints listed
```

</details>

---

## 13. Update a Deployment Manifest API Version

**Task:** Update `~/ckad-deploy.yaml` (created on an old cluster) so it works on Kubernetes v1.32.

**Required changes:**

- Change `apiVersion` from `extensions/v1beta1` to `apps/v1`.
- Add the `spec.selector.matchLabels` block. In `apps/v1` the selector is strictly required and must match the pod template labels.

<details>
<summary>Hint</summary>

[Deprecated API Migration Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

</details>

<details>
<summary>Answer</summary>

```yaml
# OLD (extensions/v1beta1):
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx

# NEW (apps/v1):
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:              # REQUIRED IN v1
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx
```

**Verify the correct API version in the terminal:**

- `kubectl api-resources` — lists all available resources and their supported API group/version for your cluster.
- `kubectl explain deployment` — outputs the schema and the correct API version (`VERSION: apps/v1`) active on the cluster.

</details>
