# Luathys

Professional-grade Roblox Luau bytecode analysis and decompilation toolkit.

## Overview

Luathys is a comprehensive toolkit for extracting, decompiling, and analyzing Luau bytecode from Roblox games. It features advanced anti-detection mechanisms, multi-executor compatibility, and extensive service coverage.

## Features

- **Full Game Service Coverage** — Dumps from 9+ services including ServerScriptService, Workspace, StarterPlayer, and more
- **Multi-Method Decompilation** — Native decompile, Source extraction, and external API fallback chain
- **Anti-Detection Architecture** — XOR string obfuscation, timing jitter, chunked I/O, dynamic function resolution
- **Multi-Executor Support** — Resolves functions from Synapse, KRNL, Fluxus, and generic executor environments
- **Bytecode Recovery** — Extracts bytecode from null/orphaned instances and handles locked scripts
- **Automated Remote Discovery** — Catalogs all RemoteEvents, RemoteFunctions, and Bindable instances across all services

## Project Structure

```
luathys/
├── src/
│   ├── core/          # Core dumper engine
│   ├── decompiler/    # Decompilation logic and fallbacks
│   ├── security/      # Anti-detection and obfuscation
│   └── utils/         # Utility functions
├── dist/
│   ├── enhanced_dumper.lua       # Full-featured single-file loader
│   ├── obfuscated_loader.lua     # Minimized, string-obfuscated version
│   └── byfrun_bypass.lua        # Byfrun-resistant variant
├── docs/
│   ├── comparison.md     # Feature comparison vs other dumpers
│   └── usage.md          # Detailed usage guide
└── tests/
    └── test_dumper.lua   # Test suite
```

## Quick Start

Load in your Roblox executor:

```lua
loadstring(game:HttpGet("https://gitlab.com/entayga/luathys/-/raw/main/dist/enhanced_dumper.lua"))()
```

## Documentation

See the [docs directory](docs/) for detailed documentation.

## License

Educational use only. See LICENSE file for details.
