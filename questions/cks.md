# CKS Practice Questions

Each lab below is written as an exam-style task. Expand **Hint** for a pointer to the official Kubernetes docs, and expand **Answer** to reveal the solution.

The scenarios cover every domain of the **Certified Kubernetes Security Specialist (CKS)** exam:

| Domain | Weight | Scenarios |
| --- | --- | --- |
| Cluster Setup | 15% | 6, 7, 8, 15 |
| Cluster Hardening | 15% | 3, 4, 5, 20 |
| System Hardening | 10% | 10, 11 |
| Minimize Microservice Vulnerabilities | 20% | 2, 9, 12, 13 |
| Supply Chain Security | 20% | 1, 16, 17, 18 |
| Monitoring, Logging & Runtime Security | 20% | 13, 14, 19 |

> [!NOTE]
> Some scenarios are **local file** or **node** exercises that do not map to a
> `task setup`: **1** and **17** (edit a file), **14** (apiserver audit policy on
> the control-plane node), **15** (CIS benchmark / kube-bench), **18** (SBOM), and
> **20** (kubeadm upgrade). Scenarios **10** (AppArmor) and **19** (Falco) create
> in-cluster resources but also need node-level tooling that vanilla kind does not
> ship — read their notes.

> [!TIP]
> On the real exam you may install/upgrade tools and read the docs at
> `kubernetes.io`, `github.com/kubernetes`, and the Falco/Trivy/AppArmor sites.
> Set up your kubectl alias and, importantly, always `ssh` to the host named in
> the task before you start — solving on the wrong node scores zero.

## Table of Contents

