#!/bin/sh
# Installs the cloudcosttree CLI: downloads the release binary matching
# your OS/CPU from github.com/rulssss/cloudcosttree/releases, puts it in
# ~/.local/bin (no admin/sudo needed — this is a directory you own), and
# adds that directory to your shell's PATH if it isn't there already, so
# `cloudcosttree` works in a fresh terminal right after this finishes.
#
# Usage:
#
#   curl -fsSL https://cloudcosttree.com/install.sh | sh
#
# Override the install directory by exporting the variable first — NOT as
# a prefix on the same line as curl, which only sets it for curl itself,
# not the sh on the other end of the pipe:
#
#   export CLOUDCOSTTREE_INSTALL_DIR=/usr/local/bin
#   curl -fsSL https://cloudcosttree.com/install.sh | sh

set -e

REPO="rulssss/cloudcosttree"
BIN_NAME="cloudcosttree"
INSTALL_DIR="${CLOUDCOSTTREE_INSTALL_DIR:-$HOME/.local/bin}"

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
if [ -w "$INSTALL_DIR" ] || [ -w "$(dirname "$INSTALL_DIR")" ] || mkdir -p "$INSTALL_DIR" 2>/dev/null; then
  mkdir -p "$INSTALL_DIR"
  mv "$tmp_file" "$target"
else
  echo "Need elevated permissions to write to $INSTALL_DIR..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo mv "$tmp_file" "$target"
fi

echo "Installed cloudcosttree to $target"

# Add INSTALL_DIR to PATH for future shells if it isn't already there, the
# same way rustup/uv's installers do — so a brand-new terminal (not just
# this one) can run `cloudcosttree` with no manual PATH edit.
case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    already_on_path=1
    ;;
  *)
    already_on_path=0
    ;;
esac

if [ "$already_on_path" = "0" ]; then
  line="export PATH=\"$INSTALL_DIR:\$PATH\""
  profile=""
  case "${SHELL:-}" in
    */zsh) profile="$HOME/.zshrc" ;;
    */bash)
      if [ -f "$HOME/.bash_profile" ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.bashrc"; fi
      ;;
    *) profile="$HOME/.profile" ;;
  esac

  if [ -n "$profile" ]; then
    if [ -f "$profile" ] && grep -qF "$INSTALL_DIR" "$profile" 2>/dev/null; then
      : # already added on a previous install; don't duplicate it
    else
      printf '\n# Added by the cloudcosttree installer\n%s\n' "$line" >> "$profile"
      echo "Added $INSTALL_DIR to your PATH in $profile"
    fi
  fi

  # Also export it for the rest of *this* script's checks, and tell the
  # user how to pick it up in the current shell without restarting it.
  PATH="$INSTALL_DIR:$PATH"
  echo ""
  echo "Open a new terminal, or run this to use it right now:"
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo ""
"$target" --help | head -3
echo ""
echo "Done. Run 'cloudcosttree --help' to get started."
