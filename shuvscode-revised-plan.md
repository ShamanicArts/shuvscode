# ShuvScode Execution Plan

Generated: 2026-04-24 (v2)

Base repo: `shuv1337/shuvscode` (fork of `VSCodium/vscodium`)

Upstream VSCodium at time of writing: tracks VS Code tag `1.112.0`

Ship a branded, packageable editor first; start gutting workbench features later.

---

## 0. Operating decisions

| Area | Decision |
|---|---|
| Base | Fork `VSCodium/vscodium` |
| Target | Linux x86_64 |
| Primary distro | Arch Linux |
| App name | `ShuvScode` |
| CLI binary | `shuvscode` |
| URL protocol | `shuvscode://` |
| User data isolation | `.shuvscode` / `.shuvscode-server` |
| Extension registry | Open VSX, inherited from VSCodium |
| Auto-update policy | Disabled; package manager owns updates |
| First package | `shuvscode-bin` |
| CI artifact | GitHub release tarball consumed by AUR |
| Remote SSH | Gate behind a tested REH/server-download path |
| Hard fork | Optional off-ramp after patch drift becomes the real tax |
| GitHub path | `shuv1337/shuvscode` |

---

## 1. Key corrections and verified assumptions

### 1.1 Dot-source VSCodium build scripts

Use:

```bash
. ./get_repo.sh
. ./build.sh
```

Do not use:

```bash
./get_repo.sh
./build.sh
```

`get_repo.sh` exports `MS_TAG`, `MS_COMMIT`, `RELEASE_VERSION`. `build.sh` sources `version.sh` and `prepare_vscode.sh` internally. These variables must survive across scripts. VSCodium's downstream docs show the dot-sourced form.

### 1.2 Do not hardcode Node LTS names

Use `.nvmrc` from the repo. Current VSCodium `master` pins:

```text
22.22.0
```

Do not assume `nodejs-lts-iron`, system Node, or whatever Arch happens to have.

### 1.3 Use Python 3.11

VSCodium's downstream build docs call out Python 3.11:

```bash
uv python install 3.11
export npm_config_python="$(uv python find 3.11)"
```

### 1.4 Product overlay merge order (verified)

`prepare_vscode.sh` operates inside `vscode/` (the cloned VS Code tree):

1. Sets branding fields (`nameShort`, `applicationName`, etc.) via `setpath` to VSCodium defaults.
2. Then merges repo-root `product.json` as `.[1]`:

```bash
jsonTmp=$( jq -s '.[0] * .[1]' product.json ../product.json )
```

Since `jq`'s `*` operator gives `.[1]` (repo-root) precedence on conflicts, any field in the repo-root product.json overrides the setpath-written VSCodium defaults. Our build wrapper merges `shuvscode.product.json` into repo-root `product.json` before the build starts, so the overlay values flow through and win.

### 1.5 `.gitignore` blocks `*.env` files

The upstream `.gitignore` contains `*.env`. This means `shuvscode.env` will be git-ignored by default. Add a negation rule:

```gitignore
!shuvscode.env
```

The local-secrets override `shuvscode.env.local` is already covered by the `*.env` wildcard. No extra `.gitignore` entry needed for it.

### 1.6 Extensions must go under `src/stable/`

`prepare_vscode.sh` runs:

```bash
cp -rp src/stable/* vscode/
```

This copies everything from `src/stable/` into the VS Code source tree. Built-in extensions live in `vscode/extensions/`. To add custom built-in extensions:

```text
src/stable/extensions/shuvscode-defaults/   -> vscode/extensions/shuvscode-defaults/
src/stable/extensions/shuvscode-bootstrap/  -> vscode/extensions/shuvscode-bootstrap/
```

Do NOT create extensions at the repo root — they will not be included in the build.

### 1.7 No invalid JSON

Do not write this:

```json
"configurationSync.store": undefined
```

JSON does not have `undefined`. Use `null`, omit the key, or patch the sync UI.

### 1.8 Do not delete non-Linux platform resources early

Do not delete `src/stable/resources/win32` or `src/stable/resources/darwin`. It saves nothing and creates upstream conflict bait.

### 1.9 VSCodium already handles several things the defaults extension does not need to duplicate

VSCodium's existing patches already handle:

- `chat.disableAIFeatures` default changed to `true` (`disable-copilot.patch`)
- Cloud sync sign-in action removed (`disable-cloud.patch`)
- Signature verification disabled (`disable-signature-verification.patch`)
- Telemetry disabled (`telemetry.patch` + `undo_telemetry.sh`)
- Copilot chat UI gated behind `disableAIFeatures` context key (`disable-copilot.patch`)

Do not duplicate these in the defaults extension.

### 1.10 Linux resources use `@@` build-time templates

The files in `src/stable/resources/linux/` use `@@` template variables:

```text
@@NAME_LONG@@    -> resolved from product.json nameShort/nameLong
@@EXEC@@         -> resolved from product.json applicationName
@@ICON@@         -> resolved from product.json linuxIconName
@@NAME_SHORT@@   -> resolved from product.json nameShort
@@URLPROTOCOL@@  -> resolved from product.json urlProtocol
@@LICENSE@@      -> resolved by VS Code's gulp tasks
```

These are substituted by VS Code's gulp packaging tasks, NOT by VSCodium's patch system. If the product overlay correctly sets `nameShort`, `applicationName`, `linuxIconName`, etc., the templates resolve correctly. You do not need to manually edit `.desktop` or URL-handler files for branding.

However, `prepare_vscode.sh` also does hardcoded text substitution on `code.appdata.xml` (replacing "Visual Studio Code" with "VSCodium"). If you want "ShuvScode" instead, you must either override the appdata source file or add a user patch.

### 1.11 Remote SSH is not just an extension install

`jeanp413.open-remote-ssh` needs proposed APIs and a working remote server/REH artifact path. Do not call Remote SSH production-ready until tested end-to-end.

### 1.12 AUR package must use real checksums

`SKIP` for a static release tarball is lazy packaging. Use the actual SHA256 from the GitHub release artifact.

### 1.13 `dataFolderName` is only set for insider builds

`prepare_vscode.sh` only calls `setpath "product" "dataFolderName"` in the insider branch. For stable builds, VS Code's default `.vscode` would remain unless overridden by the repo-root product.json merge. The overlay MUST include `"dataFolderName": ".shuvscode"`.

### 1.14 Upstream CI workflows must be removed

The fork inherits 14 VSCodium CI/publish workflow files in `.github/workflows/`. These reference VSCodium-specific secrets and repos. They will fail or be noisy in the fork. Remove or replace them.

---

# Phase 0 -- Validate toolchain

Goal: prove the forked repo builds a stock VSCodium locally before adding overlay.

The fork is already cloned with remotes configured:

```text
origin   -> git@github.com:shuv1337/shuvscode.git
upstream -> git@github.com:VSCodium/vscodium.git
```

## 0.1 Install Arch build dependencies

```bash
sudo pacman -S --needed \
  base-devel git jq ripgrep python rustup uv \
  fakeroot dpkg imagemagick \
  libx11 libxkbfile libsecret krb5 gtk3 nss alsa-lib \
  libxss libxtst libdrm libgbm pango cairo libnotify xdg-utils
```