1. [Harden a Dockerfile](#1-harden-a-dockerfile)
2. [Fix an Insecure Security Context](#2-fix-an-insecure-security-context)
3. [Disable Token Automount and Inject a Projected Token](#3-disable-token-automount-and-inject-a-projected-token)
4. [Minimize RBAC Permissions](#4-minimize-rbac-permissions)
5. [Create a ServiceAccount With No Secret Access](#5-create-a-serviceaccount-with-no-secret-access)
6. [Expose a Pod via an Ingress With TLS](#6-expose-a-pod-via-an-ingress-with-tls)
7. [Default-Deny NetworkPolicy Baseline](#7-default-deny-networkpolicy-baseline)
8. [Protect the Node Metadata Endpoint](#8-protect-the-node-metadata-endpoint)
9. [Enforce Pod Security Standards](#9-enforce-pod-security-standards)
10. [Confine a Pod With AppArmor](#10-confine-a-pod-with-apparmor)
11. [Confine a Pod With seccomp](#11-confine-a-pod-with-seccomp)
12. [Manage Kubernetes Secrets](#12-manage-kubernetes-secrets)
13. [Make a Container Immutable at Runtime](#13-make-a-container-immutable-at-runtime)
14. [Enable Kubernetes Audit Logging](#14-enable-kubernetes-audit-logging)
15. [Review the Cluster With the CIS Benchmark](#15-review-the-cluster-with-the-cis-benchmark)
16. [Restrict Images to a Permitted Registry](#16-restrict-images-to-a-permitted-registry)
17. [Static Analysis of a Workload Manifest](#17-static-analysis-of-a-workload-manifest)
18. [Generate a Software Bill of Materials (SBOM)](#18-generate-a-software-bill-of-materials-sbom)
19. [Detect Runtime Threats With Falco](#19-detect-runtime-threats-with-falco)
20. [Upgrade Kubernetes With kubeadm](#20-upgrade-kubernetes-with-kubeadm)

---

## 1. Harden a Dockerfile

**Task:** Analyze and edit the Dockerfile at `scenarios/cks/01-dockerfile-hardening/Dockerfile`. Fix the **two** most prominent security best-practice issues without changing what the image does. Whenever an unprivileged user is needed, use user `test-user` with uid `5487`.

<details>
<summary>Hint</summary>

[Docker: Dockerfile best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/) · [Kubernetes: Images](https://kubernetes.io/docs/concepts/containers/images/)

</details>

<details>
<summary>Answer</summary>

The two prominent security issues are the **floating `latest` base image tag** (non-reproducible, may pull an image with new CVEs) and **running as `root`** (`USER root`).

```dockerfile
# BEFORE
FROM ubuntu:latest
...
USER root

# AFTER
FROM ubuntu:24.04            # pin the base image to a specific, known tag
...
# create and switch to an unprivileged user instead of root
RUN useradd -u 5487 test-user
USER test-user               # or: USER 5487
```

```dockerfile
# Full hardened Dockerfile
FROM ubuntu:24.04
RUN apt-get update -y
RUN apt-get install nginx -y
COPY entrypoint.sh /
RUN useradd -u 5487 test-user
ENTRYPOINT ["/entrypoint.sh"]
USER test-user
```

> [!IMPORTANT]
> Fix only the two prominent security issues asked for. The order matters: put
> `USER` after the `apt-get`/`useradd` steps that need root, and keep it as the
> last instruction so the container runs unprivileged.

</details>

---

## 2. Fix an Insecure Security Context

**Task:** `task setup S=02 C=cks`. The Deployment `security-context-demo` in namespace `sec-ctx` runs with two prominent security-context problems. Fix **only** those two fields; do not add or remove any other configuration. Where an unprivileged user is required, use uid `5487`.

<details>
<summary>Hint</summary>

[Configure a Security Context for a Pod or Container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

</details>

<details>
<summary>Answer</summary>

The two problems are the container running as **root** (`runAsUser: 0`, overriding the pod-level `1000`) and running **privileged** (`privileged: true`).

```bash
kubectl edit deployment security-context-demo -n sec-ctx
```

```yaml
# spec.template.spec.containers[].securityContext
securityContext:
  runAsUser: 5487        # was 0 (root)
  privileged: false      # was true
  allowPrivilegeEscalation: false   # leave as-is
```

```bash
# Verify the new pod runs as 5487 and is no longer privileged
kubectl get pod -n sec-ctx -l app=sec-ctx-demo \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}{"\n"}'
kubectl exec -n sec-ctx deploy/security-context-demo -- id   # uid=5487
```

> [!NOTE]
> Don't touch the other fields. `privileged: true` grants near-root access to the
> host; `runAsUser: 0` runs the process as root inside the container. Both are the
> "prominent" issues here.

</details>

---

## 3. Disable Token Automount and Inject a Projected Token

**Task:** `task setup S=03 C=cks`. A security audit found the `stats-monitor` Deployment in namespace `monitoring` improperly handling its ServiceAccount token. First, modify the existing ServiceAccount `stats-monitor-sa` to turn off automounting of API credentials. Then modify the Deployment to inject the ServiceAccount token via a **projected volume** named `token`, mounted **read-only** at `/var/run/secrets/kubernetes.io/serviceaccount/token`.

<details>
<summary>Hint</summary>

[Configure Service Accounts: opt out of automounting](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting) · [Projected Volumes: serviceAccountToken](https://kubernetes.io/docs/concepts/storage/projected-volumes/#serviceaccounttoken)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Turn off automounting on the ServiceAccount
kubectl patch serviceaccount stats-monitor-sa -n monitoring \
  -p '{"automountServiceAccountToken": false}'
```

```bash
# 2. Add a projected token volume + read-only mount to the Deployment
kubectl edit deployment stats-monitor -n monitoring
```

```yaml
# spec.template.spec
spec:
  serviceAccountName: stats-monitor-sa
  automountServiceAccountToken: false     # keep the pod from automounting too
  volumes:
    - name: token
      projected:
        sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600
  containers:
    - name: stats-monitor
      # ...
      volumeMounts:
        - name: token
          mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          readOnly: true
```

```bash
# 3. Verify the token is present and the mount is read-only
kubectl exec -n monitoring deploy/stats-monitor -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token | head -c 20; echo
kubectl get sa stats-monitor-sa -n monitoring -o jsonpath='{.automountServiceAccountToken}{"\n"}'
```

> [!IMPORTANT]
> The mount path is the **directory** `/var/run/secrets/kubernetes.io/serviceaccount`
> and the projected source `path: token` places the file `token` inside it. Setting
> `readOnly: true` on the `volumeMount` satisfies the read-only requirement.

</details>

---

## 4. Minimize RBAC Permissions

**Task:** `task setup S=04 C=cks`. In namespace `security`, the Pod `web-pod` runs as ServiceAccount `sa-dev-1`, whose bound Role `role-1` is overly permissive. Edit `role-1` to allow **only** `watch` on `services`. Then create a new Role `role-2` that allows **only** `update` on `namespaces`, and a RoleBinding `role-2-binding` binding it to `sa-dev-1`.

<details>
<summary>Hint</summary>

[Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Trim role-1 down to only watch on services
kubectl edit role role-1 -n security
```

```yaml
rules:
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["watch"]
```

```bash
# 2. Create the minimal role-2 (update on namespaces)
kubectl create role role-2 -n security \
  --verb=update --resource=namespaces

# 3. Bind role-2 to the pod's ServiceAccount
kubectl create rolebinding role-2-binding -n security \
  --role=role-2 --serviceaccount=security:sa-dev-1
```

```bash
# 4. Verify with auth can-i (impersonating the ServiceAccount)
kubectl auth can-i watch services -n security \
  --as=system:serviceaccount:security:sa-dev-1        # yes
kubectl auth can-i update namespaces \
  --as=system:serviceaccount:security:sa-dev-1        # yes
kubectl auth can-i delete pods -n security \
  --as=system:serviceaccount:security:sa-dev-1        # no
```

> [!NOTE]
> `namespaces` are cluster-scoped, but a namespaced Role/RoleBinding can still
> grant `update` on the resource type here as the exam intends. Confirm the trimmed
> permissions with `kubectl auth can-i ... --as=system:serviceaccount:<ns>:<sa>`.

</details>

---

## 5. Create a ServiceAccount With No Secret Access

**Task:** `task setup S=05 C=cks`. In namespace `qa`, the `frontend` pod runs as the `default` ServiceAccount, which can currently read Secrets. Create a new ServiceAccount `backend-qa` that must **not** have access to any Secret, and update the `frontend` pod to use it.

<details>
<summary>Hint</summary>

[Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Create the new ServiceAccount. A fresh SA has no RoleBindings, so it has no
#    access to Secrets (or anything else) by default — exactly what's required.
kubectl create serviceaccount backend-qa -n qa

# 2. Confirm it cannot read secrets (default has been granted access; backend-qa hasn't)
kubectl auth can-i list secrets -n qa \
  --as=system:serviceaccount:qa:default       # yes (the insecure default)
kubectl auth can-i list secrets -n qa \
  --as=system:serviceaccount:qa:backend-qa    # no
```

A running pod's `serviceAccountName` is immutable, so recreate it. If the manifest is on disk (e.g. `/home/candidate/frontend-pod.yaml`), edit it; otherwise dump, edit, re-apply:

```bash
kubectl get pod frontend -n qa -o yaml > frontend-pod.yaml
# set spec.serviceAccountName: backend-qa and strip status/runtime fields
kubectl delete pod frontend -n qa
# add "serviceAccountName: backend-qa" under spec, then:
kubectl apply -f frontend-pod.yaml
```

```bash
# 3. Verify the pod now runs as backend-qa
kubectl get pod frontend -n qa -o jsonpath='{.spec.serviceAccountName}{"\n"}'
```

> [!IMPORTANT]
> "Must not have access to any secret" is satisfied by **not granting** any
> Role that includes `secrets` — do not create a RoleBinding for `backend-qa`.
> RBAC is deny-by-default.

</details>

---

## 6. Expose a Pod via an Ingress With TLS

**Task:** `task setup S=06 C=cks`. In namespace `testing`, create a Pod named `nginx-pod` (image `nginx`), a Service named `nginx-svc` targeting it, and an Ingress that serves the Service over **TLS** on the secure port (443).

<details>
<summary>Hint</summary>

[Ingress: TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) · [Managing TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Create the pod and expose it as a service
kubectl run nginx-pod --image=nginx --port=80 -n testing --labels=app=nginx-pod
kubectl expose pod nginx-pod --name=nginx-svc --port=80 --target-port=80 -n testing

# 2. Generate a self-signed cert and store it as a TLS Secret
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=nginx.example.com/O=cks"
kubectl create secret tls nginx-tls -n testing --cert=tls.crt --key=tls.key
```

```yaml
# 3. ingress.yaml — reference the TLS secret
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: testing
spec:
  tls:
    - hosts:
        - nginx.example.com
      secretName: nginx-tls
  rules:
    - host: nginx.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-svc
                port:
                  number: 80
```

```bash
kubectl apply -f ingress.yaml
kubectl describe ingress nginx-ingress -n testing   # TLS terminates nginx.example.com
```

> [!NOTE]
> The `tls` block makes the Ingress terminate HTTPS on 443 using the referenced
> Secret. kind has no Ingress controller, so the object won't actually route
> traffic — creating it correctly (valid TLS Secret + backend port) is the task.

</details>

---

## 7. Default-Deny NetworkPolicy Baseline

**Task:** `task setup S=07 C=cks`. Namespace `ecom` has `app` (with Service `app`) and `client` pods and no NetworkPolicies. Create a **default-deny** baseline for both ingress and egress in the namespace, then re-allow only (a) DNS to kube-dns and (b) same-namespace traffic, so `client` can still reach `app` but nothing can leave the namespace.

<details>
<summary>Hint</summary>

[Network Policies: default deny all](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-ingress-and-all-egress-traffic) · [Allow DNS egress](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

</details>

<details>
<summary>Answer</summary>

```yaml
# netpol.yaml
# 1. Deny all ingress and egress in the namespace.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ecom
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
# 2. Allow DNS egress (UDP/TCP 53 to kube-dns in kube-system).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ecom
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
# 3. Allow ingress + egress WITHIN the namespace only.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ecom
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
```

```bash
kubectl apply -f netpol.yaml

# Verify: client -> app succeeds, but egress out of the namespace is blocked.
APP_IP=$(kubectl get pod app -n ecom -o jsonpath='{.status.podIP}')
kubectl exec client -n ecom -- curl -s --max-time 3 http://$APP_IP        # succeeds
kubectl exec client -n ecom -- curl -s --max-time 3 https://example.com   # times out
```

> [!NOTE]
> NetworkPolicies are additive: `default-deny-all` blocks everything, then the
> `allow-*` policies punch specific holes. DNS egress is easy to forget — without
> it, in-cluster name resolution breaks. Calico (installed by `task cluster:up`)
> enforces these policies.

</details>

---

## 8. Protect the Node Metadata Endpoint

**Task:** `task setup S=08 C=cks`. In namespace `metadata-lab`, block all pods from reaching the cloud node-metadata endpoint `169.254.169.254`, **except** pods labelled `role=metadata-client`.

<details>
<summary>Hint</summary>

[Network Policies: ipBlock](https://kubernetes.io/docs/concepts/services-networking/network-policies/#behavior-of-to-and-from-selectors) · [Restricting cloud metadata API access](https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/)

</details>

<details>
<summary>Answer</summary>

```yaml
# metadata-netpol.yaml
# Deny egress to the metadata IP for pods WITHOUT the role=metadata-client label,
# while still allowing all other egress + DNS.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata
  namespace: metadata-lab
spec:
  podSelector:
    matchExpressions:
      - key: role
        operator: NotIn
        values: ["metadata-client"]
  policyTypes: ["Egress"]
  egress:
    # allow everything EXCEPT the metadata address
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 169.254.169.254/32
    # keep DNS working
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

```bash
kubectl apply -f metadata-netpol.yaml

# app (no role label) is blocked; metadata-client is allowed.
kubectl exec app -n metadata-lab -- curl -s --max-time 3 http://169.254.169.254   # times out
kubectl exec metadata-client -n metadata-lab -- curl -s --max-time 3 http://169.254.169.254  # allowed
```

> [!NOTE]
> The policy selects every pod whose `role` is **not** `metadata-client` and
> allows egress to `0.0.0.0/0` **except** the metadata `/32`. `metadata-client`
> is not selected by any deny policy, so it keeps full access.

</details>

---

## 9. Enforce Pod Security Standards

**Task:** `task setup S=09 C=cks`. Enforce the **restricted** Pod Security Standard on namespace `pss` using Pod Security Admission, then fix the `web` Deployment so its pods are admitted under that standard.

<details>
<summary>Hint</summary>

[Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) · [Enforce Pod Security Standards with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Enforce the restricted standard via namespace labels
kubectl label namespace pss \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted --overwrite
```

```bash
# 2. Fix the deployment to comply with restricted (drop privileged, add the
#    required securityContext fields).
kubectl edit deployment web -n pss
```

```yaml
# spec.template.spec
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: web
      image: nginx:1.25
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        # remove privileged: true
```

```bash
# 3. Verify the pods are recreated and admitted (no PSA rejection)
kubectl rollout status deployment/web -n pss
kubectl get pods -n pss
```

> [!IMPORTANT]
> `restricted` requires `runAsNonRoot: true`, `allowPrivilegeEscalation: false`,
> `capabilities.drop: [ALL]`, and a `RuntimeDefault`/`Localhost` seccomp profile,
> and forbids `privileged`. Labelling the namespace only blocks **new** pods; you
> must roll the Deployment for the change to take effect.

</details>

---

## 10. Confine a Pod With AppArmor

**Task:** `task setup S=10 C=cks`. Confine the container in Pod `hello-apparmor` (namespace `apparmor`) with the AppArmor profile `k8s-apparmor-example-deny-write`, which is loaded on the node.

<details>
<summary>Hint</summary>

[Restrict a Container's Access to Resources with AppArmor](https://kubernetes.io/docs/tutorials/security/apparmor/)

</details>

<details>
<summary>Answer</summary>

On Kubernetes v1.30+ AppArmor is set via `securityContext.appArmorProfile`. A running pod's securityContext is immutable, so recreate it:

```yaml
# hello-apparmor.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello-apparmor
  namespace: apparmor
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-apparmor-example-deny-write
  containers:
    - name: hello
      image: busybox:1.36
      command: ["sh", "-c", "sleep infinity"]
```

```bash
kubectl delete pod hello-apparmor -n apparmor --ignore-not-found
kubectl apply -f hello-apparmor.yaml

# Verify: writes to the filesystem are now denied by the profile.
kubectl exec hello-apparmor -n apparmor -- sh -c 'echo test > /tmp/x'   # Permission denied
```

On older clusters the equivalent is the annotation:

```bash
container.apparmor.security.beta.kubernetes.io/hello: localhost/k8s-apparmor-example-deny-write
```

> [!IMPORTANT]
> AppArmor is a **node** feature. On kind the example profile isn't loaded, so load
> it on the node first (real exam nodes already have it):
> ```bash
> docker exec labs-worker bash -c 'cat > /etc/apparmor.d/deny-write <<EOF
> #include <tunables/global>
> profile k8s-apparmor-example-deny-write flags=(attach_disconnected) {
>   #include <abstractions/base>
>   file,
>   deny /** w,
> }
> EOF
> apparmor_parser -r /etc/apparmor.d/deny-write'
> ```
> (Use `podman exec` if kind runs under Podman; the host kernel must have AppArmor enabled.)

</details>

---

## 11. Confine a Pod With seccomp

**Task:** `task setup S=11 C=cks`. Confine every container in Pod `audit-nginx` (namespace `seccomp`) with the `RuntimeDefault` seccomp profile.

<details>
<summary>Hint</summary>

[Restrict a Container's Syscalls with seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)

</details>

<details>
<summary>Answer</summary>

A pod's securityContext is immutable once running, so recreate it with the seccomp profile set at the pod level:

```yaml
# audit-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: audit-nginx
  namespace: seccomp
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: nginx
      image: nginx:1.25
      ports:
        - containerPort: 80
```

```bash
kubectl delete pod audit-nginx -n seccomp --ignore-not-found
kubectl apply -f audit-nginx.yaml

# Verify the profile is applied
kubectl get pod audit-nginx -n seccomp \
  -o jsonpath='{.spec.securityContext.seccompProfile.type}{"\n"}'   # RuntimeDefault
```

> [!NOTE]
> `RuntimeDefault` uses the container runtime's default seccomp profile (blocks
> dangerous syscalls). For a **custom** profile you'd use
> `type: Localhost` with `localhostProfile: profiles/audit.json`, where the file
> lives under the kubelet's seccomp root (`/var/lib/kubelet/seccomp/`).

</details>

---

## 12. Manage Kubernetes Secrets

**Task:** `task setup S=12 C=cks`. In namespace `vault`: (1) read the value of the existing Secret `db-secret` (key `password`) and save the **decoded** value to `/tmp/db-password.txt`. (2) Create a new Secret `api-key` with the literal `key=Zx9-secret` and mount it **read-only** into the `consumer` pod at `/etc/api`.

<details>
<summary>Hint</summary>

[Managing Secrets using kubectl](https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/) · [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Decode the existing secret to a file
kubectl get secret db-secret -n vault -o jsonpath='{.data.password}' | base64 -d > /tmp/db-password.txt
cat /tmp/db-password.txt   # S3ubern3tes-CKS!

# 2. Create the new secret
kubectl create secret generic api-key -n vault --from-literal=key=Zx9-secret
```

The `consumer` pod's volumes are immutable, so recreate it with a read-only mount:

```yaml
# consumer.yaml
apiVersion: v1
kind: Pod
metadata:
  name: consumer
  namespace: vault
spec:
  volumes:
    - name: api
      secret:
        secretName: api-key
  containers:
    - name: app
      image: nginx:1.25
      volumeMounts:
        - name: api
          mountPath: /etc/api
          readOnly: true
```

```bash
kubectl delete pod consumer -n vault --ignore-not-found
kubectl apply -f consumer.yaml
kubectl exec consumer -n vault -- cat /etc/api/key; echo   # Zx9-secret
```

> [!NOTE]
> Secret volume mounts are already read-only for the container, but the exam wants
> `readOnly: true` set explicitly. On the exam you may also be asked to enable
> **encryption at rest** with an `EncryptionConfiguration` on the apiserver.

</details>

---

## 13. Make a Container Immutable at Runtime

**Task:** `task setup S=13 C=cks`. Harden the `payment` Deployment in namespace `runtime` so its container is immutable at runtime and runs with least privilege: a **read-only root filesystem**, **no privilege escalation**, **all capabilities dropped**, and running as a **non-root** user.

<details>
<summary>Hint</summary>

[Security Context: readOnlyRootFilesystem & capabilities](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) · [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl edit deployment payment -n runtime
```

```yaml
# spec.template.spec
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 5487
  containers:
    - name: payment
      image: busybox:1.36
      command: ["sh", "-c", "sleep infinity"]
      securityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      # if the app needs to write, add an emptyDir volume for the writable path:
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
```

```bash
kubectl rollout status deployment/payment -n runtime

# Verify immutability: writing to the root fs is denied.
kubectl exec -n runtime deploy/payment -- sh -c 'echo x > /root.txt'   # Read-only file system
kubectl get deploy payment -n runtime \
  -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
```

> [!NOTE]
> `readOnlyRootFilesystem: true` is the core of runtime immutability. If the
> workload must write somewhere, mount a dedicated writable `emptyDir` (e.g. `/tmp`)
> rather than making the whole root filesystem writable.

</details>

---

## 14. Enable Kubernetes Audit Logging

**Task:** *(control-plane node exercise — no `task setup`.)* Configure the kube-apiserver to write audit logs using the policy at `scenarios/cks/14-audit-logging/audit-policy.yaml`. Logs must go to `/var/log/kubernetes/audit/audit.log`, keep at most 5 days of history and 10 rotated files.

<details>
<summary>Hint</summary>

[Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/) · [Audit Policy](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/#audit-policy)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Place the audit policy on the control-plane node
sudo mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
sudo cp audit-policy.yaml /etc/kubernetes/audit/audit-policy.yaml

# 2. Edit the static pod manifest
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add these flags to the `kube-apiserver` command:

```yaml
    - --audit-policy-file=/etc/kubernetes/audit/audit-policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=5
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
```

Mount the policy and log directories into the static pod:

```yaml
    volumeMounts:
      - name: audit-policy
        mountPath: /etc/kubernetes/audit/audit-policy.yaml
        readOnly: true
      - name: audit-log
        mountPath: /var/log/kubernetes/audit
  volumes:
    - name: audit-policy
      hostPath:
        path: /etc/kubernetes/audit/audit-policy.yaml
        type: File
    - name: audit-log
      hostPath:
        path: /var/log/kubernetes/audit
        type: DirectoryOrCreate
```

```bash
# 3. The kubelet restarts the apiserver automatically. Watch it come back, then tail the log.
sudo crictl ps | grep kube-apiserver
sudo tail -f /var/log/kubernetes/audit/audit.log
```

> [!IMPORTANT]
> After editing the manifest the apiserver restarts and briefly becomes
> unavailable — wait for it. A YAML typo will keep it down; check
> `/var/log/pods/` or `crictl logs` if `kubectl` stops responding.

</details>

---

## 15. Review the Cluster With the CIS Benchmark

**Task:** *(node exercise — no `task setup`.)* Run `kube-bench` against the control-plane node, then remediate two common failures: disable anonymous auth on the kube-apiserver and ensure the kubelet does not allow anonymous access.

<details>
<summary>Hint</summary>

[CIS Benchmark for Kubernetes](https://www.cisecurity.org/benchmark/kubernetes) · [kube-bench](https://github.com/aquasecurity/kube-bench) · [Securing a Cluster](https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Run kube-bench (as a job or the binary) and read the FAIL/WARN items
kube-bench run --targets master | less
# or in-cluster:
kubectl run kube-bench --image=aquasec/kube-bench:latest --restart=Never \
  --overrides='{"spec":{"hostPID":true}}' -- run --targets master
```

```bash
# 2a. kube-apiserver: ensure anonymous auth is off (CIS 1.2.1)
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
#   add:  --anonymous-auth=false
```

```bash
# 2b. kubelet: disable anonymous access (CIS 4.2.1)
sudo vi /var/lib/kubelet/config.yaml
```

```yaml
authentication:
  anonymous:
    enabled: false      # was true
  webhook:
    enabled: true
authorization:
  mode: Webhook          # not AlwaysAllow
```

```bash
sudo systemctl restart kubelet
# Re-run kube-bench and confirm the two items now PASS.
kube-bench run --targets master,node | grep -E '1.2.1|4.2.1'
```

> [!NOTE]
> kube-bench maps each finding to a CIS control number and prints the exact
> remediation. On the exam, fix the specific control the task names, edit the
> apiserver **static pod manifest** or the **kubelet config**, then restart the
> relevant component (kubelet restart / apiserver auto-restart).

</details>

---

## 16. Restrict Images to a Permitted Registry

**Task:** `task setup S=16 C=cks`. Ensure that only container images from the permitted registry `registry.internal/` can run in namespace `trusted`; any other image must be rejected at admission. Use a native `ValidatingAdmissionPolicy`.

<details>
<summary>Hint</summary>

[Validating Admission Policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/) · [ImagePolicyWebhook (alternative)](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook)

</details>

<details>
<summary>Answer</summary>

```yaml
# image-policy.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: allowed-registries
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: >-
        object.spec.containers.all(c, c.image.startsWith('registry.internal/'))
      message: "images must come from registry.internal/"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: allowed-registries-binding
  labels:
    scenario: "16"
spec:
  policyName: allowed-registries
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: trusted
```

```bash
kubectl apply -f image-policy.yaml

# Rejected: image not from registry.internal/
kubectl run bad --image=nginx:1.25 -n trusted            # denied by the policy
# Allowed (would pass admission; image pull is separate):
kubectl run good --image=registry.internal/nginx:1.25 -n trusted --dry-run=server
```

> [!NOTE]
> `ValidatingAdmissionPolicy` (GA in v1.30) enforces CEL rules with no external
> webhook. The `namespaceSelector` scopes it to `trusted`. On older exam clusters
> the classic approaches are an OPA Gatekeeper `ConstraintTemplate` or an
> `ImagePolicyWebhook` admission plugin.

</details>

---

## 17. Static Analysis of a Workload Manifest

**Task:** *(local file exercise — no `task setup`.)* Run a static analyzer against `scenarios/cks/17-static-analysis/deployment.yaml` and fix every high-severity finding so it would pass.

<details>
<summary>Hint</summary>

[kubesec.io](https://kubesec.io/) · [KubeLinter](https://docs.kubelinter.io/) · [Trivy config scanning](https://aquasecurity.github.io/trivy/latest/docs/scanner/misconfiguration/)

</details>

<details>
<summary>Answer</summary>

```bash
# Scan with any of these
kubesec scan scenarios/cks/17-static-analysis/deployment.yaml
kube-linter lint scenarios/cks/17-static-analysis/deployment.yaml
trivy config scenarios/cks/17-static-analysis/deployment.yaml
```

The scanners flag: `hostNetwork`, `hostPID`, `privileged`, `runAsUser: 0`,
`allowPrivilegeEscalation`, writable root fs, added dangerous capabilities, and the
`:latest` image tag. Fix them:

```yaml
# spec.template.spec — hardened
spec:
  hostNetwork: false          # remove
  hostPID: false              # remove
  securityContext:
    runAsNonRoot: true
    runAsUser: 5487
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: api
      image: nginx:1.25       # pin the tag
      ports:
        - containerPort: 80
      securityContext:
        privileged: false
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]        # remove the SYS_ADMIN/NET_ADMIN adds
```

```bash
# Re-scan and confirm the score improves / findings clear
kubesec scan scenarios/cks/17-static-analysis/deployment.yaml
```

> [!NOTE]
> kubesec returns a numeric score and lists which fields raise or lower it; aim
> for a positive score with critical findings resolved. The dangerous items here
> are host namespaces, privileged mode, running as root, and the added capabilities.

</details>

---

## 18. Generate a Software Bill of Materials (SBOM)

**Task:** *(local exercise — no `task setup`.)* Generate an SBOM in SPDX JSON format for the image `nginx:1.25` and save it to `/tmp/nginx-sbom.spdx.json`, then scan that SBOM for known vulnerabilities.

<details>
<summary>Hint</summary>

[Trivy SBOM](https://aquasecurity.github.io/trivy/latest/docs/supply-chain/sbom/) · [Syft](https://github.com/anchore/syft) · [SPDX](https://spdx.dev/)

</details>

<details>
<summary>Answer</summary>

```bash
# Option A: Trivy (generate + scan)
trivy image --format spdx-json --output /tmp/nginx-sbom.spdx.json nginx:1.25
trivy sbom /tmp/nginx-sbom.spdx.json          # scan the SBOM for CVEs

# Option B: Syft (generate) + Grype (scan)
syft nginx:1.25 -o spdx-json=/tmp/nginx-sbom.spdx.json
grype sbom:/tmp/nginx-sbom.spdx.json
```

```bash
# Inspect the SBOM
jq '.name, (.packages | length)' /tmp/nginx-sbom.spdx.json
```

> [!NOTE]
> An SBOM lists every package/dependency in an image (SPDX or CycloneDX format).
> Generating it once and scanning the SBOM (rather than re-pulling the image) is
> the supply-chain workflow the exam expects. Trivy can both **create** the SBOM
> and **scan** it for CVEs.

</details>

---

## 19. Detect Runtime Threats With Falco

**Task:** `task setup S=19 C=cks`. Using Falco, detect when a shell is opened inside a running container. Trigger the rule by exec'ing a shell into the `suspicious` pod (namespace `falco-demo`) and find the corresponding Falco alert. Then write a **custom** Falco rule that logs at `WARNING` when a process reads `/etc/shadow` in any container.

<details>
<summary>Hint</summary>

[Falco](https://falco.org/docs/) · [Falco default rules](https://github.com/falcosecurity/rules) · [Writing Falco rules](https://falco.org/docs/rules/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Falco must run on the node. On the exam it's already installed; otherwise:
helm repo add falcosecurity https://falcosecurity.github.io/charts && helm repo update
helm install falco falcosecurity/falco -n falco --create-namespace \
  --set driver.kind=ebpf

# 2. Trigger the built-in "Terminal shell in container" rule
kubectl exec -it suspicious -n falco-demo -- sh

# 3. Read the alert from Falco (host process or DaemonSet pod)
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep -i "shell in a container"
# or on the node: sudo journalctl -u falco | grep -i shell
```

Add a custom rule in `/etc/falco/falco_rules.local.yaml` (or a mounted rules file):

```yaml
- rule: Read sensitive file /etc/shadow
  desc: Detect any process reading /etc/shadow inside a container
  condition: >
    open_read and container and fd.name = /etc/shadow
  output: "Sensitive file opened for reading (user=%user.name command=%proc.cmdline file=%fd.name container=%container.name)"
  priority: WARNING
  tags: [filesystem, mitre_credential_access]
```

```bash
# Reload Falco and trigger it
kubectl exec suspicious -n falco-demo -- cat /etc/shadow
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep -i "/etc/shadow"
```

> [!IMPORTANT]
> Falco reads syscalls via an eBPF/kernel driver on the **node**, so it can't run
> in a plain kind cluster without a compatible host kernel. On the exam, identify
> which default rule fired for a given activity, or add/modify a rule and confirm
> the alert. Note the `priority` (WARNING) and `output` fields the task asks for.

</details>

---

## 20. Upgrade Kubernetes With kubeadm

**Task:** *(node exercise — no `task setup`.)* Upgrade the control-plane node from the current version to the next patch/minor release using `kubeadm`, draining and uncordoning the node around the upgrade.

<details>
<summary>Hint</summary>

[Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) · [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)

</details>

<details>
<summary>Answer</summary>

```bash
# 1. Cordon + drain the control-plane node
kubectl drain <cp-node> --ignore-daemonsets --delete-emptydir-data

# 2. Upgrade kubeadm itself (adjust the apt/yum pin to the target version)
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.32.1-1.1
sudo apt-mark hold kubeadm

# 3. Plan and apply the control-plane upgrade
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.32.1

# 4. Upgrade the kubelet + kubectl on this node, then restart the kubelet
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.32.1-1.1 kubectl=1.32.1-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. Uncordon and verify
kubectl uncordon <cp-node>
kubectl get nodes    # control-plane now on v1.32.1
```

For **worker** nodes, use `sudo kubeadm upgrade node` (instead of `upgrade apply`)
after upgrading the kubeadm package, then upgrade the kubelet and restart it.

> [!IMPORTANT]
> Upgrade one minor version at a time and always `drain` before and `uncordon`
> after. `kubeadm upgrade apply` runs on the control plane; `kubeadm upgrade node`
> runs on workers and additional control-plane nodes.

</details>
