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

    try:
        with open(input_file, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"Невалідний YAML у {input_file}: {e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Не вдалося прочитати {input_file}: {e}", file=sys.stderr)
        sys.exit(1)

    if not data or "items" not in data:
        print("Invalid format: expected list of items")
        sys.exit(1)

    # Виключити Pods, ReplicaSets
    skip_kinds = {"Pod", "ReplicaSet"}
    # Виключити системні k3s
    skip_names = {"coredns", "traefik", "local-path-provisioner", "metrics-server", "svclb-traefik", "flannel"}

    items = []
    for item in data["items"]:
        if not isinstance(item, dict):
            continue
        kind = item.get("kind", "")
        meta = item.get("metadata")
        if not isinstance(meta, dict):
            meta = {}
            item["metadata"] = meta
        name = meta.get("name", "")
        ns = meta.get("namespace", "")

        if kind in skip_kinds:
            continue
        if ns == "kube-system" and any(s in name for s in skip_names):
            continue

        # Очистити metadata для apply (завжди той самий dict, що в item)
        for key in ("resourceVersion", "uid", "creationTimestamp", "generation", "selfLink"):
            meta.pop(key, None)
        if "status" in item:
            del item["status"]

        items.append(item)

    out = {"apiVersion": "v1", "kind": "List", "items": items}
    with open(output_file, "w", encoding="utf-8") as f:
        yaml.dump(out, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

    print(f"Written {len(items)} resources to {output_file}")

if __name__ == "__main__":
    main()
