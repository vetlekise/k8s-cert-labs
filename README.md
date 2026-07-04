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
task reset S=03        # remove scenario 3's resources
task reset:namespaces  # delete the leftover empty scenario namespaces
task cluster:down      # delete the cluster when finished
```

> [!TIP]
> Alias `k` to `kubectl` to save keystrokes (just like on the exam). Add to `~/.bashrc`:
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
(pre-existing deployments, secrets, roles, policies, etc.). All resources are
labeled `scenario: "NN"`, and `task reset` deletes by that label so scenarios that
share a namespace (e.g. `nov2025`, `production`) don't interfere. Use
`task reset:namespaces` to remove the leftover empty namespaces.

Scenarios are grouped per certification under `scenarios/<cert>/`. The tasks default
to CKAD; target another set with the `C` variable, e.g. `task list C=cka` or
`task setup S=03 C=cka`.

> [!NOTE]
> CKAD scenarios **1** (build/export an image) and **13** (fix an old manifest) are local
> file exercises under `scenarios/ckad/` — they have no `task setup`.

### Podman troubleshooting

On rootless Podman with cgroups v2, `task cluster:up` may fail during node creation
if CPU/cpuset controllers aren't delegated to your user. If that happens:

```bash
sudo mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
sudo systemctl daemon-reload
# then log out/in (or reboot) and retry
```
