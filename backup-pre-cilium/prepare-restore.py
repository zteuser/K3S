#!/usr/bin/env python3
"""
Підготовка YAML для відновлення з бекапу all-resources.yaml.
Видаляє Pods, ReplicaSets та очищує metadata для kubectl apply.
"""
import yaml
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: prepare-restore.py all-resources.yaml [output.yaml]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "restore-workloads.yaml"

    with open(input_file) as f:
        data = yaml.safe_load(f)

    if not data or "items" not in data:
        print("Invalid format: expected list of items")
        sys.exit(1)

    # Виключити Pods, ReplicaSets
    skip_kinds = {"Pod", "ReplicaSet"}
    # Виключити системні k3s
    skip_names = {"coredns", "traefik", "local-path-provisioner", "metrics-server", "svclb-traefik", "flannel"}

    items = []
    for item in data["items"]:
        kind = item.get("kind", "")
        name = item.get("metadata", {}).get("name", "")
        ns = item.get("metadata", {}).get("namespace", "")

        if kind in skip_kinds:
            continue
        if ns == "kube-system" and any(s in name for s in skip_names):
            continue

        # Очистити metadata для apply
        meta = item.get("metadata", {})
        for key in ("resourceVersion", "uid", "creationTimestamp", "generation", "selfLink"):
            meta.pop(key, None)
        if "status" in item:
            del item["status"]

        items.append(item)

    out = {"apiVersion": "v1", "kind": "List", "items": items}
    with open(output_file, "w") as f:
        yaml.dump(out, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

    print(f"Written {len(items)} resources to {output_file}")

if __name__ == "__main__":
    main()