Install and initialize a Node manager:

```bash
source /usr/share/nvm/init-nvm.sh
```

## 0.2 Build stock VSCodium from the fork

```bash
source /usr/share/nvm/init-nvm.sh
nvm install "$(cat .nvmrc)"
nvm use "$(cat .nvmrc)"

uv python install 3.11
export npm_config_python="$(uv python find 3.11)"

rustup default stable

export OS_NAME=linux
export VSCODE_ARCH=x64
export VSCODE_QUALITY=stable
export SHOULD_BUILD=yes
export SHOULD_BUILD_REH=no
export SHOULD_BUILD_REH_WEB=no
export CI_BUILD=no
export DISABLE_UPDATE=yes
export VSCODE_LATEST=no

time bash -lc '. ./get_repo.sh && . ./build.sh'
```

## 0.3 Verify stock build

```bash
./VSCode-linux-x64/codium --version

./VSCode-linux-x64/codium \
  --user-data-dir=/tmp/codium-stock-user \
  --extensions-dir=/tmp/codium-stock-exts
```

Done when:

```text
[ ] Stock VSCodium launches from the fork repo.
[ ] Open VSX extension search works.
[ ] One Open VSX extension installs.
[ ] Baseline build time recorded.
```

---

# Phase 1 -- Scaffold

Goal: add build wrappers, product overlay, and branch structure on top of the existing fork.

## 1.1 Branch setup

```bash
git branch -m master shuvscode-main
git push -u origin shuvscode-main
```

Set `shuvscode-main` as the default branch on GitHub, then:

```bash
git push origin --delete master
```

## 1.2 Fix `.gitignore`

```bash
cat >> .gitignore <<'EOF'

# ShuvScode: track the env file (*.env would block it)
!shuvscode.env

# Local build overrides / secrets (already covered by *.env)
# shuvscode.env.local
EOF
```

## 1.3 Remove upstream CI workflows

```bash
rm .github/workflows/ci-build-*.yml
rm .github/workflows/publish-*.yml
rm .github/workflows/mod-*.yml
rm .github/workflows/lint-*.yml
```

These reference VSCodium-specific secrets and repos. Our CI goes in Phase 5.

## 1.4 Create `shuvscode.env`

```bash
cat > shuvscode.env <<'EOF'
# Branding
export APP_NAME="ShuvScode"
export BINARY_NAME="shuvscode"
export GH_REPO_PATH="shuv1337/shuvscode"
export ASSETS_REPOSITORY="shuv1337/shuvscode"
export ORG_NAME="ShuvScode"
export TUNNEL_APP_NAME="shuvscode-tunnel"
export GLOBAL_DIRNAME="shuvscode"

# Build
export OS_NAME="linux"
export VSCODE_ARCH="x64"
export VSCODE_QUALITY="stable"
export SHOULD_BUILD="yes"
export SHOULD_BUILD_REH="no"
export SHOULD_BUILD_REH_WEB="no"
export CI_BUILD="no"
export DISABLE_UPDATE="yes"
export VSCODE_LATEST="no"
EOF
```

Do not set `RELEASE_VERSION` here. Let VSCodium derive it locally, and set it explicitly only in CI/release flows when needed.

## 1.5 Create `shuvscode.product.json`

```bash
cat > shuvscode.product.json <<'EOF'
{
  "nameShort": "ShuvScode",
  "nameLong": "ShuvScode",
  "applicationName": "shuvscode",
  "dataFolderName": ".shuvscode",
  "linuxIconName": "shuvscode",
  "quality": "stable",
  "urlProtocol": "shuvscode",

  "serverApplicationName": "shuvscode-server",
  "serverDataFolderName": ".shuvscode-server",
  "tunnelApplicationName": "shuvscode-tunnel",

  "reportIssueUrl": "https://github.com/shuv1337/shuvscode/issues/new",
  "requestFeatureUrl": "https://github.com/shuv1337/shuvscode/issues/new",
  "licenseUrl": "https://github.com/shuv1337/shuvscode/blob/shuvscode-main/LICENSE",

  "linkProtectionTrustedDomains": [
    "https://open-vsx.org",
    "https://github.com/shuv1337/shuvscode"
  ],

  "extensionTips": {},
  "extensionImportantTips": {},
  "keymapExtensionTips": [],
  "languageExtensionTips": [],
  "configBasedExtensionTips": {},
  "extensionKeywords": {},

  "builtInExtensions": [],

  "extensionEnabledApiProposals": {
    "jeanp413.open-remote-ssh": [
      "resolvers",
      "contribViewsRemote"
    ]
  }
}
EOF
```

Notes:

- `dataFolderName` is required because `prepare_vscode.sh` only sets it for insider builds. Without this, user data would go to `~/.vscode`.
- `quality` is redundant with `prepare_vscode.sh`'s setpath but makes the overlay self-documenting.
- `extensionEnabledApiProposals` for open-remote-ssh is present early but Remote SSH is gated until tested (Phase 7.5).
- No invalid `undefined` values.

## 1.6 Create `scripts/build-shuvscode.sh`

```bash
mkdir -p scripts

cat > scripts/build-shuvscode.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source ./shuvscode.env

if [[ -f ./shuvscode.env.local ]]; then
  source ./shuvscode.env.local
fi

if command -v nvm >/dev/null 2>&1; then
  nvm use "$(cat .nvmrc)"
elif [[ -s /usr/share/nvm/init-nvm.sh ]]; then
  source /usr/share/nvm/init-nvm.sh
  nvm use "$(cat .nvmrc)"
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

# Upstream scripts assume some vars can be unset.
set +u
. ./get_repo.sh
. ./build.sh
set -u

echo "Built: VSCode-linux-${VSCODE_ARCH}/${BINARY_NAME}"
SCRIPT

chmod +x scripts/build-shuvscode.sh
```

## 1.7 Create `scripts/prepare-shuvscode-tree.sh`

This prepares the patched `./vscode` tree without doing a full build. Use it to create/update user patches.

```bash
cat > scripts/prepare-shuvscode-tree.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source ./shuvscode.env

if [[ -f ./shuvscode.env.local ]]; then
  source ./shuvscode.env.local
fi

if command -v nvm >/dev/null 2>&1; then
  nvm use "$(cat .nvmrc)"
elif [[ -s /usr/share/nvm/init-nvm.sh ]]; then
  source /usr/share/nvm/init-nvm.sh
  nvm use "$(cat .nvmrc)"
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
SCRIPT

chmod +x scripts/prepare-shuvscode-tree.sh
```

Note: this script includes Node setup (via nvm) because `prepare_vscode.sh` runs `npm ci`. The original plan omitted this and would have failed.

## 1.8 Create `scripts/sync-upstream.sh`

```bash
cat > scripts/sync-upstream.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

git fetch upstream

echo "Upstream commits since last sync:"
git log --oneline HEAD..upstream/master | head -50

read -r -p "Merge upstream/master into current branch? [y/N] " ans
[[ "$ans" == "y" ]] || exit 0

git merge --no-ff upstream/master -m "chore: sync upstream VSCodium $(date +%Y-%m-%d)"
SCRIPT

chmod +x scripts/sync-upstream.sh
```

