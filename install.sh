#!/bin/sh
# Installs the cloudcosttree CLI: downloads the release binary matching
# your OS/CPU from github.com/rulssss/cloudcosttree/releases and puts it
# on your PATH. Usage:
#
#   curl -fsSL https://cloudcosttree.com/install.sh | sh
#
# Override the install directory (default /usr/local/bin) by exporting the
# variable first — NOT as a prefix on the same line as curl, which only
# sets it for curl itself, not the sh on the other end of the pipe:
#
#   export CLOUDCOSTTREE_INSTALL_DIR=~/.local/bin
#   curl -fsSL https://cloudcosttree.com/install.sh | sh

set -e

REPO="rulssss/cloudcosttree"
BIN_NAME="cloudcosttree"
INSTALL_DIR="${CLOUDCOSTTREE_INSTALL_DIR:-/usr/local/bin}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux) os_name="linux" ;;
  Darwin) os_name="darwin" ;;
  *)
    echo "error: unsupported OS '$os'. Download a binary manually from https://github.com/${REPO}/releases" >&2
    exit 1
    ;;
esac

case "$arch" in
  x86_64|amd64) arch_name="amd64" ;;
  arm64|aarch64) arch_name="arm64" ;;
  *)
    echo "error: unsupported architecture '$arch'. Download a binary manually from https://github.com/${REPO}/releases" >&2
    exit 1
    ;;
esac

asset="cloudcosttree-${os_name}-${arch_name}"
url="https://github.com/${REPO}/releases/latest/download/${asset}"

tmp_file="$(mktemp)"
echo "Downloading ${asset}..."
if ! curl -fsSL "$url" -o "$tmp_file"; then
  echo "error: could not download $url" >&2
  rm -f "$tmp_file"
  exit 1
fi
chmod +x "$tmp_file"

target="${INSTALL_DIR}/${BIN_NAME}"
if [ -w "$INSTALL_DIR" ] || [ -w "$(dirname "$INSTALL_DIR")" ]; then
  mkdir -p "$INSTALL_DIR"
  mv "$tmp_file" "$target"
else
  echo "Need elevated permissions to write to $INSTALL_DIR..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo mv "$tmp_file" "$target"
fi

echo "Installed cloudcosttree to $target"
"$target" --help | head -3
echo ""
echo "Done. Run 'cloudcosttree --help' to get started."
