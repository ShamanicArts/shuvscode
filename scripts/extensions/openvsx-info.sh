#!/usr/bin/env bash
set -euo pipefail

id="${1:?usage: $0 publisher.extension}"
publisher="${id%%.*}"
name="${id#*.}"

curl -fsSL "https://open-vsx.org/api/${publisher}/${name}" | jq