Note: this uses interactive `read -p`. For CI-driven syncs, merge directly.

## 1.9 Commit scaffold

```bash
git add \
  .gitignore \
  shuvscode.env \
  shuvscode.product.json \
  scripts/

git rm .github/workflows/ci-build-*.yml \
      .github/workflows/publish-*.yml \
      .github/workflows/mod-*.yml \
      .github/workflows/lint-*.yml

git commit -m "chore: add shuvscode build scaffold, remove upstream CI"
git push
```

Done when:

```text
[ ] Fork has `upstream` remote pointing at VSCodium.
[ ] Build wrapper dot-sources upstream build scripts.
[ ] Product overlay exists separately from upstream `product.json`.
[ ] `shuvscode.env` is tracked (not blocked by `.gitignore`).
[ ] `shuvscode.env.local` is ignored (covered by `*.env` wildcard).
[ ] `prepare-shuvscode-tree.sh` includes Node setup.
[ ] Upstream CI workflows are removed.
[ ] No tokens/secrets are committed.
```

---

# Phase 2 -- First real rebrand

Goal: produce a working `shuvscode` build with product branding overridden by the overlay.

## 2.1 Build

```bash
rm -rf vscode VSCode-linux-x64
./scripts/build-shuvscode.sh
```

## 2.2 Inspect product metadata

```bash
jq '{
  nameShort,
  nameLong,
  applicationName,
  dataFolderName,
  linuxIconName,
  urlProtocol,
  serverApplicationName,
  serverDataFolderName,
  tunnelApplicationName,
  reportIssueUrl,
  extensionsGallery
}' vscode/product.json
```

Expected:

```text
nameShort:              ShuvScode
applicationName:        shuvscode
dataFolderName:         .shuvscode
linuxIconName:          shuvscode
urlProtocol:            shuvscode
serverApplicationName:  shuvscode-server
serverDataFolderName:   .shuvscode-server
extensionsGallery:      (Open VSX URLs)
```

## 2.3 Launch

```bash
./VSCode-linux-x64/shuvscode --version

./VSCode-linux-x64/shuvscode \
  --user-data-dir=/tmp/shuvscode-phase2-user \
  --extensions-dir=/tmp/shuvscode-phase2-exts
```

Done when:

```text
[ ] Binary is `VSCode-linux-x64/shuvscode`.
[ ] Window title says ShuvScode.
[ ] Product metadata says shuvscode, not shuvcode/codium/vscodium.
[ ] Issue URL points to shuv1337/shuvscode.
[ ] Fresh profile does not collide with Code or VSCodium.
[ ] Open VSX extension search still works.
```

Tag:

```bash
git tag v0.0.1-rebrand
git push origin v0.0.1-rebrand
```

---

# Phase 3 -- Linux branding assets

Goal: replace visible Linux branding without deleting unrelated platform resources.

## 3.1 What `@@` templates handle automatically

The `.desktop`, `.appdata.xml`, and URL-handler files in `src/stable/resources/linux/` use `@@` template variables (`@@NAME_LONG@@`, `@@EXEC@@`, `@@ICON@@`, `@@URLPROTOCOL@@`) that are resolved by VS Code's gulp packaging tasks using product.json values. Since the overlay sets `nameShort`, `applicationName`, and `linuxIconName`, these templates resolve correctly without manual edits.

## 3.2 What you must replace manually

| File | Why |
|---|---|
| `src/stable/resources/linux/code.png` | App icon — replace with ShuvScode 512x512 PNG |
| `src/stable/resources/linux/code.svg` | Vector icon source |
| `src/stable/resources/linux/rpm/code.xpm` | RPM icon (if you ever build RPMs) |
| `src/stable/resources/server/favicon.ico` | Server/browser favicon |
| `src/stable/resources/server/code-192.png` | Server/web app icon |
| `src/stable/resources/server/code-512.png` | Server/web app icon |
| `src/stable/resources/linux/code.appdata.xml` | Has hardcoded "VSCodium" text in `<summary>` and `<description>` that `@@` templates do not cover |
| `src/stable/src/vs/workbench/browser/media/code-icon.svg` | Workbench icon |
| `src/stable/src/vs/workbench/browser/parts/editor/media/letterpress-*.svg` | Empty-editor watermark (4 theme variants) |
| `icons/stable/codium_*.svg` and `icons/insider/codium_*.svg` | Source inputs used by the VSCodium icon build script |

Additionally, `prepare_vscode.sh` does post-copy `sed` substitution on `resources/linux/code.appdata.xml`, replacing "Visual Studio Code" with "VSCodium". Since your source file already says "VSCodium", this sed is a no-op. Replace the text with "ShuvScode" in the source file:

```bash
sed -i \
  -e 's/VSCodium/ShuvScode/g' \
  -e 's/vscodium\.com/github.com\/shuv1337\/shuvscode/g' \
  src/stable/resources/linux/code.appdata.xml
```

## 3.3 Desktop file keywords

The desktop file template at `src/stable/resources/linux/code.desktop` has:

```text
Keywords=vscodium;codium;vscode;
```

Add ShuvScode keywords:

```text
Keywords=shuvscode;vscodium;codium;vscode;
```

Same for `code-url-handler.desktop`.

## 3.4 Asset requirements

Use the generated BOFH-inspired devil phone image as the canonical source:

```text
[ ] `assets/branding/shuvscode-devil-phone-source.png`.
[ ] `scripts/generate-shuvscode-assets.sh`.
[ ] Linux PNG/SVG/XPM generated from the source.
[ ] Server favicon plus 192px/512px PNGs generated from the source.
[ ] Workbench icon and all 4 letterpress variants generated from the source.
[ ] `icons/stable` and `icons/insider` source SVG wrappers regenerated from the source.
```

Regenerate all checked-in icon assets with:

```bash
./scripts/generate-shuvscode-assets.sh
```

The script normalizes the generated source by removing the white background,
padding it into a transparent square, then deriving every icon from that single
source. Do not hand-edit the generated icon outputs.

## 3.5 Build and verify

```bash
rm -rf vscode VSCode-linux-x64
./scripts/build-shuvscode.sh

./VSCode-linux-x64/shuvscode \
  --user-data-dir=/tmp/shuvscode-icon-user \
  --extensions-dir=/tmp/shuvscode-icon-exts
```

Check WM class:

```bash
xprop WM_CLASS
```

Done when:

```text
[ ] App window icon is yours.
[ ] Taskbar/dock icon is yours.
[ ] AppStream XML says ShuvScode.
[ ] Desktop launcher resolves to `Icon=shuvscode` (via @@ICON@@).
[ ] StartupWMClass matches actual WM_CLASS.
```

Commit/tag:

```bash
git add src/stable/resources src/stable/src shuvscode.product.json
git commit -m "feat: add shuvscode linux branding assets"
git tag v0.0.2-linux-assets
git push --follow-tags
```

---

# Phase 4 -- Defaults extension

Goal: make ShuvScode opinionated without fighting upstream source defaults.

## 4.1 Create `src/stable/extensions/shuvscode-defaults`

