# Luathys

Professional-grade Roblox Luau bytecode analysis toolkit.

> Extract, decompile, and analyze Luau bytecode from Roblox games for research and educational purposes.

---

## 🚀 Quick Start

### Desktop Application

Download the pre-built binary:
```
https://github.com/heimned/luathys/releases/download/v1.0.0/LuathysExtractor.zip
```

1. Extract the zip file
2. Run `LuathysExtractor.exe`
3. Launch Roblox and join your game
4. Click "Check Process" then "Scan Now"
5. Click "Export Results" to save decompiled scripts

### Lua Loader (In-Executor)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/dist/enhanced_dumper.lua"))()
```

---

## 📋 Features

- **9+ Service Coverage**: ReplicatedStorage, ServerStorage, Workspace, StarterPlayer, StarterGui, StarterPack, ServerScriptService, Lighting, SoundService
- **Multi-Method Decompilation**: 
  - Native `decompile()` function
  - Direct `Source` property read
  - Bytecode extraction → unluau API fallback
- **Anti-Detection**: XOR string obfuscation, timing jitter, chunked I/O
- **External Memory Scanning**: Desktop app bypasses in-game anti-cheat
- **Remote Discovery**: Catalogs RemoteEvents, RemoteFunctions, BindableEvents
- **Null Instance Handling**: Captures orphaned/destroyed scripts

---

## 📦 Downloads

| Platform | Type | Link |
|----------|------|------|
| Windows | Desktop App | [LuathysExtractor.zip](https://github.com/heimned/luathys/releases/download/v1.0.0/LuathysExtractor.zip) |
| Any | Lua Loader | `loadstring(game:HttpGet("https://raw.githubusercontent.com/heimned/luathys/master/dist/enhanced_dumper.lua"))()` |

---

## 📁 Output Structure

```
HUKI/
├── {GameName}_{PlaceId}/
│   ├── _summary.txt          # Dump statistics
│   ├── _tree.txt             # Instance hierarchy
│   ├── _remotes.lua          # Remote catalog
│   ├── {Service}/            # Per-service dump
│   │   ├── _tree.txt
│   │   ├── _remotes.lua
│   │   └── {ScriptName}_{Class}.lua
│   └── _null/                # Null/orphaned instances
```

---

## 🛠️ Development

Build from source:
```bash
git clone https://github.com/heimned/luathys.git
cd luathys
pip install -r requirements.txt
python build_installer.py
```

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

Provided for educational and research purposes only. Use responsibly and in accordance with Roblox's Terms of Service.
