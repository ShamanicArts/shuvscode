#!/usr/bin/env bash
set -euo pipefail

git fetch upstream

echo "Upstream commits since last sync:"
git log --oneline HEAD..upstream/master | head -50

read -r -p "Merge upstream/master into current branch? [y/N] " ans
[[ "$ans" == "y" ]] || exit 0

git merge --no-ff upstream/master -m "chore: sync upstream VSCodium $(date +%Y-%m-%d)"
