# VersaUI

## About the project

VersaUI is a World of Warcraft addon that modifies the default game UI with minor features.

## References

- Use the original Blizzard interface code as a reference: `D:\Dev External\BlizzardInterfaceCode`.
- Use the AuctiMogger addon (`D:\Dev\WoW Goop\AuctiMogger`) as the reference for project structure, architecture, and misc tooling (CI, formatting, type-safety, etc.).

## Coding rules

- Everything must be type-safe. No missing types, no vague `table` types, etc. Use very strict typing with a structs/classes approach.

## Tooling & CI

The toolchain mirrors AuctiMogger's, with pinned versions (StyLua 2.6.0, luacheck 1.2.0, busted 2.2.0, lua-language-server 3.19.1). `.github/workflows/ci.yml` is the gate: format → lint → tests → TOC coverage → strict type check → package.

- Format with `tools/stylua/stylua.exe <files you edited>` — formatting is canonical, never hand-format. Spaces/4, double quotes, 120 cols, Unix endings.
- Run the full local gate before every commit: `bash scripts/ci_local.sh`. stylua + LuaLS run as vendored Windows binaries (under `tools/`, gitignored); luacheck/busted/TOC run in WSL with offline rocks from `tools/wsl-rocks/`.
- Quick test shim: `lua scripts/run_tests.lua spec/*_spec.lua` (supports `assert.equals`, `assert.is_true`, `assert.is_false` and raw `assert` only — specs must also pass real busted in CI).
- Type gate: LuaLS `--checklevel=Warning` must report zero problems; `scripts/assert_lls_clean.lua` parses the report and fails safe. Use the exact CI invocation (`> ./lls.log 2>&1`, never `--out=` — it writes an unparseable summary).
- Module pattern: modules register into the `VersaUI` global namespace and return their table, so specs can `require("VersaUI.x")` from the repo root.
- Any new game global/API usage must be added to the `.luacheckrc` and `.luarc.json` allowlists.
- `## Interface:` in `VersaUI/VersaUI.toc` must match the target client build.

## Taint safety suggestions

Addon code is tainted, and taint spreads along the execution path: when tainted code reaches a secure operation, the game blocks it — often silently and long after the offending call (`AddOn 'X' tried to call the protected function 'Y()'`). Always prefer the least intrusive approach: official APIs and events first, read-only access, post-hooks over replacement.

- Avoid using protected and secure functions that will taint the UI.
- Never overwrite or replace Blizzard global functions and variables. Extend behavior with post-hooks via `hooksecurefunc` instead.
- Do not call protected functions (e.g. `UseAction`, `TargetUnit`, `FocusUnit`, `SpellStopCasting`, `PickupInventoryItem`) from addon code.
- Do not show, hide, move, or reparent protected frames (e.g. `PlayerFrame`, `TargetFrame`, action buttons) while the player is in combat.
- Implement click-driven casting and item usage with `SecureActionButtonTemplate` and attributes (e.g. `SetAttribute("type", "spell")`) instead of calling protected functions from script handlers. Many protected functions (`UseAction`, targeting, movement, camera) additionally require real hardware events (mouse click, key press) — the secure button template exists to satisfy this.
- Guard any operation that touches protected frames or settings with `InCombatLockdown()`, and defer protected work until the `PLAYER_REGEN_ENABLED` event.
- Regular frame methods on addon-owned frames (`SetPoint`, `SetScale`, `SetAlpha`, `RegisterEvent`, etc.) are safe; the hazards concern Blizzard globals, protected frames, and Blizzard-shared state.
- Do not mutate Blizzard tables in place; prefer composition or post-hooks.
- Diagnose taint with `issecurevariable()` and enable taint logging with `console taintLog 1` (writes to `taintLog.txt`).

## Edit Mode integration rules

VersaUI's primary integration target is the default HUD Edit Mode (`Blizzard_EditMode`). These rules are verified against the official interface source.

Preferred, taint-free integration surfaces:

- React to Edit Mode enter/exit with `EventRegistry:RegisterCallback("EditMode.Enter", func, owner)` and `"EditMode.Exit"` — this is how the manager announces the transitions.
- React to layout changes with the `EDIT_MODE_LAYOUTS_UPDATED` event (payload: `layoutInfo`, `reconcileLayouts`).
- Read layout/anchor/setting values via `C_EditMode.GetLayouts()` and `C_EditMode.GetAccountSettings()`, or via `EditModeManagerFrame:GetSettingValue(system, systemIndex, setting)` / `IsEditModeActive()` once the manager is loaded.
- Observe behavior with post-hooks only: `hooksecurefunc(EditModeManagerFrame, "MethodName", fn)`.

Limitations and hazards:

- `C_EditMode` write APIs (`SaveLayouts`, `SetActiveLayout`, `SetAccountSetting`, `OnLayoutAdded`, `OnLayoutDeleted`, `ConvertLayoutInfoToString`, `ConvertStringToLayoutInfo`) are annotated `SecretArguments = "AllowedWhenUntainted"` — their arguments are restricted when called from tainted addon code. Treat layout writing as Blizzard-only; never build or save layout tables from VersaUI.
- `EditModeSystemMixin:OnSystemLoad` replaces `SetScale`, `SetPoint`, `ClearAllPoints`, `SetShown` (action bars also `Show`, `Hide`, `IsShown`) on system frames. Never replace these methods on any frame; post-hook only.
- Never fade, hide, or flash Edit Mode system frames through shared helpers (`UIFrameFade*`, flash utilities): the shared `FADEFRAMES`/`FLASHFRAMES` tables spread taint to every Blizzard frame using them.
- Do not write into Blizzard-shared containers (frame pools, `EventRegistry` keys, chat filter tables, CVar caches). Blizzard isolates these with `SecureMap`/`SecureArray`/`CreateSecureDelegate` (`Blizzard_SharedXMLBase/SecureTypes.lua`) precisely because tainted writes break secure code paths.
- Making a custom frame an Edit Mode system (mixin `EditModeSystemMixin` + `system`/`systemIndex` key values + `OnSystemLoad`) is mechanically possible, but layout persistence for third-party systems is unverified — validate in-game before depending on it.

Diagnostics: `issecure()`, `issecurevariable([tbl,] name)`, `InCombatLockdown()`, `forceinsecure()`, `issecretvalue(value)`.

Source references for deeper dives: `Blizzard_EditMode/Shared/EditModeManager.lua`, `Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`, `Blizzard_APIDocumentationGenerated/EditModeManagerDocumentation.lua`.
