# Luathys Usage Guide

## Loading the Dumper

### Standard Deployment (Enhanced Dumper)

```lua
loadstring(game:HttpGet("https://gitlab.com/entayga/luathys/-/raw/main/dist/enhanced_dumper.lua"))()
```

### Obfuscated Loader

```lua
loadstring(game:HttpGet("https://gitlab.com/entayga/luathys/-/raw/main/dist/obfuscated_loader.lua"))()
```

### Byfrun-Resistant Variant

```lua
loadstring(game:HttpGet("https://gitlab.com/entayga/luathys/-/raw/main/dist/byfrun_bypass.lua"))()
```

## Output Structure

```
HUKI/
├── {GameName}_{PlaceId}/
│   ├── _summary.txt
│   ├── ReplicatedStorage/
│   ├── ServerStorage/
│   ├── Workspace/
│   ├── StarterPlayer/
│   ├── ServerScriptService/
│   ├── Lighting/
│   ├── SoundService/
│   ├── _null/
│   └── {Service}/
│       ├── _tree.txt
│       ├── _remotes.lua
│       └── {ScriptName}_{ClassName}.lua
```

## Configuration

```lua
_G.STOP_DUMP = true  -- Prevent auto-execution
loadstring(game:HttpGet("..."))()
-- Then call manually: Luathys.dump()
```

## Executor Compatibility

| Executor | Status | Notes |
|----------|--------|-------|
| Synapse X (Z64) | Tested | Full support |
| KRNL | Supported | Use Byfrun bypass variant |
| Fluxus | Supported | Multi-executor resolution |
| JJSploit | Supported | Limited by executor capabilities |
__zcode_status=$?
if [ "$__zcode_status" -eq 0 ]; then pwd -P > '/c/Users/wokes/AppData/Local/Temp/zcode-6f8eafc7-1e48-4e72-8d3c-87f6a7644572-cwd'; fi
exit "$__zcode_status"
