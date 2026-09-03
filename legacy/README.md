# Legacy / Superseded Code

These files were part of earlier versions of Luathys and are kept here for
reference only. They are **not** maintained, and most reference decompiler
APIs that are no longer operational. Do not load or run them.

The current, supported toolchain is:

| Purpose | File |
|---------|------|
| In-executor dump (raw bytecode) | [`luathys.lua`](../luathys.lua) |
| In-executor remote spy (passive) | [`luathys_spy.lua`](../luathys_spy.lua) |
| In-executor remote spy (hook-free) | [`luathys_spy_safe.lua`](../luathys_spy_safe.lua) |
| Offline bytecode → source | [`decompile_all.py`](../decompile_all.py) (Luacid API) |
| Desktop GUI (memory scanner) | [`src/core/main.py`](../src/core/main.py) |

## Why each file was archived

- **`dumper_engine.lua`** — "Universal Dumper v2.1". Superseded by
  `luathys.lua` (bytecode-mode). Its fallback chain targets dead public
  decompiler APIs, and its XOR string obfuscation used a key schedule
  (`key ~ (i*0x13)`) that was incompatible with `obfuscation.lua`.
- **`obfuscated_loader.lua`** — "Obfuscated Dumper Loader v2.0". Same dead
  endpoints, same superseded pipeline.
- **`byfrun_bypass.lua`** — "Byfron-Resistant Dumper v1.0". Older variant of
  the same approach; never actually Byfron-resistant (client-side string
  obfuscation does not evade behavioral anti-cheat).
- **`chain.lua`** — decompilation-chain module that only wrapped the dead
  public APIs referenced above. Also uses the Luau-only `continue` keyword,
  so it will not parse under stock Lua.
- **`obfuscation.lua`** — string-obfuscation library whose key schedule
  disagreed with the dumper that used it, and whose lookup/`GetService`
  integration was never wired up.
- **`main_gui.py`** — an earlier copy of the desktop GUI that imported the
  unfinished `timeline_log.py`; `src/core/main.py` is the single GUI.
- **`timeline_log.py`** — an unfinished (truncated mid-function) "dynamic
  timeline log" widget that was never integrated into the main GUI.
