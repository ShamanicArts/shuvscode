# HANDOFF

## Objective
- Update shuvscode to VS Code `1.120.0` and ship `1.120.0.shuv2` with a differentiated but tasteful UI.

## Current status
- `./scripts/prepare-shuvscode-tree.sh` ✅ passes.
- `./scripts/build-shuvscode.sh` ✅ passes.
- Current built binary:
  ```
  ./shuvscode-linux-x64/bin/shuvscode --version
  1.120.03216
  bcb6f2c8e716fe211520cc48b5b8c597df0544fb
  x64
  ```
- CLI smoke ✅: `--list-extensions` exits 0.
- Final UI polish included:
  - top-left devil phone logo visible
  - activity/sidebar icons centered
  - profile icon is user-circle, settings icon is sliders, remote/status is plug
  - background devil watermark forced to whole-window center (`50vw/50vh`)
  - primary buttons changed from purple to teal/sea-blue
  - notifications default to bottom-left
  - remote/forwarded-ports/problems moved to the right side of the status bar
  - Outline pane stripped entirely
  - Night Owl bundled directly; no `sdras.night-owl` trust prompt
- Release tarball regenerated:
  - `dist/shuvscode-1.120.0-linux-x64.tar.gz`
  - sha256: `b97984febcd7956688e7e68ef8bed1869c28ef5c719010425e21630731170cb6`
- AUR PKGBUILD updated and locally validated for `1.120.0.shuv2`.

## Save points
- `before-ui-redesign` — before reverting the bad Ember UI pass.
- `vscode-1.120-shuv2-ui-final` — earlier shuv2 UI/build state.
- `vscode-1.120-shuv2-polished-final` — current final polished state.

## Key UI decisions
- Reverted commit `7126140 feat: add shuvscode Ember UI identity` because it looked like a generic red VS Code fork.
- Preserved the earlier good direction: dark teal/sky background, devil phone watermark, minimal red brand accent.
- Added built-in Phosphor product icons to move away from stock VS Code codicons.
- Bundled Night Owl theme directly to preserve familiar palette without first-run extension trust prompt.
- Added restrained chrome CSS:
  - cut-corner teal primary buttons
  - cut-corner tabs/dialogs/quick input
  - centered devil-phone watermark
  - centered Phosphor activity bar icons
- Removed stock Outline pane from the Explorer.
- Rebalanced status bar: notifications left, remote/diagnostics right.

## Notable UI files
- `patches/user/20-inject-shuvscode-chrome.patch` — injects CSS into workbench and includes it in package resources.
- `patches/user/21-statusbar-shuv-layout.patch` — moves Problems/remote status entries to right side of status bar.
- `patches/user/22-strip-outline-pane.patch` — removes Outline contributions.
- `src/stable/src/vs/code/electron-browser/workbench/shuvscode.css` — chrome overlay.
- `src/stable/extensions/shuvscode-phosphor-product-icons/` — built-in Phosphor product icon theme + font.
- `src/stable/extensions/shuvscode-night-owl/` — bundled Night Owl theme files + license.
- `src/stable/extensions/shuvscode-defaults/package.json` — defaults include:
  - `workbench.colorTheme = Night Owl`
  - `workbench.productIconTheme = shuvscode-phosphor`
  - `workbench.iconTheme = seti`
  - `workbench.notifications.position = bottom-left`
- `src/stable/extensions/shuvscode-bootstrap/extension.js` — bootstrap install list is empty.

## 1.120 build/rebase changes in this tree
- `upstream/stable.json` pinned to `1.120.0` commit `0958016b2af9f09bb4257e0df4a95e2f90590f9f`.
- Rebased key patches for 1.120:
  - `fix-policies`
  - `use-github-pat`
  - `cli` (`agent_host.rs` new `.unwrap()` callsite)
  - `linux/feat-logs-home`
  - `linux/fix-npm-postinstall`
  - user strip patches `10/11/14/15/16`
- Added:
  - `patches/fix-non-ascii-regex.patch`
  - `patches/skip-copilot-ripgrep-shim.patch`
- Removed/disabled:
  - `patches/update-electron.patch` deleted (upstream already Electron 39.8.8)
  - `patches/version-1-update.patch` moved to `.yet` because `DISABLE_UPDATE=yes`
- Tooling:
  - `.nvmrc` and `mise.toml` pin Node `22.22.3`
  - prepare/build scripts hardened for mise PATH ordering
  - `prepare_vscode.sh` uses `npm install` instead of `npm ci`

## Packaging
- `packaging/aur/shuvscode-bin/PKGBUILD`:
  - `pkgver=1.120.0.shuv2`
  - first sha256 is `b97984febcd7956688e7e68ef8bed1869c28ef5c719010425e21630731170cb6`
- Local validation:
  - `makepkg --nodeps -f` was run in `/tmp/aur-shuv2-polish` with source URL redirected to the local tarball.
  - Result: package builds successfully.

## Validation commands run
```bash
./scripts/prepare-shuvscode-tree.sh
./scripts/build-shuvscode.sh
./shuvscode-linux-x64/bin/shuvscode --version
./shuvscode-linux-x64/bin/shuvscode --user-data-dir /tmp/... --extensions-dir /tmp/... --list-extensions
makepkg --nodeps -f  # in temp AUR copy with local file:// tarball source
```

## Important caveats
- `dist/` is gitignored; the release tarball exists locally but must be uploaded to GitHub Releases.
- AUR source URL will 404 until GitHub release `v1.120.0.shuv2` has `shuvscode-1.120.0-linux-x64.tar.gz` attached.
- `prepare_vscode.sh` using `npm install` can drift lockfile state; eventually regenerate lockfile or restore `npm ci` when lockfile covers `@vscodium/*` packages.
- `version-1-update.patch.yet` remains disabled; do not re-enable updates without rebasing it.

## Next steps
1. Commit current changes in logical commits.
2. Create git tag `v1.120.0.shuv2`.
3. Publish GitHub release with `dist/shuvscode-1.120.0-linux-x64.tar.gz`.
4. Push updated AUR package.

## Resume prompt
Finalize and commit the `1.120.0.shuv2` update. Build is green, visual polish is accepted, AUR PKGBUILD is updated and locally validated. Next: commit, tag `v1.120.0.shuv2`, upload `dist/shuvscode-1.120.0-linux-x64.tar.gz` to the GitHub release, then publish the AUR update.