The extension goes under `src/stable/extensions/` so `prepare_vscode.sh` copies it into the build tree at `vscode/extensions/shuvscode-defaults/`.

```bash
mkdir -p src/stable/extensions/shuvscode-defaults

cat > src/stable/extensions/shuvscode-defaults/package.json <<'EOF'
{
  "name": "shuvscode-defaults",
  "displayName": "ShuvScode Defaults",
  "description": "Opinionated default settings for ShuvScode.",
  "version": "0.0.1",
  "publisher": "shuvscode",
  "engines": {
    "vscode": "*"
  },
  "categories": [
    "Other"
  ],
  "contributes": {
    "configurationDefaults": {
      "workbench.startupEditor": "none",
      "workbench.tips.enabled": false,
      "workbench.welcomePage.walkthroughs.openOnInstall": false,
      "workbench.commandPalette.experimental.suggestCommands": false,

      "extensions.ignoreRecommendations": true,
      "update.showReleaseNotes": false,

      "window.commandCenter": false,
      "workbench.layoutControl.enabled": false,

      "breadcrumbs.enabled": false,
      "editor.minimap.enabled": false,
      "editor.stickyScroll.enabled": false,
      "editor.inlayHints.enabled": "off"
    }
  }
}
EOF
```

What was removed compared to the original plan and why:

- `"telemetry.telemetryLevel": "off"` -- VSCodium's `telemetry.patch` + `undo_telemetry.sh` already handles this at the source level.
- `"chat.disableAIFeatures": true` -- VSCodium's `disable-copilot.patch` already changes this default to `true` in the source.
- `"github.copilot.enable": {"*": false}` -- Copilot is not available via Open VSX. If a user sideloads it, they want it on. No point defaulting it off.

What remains is pure UX opinion: no welcome tab, no minimap, no breadcrumbs, no command center, no sticky scroll, no inlay hints, no extension recommendations, no release notes popup. All user-overridable.

Engine version set to `"*"` because this is a built-in extension that always ships with the matching editor. Pinning a specific version creates pointless maintenance during upstream syncs.

## 4.2 Build and verify

```bash
rm -rf vscode VSCode-linux-x64
./scripts/build-shuvscode.sh

./VSCode-linux-x64/shuvscode \
  --user-data-dir=/tmp/shuvscode-defaults-user \
  --extensions-dir=/tmp/shuvscode-defaults-exts
```

Check:

```text
[ ] Fresh startup opens no welcome editor.
[ ] Minimap is off.
[ ] Breadcrumbs are off.
[ ] Command center is off.
[ ] Extension recommendations are quiet.
[ ] Settings UI shows defaults as contributed by "ShuvScode Defaults", not user-written.
```

Commit:

```bash
git add src/stable/extensions/shuvscode-defaults
git commit -m "feat: add shuvscode default settings extension"
```

---

# Phase 5 -- CI release tarball

Goal: one tag creates one Linux x64 tarball plus SHA256. No deb/rpm/AppImage circus yet.

## 5.1 Versioning rule

Use tags shaped like:

```text
v<base-version>.shuv<revision>
```

Example:

```text
v1.112.01907.shuv1
```

Meaning:

```text
VSCodium/VS Code base release:  1.112.01907
ShuvScode package revision:     shuv1
AUR pkgver:                     1.112.01907.shuv1
Internal RELEASE_VERSION:       1.112.01907
```

## 5.2 GitHub Actions workflow

```bash
mkdir -p .github/workflows

cat > .github/workflows/build-release.yml <<'EOF'
name: Build release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      release_version:
        description: 'VSCodium RELEASE_VERSION, e.g. 1.112.01907'
        required: false
        type: string

permissions:
  contents: write

jobs:
  linux-x64:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v6
        with:
          node-version-file: .nvmrc

      - uses: astral-sh/setup-uv@v8.1.0

      - name: Install system deps
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            jq ripgrep git curl python3 python3-pip \
            libx11-dev libxkbfile-dev libsecret-1-dev libkrb5-dev \
            fakeroot rpm imagemagick pkg-config build-essential dpkg

      - name: Install Python and Rust
        run: |
          uv python install 3.11
          rustup toolchain install stable --profile minimal
          rustup default stable

      - name: Derive RELEASE_VERSION
        shell: bash
        run: |
          set -euo pipefail

          release_version="${{ inputs.release_version }}"

          if [[ -z "$release_version" && "${GITHUB_REF_TYPE}" == "tag" ]]; then
            tag="${GITHUB_REF_NAME#v}"
            release_version="${tag%%.shuv*}"
          fi

          if [[ -n "$release_version" ]]; then
            echo "RELEASE_VERSION=${release_version}" >> "$GITHUB_ENV"
            echo "Using RELEASE_VERSION=${release_version}"
          else
            echo "No RELEASE_VERSION override; VSCodium scripts will derive it."
          fi

      - name: Build
        env:
          CI_BUILD: "no"
        run: |
          export npm_config_python="$(uv python find 3.11)"
          ./scripts/build-shuvscode.sh

      - name: Package tarball
        run: |
          mv VSCode-linux-x64 shuvscode
          tar czf shuvscode-linux-x64.tar.gz shuvscode
          sha256sum shuvscode-linux-x64.tar.gz > shuvscode-linux-x64.tar.gz.sha256

      - name: Create GitHub release
        if: startsWith(github.ref, 'refs/tags/')
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "${GITHUB_REF_NAME}" \
            shuvscode-linux-x64.tar.gz \
            shuvscode-linux-x64.tar.gz.sha256 \
            --title "${GITHUB_REF_NAME}" \
            --notes "ShuvScode Linux x64 release ${GITHUB_REF_NAME}"
EOF
```

Changes from original plan:

- `astral-sh/setup-uv@v8.1.0` pinned to exact tag (bare `@v8` may not resolve).
- Tarball renamed to include top-level `shuvscode/` directory (`mv VSCode-linux-x64 shuvscode` before tar). This makes the PKGBUILD cleaner — no need to copy-then-cleanup.
- `CI_BUILD=no` kept for the simple local artifact/tarball path.

## 5.3 Test CI

```bash
git add .github/workflows/build-release.yml
git commit -m "ci: add linux release build"
git push

git tag v1.112.01907.shuv1
git push origin v1.112.01907.shuv1
```

Done when:

```text
[ ] Tag push creates a GitHub release.
[ ] Release contains `shuvscode-linux-x64.tar.gz`.
[ ] Release contains `shuvscode-linux-x64.tar.gz.sha256`.
[ ] Tarball extracts to a `shuvscode/` directory.
[ ] Downloaded tarball launches outside the repo.
[ ] `shuvscode/shuvscode --version` works from extracted tarball.
```

---

# Phase 6 -- AUR package: `shuvscode-bin`

Goal: install the GitHub release tarball into `/opt/shuvscode`, expose `/usr/bin/shuvscode`, install desktop/icon metadata, and use real checksums.

## 6.1 Package skeleton

```bash
mkdir -p packaging/aur/shuvscode-bin
cd packaging/aur/shuvscode-bin
```

## 6.2 `PKGBUILD`

