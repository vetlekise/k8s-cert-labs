# CAPA Practice Questions

Practice labs for the [Certified Argo Project Associate (CAPA)](https://www.cncf.io/training/certification/capa/) exam, grouped by the exam's four domains.

> [!NOTE]
> Unlike CKAD, **CAPA is a multiple-choice, knowledge-based exam**, not a hands-on one. These labs are not one-to-one exam simulations; they exist so you learn the concepts by actually running the four Argo projects. Doing beats memorising. The scenarios are grouped by exam domain: 1-7 Workflows, 8-12 Argo CD, 13-15 Rollouts, 16-17 Events.

Each lab is written as a task. Expand **Hint** for pointers to the official docs, and expand **Answer** to reveal the solution.

## Prerequisites

Install the Argo components into your kind cluster. Install everything, or just the project for the section you are practicing:

```bash
task argo:install     # all four projects
task argo:workflows   # Argo Workflows  -> namespace `argo`
task argo:cd          # Argo CD         -> namespace `argocd`
task argo:rollouts    # Argo Rollouts   -> namespace `argo-rollouts`
task argo:events      # Argo Events     -> namespace `argo-events`
task argo:uninstall   # remove them all
```

Then use the scenarios as usual, targeting the CAPA set with `C=capa`:

```bash
task list C=capa
task setup S=09 C=capa    # scenarios 9 and 12 need `task argo:cd` first
task reset S=09 C=capa
```

Two CLIs make the labs smoother (optional but recommended):

- [`argo`](https://github.com/argoproj/argo-workflows/releases) for Argo Workflows.
- [`kubectl argo rollouts`](https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin-installation) plugin for Argo Rollouts.

Access the Argo CD UI/API (initial admin password shown below):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
# then: argocd login localhost:8080 --username admin --insecure
```

> [!IMPORTANT]
> Scenarios **9** and **12** ship a pre-existing Argo CD `Application`, so run `task argo:cd` **before** `task setup S=09 C=capa` (or `S=12`). The other CD scenarios (8, 10, 11) create the Application themselves, but still need Argo CD installed to sync.

## Table of Contents

**Argo Workflows**

1. [Submit a Workflow](#1-submit-a-workflow)
2. [Pass Parameters Between Steps](#2-pass-parameters-between-steps)
3. [Reuse Logic with a WorkflowTemplate](#3-reuse-logic-with-a-workflowtemplate)
4. [Schedule a CronWorkflow](#4-schedule-a-cronworkflow)
5. [Build a DAG Workflow](#5-build-a-dag-workflow)
6. [Generate and Consume Artifacts](#6-generate-and-consume-artifacts)
7. [Run a Data Processing Job with Loops](#7-run-a-data-processing-job-with-loops)

**Argo CD**

8. [Deploy an Application with Argo CD](#8-deploy-an-application-with-argo-cd)
9. [Enable Automated Sync and Self-Heal](#9-enable-automated-sync-and-self-heal)
10. [Configure an Application with Helm](#10-configure-an-application-with-helm)
11. [Configure an Application with Kustomize](#11-configure-an-application-with-kustomize)
12. [Observe Reconciliation and Drift](#12-observe-reconciliation-and-drift)

**Argo Rollouts**

13. [Roll Out a Canary and Promote It](#13-roll-out-a-canary-and-promote-it)
14. [Roll Out Blue-Green and Promote It](#14-roll-out-blue-green-and-promote-it)
15. [Gate a Rollout with an AnalysisTemplate](#15-gate-a-rollout-with-an-analysistemplate)

**Argo Events**

16. [Trigger a Workload from a Webhook Event](#16-trigger-a-workload-from-a-webhook-event)
17. [Trigger a Workload on a Schedule](#17-trigger-a-workload-on-a-schedule)

---

## Argo Workflows

## 1. Submit a Workflow

**Task:** In namespace `capa-wf`, create and submit a `Workflow` named `hello` that runs a single container printing `hello CAPA`. Use the `workflow` ServiceAccount that already exists. Confirm the workflow reaches phase `Succeeded`.

<details>
<summary>Hint</summary>

[Argo Workflows: Core Concepts](https://argo-workflows.readthedocs.io/en/latest/workflow-concepts/) · [Argo CLI](https://argo-workflows.readthedocs.io/en/latest/cli/argo/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: hello
  namespace: capa-wf
spec:
  serviceAccountName: workflow
  entrypoint: main
  templates:
    - name: main
      container:
        image: alpine:3.20
        command: [sh, -c]
        args: ["echo hello CAPA"]
EOF
```

Or, with the `argo` CLI, `argo submit -n capa-wf --serviceaccount workflow --watch <file>.yaml`.

Check the result:

```bash
kubectl -n capa-wf get workflow hello -o jsonpath='{.status.phase}'; echo
argo logs -n capa-wf hello   # if the CLI is installed
```

</details>

---

## 2. Pass Parameters Between Steps

**Task:** In namespace `capa-wf-params`, create a `Workflow` named `params` that: (1) takes a global input parameter `name` defaulting to `CAPA`, (2) has a `generate` step that outputs a parameter, and (3) has a `print` step that consumes both the global parameter and the previous step's output. Use the `workflow` ServiceAccount.

<details>
<summary>Hint</summary>

[Argo Workflows: Parameters](https://argo-workflows.readthedocs.io/en/latest/walk-through/parameters/) · [Output Parameters](https://argo-workflows.readthedocs.io/en/latest/walk-through/output-parameters/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: params
  namespace: capa-wf-params
spec:
  serviceAccountName: workflow
  entrypoint: main
  arguments:
    parameters:
      - name: name
        value: CAPA
  templates:
    - name: main
      steps:
        - - name: generate
            template: generate
        - - name: print
            template: print
            arguments:
              parameters:
                - name: greeting
                  value: "{{steps.generate.outputs.parameters.msg}}"
    - name: generate
      script:
        image: alpine:3.20
        command: [sh]
        source: |
          echo -n "hello from generate" > /tmp/out.txt
      outputs:
        parameters:
          - name: msg
            valueFrom:
              path: /tmp/out.txt
    - name: print
      inputs:
        parameters:
          - name: greeting
      container:
        image: alpine:3.20
        command: [sh, -c]
        args: ["echo '{{inputs.parameters.greeting}}' for '{{workflow.parameters.name}}'"]
EOF

kubectl -n capa-wf-params get workflow params -o jsonpath='{.status.phase}'; echo
```

`{{workflow.parameters.name}}` reads a global argument; `{{steps.<step>.outputs.parameters.<name>}}` passes one step's output into the next.

</details>

---

## 3. Reuse Logic with a WorkflowTemplate

**Task:** In namespace `capa-wf-tmpl`, create a reusable `WorkflowTemplate` named `echo-template` with an `echo` template that takes a `msg` parameter. Then create a `Workflow` named `use-template` that calls it via `templateRef`. Use the `workflow` ServiceAccount.

<details>
<summary>Hint</summary>

[Argo Workflows: Workflow Templates](https://argo-workflows.readthedocs.io/en/latest/workflow-templates/) · [Template References](https://argo-workflows.readthedocs.io/en/latest/workflow-templates/#referencing-other-workflowtemplates)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: echo-template
  namespace: capa-wf-tmpl
spec:
  templates:
    - name: echo
      inputs:
        parameters:
          - name: msg
      container:
        image: alpine:3.20
        command: [sh, -c]
        args: ["echo {{inputs.parameters.msg}}"]
---
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: use-template
  namespace: capa-wf-tmpl
spec:
  serviceAccountName: workflow
  entrypoint: main
  templates:
    - name: main
      steps:
        - - name: call
            templateRef:
              name: echo-template
              template: echo
            arguments:
              parameters:
                - name: msg
                  value: "reused from a WorkflowTemplate"
EOF

kubectl -n capa-wf-tmpl get workflow use-template -o jsonpath='{.status.phase}'; echo
```

> A `WorkflowTemplate` is namespaced; a `ClusterWorkflowTemplate` is the same idea but cluster-scoped and referenced with `clusterScope: true`. (Avoid creating cluster-scoped objects in these labs, since `task reset` cleans up by namespace.)

</details>

---

## 4. Schedule a CronWorkflow

**Task:** In namespace `capa-wf-cron`, create a `CronWorkflow` named `every-minute` that runs every minute (`* * * * *`), printing the current date. Use the `workflow` ServiceAccount. Verify at least one Workflow is created from the schedule.

<details>
<summary>Hint</summary>

[Argo Workflows: Cron Workflows](https://argo-workflows.readthedocs.io/en/latest/cron-workflows/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: every-minute
  namespace: capa-wf-cron
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  workflowSpec:
    serviceAccountName: workflow
    entrypoint: main
    templates:
      - name: main
        container:
          image: alpine:3.20
          command: [sh, -c]
          args: ["date"]
EOF

# Wait ~1 minute, then confirm a Workflow was spawned:
kubectl -n capa-wf-cron get workflows
kubectl -n capa-wf-cron get cronworkflow every-minute
```

</details>

---

## 5. Build a DAG Workflow

**Task:** In namespace `capa-wf-dag`, create a `Workflow` named `diamond` whose steps form a DAG: task `a` runs first, then `b` and `c` run in parallel (both depend on `a`), and `d` runs last (depends on `b` and `c`). Each task can just echo its own name. Use the `workflow` ServiceAccount.

<details>
<summary>Hint</summary>

[Argo Workflows: DAG](https://argo-workflows.readthedocs.io/en/latest/walk-through/dag/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: diamond
  namespace: capa-wf-dag
spec:
  serviceAccountName: workflow
  entrypoint: diamond
  templates:
    - name: echo
      inputs:
        parameters:
          - name: msg
      container:
        image: alpine:3.20
        command: [sh, -c]
        args: ["echo {{inputs.parameters.msg}}"]
    - name: diamond
      dag:
        tasks:
          - name: a
            template: echo
            arguments: {parameters: [{name: msg, value: a}]}
          - name: b
            template: echo
            dependencies: [a]
            arguments: {parameters: [{name: msg, value: b}]}
          - name: c
            template: echo
            dependencies: [a]
            arguments: {parameters: [{name: msg, value: c}]}
          - name: d
            template: echo
            dependencies: [b, c]
            arguments: {parameters: [{name: msg, value: d}]}
EOF

kubectl -n capa-wf-dag get workflow diamond -o jsonpath='{.status.phase}'; echo
```

</details>

---

## 6. Generate and Consume Artifacts

**Task:** Namespace `capa-wf-artifacts` ships a small MinIO acting as an S3 artifact store (service `minio:9000`, bucket `argo`, credentials in Secret `minio-creds`). Create a `Workflow` named `artifacts` where a `generate` step writes a file and exports it as an **output artifact**, and a `consume` step takes it as an **input artifact** and prints its contents. Use the `workflow` ServiceAccount.

<details>
<summary>Hint</summary>

[Argo Workflows: Artifacts](https://argo-workflows.readthedocs.io/en/latest/walk-through/artifacts/) · [Configuring Your Artifact Repository](https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: artifacts
  namespace: capa-wf-artifacts
spec:
  serviceAccountName: workflow
  entrypoint: main
  templates:
    - name: main
      steps:
        - - name: generate
            template: generate
        - - name: consume
            template: consume
            arguments:
              artifacts:
                - name: in
                  from: "{{steps.generate.outputs.artifacts.out}}"
    - name: generate
      container:
        image: alpine:3.20
        command: [sh, -c]
        args: ["echo 'artifact payload' > /tmp/data.txt"]
      outputs:
        artifacts:
          - name: out
            path: /tmp/data.txt
            s3:
              endpoint: minio:9000
              insecure: true
              bucket: argo
              key: artifacts/data.txt
              accessKeySecret: {name: minio-creds, key: accesskey}
              secretKeySecret: {name: minio-creds, key: secretkey}
    - name: consume
      inputs:
        artifacts:
          - name: in
            path: /tmp/in.txt
      container:
        image: alpine:3.20
        command: [sh, -c]
        args: ["cat /tmp/in.txt"]
EOF

kubectl -n capa-wf-artifacts get workflow artifacts -o jsonpath='{.status.phase}'; echo
```

The `generate` step's `s3` block writes the artifact to MinIO; the `consume` step pulls it back in via `from`. In a real cluster you would usually configure a default artifact repository once instead of inlining `s3` on every artifact.

</details>

---

## 7. Run a Data Processing Job with Loops

**Task:** In namespace `capa-wf-data`, create a `Workflow` named `fanout` that processes a list of items (`red`, `green`, `blue`) **in parallel**, one pod per item, using `withItems`. Each pod should print `processing <item>`. Use the `workflow` ServiceAccount.

<details>
<summary>Hint</summary>

[Argo Workflows: Loops](https://argo-workflows.readthedocs.io/en/latest/walk-through/loops/) · [Scripts and Results](https://argo-workflows.readthedocs.io/en/latest/walk-through/scripts-and-results/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: fanout
  namespace: capa-wf-data
spec:
  serviceAccountName: workflow
  entrypoint: main
  templates:
    - name: main
      steps:
        - - name: process
            template: worker
            arguments:
              parameters:
                - name: item
                  value: "{{item}}"
            withItems: [red, green, blue]
    - name: worker
      inputs:
        parameters:
          - name: item
      container:
        image: alpine:3.20
        command: [sh, -c]
        args: ["echo processing {{inputs.parameters.item}}"]
EOF

kubectl -n capa-wf-data get workflow fanout -o jsonpath='{.status.phase}'; echo
kubectl -n capa-wf-data get pods -l workflows.argoproj.io/workflow=fanout
```

`withItems` fans out one pod per element (map-style parallelism). Use `withParam` to loop over a JSON list produced by a previous step, which is the basis of map-reduce style data processing.

</details>

---

## Argo CD

## 8. Deploy an Application with Argo CD

**Task:** Requires `task argo:cd`. Declaratively create an Argo CD `Application` named `guestbook` that deploys `path: guestbook` from `https://github.com/argoproj/argocd-example-apps` into the `capa-cd` namespace. Sync it and confirm it becomes `Healthy` and `Synced`.

<details>
<summary>Hint</summary>

[Argo CD: Declarative Setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/) · [Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  labels:
    scenario: "08"
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: capa-cd
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
EOF

# Trigger a sync (or click Sync in the UI):
argocd app sync guestbook
kubectl -n argocd get application guestbook \
  -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status
```

> The `scenario: "08"` label lets `task reset S=08 C=capa` delete the Application again.

</details>

---

## 9. Enable Automated Sync and Self-Heal

**Task:** Requires `task argo:cd` (and `task setup S=09 C=capa`). The Application `guestbook-manual` (in the `argocd` namespace) currently syncs only when triggered manually. Reconfigure it so Argo CD keeps it in sync automatically, reverts manual drift, and prunes resources that are removed from Git.

<details>
<summary>Hint</summary>

[Argo CD: Automated Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl -n argocd patch application guestbook-manual --type merge -p '
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
'
```

`automated` enables auto-sync, `selfHeal: true` reverts out-of-band changes, and
`prune: true` removes resources deleted from Git. Verify:

```bash
kubectl -n argocd get application guestbook-manual \
  -o jsonpath='{.spec.syncPolicy.automated}'; echo
```

</details>

---

## 10. Configure an Application with Helm

**Task:** Requires `task argo:cd`. Create an Argo CD `Application` named `helm-guestbook` from `path: helm-guestbook` of the `argocd-example-apps` repo, deploying into `capa-cd-helm`. Override the Helm value `replicaCount` to `2`. Sync it and confirm two pods run.

<details>
<summary>Hint</summary>

[Argo CD: Helm](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: helm-guestbook
  namespace: argocd
  labels:
    scenario: "10"
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: helm-guestbook
    helm:
      parameters:
        - name: replicaCount
          value: "2"
  destination:
    server: https://kubernetes.default.svc
    namespace: capa-cd-helm
  syncPolicy:
    automated: {}
    syncOptions:
      - CreateNamespace=true
EOF

kubectl -n argocd get application helm-guestbook \
  -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl -n capa-cd-helm get pods
```

`source.helm.parameters` is equivalent to `helm install --set`. You can also point at a `values` file with `helm.valueFiles`.

</details>

---

## 11. Configure an Application with Kustomize

**Task:** Requires `task argo:cd`. Create an Argo CD `Application` named `kustomize-guestbook` from `path: kustomize-guestbook` of the `argocd-example-apps` repo, deploying into `capa-cd-kustomize`. Use Kustomize to add the name prefix `dev-` to every resource. Sync it and confirm the deployment is named `dev-...`.

<details>
<summary>Hint</summary>

[Argo CD: Kustomize](https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kustomize-guestbook
  namespace: argocd
  labels:
    scenario: "11"
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: kustomize-guestbook
    kustomize:
      namePrefix: dev-
  destination:
    server: https://kubernetes.default.svc
    namespace: capa-cd-kustomize
  syncPolicy:
    automated: {}
    syncOptions:
      - CreateNamespace=true
EOF

kubectl -n argocd get application kustomize-guestbook \
  -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl -n capa-cd-kustomize get deploy
```

`source.kustomize` lets Argo CD apply Kustomize transforms (`namePrefix`, `nameSuffix`, `images`, `commonLabels`, ...) without editing the base manifests.

</details>

---

## 12. Observe Reconciliation and Drift

**Task:** Requires `task argo:cd` (and `task setup S=12 C=capa`). The auto-synced Application `guestbook-recon` deploys the guestbook into `capa-cd-recon`. Manually scale its live Deployment to break desired state, observe Argo CD report the drift, and watch self-heal restore it.

<details>
<summary>Hint</summary>

[Argo CD: Sync/diff](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/) · [Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/) · [Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

</details>

<details>
<summary>Answer</summary>

```bash
# Introduce drift: scale the live Deployment away from what Git declares.
kubectl -n capa-cd-recon scale deploy/guestbook-ui --replicas=5

# Argo CD detects the difference (OutOfSync) ...
argocd app diff guestbook-recon || \
  kubectl -n argocd get application guestbook-recon -o jsonpath='{.status.sync.status}'; echo

# ... and because selfHeal is on, it reverts the replica count back to 1.
kubectl -n capa-cd-recon get deploy guestbook-ui -w
```

Key reconciliation patterns to know for the exam:

- **Diffing / drift detection:** Argo CD continuously compares the live cluster state to the desired state in Git and marks the app `Synced` or `OutOfSync`.
- **Self-heal:** with `syncPolicy.automated.selfHeal`, out-of-band changes are reverted automatically.
- **Prune:** with `automated.prune`, resources removed from Git are deleted from the cluster.
- **Sync waves:** annotate resources with `argocd.argoproj.io/sync-wave: "<n>"` to order how they apply (lower waves first).
- **Resource hooks:** annotate with `argocd.argoproj.io/hook: PreSync|Sync|PostSync` to run jobs around a sync (e.g. DB migrations).

</details>

---

## Argo Rollouts

## 13. Roll Out a Canary and Promote It

**Task:** Requires `task argo:rollouts`. In namespace `capa-rollouts`, create a `Rollout` named `rollouts-demo` (4 replicas, image `argoproj/rollouts-demo:blue`) using a canary strategy: 25% weight, pause, 75% weight, pause. After it is healthy, update the image to `argoproj/rollouts-demo:yellow` and promote it through both pauses to completion.

<details>
<summary>Hint</summary>

[Argo Rollouts: Canary](https://argo-rollouts.readthedocs.io/en/stable/features/canary/) · [Getting Started](https://argo-rollouts.readthedocs.io/en/stable/getting-started/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: rollouts-demo
  namespace: capa-rollouts
spec:
  replicas: 4
  selector:
    matchLabels:
      app: rollouts-demo
  template:
    metadata:
      labels:
        app: rollouts-demo
    spec:
      containers:
        - name: rollouts-demo
          image: argoproj/rollouts-demo:blue
          ports:
            - containerPort: 8080
  strategy:
    canary:
      steps:
        - setWeight: 25
        - pause: {}
        - setWeight: 75
        - pause: {}
EOF

# Watch progress (plugin):
kubectl argo rollouts get rollout rollouts-demo -n capa-rollouts --watch

# Trigger an update, then promote through each pause:
kubectl argo rollouts set image rollouts-demo \
  rollouts-demo=argoproj/rollouts-demo:yellow -n capa-rollouts
kubectl argo rollouts promote rollouts-demo -n capa-rollouts   # past pause 1
kubectl argo rollouts promote rollouts-demo -n capa-rollouts   # past pause 2
```

`kubectl argo rollouts promote --full rollouts-demo -n capa-rollouts` skips all
remaining steps at once.

</details>

---

## 14. Roll Out Blue-Green and Promote It

**Task:** Requires `task argo:rollouts`. In namespace `capa-bluegreen`, create a `Rollout` named `bg-demo` (3 replicas, image `argoproj/rollouts-demo:blue`, container port 8080, pod label `app: bg-demo`) using the blue-green strategy with `activeService: bg-active` and `previewService: bg-preview` and auto-promotion disabled. Update the image to `argoproj/rollouts-demo:green` and promote the preview to active.

<details>
<summary>Hint</summary>

[Argo Rollouts: Blue-Green](https://argo-rollouts.readthedocs.io/en/stable/features/bluegreen/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: bg-demo
  namespace: capa-bluegreen
spec:
  replicas: 3
  selector:
    matchLabels:
      app: bg-demo
  template:
    metadata:
      labels:
        app: bg-demo
    spec:
      containers:
        - name: bg-demo
          image: argoproj/rollouts-demo:blue
          ports:
            - containerPort: 8080
  strategy:
    blueGreen:
      activeService: bg-active
      previewService: bg-preview
      autoPromotionEnabled: false
EOF

kubectl argo rollouts get rollout bg-demo -n capa-bluegreen --watch

# New version goes to the preview Service first; promote to flip active -> new:
kubectl argo rollouts set image bg-demo \
  bg-demo=argoproj/rollouts-demo:green -n capa-bluegreen
kubectl argo rollouts promote bg-demo -n capa-bluegreen
```

</details>

---

## 15. Gate a Rollout with an AnalysisTemplate

**Task:** Requires `task argo:rollouts`. In namespace `capa-rollouts-analysis`, create an `AnalysisTemplate` named `smoke-test` whose single metric runs a Kubernetes Job that must succeed (`exit 0`). Then create a canary `Rollout` named `analyzed` (image `argoproj/rollouts-demo:blue`) that runs this analysis as a mid-rollout step. Update the image and confirm the resulting `AnalysisRun` succeeds and the rollout proceeds.

<details>
<summary>Hint</summary>

[Argo Rollouts: Analysis](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/) · [Job Metric](https://argo-rollouts.readthedocs.io/en/stable/analysis/job/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: smoke-test
  namespace: capa-rollouts-analysis
spec:
  metrics:
    - name: smoke-test
      provider:
        job:
          spec:
            backoffLimit: 0
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: test
                    image: alpine:3.20
                    command: [sh, -c, "echo smoke test passed; exit 0"]
---
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: analyzed
  namespace: capa-rollouts-analysis
spec:
  replicas: 2
  selector:
    matchLabels:
      app: analyzed
  template:
    metadata:
      labels:
        app: analyzed
    spec:
      containers:
        - name: analyzed
          image: argoproj/rollouts-demo:blue
          ports:
            - containerPort: 8080
  strategy:
    canary:
      steps:
        - setWeight: 50
        - analysis:
            templates:
              - templateName: smoke-test
        - setWeight: 100
EOF

# Trigger an update so the analysis step runs:
kubectl argo rollouts set image analyzed \
  analyzed=argoproj/rollouts-demo:yellow -n capa-rollouts-analysis
kubectl argo rollouts get rollout analyzed -n capa-rollouts-analysis --watch
kubectl -n capa-rollouts-analysis get analysisrun
```

An `AnalysisTemplate` defines *what* to measure; when a Rollout references it, the controller creates an `AnalysisRun` that executes the metrics. A failed metric aborts (and can auto-rollback) the release. The `job` provider is handy for demos; in production you would typically use `prometheus`, `datadog`, or a `web` metric.

</details>

---

## Argo Events

## 16. Trigger a Workload from a Webhook Event

**Task:** Requires `task argo:events`. In namespace `capa-events`, wire up Argo Events so that an HTTP POST creates a Pod. Create an `EventBus` (native NATS), a webhook `EventSource` listening on port `12000` at endpoint `/example`, and a `Sensor` (using the `events-sa` ServiceAccount) that creates a short-lived Pod when the event fires. Send a request and confirm a new Pod appears.

<details>
<summary>Hint</summary>

[Argo Events: Architecture](https://argoproj.github.io/argo-events/concepts/architecture/) · [Webhook Quickstart](https://argoproj.github.io/argo-events/quick_start/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
  namespace: capa-events
spec:
  nats:
    native: {}
---
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: webhook
  namespace: capa-events
spec:
  service:
    ports:
      - port: 12000
        targetPort: 12000
  webhook:
    example:
      port: "12000"
      endpoint: /example
      method: POST
---
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: webhook
  namespace: capa-events
spec:
  template:
    serviceAccountName: events-sa
  dependencies:
    - name: dep
      eventSourceName: webhook
      eventName: example
  triggers:
    - template:
        name: create-pod
        k8s:
          operation: create
          source:
            resource:
              apiVersion: v1
              kind: Pod
              metadata:
                generateName: webhook-triggered-
              spec:
                restartPolicy: Never
                containers:
                  - name: hello
                    image: alpine:3.20
                    command: [sh, -c]
                    args: ["echo triggered by argo events; sleep 5"]
EOF

# Wait for the EventBus and the eventsource/sensor pods to be Running:
kubectl -n capa-events get pods

# In one terminal, forward the webhook service:
kubectl -n capa-events port-forward svc/webhook-eventsource-svc 12000:12000

# In another, fire the event:
curl -d '{"message":"hi"}' -H "Content-Type: application/json" \
  -X POST http://localhost:12000/example

# A new Pod should be created by the Sensor's trigger:
kubectl -n capa-events get pods
```

The four core components: the **EventBus** (NATS) transports events, the **EventSource** ingests external events (here a webhook), and the **Sensor** defines **dependencies** (which events to wait for) and **triggers** (what to do), all connected through the bus.

</details>

---

## 17. Trigger a Workload on a Schedule

**Task:** Requires `task argo:events`. In namespace `capa-events-cal`, create an `EventBus` (native NATS), a `calendar` `EventSource` that emits an event every minute, and a `Sensor` (using `events-sa`) that creates a short-lived Pod on each event. Confirm pods appear roughly once per minute.

<details>
<summary>Hint</summary>

[Argo Events: Calendar EventSource](https://argoproj.github.io/argo-events/eventsources/setup/calendar/) · [Sensor Triggers](https://argoproj.github.io/argo-events/sensors/triggers/k8s-object-trigger/)

</details>

<details>
<summary>Answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
  namespace: capa-events-cal
spec:
  nats:
    native: {}
---
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: calendar
  namespace: capa-events-cal
spec:
  calendar:
    tick:
      interval: 60s
---
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: calendar
  namespace: capa-events-cal
spec:
  template:
    serviceAccountName: events-sa
  dependencies:
    - name: dep
      eventSourceName: calendar
      eventName: tick
  triggers:
    - template:
        name: create-pod
        k8s:
          operation: create
          source:
            resource:
              apiVersion: v1
              kind: Pod
              metadata:
                generateName: tick-triggered-
              spec:
                restartPolicy: Never
                containers:
                  - name: hello
                    image: alpine:3.20
                    command: [sh, -c]
                    args: ["echo tick; sleep 2"]
EOF

# Watch a new pod get created about once a minute:
kubectl -n capa-events-cal get pods -w
```

This shows the same EventBus / EventSource / Sensor architecture as the webhook lab, but with a **calendar** source (schedules and intervals) instead of an HTTP webhook. Reset the scenario when done so it stops creating pods: `task reset S=17 C=capa`.

</details>
