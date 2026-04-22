#!/usr/bin/env bash
# Встановлення Cilium CLI для запуску cilium status та cilium connectivity test.
# Підтримка: Linux (amd64, arm64), macOS (darwin/amd64, darwin/arm64).
# Використання: ./install-cilium-cli.sh [--dir INSTALL_DIR]
# За замовчуванням INSTALL_DIR=/usr/local/bin (потрібен sudo).

set -e

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
BASE_URL="https://github.com/cilium/cilium-cli/releases"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--dir INSTALL_DIR]"
      echo "  INSTALL_DIR: where to install 'cilium' binary (default: /usr/local/bin)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# OS and arch
case "$(uname -s)" in
  Linux)   GOOS=linux ;;
  Darwin)  GOOS=darwin ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64)  GOARCH=amd64 ;;
  aarch64|arm64) GOARCH=arm64 ;;
  *)
    echo "Unsupported arch: $(uname -m)" >&2
    exit 1
    ;;
esac

# stable.txt закінчується newline — прибрати, інакше URL .../download/${VER}/... ламається
CILIUM_CLI_VERSION="$(curl -fsSL "https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt" | tr -d '\r\n')"
if [[ -z "${CILIUM_CLI_VERSION}" ]]; then
  echo "Failed to read Cilium CLI version from stable.txt" >&2
  exit 1
fi
echo "Cilium CLI version: ${CILIUM_CLI_VERSION}"
TARBALL="cilium-${GOOS}-${GOARCH}.tar.gz"
URL_TAR="${BASE_URL}/download/${CILIUM_CLI_VERSION}/${TARBALL}"
URL_SHA="${URL_TAR}.sha256sum"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

echo "Downloading ${TARBALL}..."
# -f: HTTP помилки (404 тощо) → ненульовий exit; -S: показати причину при збої
curl -fsSLo "$TARBALL" "$URL_TAR"
curl -fsSLo "${TARBALL}.sha256sum" "$URL_SHA"
if [[ ! -s "$TARBALL" || ! -s "${TARBALL}.sha256sum" ]]; then
  echo "Download failed or produced empty files (tarball / checksum)." >&2
  exit 1
fi

if command -v sha256sum &>/dev/null; then
  sha256sum --check "${TARBALL}.sha256sum"
elif command -v shasum &>/dev/null; then
  shasum -a 256 -c "${TARBALL}.sha256sum"
else
  echo "No sha256 checker (sha256sum/shasum) found, skipping checksum." >&2
fi

mkdir -p "$INSTALL_DIR"
tar -xzf "$TARBALL" -C "$INSTALL_DIR"
echo "Installed cilium to ${INSTALL_DIR}/cilium"
"${INSTALL_DIR}/cilium" version