```bash
cat > PKGBUILD <<'EOF'
# Maintainer: shuv <you@example.com>

pkgname=shuvscode-bin
_pkgname=shuvscode
pkgver=1.112.01907.shuv1
pkgrel=1
pkgdesc="ShuvScode: an opinionated VS Code/VSCodium fork (bundles Electron)"
arch=('x86_64')
url="https://github.com/shuv1337/shuvscode"
license=('MIT')
depends=(
  'alsa-lib'
  'at-spi2-core'
  'cairo'
  'fontconfig'
  'gtk3'
  'libdrm'
  'libgbm'
  'libsecret'
  'libx11'
  'libxkbfile'
  'libxss'
  'libxtst'
  'nss'
  'pango'
)
optdepends=(
  'org.freedesktop.secrets: keyring/secrets support'
)
provides=("shuvscode=${pkgver}")
conflicts=('shuvscode' 'shuvscode-git' 'shuvscode-electron')
source=(
  "${pkgname}-${pkgver}.tar.gz::https://github.com/shuv1337/shuvscode/releases/download/v${pkgver}/shuvscode-linux-x64.tar.gz"
  "shuvscode.sh"
  "shuvscode.desktop"
)
sha256sums=(
  '<release-tarball-sha256>'
  '<shuvscode-sh-sha256>'
  '<desktop-sha256>'
)

package() {
  install -dm755 "${pkgdir}/opt/${_pkgname}"

  # Tarball extracts to shuvscode/ (top-level dir included in archive)
  cp -a "${srcdir}/${_pkgname}/." "${pkgdir}/opt/${_pkgname}/"

  install -Dm755 "${srcdir}/shuvscode.sh" \
    "${pkgdir}/usr/bin/shuvscode"

  install -Dm644 "${srcdir}/shuvscode.desktop" \
    "${pkgdir}/usr/share/applications/shuvscode.desktop"

  if [[ -f "${pkgdir}/opt/${_pkgname}/resources/app/LICENSE.txt" ]]; then
    install -Dm644 "${pkgdir}/opt/${_pkgname}/resources/app/LICENSE.txt" \
      "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  fi

  if [[ -f "${pkgdir}/opt/${_pkgname}/resources/app/resources/linux/code.png" ]]; then
    install -Dm644 "${pkgdir}/opt/${_pkgname}/resources/app/resources/linux/code.png" \
      "${pkgdir}/usr/share/icons/hicolor/512x512/apps/shuvscode.png"
  fi
}
EOF
```

Changes from original plan:

- `pkgdesc` notes bundled Electron.
- `package()` uses `cp -a "${srcdir}/${_pkgname}/."` directly, no cleanup step needed because the tarball extracts into a `shuvscode/` subdirectory (see Phase 5 tarball creation change). The other source files (`shuvscode.sh`, `shuvscode.desktop`) are in `${srcdir}/` at the top level and are NOT inside `shuvscode/`.

## 6.3 Launcher wrapper

```bash
cat > shuvscode.sh <<'EOF'
#!/usr/bin/env bash
exec /opt/shuvscode/bin/shuvscode "$@"
EOF

chmod +x shuvscode.sh
```

## 6.4 Desktop file

```bash
cat > shuvscode.desktop <<'EOF'
[Desktop Entry]
Name=ShuvScode
Comment=Opinionated code editor
Exec=shuvscode %F
Icon=shuvscode
Type=Application
StartupNotify=false
StartupWMClass=ShuvScode
Categories=Utility;TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;
Actions=new-empty-window;
Keywords=shuvscode;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=shuvscode --new-window %F
Icon=shuvscode
EOF
```

`StartupNotify=false` matches the upstream template. After installing, check `StartupWMClass` against reality:

```bash
xprop WM_CLASS
```

If it differs, fix the desktop file.

## 6.5 Generate checksums and `.SRCINFO`

```bash
updpkgsums
makepkg --printsrcinfo > .SRCINFO
```

## 6.6 Local install test

```bash
makepkg -si

which shuvscode
shuvscode --version

shuvscode \
  --user-data-dir=/tmp/shuvscode-aur-user \
  --extensions-dir=/tmp/shuvscode-aur-exts

pacman -Ql shuvscode-bin | grep -E 'desktop|icons|licenses|/usr/bin'
```

Done when:

```text
[ ] `makepkg -si` installs cleanly.
[ ] `/usr/bin/shuvscode` launches.
[ ] App launcher shows correct name/icon.
[ ] StartupWMClass matches actual WM_CLASS.
[ ] License is installed.
[ ] sha256sums are real, not `SKIP`.
[ ] Open VSX extension install works.
```

---

# Phase 7 -- Extensions: bake small/stable, bootstrap big/fast-moving

Goal: make ShuvScode useful out of the box without pinning giant fast-moving VSIX blobs into every editor release.

## 7.1 Extension policy

| Extension | Strategy | Reason |
|---|---|---|
| `detachhead.basedpyright` | Bake | Small/stable Pylance replacement (v1.39.3 on Open VSX) |
| `EditorConfig.EditorConfig` | Bake | Tiny and universal |
| `jeanp413.open-remote-ssh` | Bake only after REH test | Needs proposed APIs and server download correctness |
| `sdras.night-owl` | Bootstrap | Default shuvscode color theme without baking a marketplace VSIX blob |
| `vscode-icons-team.vscode-icons` | Bootstrap | User taste, large-ish, easy uninstall |
| `ms-python.python` | Optional/bootstrap | Validate current Open VSX behavior/licensing first |

## 7.2 Open VSX metadata helper

```bash
mkdir -p scripts/extensions

cat > scripts/extensions/openvsx-info.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

id="${1:?usage: $0 publisher.extension}"
publisher="${id%%.*}"
name="${id#*.}"

curl -fsSL "https://open-vsx.org/api/${publisher}/${name}" | jq
EOF

chmod +x scripts/extensions/openvsx-info.sh
```

Download and checksum a VSIX:

```bash
id="detachhead.basedpyright"
publisher="${id%%.*}"
name="${id#*.}"

url="$(./scripts/extensions/openvsx-info.sh "$id" | jq -r '.files.download')"
version="$(./scripts/extensions/openvsx-info.sh "$id" | jq -r '.version')"

curl -fL "$url" -o "${id}-${version}.vsix"
sha256sum "${id}-${version}.vsix"
```

## 7.3 Add baked extensions to `shuvscode.product.json`

The shape should look like this:

```json
{
  "name": "detachhead.basedpyright",
  "version": "<version>",
  "sha256": "<sha256>",
  "repo": "https://github.com/detachhead/basedpyright",
  "metadata": {
    "id": "<extension-id-from-openvsx-metadata>",
    "publisherId": {
      "publisherId": "<publisher-id>",
      "publisherName": "detachhead",
      "displayName": "detachhead",
      "flags": "verified"
    },
    "publisherDisplayName": "detachhead"
  }
}
```

Do not hand-edit UUIDs. Script the metadata extraction.

Done for each baked extension:

```text
[ ] Version pinned.
[ ] SHA256 pinned.
[ ] Metadata captured from Open VSX.
[ ] Extension activates in fresh profile.
[ ] Extension updates only by ShuvScode release bump.
```

