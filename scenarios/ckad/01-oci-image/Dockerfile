# Scenario 1: Build and Export a Container Image in OCI Format
#
# This scenario is LOCAL (podman/docker on your host); it does not run in the
# kind cluster, so there is no `task setup` for it.
#
# Practice:
#   podman build -t devmaq:3.0 -f Dockerfile .
#   mkdir -p /tmp/human-stork/
#   podman save --format oci-archive -o /tmp/human-stork/devmac-3.0.tar devmaq:3.0

FROM busybox:1.36
CMD ["sh", "-c", "echo devmaq && sleep 3600"]
