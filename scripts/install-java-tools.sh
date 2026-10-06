#!/usr/bin/env bash
# Installs the tools lua/user/lang/java.lua expects, into
# ${XDG_DATA_HOME:-~/.local/share}/nvim-java-tools:
#   jdtls/         Eclipse JDT language server (latest milestone release)
#   lombok.jar     Lombok agent, so jdtls understands @Getter, @Builder, ...
#   java-debug/    java-debug bundle (debugging through nvim-dap)
#   java-test/     vscode-java-test bundles (run/debug JUnit tests)
# Re-run it to update everything. Needs curl, tar, unzip and python3.
set -euo pipefail

TOOLS="${XDG_DATA_HOME:-$HOME/.local/share}/nvim-java-tools"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$TOOLS"

echo "==> jdtls"
JDTLS_VERSION="$(curl -fsSL https://download.eclipse.org/jdtls/milestones/ \
  | grep -oE 'milestones/[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1 | cut -d/ -f2)"
JDTLS_FILE="$(curl -fsSL "https://download.eclipse.org/jdtls/milestones/$JDTLS_VERSION/latest.txt")"
curl -fsSL -o "$WORK/jdtls.tar.gz" "https://download.eclipse.org/jdtls/milestones/$JDTLS_VERSION/$JDTLS_FILE"
mkdir -p "$WORK/jdtls"
tar -xzf "$WORK/jdtls.tar.gz" -C "$WORK/jdtls"
rm -rf "$TOOLS/jdtls"
mv "$WORK/jdtls" "$TOOLS/jdtls"
echo "    $JDTLS_FILE"

echo "==> lombok"
curl -fsSL -o "$TOOLS/lombok.jar" https://projectlombok.org/downloads/lombok.jar

# The debug and test bundles ship inside the VS Code extensions on Open VSX.
install_vsix_jars() {
  local extension="$1" target="$2"
  local url
  url="$(curl -fsSL "https://open-vsx.org/api/vscjava/$extension/latest" \
    | python3 -I -c 'import json, sys; d = json.load(sys.stdin); print(d["files"]["download"])')"
  curl -fsSL -o "$WORK/$extension.vsix" "$url"
  mkdir -p "$WORK/$extension"
  unzip -q "$WORK/$extension.vsix" 'extension/server/*.jar' -d "$WORK/$extension"
  rm -rf "$TOOLS/$target"
  mkdir -p "$TOOLS/$target"
  mv "$WORK/$extension"/extension/server/*.jar "$TOOLS/$target/"
  echo "    $(basename "$url")"
}

echo "==> java-debug"
install_vsix_jars vscode-java-debug java-debug

echo "==> java-test"
install_vsix_jars vscode-java-test java-test

echo "Installed into $TOOLS"