## 7.4 Bootstrap extension

Use plain JS. Goes under `src/stable/extensions/` like the defaults extension.

```bash
mkdir -p src/stable/extensions/shuvscode-bootstrap

cat > src/stable/extensions/shuvscode-bootstrap/package.json <<'EOF'
{
  "name": "shuvscode-bootstrap",
  "displayName": "ShuvScode Bootstrap",
  "description": "Installs selected first-run extensions for ShuvScode.",
  "version": "0.0.1",
  "publisher": "shuvscode",
  "engines": {
    "vscode": "*"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [
    "onStartupFinished"
  ],
  "main": "./extension.js",
  "extensionKind": [
    "ui"
  ],
  "contributes": {
    "configuration": {
      "title": "ShuvScode Bootstrap",
      "properties": {
        "shuvscode.bootstrap.enabled": {
          "type": "boolean",
          "default": true,
          "description": "Install ShuvScode first-run extension recommendations once."
        }
      }
    }
  }
}
EOF

cat > src/stable/extensions/shuvscode-bootstrap/extension.js <<'EOF'
const vscode = require('vscode');

const FLAG = 'shuvscode.bootstrapped';

const EXTENSIONS = [
  'sdras.night-owl',
  'vscode-icons-team.vscode-icons'
];

async function activate(ctx) {
  const enabled = vscode.workspace
    .getConfiguration('shuvscode.bootstrap')
    .get('enabled', true);

  if (!enabled || ctx.globalState.get(FLAG)) {
    return;
  }

  const results = await Promise.allSettled(
    EXTENSIONS
      .filter(id => !vscode.extensions.getExtension(id))
      .map(id =>
        vscode.commands.executeCommand(
          'workbench.extensions.installExtension',
          id
        )
      )
  );

  const anyFailure = results.some(r => r.status === 'rejected');

  if (!anyFailure) {
    await ctx.globalState.update(FLAG, true);
  }
}

function deactivate() {}

module.exports = {
  activate,
  deactivate
};
EOF
```

Changes from original plan:

- Location moved from `extensions/` to `src/stable/extensions/`.
- Engine version set to `"*"` (built-in extension, always matches editor).
- Uses `Promise.allSettled` for parallel installs instead of sequential `for...of` loop.

Done when:

```text
[ ] Bootstrapped extensions install once.
[ ] User can uninstall them and they stay uninstalled.
[ ] Bootstrap can be disabled via `shuvscode.bootstrap.enabled=false`.
[ ] Failure to install one extension does not block others.
```

## 7.5 Remote SSH gate

Do not call Open Remote SSH production-ready until this passes:

```text
[ ] `jeanp413.open-remote-ssh` is baked or bootstrap-installed.
[ ] Product overlay grants `resolvers` and `contribViewsRemote` proposed APIs.
[ ] `remote.SSH.serverDownloadUrlTemplate` points to a real matching REH tarball.
[ ] `remote.SSH.experimental.serverBinaryName` is set only if needed.
[ ] Linux x64 remote host connects.
[ ] Version mismatch does not occur.
[ ] Remote Python/basedpyright behavior is tested.
```

---

# Phase 8 -- Surgical strip patches

Goal: remove features only after the branded/packageable editor exists. Defaults first, then patches. Hard deletes last.

## 8.1 What upstream already strips

Before writing strip patches, know what VSCodium's existing patches already handle:

| Upstream patch | What it does |
|---|---|
| `disable-copilot.patch` | Gates all Copilot/chat UI behind `chat.disableAIFeatures` (defaulted true) |
| `disable-cloud.patch` | Removes cloud sync sign-in action |
| `disable-vscodedev.patch` | Disables vscode.dev redirect features |
| `telemetry.patch` | Disables telemetry at source level |
| `disable-missing-vsda.patch` | Handles missing signature verification DLL |
| `disable-signature-verification.patch` | Disables extension signature checks |

Do not duplicate this work. Your user patches in `patches/user/` should only target leftovers.

## 8.2 Patch naming

```text
patches/user/10-strip-welcome.patch
patches/user/11-strip-release-notes.patch
patches/user/12-strip-feedback.patch
patches/user/13-strip-command-center-leftovers.patch
```

Use numeric prefixes. Glob order is a jerk.

## 8.3 Patch workflow

```bash
rm -rf vscode VSCode-linux-x64
./scripts/prepare-shuvscode-tree.sh

cd vscode

# Edit files.
$EDITOR src/vs/workbench/workbench.common.main.ts

# Create patch.
git diff > ../patches/user/10-strip-something.patch

cd ..

# Replace branding-sensitive literals only if they appear in the patch.
sed -i \
  -e 's/ShuvScode/!!APP_NAME!!/g' \
  -e 's/shuvscode/!!BINARY_NAME!!/g' \
  -e 's/shuvscode/!!APP_NAME_LC!!/g' \
  patches/user/10-strip-something.patch

rm -rf vscode VSCode-linux-x64
./scripts/build-shuvscode.sh
```

## 8.4 First strip batch

| Patch | Target | Risk |
|---|---|---|
| `10-strip-welcome-runtime.patch` | Welcome/getting-started runtime leftovers not covered by `startupEditor=none` default | Low |
| `11-strip-release-notes-banner.patch` | Release notes nagging | Low |
| `12-strip-feedback.patch` | Feedback widgets / issue prompts | Low |
| `13-strip-command-center-leftovers.patch` | UI leftovers after `window.commandCenter=false` default | Low |

Avoid first-pass deletion of:

```text
[ ] Outline
[ ] Timeline
[ ] Local History
[ ] Breadcrumb implementation (just default it off)
[ ] Minimap implementation (just default it off)
[ ] Entire workbench contrib directories
```

## 8.5 Lightweight strip batch

Goal: move from branded VS Code to a bare-bones, quick-start editor by removing startup registrations for high-churn or non-core workbench contributions while keeping the basic local editor loop intact.

| Patch | Target | Notes |
|---|---|---|
| `14-strip-ai-notebook-testing.patch` | Chat, MCP, inline chat/completions, notebooks, REPL/interactive, testing, remote coding agents | Removes the fastest-moving AI/notebook/test surfaces first. |
| `15-strip-accounts-sync-telemetry.patch` | Default account, authentication, Settings Sync, edit sessions, share, telemetry/experiment surfaces | Keeps the fork offline-first and avoids account prompts. |
| `16-strip-heavy-optional-workbench.patch` | Debug, search editor, process explorer, merge/multi-diff editors, comments, external terminal, timeline, local history | Removes nonessential panels/tools from the default workbench. |
| `17-wire-product-configuration-defaults.patch` | Native workbench environment | Lets `shuvscode.product.json` provide application-scoped defaults for desktop builds. |

Extension defaults now turn off natural-language settings search, chat AI features, Git auto-fetch, and other profile-scoped startup noise. Product-level `configurationDefaults` now turn off application-scoped update/extension auto-update/experiment/telemetry defaults.

## 8.6 Per-patch done criteria

```text
[ ] Patch applies from a clean tree.
[ ] Build passes.
[ ] Fresh profile launch passes.
[ ] Patch has one behavior.
[ ] Patch contains placeholders where branding-sensitive.
[ ] Commit message names exactly what was removed.
```

