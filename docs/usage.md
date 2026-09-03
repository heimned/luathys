# Luathys Usage Guide

## Loading the Dumper

The canonical in-executor dumper is [`luathys.lua`](../luathys.lua). It dumps
raw Luau bytecode (`.luac`) for every script the client can see, plus the
instance tree and remote catalog.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/luathys.lua"))()
```

Decompilation happens **offline** afterwards — see below.

> The old `dist/obfuscated_loader.lua` and `dist/byfrun_bypass.lua` loaders
> have been superseded and moved to [`legacy/`](../legacy/README.md). They
> reference decompiler APIs that are no longer operational and are not
> maintained.

## Decompiling the Dump

Run this on your PC against the dumped folder (it requires Python 3.10+):

```bash
python decompile_all.py <dump_folder>
python decompile_all.py <dump_folder> --key 67_your_luacid_key   # optional API key
```

- Every `.luac` in the folder (recursively) is sent to the
  [Luacid](https://luacid.dev) API and a sibling `.lua` is written.
- Self-rate-limits to the keyless tier (~1.1s between requests).
- **Resumable**: files whose `.lua` already exists and isn't a failure marker
  are skipped. Use `--fresh` to force re-decompilation.

## Output Structure

```
{GameName}_{PlaceId}/
├── _README.txt
├── ReplicatedStorage/
│   ├── _tree.txt        # instance hierarchy
│   ├── _remotes.txt     # RemoteEvents / RemoteFunctions
│   └── {ScriptName}_{ClassName}.luac      # raw bytecode
├── ServerScriptService/
├── Workspace/
├── StarterPlayer/
├── StarterGui/
├── StarterPack/
├── Lighting/
├── SoundService/
├── ReplicatedFirst/
├── Teams/
├── LocalPlayer_PlayerGui/
├── LoadedModules/
└── NilInstances/
```

After `decompile_all.py`, each `.luac` gains a `{ScriptName}_{ClassName}.lua`.

## Remote Spy

```lua
-- Passive, with outgoing capture (needs namecall hook support)
loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/luathys_spy.lua"))()

-- Hook-free variant (incoming only + manual probing via _G.luathys.fire)
loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/luathys_spy_safe.lua"))()
```

Logs are written to `HUKI/Spy/{Game}_{PlaceId}_spy.log`.

## Executor Requirements

The dumper degrades gracefully, but for best results the executor should
provide:

| Function | Used for |
|----------|----------|
| `getscriptbytecode` | extracting raw bytecode from each script |
| `writefile` / `makefolder` | writing output files |
| `getnilinstances` | capturing orphaned/destroyed scripts |
| `getloadedmodules` | dumping modules loaded at runtime |

If `getscriptbytecode` is unavailable, only scripts with a readable `Source`
property are captured.
