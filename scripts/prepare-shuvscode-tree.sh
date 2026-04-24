#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source ./shuvscode.env

if [[ -f ./shuvscode.env.local ]]; then
  source ./shuvscode.env.local
fi

node_version="$(cat .nvmrc)"
if command -v mise >/dev/null 2>&1; then
  eval "$(mise env node@"$node_version")"
elif command -v nvm >/dev/null 2>&1; then
  nvm use "$node_version"
elif [[ -s /usr/share/nvm/init-nvm.sh ]]; then
  source /usr/share/nvm/init-nvm.sh
  nvm use "$node_version"
fi

export npm_config_python="${npm_config_python:-$(uv python find 3.11)}"

orig_product="$(mktemp)"
cp product.json "$orig_product"

cleanup() {
  cp "$orig_product" product.json
  rm -f "$orig_product"
}
trap cleanup EXIT

jq -s '.[0] * .[1]' "$orig_product" shuvscode.product.json > product.json

set +u
. ./get_repo.sh
. ./prepare_vscode.sh
set -u

echo "Prepared patched source tree at ./vscode"