Commit one patch at a time:

```bash
git add patches/user/10-strip-something.patch
git commit -m "feat: strip <feature>"
```

---

# Phase 9 -- Release smoke tests

Run these before each GitHub release/AUR bump.

## 9.1 Local tarball smoke

```bash
rm -rf /tmp/shuvscode-smoke
mkdir -p /tmp/shuvscode-smoke

tar xzf shuvscode-linux-x64.tar.gz -C /tmp/shuvscode-smoke

/tmp/shuvscode-smoke/shuvscode/shuvscode --version

/tmp/shuvscode-smoke/shuvscode/shuvscode \
  --user-data-dir=/tmp/shuvscode-smoke-user \
  --extensions-dir=/tmp/shuvscode-smoke-exts
```

Note the extra `shuvscode/` directory in the path — the tarball now includes a top-level directory (see Phase 5 change).

## 9.2 Product sanity

```bash
jq '{
  nameShort,
  applicationName,
  dataFolderName,
  linuxIconName,
  urlProtocol,
  serverApplicationName,
  serverDataFolderName,
  extensionsGallery,
  builtInExtensions,
  extensionEnabledApiProposals
}' /tmp/shuvscode-smoke/shuvscode/resources/app/product.json
```

## 9.3 Network sanity

```bash
rg -i \
  'marketplace.visualstudio.com|gallerycdn.vsassets.io|vscode-sync.trafficmanager.net' \
  /tmp/shuvscode-smoke/shuvscode/resources/app \
  || true
```

Then launch, install one Open VSX extension, and watch traffic if you care:

```bash
sudo tcpdump -i any -n 'host marketplace.visualstudio.com'
```

Done when:

```text
[ ] Fresh profile starts clean.
[ ] Extension search uses Open VSX.
[ ] Baked extensions activate.
[ ] Bootstrap extensions install once.
[ ] No obvious Microsoft Marketplace traffic during extension search/install.
[ ] Icons and launcher work.
[ ] AUR package installs and uninstalls cleanly.
```

---

# Phase 10 -- Monthly upstream sync runbook

Goal: keep drift boring.

## 10.1 Sync

```bash
git checkout shuvscode-main
./scripts/sync-upstream.sh
```

## 10.2 Build

```bash
rm -rf vscode VSCode-linux-x64
./scripts/build-shuvscode.sh
```

## 10.3 If a user patch fails

```bash
rm -rf vscode VSCode-linux-x64
./scripts/prepare-shuvscode-tree.sh

cd vscode

git apply --reject ../patches/user/<failed>.patch || true

# Fix .rej files manually.
find . -name '*.rej' -print

git diff > ../patches/user/<failed>.patch

cd ..

rm -rf vscode VSCode-linux-x64
./scripts/build-shuvscode.sh
```

## 10.4 Sync completion checklist

```text
[ ] Build passes.
[ ] Fresh profile launch passes.
[ ] Product metadata still says ShuvScode.
[ ] Open VSX extension install works.
[ ] Baked extensions activate.
[ ] Bootstrap behavior still runs once.
[ ] Remote SSH works or is explicitly marked broken/experimental.
[ ] GitHub release tag pushed.
[ ] AUR pkgver/checksum updated.
```

## 10.5 Drift rules

```text
[ ] If a patch conflicts twice, shrink it.
[ ] If a patch touches five unrelated files, split it.
[ ] If an upstream sync takes over 4 hours for three cycles, consider hard fork.
[ ] If VSCodium itself is broken, wait; do not fork their broken patch stack blindly.
```

---

# Phase 11 -- Hard-fork off-ramp

Goal: know when to stop being downstream of downstream.

## 11.1 Hard-fork triggers

Consider hard fork when any of these are true:

```text
[ ] `patches/user` exceeds roughly 5k LOC.
[ ] Three upstream syncs in a row each take more than 4 hours.
[ ] You need new extension APIs.
[ ] You need new workbench services/views that extensions depend on.
[ ] You want to delete whole subsystems, not just hide/gate them.
[ ] You need your own extension registry/auth policy.
[ ] VSCodium stalls or stops tracking VS Code fast enough.
```

## 11.2 Off-ramp mechanics

```bash
# In the VSCodium-based repo
rm -rf vscode
./scripts/prepare-shuvscode-tree.sh

cd vscode
git init
git add -A
git commit -m "baseline: VSCodium plus ShuvScode patches"
```

Then:

```text
[ ] Move `./vscode` to new repo: `shuv1337/shuvscode-src`.
[ ] Add `microsoft/vscode` as upstream.
[ ] Preserve `shuvscode.env`, product overlay, CI, and packaging.
[ ] Convert `patches/user` into in-tree edits.
[ ] Use fenced comments for invasive source edits:
    // --- Start shuvscode ---
    // --- End shuvscode ---
[ ] Delete patch generation as the primary workflow.
```

---

# Final execution order

```text
[ ] Phase 0: Validate toolchain with stock VSCodium build.
[ ] Phase 1: Scaffold (branch, env, overlay, scripts, CI cleanup).
[ ] Phase 2: Product overlay rebrand.
[ ] Phase 3: Linux assets.
[ ] Phase 4: Defaults extension.
[ ] Phase 5: CI tarball.
[ ] Phase 6: AUR shuvscode-bin.
[ ] Phase 7: Extensions.
[ ] Phase 8: Surgical strip patches.
[ ] Phase 9: Release smoke tests.
[ ] Phase 10: Monthly upstream sync.
[ ] Phase 11: Hard fork only when patch drift earns it.
```

---

# Appendices

## Appendix A -- Environment variable cheat sheet

```bash
# Branding
APP_NAME="ShuvScode"
BINARY_NAME="shuvscode"
GH_REPO_PATH="shuv1337/shuvscode"
ASSETS_REPOSITORY="shuv1337/shuvscode"
ORG_NAME="ShuvScode"
TUNNEL_APP_NAME="shuvscode-tunnel"
GLOBAL_DIRNAME="shuvscode"

# Build
OS_NAME="linux"
VSCODE_ARCH="x64"
VSCODE_QUALITY="stable"
SHOULD_BUILD="yes"
SHOULD_BUILD_REH="no"
SHOULD_BUILD_REH_WEB="no"
CI_BUILD="no"
DISABLE_UPDATE="yes"
VSCODE_LATEST="no"
```

## Appendix B -- Patch placeholder cheat sheet

`utils.sh` substitutes these placeholders when applying patches:

```text
!!APP_NAME!!          -> ShuvScode
!!APP_NAME_LC!!       -> shuvscode
!!BINARY_NAME!!       -> shuvscode
!!GH_REPO_PATH!!      -> shuv1337/shuvscode
!!ASSETS_REPOSITORY!! -> shuv1337/shuvscode
!!ORG_NAME!!          -> ShuvScode
!!TUNNEL_APP_NAME!!   -> shuvscode-tunnel
!!GLOBAL_DIRNAME!!    -> shuvscode
!!RELEASE_VERSION!!   -> current release version
```

