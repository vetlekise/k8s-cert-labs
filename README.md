# k8s-cert-labs

Labs for practicing the Kubernetes certifications.

Each lab is written as an exam-style task with a hint pointing to the official Kubernetes docs and a collapsible answer.

## Question Sets

- [CKAD: Certified Kubernetes Application Developer](questions/ckad.md)
- [CAPA: Certified Argo Project Associate](questions/capa.md)

## Usage

Most scenarios can be reproduced in a local [kind](https://kind.sigs.k8s.io/) cluster so you can actually solve them. The cluster uses Calico (so NetworkPolicies are enforced) and metrics-server (so `kubectl top` works).

### Prerequisites

- [kind](https://kind.sigs.k8s.io/), [kubectl](https://kubernetes.io/docs/tasks/tools/), and [Task](https://taskfile.dev/) on your `PATH`.
- [Podman](https://podman.io/) as the container runtime. The Taskfile is preconfigured to use it via `KIND_EXPERIMENTAL_PROVIDER=podman`.

### Running scenarios

```bash
task                   # list all available tasks
task cluster:up        # create the cluster (Calico + metrics-server)
task list              # list available scenarios
task setup S=03        # load scenario 3's starting state into the cluster
# ...solve it using the matching question set...
task reset S=03        # remove scenario 3's resources and its namespace
task cluster:down      # delete the cluster when finished
```

> [!TIP]
> Alias `k` to `kubectl` to save keystrokes (just like on the exam).
>
> **macOS (zsh, the default shell)**, add to `~/.zshrc`:
>
> ```zsh
> alias k=kubectl
> source <(kubectl completion zsh)
> compdef k=kubectl
> ```
>
> **Linux (bash)**, add to `~/.bashrc`:
>
> ```bash
> alias k=kubectl
> source <(kubectl completion bash)
> complete -o default -F __start_kubectl k
> ```

Typical loop for a single lab:

1. `task setup S=NN` to create the "broken" starting state.
2. Open the matching question set under [questions/](questions/), read the task, and solve it with `kubectl` (peek at the answer only if stuck).
3. `task reset S=NN` to clean up, then move to the next scenario.

Each scenario lives under [scenarios/](scenarios/) and creates its starting state
(pre-existing deployments, secrets, roles, policies, etc.). All resources, including the
namespace itself, are labeled `scenario: "NN"`, and `task reset S=NN` deletes everything
with that label, namespace included, giving each scenario a clean slate.

Scenarios are grouped per certification under `scenarios/<cert>/`. The tasks default
to CKAD; target another set with the `C` variable, e.g. `task list C=capa` or
`task setup S=03 C=capa`. See the per-certification question sets for details:
[CKAD](questions/ckad.md) · [CAPA](questions/capa.md).

### Podman troubleshooting

**macOS**: Podman on macOS runs via a Linux VM (`podman machine`). Initialise and start the machine once before using kind:

```bash
podman machine init
podman machine start
```

> [!WARNING]
> The default `podman machine` memory allocation (2 GiB) is **not enough** for the
> CAPA scenarios. Running kind (control-plane + worker) with Calico, metrics-server,
> and all four Argo projects (Workflows, CD, Rollouts, Events) on a 2 GiB VM causes
> memory thrashing, which makes the API server intermittently unresponsive. This
> shows up as flaky, hard-to-diagnose errors during `task capa:install`, e.g.:
>
> ```text
> Unable to connect to the server: net/http: TLS handshake timeout
> error: timed out waiting for the condition on deployments/argocd-server
> ```
>
> Give the VM at least 8 GiB before running the CAPA labs:
>
> ```bash
> podman machine stop
> podman machine set --memory 8192
> podman machine start
> ```
>
> Then recreate the cluster with `task cluster:restart` and rerun `task capa:install`.

**Linux**: On rootless Podman with cgroups v2, `task cluster:up` may fail during node creation
if CPU/cpuset controllers aren't delegated to your user. If that happens:

```bash
sudo mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
sudo systemctl daemon-reload
# then log out/in (or reboot) and retry
```

### Cluster troubleshooting

**Node(s) already exist**: If `task cluster:up` fails with:

```text
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "labs"
```

a cluster with that name is still around. Recreate it from scratch with:

```bash
task cluster:restart
```

This runs `task cluster:down` followed by `task cluster:up`.
