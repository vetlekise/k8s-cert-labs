# CKAD Practice Questions

Each lab below is written as an exam-style task. Expand **Hint** for a pointer to the official Kubernetes docs, and expand **Answer** to reveal the solution.

> [!NOTE]
> Scenarios **1** (build/export an image) and **13** (fix an old manifest) are local
> file exercises under [scenarios/ckad/](../scenarios/ckad/); they have no `task setup`.

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
11. [Monitor CPU Usage Across Pods](#11-monitor-cpu-usage-across-pods)
12. [Traffic Splitting Using Native Kubernetes Objects](#12-traffic-splitting-using-native-kubernetes-objects)
13. [Update a Deployment Manifest API Version](#13-update-a-deployment-manifest-api-version)
14. [Design a Multi-Container Pod with a Sidecar](#14-design-a-multi-container-pod-with-a-sidecar)
15. [Provision Storage with a PersistentVolume and PVC](#15-provision-storage-with-a-persistentvolume-and-pvc)
16. [Create and Consume a ConfigMap](#16-create-and-consume-a-configmap)
17. [Set Container Resources and Expand a Namespace Quota](#17-set-container-resources-and-expand-a-namespace-quota)
18. [Expose an Application with an Ingress](#18-expose-an-application-with-an-ingress)

---

## 1. Build and Export a Container Image in OCI Format

**Task:** Build the image `devmaq:3.0` from the Dockerfile at `~/home/Dockerfile`. Export it in OCI format to `~/human-stork/devmac-3.0.tar`. Do not push or run the image.

<details>
<summary>Hint</summary>

[Kubernetes: Images](https://kubernetes.io/docs/concepts/containers/images/) · [Podman: build](https://docs.podman.io/en/latest/markdown/podman-build.1.html) · [Podman: save](https://docs.podman.io/en/latest/markdown/podman-save.1.html)

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

**Task:** In namespace `nov2025`: add the label `func: webFrontend` to the pod template of `nov2025-deployment`, add both a **readiness probe** and a **liveness probe** that do an HTTP GET on path `/healthz` on port 8080, and scale the deployment to 4 replicas. Create a NodePort Service named `berry` on port 8080 that selects that label.

<details>
<summary>Hint</summary>

[Service: type NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) · [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

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

```bash
# generate the Service manifest imperatively
kubectl create service nodeport berry --tcp=8080:8080 -n nov2025 \
  --dry-run=client -o yaml > svc.yaml
# edit svc.yaml to set the selector to func: webFrontend
```

```yaml
# svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: berry
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

**Task:** Namespace `kdsn00201` contains four pods (`front`, `db`, `dmz`, and `newpod`), each labelled only with `app=<pod-name>`, plus four existing NetworkPolicies: `default-deny-all`, `allow-db-access`, `allow-front-access`, and `allow-all-access`. Without creating, modifying, or deleting any NetworkPolicy, make `newpod` able to send to and receive from **only** the `front` and `db` pods (never `dmz`).

<details>
<summary>Hint</summary>

[Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Inspect the policies to learn WHICH labels grant access to front and db
kubectl describe networkpolicy allow-db-access -n kdsn00201     # allows from db-access=true
kubectl describe networkpolicy allow-front-access -n kdsn00201  # allows from front-access=true
# allow-all-access only targets app=public (a decoy); default-deny-all blocks the rest.

# 2. Add BOTH access labels to newpod so the two policies permit it, no policy edits needed
kubectl label pod newpod -n kdsn00201 db-access=true front-access=true

# 3. Verify labels
kubectl get pod newpod -n kdsn00201 --show-labels
```

```bash
# 4. Test connectivity from newpod (netshoot has curl). Grab the target IPs first.
kubectl get pods -n kdsn00201 -o wide
kubectl exec newpod -n kdsn00201 -- curl -s --max-time 3 http://<db-ip>     # succeeds
kubectl exec newpod -n kdsn00201 -- curl -s --max-time 3 http://<front-ip>  # succeeds
kubectl exec newpod -n kdsn00201 -- curl -s --max-time 3 http://<dmz-ip>    # times out
```

> [!NOTE]
> `default-deny-all` blocks everything not explicitly allowed. `allow-db-access` and `allow-front-access` only admit traffic from pods carrying `db-access=true` / `front-access=true`, so labelling `newpod` with both is what lets it reach `front` and `db` while `dmz` stays unreachable. NetworkPolicies are stateful, so reply traffic on connections `newpod` opens comes back automatically, so you never need to touch the policies themselves. A blocked connection just hangs until `--max-time` expires.

</details>

---

## 8. Update, Rollout, and Rollback Deployments

**Task:** Update the `app` deployment in `nov2025` with `maxSurge=5%` and `maxUnavailable=2%`. Update the container image of the `web1` deployment to `nginx:1.13` using a rolling update. Then roll back the `web1` deployment to its previous revision.

<details>
<summary>Hint</summary>

[Deployments: Updating & Rolling Back](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

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
kubectl describe deployment web1 -n nov2025 | grep Image  # find container name
kubectl set image deployment/web1 web1=nginx:1.13 -n nov2025
kubectl rollout undo deployment/web1 -n nov2025
```

</details>

---

## 9. Create and Configure a CronJob

**Task:** Create a CronJob `log-cleaner` in namespace `production` that runs `busybox` executing `date` every 30 minutes. The container must be named `log`, and the job must have 2 completions, 3 retries, and terminate after 30 seconds. Finally, manually trigger the CronJob by creating a Job named `manual-run` from it, then verify it ran by checking its logs.

<details>
<summary>Hint</summary>

[Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/)
[Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)

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
kubectl create job --from=cronjob/log-cleaner manual-run -n production  # manual trigger
kubectl logs -l job-name=manual-run -n production
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

## 11. Monitor CPU Usage Across Pods

**Task:** Find the highest CPU-consuming pod in namespace `cpu-stress` and write its name to a file.

<details>
<summary>Hint</summary>

[kubectl top pod](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#top)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl top pods -n cpu-stress --sort-by=cpu
echo "<pod-name>" > /opt/ckadnov2025/pod.txt
```

</details>

---

## 12. Traffic Splitting Using Native Kubernetes Objects

**Task:** In namespace `production`, an existing NodePort Service `webapp-svc` sends traffic to the `webapp` Deployment's 5 pods. Create an **identical** Deployment with a **different** name (e.g. `webapp-canary`) so that approximately 20% of traffic reaches it, using only native Kubernetes objects (no Ingress or Service Mesh). The namespace must not exceed 10 pods total (enforced by a ResourceQuota). Verify the split by running `curl -s localhost:30080/hostname` a few times.

<details>
<summary>Hint</summary>

[Service: defining a Service](https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service)

</details>

<details>
<summary>Answer</summary>

```bash
# The Service selector is already the shared label (app: webapp), so any pod
# carrying it receives traffic. You just need a second, identical deployment
# with a DIFFERENT name and a DISTINCT selector so it doesn't clash with the
# original. Start from the existing deployment's manifest:
kubectl get deployment webapp -n production -o yaml > webapp-canary.yaml
```

Edit `webapp-canary.yaml`:

```yaml
# - metadata.name: webapp-canary
# - spec.replicas: 2
# - change the version label to canary in BOTH the selector and the pod template
#   (keep app: webapp so the Service still selects it)
# - strip runtime fields: status, metadata.uid, resourceVersion, creationTimestamp
metadata:
  name: webapp-canary
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webapp
      version: canary
  template:
    metadata:
      labels:
        app: webapp
        version: canary
        scenario: "12"
```

```bash
kubectl apply -f webapp-canary.yaml

# Scale the original up to 8 so the total stays within the 10-pod quota (8:2 = 80/20)
kubectl scale deployment webapp --replicas=8 -n production

kubectl get pods -n production --show-labels        # 8 webapp-* + 2 webapp-canary-*
kubectl describe svc webapp-svc -n production        # 10 endpoints listed
```

```bash
# /hostname returns the serving pod's name. Run it a few times to watch traffic
# load-balance across BOTH deployments (~80% webapp-*, ~20% webapp-canary-*).
curl -s localhost:30080/hostname
```

</details>

---

## 13. Update a Deployment Manifest API Version

**Task:** The deployment manifest at `scenarios/ckad/13-api-version/ckad-deploy.yaml` was written for an old cluster and no longer applies cleanly (`kubectl apply -f ckad-deploy.yaml` fails). Fix the file so it deploys successfully on the current Kubernetes version (v1.32).

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

- `kubectl api-resources` lists all available resources and their supported API group/version for your cluster.
- `kubectl explain deployment` outputs the schema and the correct API version (`VERSION: apps/v1`) active on the cluster.

</details>

---

## 14. Design a Multi-Container Pod with a Sidecar

**Task:** Create a Pod named `webserver` in namespace `logging` that runs `nginx` with a logging sidecar. The main container `nginx` uses image `nginx:1.25`. Add a **native sidecar** container named `sidecar` (an init container with `restartPolicy: Always`) using image `busybox:1.36` that runs `sh -c "tail -F /var/log/nginx/access.log"`. Both containers share an `emptyDir` volume mounted at `/var/log/nginx`, so the sidecar streams the nginx access log.

<details>
<summary>Hint</summary>

[Communicate Between Containers in the Same Pod](https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/) · [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)

</details>

<details>
<summary>Answer</summary>

```yaml
# webserver.yaml
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  namespace: logging
spec:
  volumes:
  - name: logs
    emptyDir: {}
  containers:
  - name: nginx
    image: nginx:1.25
    volumeMounts:
    - name: logs
      mountPath: /var/log/nginx
  initContainers:
  - name: sidecar
    image: busybox:1.36
    restartPolicy: Always   # makes this a native sidecar (starts before, runs alongside nginx)
    command: ["sh", "-c", "tail -F /var/log/nginx/access.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/nginx
```

```bash
kubectl apply -f webserver.yaml
kubectl get pod webserver -n logging -o jsonpath='{.spec.initContainers[*].name}{"\n"}'  # verify the sidecar
kubectl logs webserver -c sidecar -n logging   # streams the nginx access log
```

> [!NOTE]
> A **native sidecar** is an init container with `restartPolicy: Always`. Unlike a normal init container (which must run to completion first), it starts before the main containers and keeps running for the Pod's lifetime, so it does **not** block startup. Using `tail -F` (capital) is important: the sidecar starts before `nginx` creates `access.log`, and `-F` retries instead of crashing. The Pod shows `1/1` Ready because init containers don't count toward the READY total.

</details>

---

## 15. Provision Storage with a PersistentVolume and PVC

**Task:** Create a PersistentVolume `data-pv` with 1Gi capacity, `ReadWriteOnce` access, and hostPath `/mnt/data`. Create a PersistentVolumeClaim `data-pvc` in namespace `storage` that requests 512Mi with `ReadWriteOnce`. Then create a Pod `app` (image `nginx`) that mounts the claim at `/usr/share/nginx/html`.

<details>
<summary>Hint</summary>

[Configure a Pod to Use a PersistentVolume for Storage](https://kubernetes.io/docs/tutorials/configuration/configure-persistent-volume-storage/)
[PersistantVolume](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

</details>

<details>
<summary>Answer</summary>

```yaml
# storage.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: ["ReadWriteOnce"]
  hostPath:
    path: /mnt/data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: storage
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 512Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: storage
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
```

```bash
kubectl apply -f storage.yaml
kubectl get pvc data-pvc -n storage           # STATUS should be Bound
kubectl get pv data-pv                          # STATUS should be Bound to data-pvc
```

</details>

---

## 16. Create and Consume a ConfigMap

**Task:** Create a ConfigMap `app-config` in namespace `config` holding the literal `APP_COLOR=blue` and a file-style key `game.properties` with the content `difficulty=hard`. Create a Pod `configured` (image `nginx`) that exposes `APP_COLOR` as an environment variable and mounts the whole ConfigMap at `/etc/config`.

<details>
<summary>Hint</summary>

[Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl create configmap app-config -n config \
  --from-literal=APP_COLOR=blue \
  --from-literal=game.properties='difficulty=hard'
```

```yaml
# configured.yaml
apiVersion: v1
kind: Pod
metadata:
  name: configured
  namespace: config
spec:
  volumes:
  - name: config
    configMap:
      name: app-config
  containers:
  - name: nginx
    image: nginx
    env:
    - name: APP_COLOR
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: APP_COLOR
    volumeMounts:
    - name: config
      mountPath: /etc/config
```

```bash
kubectl apply -f configured.yaml
kubectl exec configured -n config -- env | grep APP_COLOR       # APP_COLOR=blue
kubectl exec configured -n config -- cat /etc/config/game.properties  # difficulty=hard
```

> [!NOTE]
> The ConfigMap value has no trailing newline, so `cat` prints `difficulty=hard` right before your shell prompt and can look like empty output. Append `echo` to force a line break: `kubectl exec configured -n config -- sh -c 'cat /etc/config/game.properties; echo'`.

</details>

---

## 17. Set Container Resources and Expand a Namespace Quota

**Task:** In namespace `budget`, the `api-deployment` Deployment runs 3 replicas whose containers have no resource constraints, so its pods are being rejected by the namespace ResourceQuota. Add resource **requests** of `cpu=250m, memory=128Mi` and **limits** of `cpu=500m, memory=256Mi` to its container. The namespace has an existing ResourceQuota named `budget-quota`; double every value in its `hard` block (both the `requests.*` and `limits.*` entries) so all three replicas can schedule.

<details>
<summary>Hint</summary>

[Assign CPU Resources to Containers](https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/) · [Assign Memory Resources to Containers](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) · [Configure Memory and CPU Quotas for a Namespace](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Inspect the current quota so you know what to double
kubectl describe resourcequota budget-quota -n budget
```

```bash
# 2. Add requests/limits to the deployment's container
kubectl edit deployment api-deployment -n budget
```

```yaml
# under spec.template.spec.containers[]
resources:
  requests:
    cpu: 250m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

```bash
# 3. Double each hard limit on the quota (read the current values first, then double them)
kubectl edit resourcequota budget-quota -n budget
```

```yaml
spec:
  hard:
    requests.cpu: "1"        # was 500m
    requests.memory: 512Mi   # was 256Mi
    limits.cpu: "2"          # was "1"
    limits.memory: 1Gi       # was 512Mi
```

```bash
# 4. Verify the deployment schedules and the quota reflects new usage
kubectl get deployment api-deployment -n budget
kubectl describe resourcequota budget-quota -n budget
```

> [!IMPORTANT]
> Every container in a namespace with a ResourceQuota that constrains `requests.*`/`limits.*` must declare those requests/limits, or the pod is rejected. Double **every** value in the quota's `hard` block, including the `requests.cpu`/`requests.memory` entries, not just the `limits.*` ones. Read the existing quota values first, "double" means multiply whatever is currently set, not a fixed number.

</details>

---

## 18. Expose an Application with an Ingress

**Task:** In namespace `frontend`, an existing Service `hello-svc` listens on port `80`. Create an Ingress named `hello-ingress` that routes HTTP requests for host `hello.example.com` on path `/` (`pathType: Prefix`) to `hello-svc:80`.

<details>
<summary>Hint</summary>

[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

</details>

<details>
<summary>Answer</summary>

```bash
# imperative: generate (or directly create) the Ingress
kubectl create ingress hello-ingress -n frontend \
  --rule="hello.example.com/*=hello-svc:80"
```

> The `/*` in the rule maps to `pathType: Prefix` on path `/`. Add `--dry-run=client -o yaml > ingress.yaml` if you want to review/tweak the manifest before applying.

```yaml
# ingress.yaml (equivalent declarative form)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-ingress
  namespace: frontend
spec:
  rules:
  - host: hello.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-svc
            port:
              number: 80
```

```bash
kubectl apply -f ingress.yaml
kubectl describe ingress hello-ingress -n frontend   # confirm host/path and backend service
```

> [!NOTE]
> An Ingress needs a running Ingress controller to actually serve traffic. On the exam the object just has to be created correctly; the backend `service.port.number` must match the Service's port.

</details>
