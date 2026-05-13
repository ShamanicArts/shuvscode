#!/usr/bin/env bash
set -euo pipefail
cd /home/shamanic/dev/shuvscode
rm -rf vscode* VSCode* .build out* shuvscode-linux-x64
cp patches/disable-update.patch patches/disable-update.patch.yet
export CI_BUILD="no"
export npm_config_python="$(which python3)"
eval "$(/usr/bin/mise activate bash)"
./scripts/build-shuvscode.sh
