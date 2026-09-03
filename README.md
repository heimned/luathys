# Luathys

Roblox Luau bytecode dump & analysis toolkit.

> Dump Luau bytecode from Roblox games, then decompile it offline. For
> research and educational purposes.

---

## 🚀 Quick Start

### Desktop Application (Windows)

Download the latest pre-built binary from
[Releases](https://github.com/heimned/luathys/releases/latest):

```
https://github.com/heimned/luathys/releases/latest/download/LuathysExtractor_v1.1.1.zip
```

1. Extract the zip file
2. Run `LuathysExtractor.exe`
3. Launch Roblox and join your game
4. Click "Check Process", then "Scan Now"
5. Click "Export Results" to save extracted bytecode

### Lua Loader (In-Executor) — two steps

**Step 1 — dump raw bytecode.** Run this in your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/luathys.lua"))()
```

It walks the game's services and writes every script's **raw Luau bytecode**
(`*.luac`), plus the instance tree and remote catalog, to a `{Game}_{PlaceId}`
folder under your executor's workspace.

**Step 2 — decompile offline.** On your PC, run:

```bash
python decompile_all.py <dump_folder>
```

This sends each `.luac` to the [Luacid](https://luacid.dev) API and writes a
readable `.lua` next to it. It self-rate-limits and resumes (files already
decompiled are skipped).

```bash
# Optional: use a Luacid API key for higher limits
python decompile_all.py <dump_folder> --key YOUR_KEY
```

### Remote Spy

Two passive remote-traffic loggers are also included:

```lua
-- Hooks outgoing FireServer/InvokeServer (needs a namecall-hooking executor)
loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/luathys_spy.lua"))()

-- Hook-free: incoming traffic + manual probing only (works on more executors)
loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/luathys_spy_safe.lua"))()
```

---

## 📋 What It Does

- **Broad service coverage** — ReplicatedStorage, ServerStorage, Workspace,
  StarterPlayer, StarterGui, StarterPack, ServerScriptService, Lighting,
  SoundService, ReplicatedFirst, Teams, plus the local player's PlayerGui /
  Backpack / Character / PlayerScripts, loaded modules, and nil (orphaned)
  instances.
- **Durable bytecode output** — raw Luau bytecode (`.luac`) is always saved
  when the executor exposes `getscriptbytecode`; readable `Source` is saved
  opportunistically when present.
- **Offline decompilation** — `decompile_all.py` turns `.luac` into `.lua` via
  the Luacid API, which handles current Roblox bytecode versions and recovers
  names + type annotations.
- **Instance tree + remote catalog** — `_tree.txt` and `_remotes.txt` are
  written per container.
- **Failure records** — scripts with no bytecode and no source are recorded
  with a reason (`_FAILED.lua`) instead of silently vanishing.
- **Remote spy** — `luathys_spy.lua` and `luathys_spy_safe.lua` log incoming
  (and, where supported, outgoing) remote traffic to a `.log` file.

> Note: this dumps **bytecode**, not decompiled source. Decompilation happens
> offline in `decompile_all.py`. It does not "bypass anti-cheat" — on the
> client you can only see what the client can see (server scripts are not
> reachable this way).

---

## 📦 Downloads

| Platform | Type | Link |
|----------|------|------|
| Windows | Desktop App | [Latest release](https://github.com/heimned/luathys/releases/latest) |
| Any | Lua Loader | `loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/luathys.lua"))()` |

---

## 📁 Output Structure

```
{GameName}_{PlaceId}/
├── _README.txt              # next-step instructions
├── ReplicatedStorage/
│   ├── _tree.txt            # instance hierarchy
│   ├── _remotes.txt         # remote catalog
│   ├── {ScriptName}_{ClassName}.luac      # raw bytecode
│   └── {ScriptName}_{ClassName}_src.lua   # readable Source (when available)
├── ServerScriptService/
├── Workspace/
├── ... (other services)
├── LocalPlayer_PlayerGui/
├── LoadedModules/
└── NilInstances/
```

After `decompile_all.py`, each `.luac` gains a sibling `{ScriptName}_{ClassName}.lua`.

---

## 🛠️ Development

```bash
git clone https://github.com/heimned/luathys.git
cd luathys
pip install -r requirements.txt
python build_installer.py   # builds LuathysExtractor.exe into dist/
```

Layout:

```
luathys.lua            # in-executor bytecode dumper (canonical loader)
luathys_spy.lua        # passive remote spy (with namecall hook)
luathys_spy_safe.lua   # passive remote spy (hook-free)
decompile_all.py       # offline Luacid decompiler (resumable, rate-limited)
build_installer.py     # PyInstaller build for the desktop GUI
src/core/main.py       # desktop GUI (PyQt6 + pymem memory scanner)
legacy/                # superseded dumper/obfuscation variants (do not use)
tests/                 # standalone Lua checks
```

---

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.

Provided for educational and research purposes only. Use responsibly and in
accordance with Roblox's Terms of Service.
