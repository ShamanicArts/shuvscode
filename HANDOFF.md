# HANDOFF

## Objective
Ship a branded, packageable `shuvscode` editor (fork of VSCodium/VS Code) for Linux x64, following the phased plan in `shuvscode-revised-plan.md`.

## Current status

### Done
- **Phase 1 (Scaffold):** Branch renamed `master` → `shuvscode-main`, remote `master` deleted. `.gitignore` fixed for `shuvscode.env`. Upstream CI workflows (14 files) removed. `shuvscode.env`, `shuvscode.product.json`, and three scripts (`build-shuvscode.sh`, `prepare-shuvscode-tree.sh`, `sync-upstream.sh`) committed.
- **Phase 2 (Rebrand):** Build produces `shuvscode` binary with correct product metadata. Tagged `v0.0.1-rebrand`.
- **Phase 3 (Linux assets):** Appdata, desktop keywords updated. All icon assets generated from `assets/branding/shuvscode-devil-phone-source.png` via `scripts/generate-shuvscode-assets.sh`. Letterpress watermark fixed to 512px resolution.
- **Phase 4 (Defaults extension):** `src/stable/extensions/shuvscode-defaults/` committed. Verified: no welcome tab, settings contributed by extension.
- **Phase 5 (CI workflow):** `.github/workflows/build-release.yml` committed. Tested with `v1.112.02750.shuv1` and `v1.112.02758.shuv1`. Build output rebranded from `VSCode-linux-x64` to `shuvscode-linux-x64`.
- **Phase 6 (AUR package):** `packaging/aur/shuvscode-bin/` is updated to `v1.112.02780.shuv1` with real checksums. `makepkg --verifysource`, `makepkg -Ccf`, and `sudo pacman -U` verified locally. Installed command is `/usr/bin/shuvscode`.
- **Phase 7 (Extensions):** Bootstrap extension committed. Baked `detachhead.basedpyright` v1.39.3 and `EditorConfig.EditorConfig` v0.18.2 with SHA256 + deterministic UUIDs. `Continue.continue` was removed from bootstrap/defaults; `sdras.night-owl` is bootstrap-installed and `workbench.colorTheme` defaults to `Night Owl`.
- **Phase 8 (Strip patches):** User patches strip welcome/surveys (10), release notes/update UI (11), command center force-off (13), AI/notebook/testing startup contributions (14), account/sync/telemetry surfaces (15), heavy optional workbench tools (16), and product-level native configuration defaults (17). Clean local build passed for patches 10/11/13/14/15/16/17. Installed product metadata shows product-level defaults for extension auto-update, release notes, experiments, and telemetry.

### Not done
- Investigate bootstrap extension activation in isolated smoke profiles; manual CLI extension install works, but automatic bootstrap did not install Night Owl/vscode-icons during the first smoke launch
- Broader GUI smoke pass: quick start, basic file editing, search, git/scm, terminal, extension install, Night Owl default, product-level defaults cached
- Phase 9-11: release smoke tests, upstream sync validation, hard-fork criteria

## Key context
- **Branding is lowercase:** User wants `shuvscode` not `ShuvScode`. All files already updated.
- **Build output rebranded:** `build-shuvscode.sh` renames `VSCode-linux-x64` → `shuvscode-linux-x64` after build. `shuvscode-linux-x64/` is local generated output and is ignored, not committed.
- **Build scripts support mise:** nvm is not installed; scripts check for `mise` first, then nvm.
- **Idempotent builds:** `disable-update.patch.yet` gets renamed during build; cleanup trap restores it. Absolute paths used in cleanup to survive cwd changes from dot-sourced upstream scripts.
- **`dataFolderName: ".shuvscode"`** is required in overlay — `prepare_vscode.sh` only sets it for insider builds.
- **`*.env` in `.gitignore`** blocks env files; `!shuvscode.env` negation and explicit `shuvscode.env.local` ignore added.
- **`git-lfs`** must be installed — VS Code repo requires it.
- **Strip patch gotcha:** patches editing the same file in adjacent lines must be combined into one patch, otherwise context lines conflict when applied sequentially.
- **Lightweight strategy:** Prefer removing `workbench.common.main.ts` contribution imports first. This avoids deleting whole directories while still preventing startup registration of non-core surfaces.
- **Application-scoped defaults:** Extension `configurationDefaults` cannot override application-scoped settings such as `extensions.autoUpdate`, `update.showReleaseNotes`, `workbench.enableExperiments`, or `telemetry.telemetryLevel`. Patch 17 wires `shuvscode.product.json.configurationDefaults` into the native workbench environment so those can default off at product level.

## Important files
- `shuvscode-revised-plan.md` — full execution plan
- `shuvscode.env` — branding + build env vars
- `shuvscode.product.json` — product overlay merged into `product.json` at build time
- `scripts/build-shuvscode.sh` — main build wrapper
- `scripts/generate-shuvscode-assets.sh` — regenerates all icons from source PNG
- `assets/branding/shuvscode-devil-phone-source.png` — 1254x1254 source logo
- `patches/user/` — shuvscode-specific strip patches

## Next steps
1. Investigate bootstrap extension activation in isolated smoke profiles; manual CLI extension install works, but automatic bootstrap did not install Night Owl/vscode-icons during the first smoke launch
2. GUI smoke pass: quick start, basic file editing, search, git/scm, terminal, extension install, Night Owl default, product-level defaults cached
3. Phase 9 release smoke tests
4. Keep `shuvscode-revised-plan.md` updated as the execution plan evolves

## Risks / open questions
- AUR `shuvscode-bin` is installed locally at `v1.112.02780.shuv1-1`; publish the AUR metadata/package source downstream if using a separate AUR remote.
- Do not use `shuvcode` for this project; that command belongs to the separate opencode fork. The shuvscode package should expose `/usr/bin/shuvscode`.
- Remote SSH (open-remote-ssh) is gated and untested
- Lightweight patches intentionally remove debug, timeline, local history, notebooks, testing, auth/sync, AI/chat/MCP, and telemetry UI contributions. Re-add as defaults/optional extensions if users miss them.
- Smoke note: product-level defaults cache correctly in a fresh isolated profile. Bootstrap extension did not auto-install Night Owl/vscode-icons during the smoke launch, although `--install-extension sdras.night-owl` works against the same Open VSX setup.
- Built output is large (`shuvscode-linux-x64/`, ~800MB with a >100MB binary); keep it ignored and publish release artifacts instead of committing it
