# Dumper Comparison: aboris vs Enhanced Universal Dumper

## Original aboris (xfwil/aboris)

| Feature | Status |
|---------|--------|
| Services covered | ReplicatedStorage only |
| Export format | `.lua`/`.luau` files |
| Loading method | `loadstring(game:HttpGet(...))` |
| Decompiler | Uses executor's `decompile` function |
| Anti-detection | Avoids `saveinstance` keyword |
| Bytecode fallback | None |
| String obfuscation | None |
| Cross-service coverage | No |
| Null instance handling | No |
| RemoteEvent collection | Yes (but only ReplicatedStorage) |

### Limitations Found in Your Dump:
1. **Only ReplicatedStorage was dumped** — Missing Workspace, ServerScriptService, StarterPlayer, etc.
2. **13 scripts failed to decompile** — "failed to read script bytecode" errors for server-side Scripts
3. **Only 1 UUID-obfuscated RemoteEvent found** — But there may be more in other services
4. **PlayerDataStorage/PlayerStats** present but only from client perspective
5. **No server-side logic** captured (ServerScriptService empty)

## Enhanced Universal Dumper (v2.1)

| Feature | Status |
|---------|--------|
| Services covered | **ALL** (9+ services including Workspace, ServerScriptService) |
| Export format | `.lua` files + `_tree.txt` + `_remotes.lua` + `_summary.txt` |
| Loading method | `loadstring(game:HttpGet(...))` or direct injection |
| Decompiler | **3 fallback methods**: native `decompile`, Source read, external API |
| Anti-detection | XOR string obfuscation, dynamic function resolution |
| Bytecode fallback | `getscriptbytecode` → `debug.getscriptbytecode` → `luau.disassemble` |
| String obfuscation | XOR with variable keys |
| Cross-service coverage | Full (9 services + null instances) |
| Null instance handling | Yes |
| RemoteEvent collection | **All services** |
| Timing jitter | Randomized delays between scripts/services |
| Chunked file writing | Yes (4KB chunks) |
| Environment resolution | Multi-executor support (syn, krnl, fluxus, shared, debug) |

### Key Improvements:

#### 1. Comprehensive Service Coverage
```
Original: ReplicatedStorage only (1 service)
Enhanced: 9 services + null instances
  - ReplicatedStorage ✓
  - ServerStorage ✓ (was missing)
  - Workspace ✓ (was missing)
  - StarterPlayer ✓ (was missing)
  - StarterGui ✓ (was missing)
  - StarterPack ✓ (was missing)
  - ServerScriptService ✓ (was missing)
  - Lighting ✓ (was missing)
  - SoundService ✓ (was missing)
  - Nil Instances ✓ (was missing)
```

#### 2. Fallback Decompilation Chain
When executor's `decompile` is hooked or blocked:
1. Try native `decompile` function
2. Read `.Source` property directly
3. Extract bytecode via `getscriptbytecode` → send to local HTTP API (lunaux-decompiler style)
4. Send to external APIs (unluau, etc.) via HTTP request

#### 3. Multi-Executor Function Resolution
Resolves executor functions from multiple possible locations:
- `_G.decompile`
- `shared.decompile`
- `debug.decompile`
- `syn.decompile`
- `krnl.decompile`
- `fluxus.decompile`

#### 4. Anti-Detection Features
- String XOR encryption with runtime decoding
- Dynamic function lookup (no hardcoded sensitive strings)
- Timing jitter (5-80ms random delays)
- Chunked file writes
- No `saveinstance` keyword usage

#### 5. Error Handling
- Each script decompilation wrapped in pcall
- Failed scripts get error message file instead of crashing
- Summary file with success/failure counts

## Files Created

1. **`universal_lua_dumper.lua`** — Full-featured dumper with comprehensive service coverage and fallback decompilation
2. **`obfuscated_dumper_loader.lua`** — Minimized version with XOR string obfuscation and indirect function calls
3. **`byfrun_bypass_dumper.lua`** — Advanced version specifically for Byfrun-protected executors with environment walking

## Usage

### Basic (same as aboris):
```lua
loadstring(game:HttpGet("https://your-server.com/dumper.lua"))()
```

### Advanced (with configuration):
```lua
_G.NO_AUTO_DUMP = true  -- Prevent auto-execution
loadstring(game:HttpGet("https://your-server.com/dumper.lua"))()
-- Then call manually:
-- dumper.dump_game()
```

### Loading from specific file:
```lua
loadstring(game:HttpGet("https://your-server.com/dumper/universal_lua_dumper.lua"))()
```

## Expected Results

With the enhanced dumper, you should get:
- **More scripts** (all from Workspace, ServerStorage, StarterPlayer, etc.)
- **Server-side code** (from ServerScriptService)
- **Better remote coverage** (remotes in all services, not just ReplicatedStorage)
- **Reduced failures** (external API fallback for blocked decompilers)
- **More RemoteEvents/RemoteFunctions** discovered