# k8s-cert-labs

Labs for practicing the Kubernetes certifications.

Each lab is written as an exam-style task with a hint pointing to the official Kubernetes docs and a collapsible answer.

## Question Sets

- [CKAD — Certified Kubernetes Application Developer](questions/ckad.md)

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
# ...solve it using questions/ckad.md...
task reset S=03        # remove scenario 3's resources and its namespace
task cluster:down      # delete the cluster when finished
```

> [!TIP]
> Alias `k` to `kubectl` to save keystrokes (just like on the exam).
>
> **macOS (zsh — default shell)** — add to `~/.zshrc`:
>
> ```zsh
> alias k=kubectl
> source <(kubectl completion zsh)
> compdef k=kubectl
> ```
>
> **Linux (bash)** — add to `~/.bashrc`:
>
> ```bash
> alias k=kubectl
> source <(kubectl completion bash)
> complete -o default -F __start_kubectl k
> ```

Typical loop for a single lab:

1. `task setup S=NN` to create the "broken" starting state.
2. Open [questions/ckad.md](questions/ckad.md), read the task, and solve it with `kubectl` (peek at the answer only if stuck).
3. `task reset S=NN` to clean up, then move to the next scenario.

Each scenario lives in [scenarios/ckad/](scenarios/ckad/) and creates its starting state
(pre-existing deployments, secrets, roles, policies, etc.). All resources — including the
namespace itself — are labeled `scenario: "NN"`, and `task reset S=NN` deletes everything
with that label, namespace included, giving each scenario a clean slate.

Scenarios are grouped per certification under `scenarios/<cert>/`. The tasks default
to CKAD; target another set with the `C` variable, e.g. `task list C=cka` or
`task setup S=03 C=cka`.

> [!NOTE]
> CKAD scenarios **1** (build/export an image) and **13** (fix an old manifest) are local
> file exercises under `scenarios/ckad/` — they have no `task setup`.

### Podman troubleshooting

**macOS** — Podman on macOS runs via a Linux VM (`podman machine`). Initialise and start the machine once before using kind:

```bash
podman machine init
podman machine start
```

**Linux** — On rootless Podman with cgroups v2, `task cluster:up` may fail during node creation
if CPU/cpuset controllers aren't delegated to your user. If that happens:

```bash
sudo mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
sudo systemctl daemon-reload
# then log out/in (or reboot) and retry
```

### Cluster troubleshooting

**Node(s) already exist** — If `task cluster:up` fails with:

```text
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "labs"
```

a cluster with that name is still around. Recreate it from scratch with:

```bash
task cluster:restart
```

This runs `task cluster:down` followed by `task cluster:up`.