Note: `APP_NAME_LC` is derived from `APP_NAME` via `awk '{print tolower($0)}'` in `utils.sh`. It is not an independent env var.

## Appendix C -- `prepare_vscode.sh` product.json field coverage

Fields set by `prepare_vscode.sh` via `setpath` (stable branch):

```text
nameShort, nameLong, applicationName, linuxIconName, quality,
urlProtocol, serverApplicationName, serverDataFolderName,
tunnelApplicationName, tunnelApplicationConfig (set to {}),
darwinBundleIdentifier, win32AppUserModelId, win32DirName,
win32MutexName, win32NameVersion, win32RegValueName,
win32ShellNameShort, win32*AppId (6 variants),
win32TunnelServiceMutex, win32TunnelMutex,
win32ContextMenu.*.clsid, extensionsGallery,
linkProtectionTrustedDomains, licenseUrl, reportIssueUrl,
requestFeatureUrl, checksumFailMoreInfoUrl, documentationUrl,
introductoryVideosUrl, keyboardShortcutsUrl*, releaseNotesUrl,
tipsAndTricksUrl, twitterUrl
```

Fields NOT set by `prepare_vscode.sh` (stable):

```text
dataFolderName (only set for insider builds)
```

Your overlay MUST include `dataFolderName`. Without it, user data goes to `~/.vscode`.

## Appendix D -- Common gotchas

### Node version mismatches

`.nvmrc` is authoritative. Wrong Node can produce native-module/runtime weirdness that looks unrelated.

### Product overlay lost after upstream sync

The wrapper temporarily merges `shuvscode.product.json` into root `product.json` and restores the original file. If branding disappears, inspect the merged `vscode/product.json` first.

### User patch filenames sort wrong

Use numeric prefixes:

```text
10-foo.patch
20-bar.patch
30-baz.patch
```

### Proposed API mismatch

If a baked extension needs proposed APIs, mirror its `enabledApiProposals` into `product.json.extensionEnabledApiProposals`. Silent degradation is very real here.

### Remote SSH version mismatch

Open Remote SSH is only as reliable as the server artifact it downloads. Test it with your exact ShuvScode build/version before claiming it works.

### AUR desktop launcher weirdness

If launchers merge ShuvScode with VSCodium/Code, check `StartupWMClass`. Desktop environments are powered by vibes and old grudges.

### System Electron package later

`shuvscode-bin` bundles Electron. If you later build `shuvscode-electron`, pin a compatible `electronNN` and expect native-module ABI cleanup. That is a separate project.

### `*.env` in `.gitignore`

Upstream `.gitignore` has `*.env`. If you add new env files and wonder why they are untracked, this is why. Use `!filename.env` negation rules.

### `prepare-shuvscode-tree.sh` needs Node

This script runs `prepare_vscode.sh`, which calls `npm ci`. If Node is not set up (via nvm or otherwise), it will fail. Both wrapper scripts (`build-shuvscode.sh` and `prepare-shuvscode-tree.sh`) must include nvm initialization.

## Appendix E -- Phase success criteria

| Phase | Done when |
|---|---|
| 0 | Stock VSCodium builds and launches from the fork repo |
| 1 | Env, overlay, wrappers, and sync scripts committed; upstream CI removed |
| 2 | Rebranded `shuvscode` launches with isolated product metadata |
| 3 | Linux icons/AppStream/desktop keywords are yours |
| 4 | Defaults extension controls opinionated settings (no upstream overlap) |
| 5 | Tag push creates release tarball with top-level directory + SHA256 |
| 6 | `shuvscode-bin` installs locally with real checksums |
| 7 | Extension bake/bootstrap policy is implemented and tested |
| 8 | Strip patches are small, surgical, no overlap with upstream patches |
| 9 | Release smoke tests pass before each release |
| 10 | Upstream sync is repeatable and boring |
| 11 | Hard fork only when patch drift justifies it |

---

# Changes from v1

Summary of what changed from the original revised plan and why:

1. **All `<your-gh>` replaced with `shuv1337`** -- was a placeholder landmine across 14+ locations.
2. **Phase 0 simplified** -- fork already exists with remotes configured. No need to clone VSCodium separately.
3. **`.gitignore` fix** -- upstream `*.env` blocks `shuvscode.env`. Added `!shuvscode.env` negation. Removed redundant `shuvscode.env.local` entry.
4. **Extensions moved to `src/stable/extensions/`** -- repo-root `extensions/` directory is not copied into the build tree. `prepare_vscode.sh` runs `cp -rp src/stable/* vscode/`, so extensions must live there.
5. **`prepare-shuvscode-tree.sh` gets Node setup** -- was missing nvm initialization, would fail on `npm ci`.
6. **Defaults extension cleaned up** -- removed `telemetry.telemetryLevel`, `chat.disableAIFeatures`, and `github.copilot.enable` (all handled by upstream patches). Engine version set to `*` (built-in extension).
7. **`astral-sh/setup-uv` pinned to `@v8.1.0`** -- bare `@v8` tag may not resolve.
8. **Tarball includes top-level directory** -- `mv VSCode-linux-x64 shuvscode` before tar, so PKGBUILD can `cp -a "${srcdir}/${_pkgname}/."` without cleanup.
9. **PKGBUILD simplified** -- no more copy-everything-then-delete-extras pattern.
10. **Upstream CI workflows removed** -- 14 VSCodium workflow files that reference their secrets/repos.
11. **Linux branding section rewritten** -- documents `@@` template variable system, focuses on what actually needs manual replacement vs. what resolves automatically.
12. **Strip patches section** -- added table of what upstream already handles to prevent duplicate work.
13. **Bootstrap extension uses `Promise.allSettled`** -- parallel installs instead of sequential.
14. **`dataFolderName` documented as required** -- only set by prepare_vscode.sh for insider builds.
15. **Desktop file `StartupNotify=false`** -- matches upstream template (was `true` in v1).
16. **Appendix C added** -- documents exactly which product.json fields prepare_vscode.sh sets, preventing guesswork.

---

# Reference sources checked

- Forked repo at `shuv1337/shuvscode` (live inspection)
- VSCodium `utils.sh`, `prepare_vscode.sh`, `build.sh`, `get_repo.sh`, `version.sh` (live read from fork)
- VSCodium `.nvmrc`: confirmed `22.22.0`
- VSCodium `.gitignore`: confirmed `*.env` pattern
- VSCodium `upstream/stable.json`: confirmed tag `1.112.0`
- VSCodium `patches/disable-copilot.patch`: confirmed `chat.disableAIFeatures` default changed to `true`
- VSCodium `patches/disable-cloud.patch`: confirmed cloud sync sign-in removed
- VSCodium `src/stable/resources/linux/`: confirmed `@@` template variables in `.desktop` and `.appdata.xml`
- `actions/checkout@v6`: confirmed exists
- `actions/setup-node@v6`: confirmed exists
- `astral-sh/setup-uv`: v8.1.0 confirmed, bare `v8` tag may not resolve
- `jeanp413/open-remote-ssh` v0.49: confirmed `enabledApiProposals` = `resolvers`, `contribViewsRemote`
- `detachhead/basedpyright` on Open VSX: confirmed v1.39.3
