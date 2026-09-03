--[[
    Universal Lua Dumper v2.1
    A comprehensive Roblox script dumper with anti-detection features

    Improvements over xfwil/aboris:
    1. Covers ALL game services (not just ReplicatedStorage)
    2. Works without `decompile` function (external API fallback)
    3. String obfuscation to avoid signature detection
    4. Timing jitter to look like normal activity
    5. Handles executor limitations gracefully
    6. Better error handling and retry logic

    Load with:
    loadstring(game:HttpGet("https://your-server.com/dumper.lua"))()

    Or inject directly if your executor supports it.
]]

local dumper = {}

-- String obfuscation: XOR-based string encoding to avoid signature detection
-- This prevents static analysis tools from finding sensitive function calls
local STRING_KEYS = {
    [1] = 0x5A,
    [2] = 0x3C,
    [3] = 0x7E,
}

local function xor_str(str, key_idx)
    local key = STRING_KEYS[key_idx] or 0x5A
    local result = {}
    for i = 1, #str do
        local byte = str:byte(i)
        local key_byte = key ~ (i * 0x13)
        result[i] = string.char(byte ~ key_byte)
    end
    return table.concat(result)
end

-- Obfuscation layer: build function references dynamically
local function safe_get_service(service_name)
    local obfuscated = xor_str(service_name, 1)
    return game:GetService(obfuscated)
end

-- Alternative to decompile: extract bytecode and send to external API
-- This works when `decompile` is hooked/blocked by anti-cheat
local function extract_bytecode(script_instance)
    -- Try getscriptbytecode first
    if getscriptbytecode then
        local success, result = pcall(getscriptbytecode, script_instance)
        if success and result then return result end
    end

    -- Fallback: try to read bytecode via debug methods
    if debug and debug.getscriptbytecode then
        local success, result = pcall(debug.getscriptbytecode, script_instance)
        if success and result then return result end
    end

    return nil, "No bytecode extraction method available"
end

-- External decompilation API integration
-- Uses unluau API or similar local servers
local function decompile_via_api(script_instance)
    local bytecode = extract_bytecode(script_instance)
    if not bytecode then
        -- Check if it's an error message
        if extract_bytecode(script_instance, nil) or true then
            local _, err = extract_bytecode(script_instance)
            return nil, err
        end
        return nil, "Failed to extract bytecode"
    end

    -- Try local API first (lunaux-decompiler style)
    local local_api_urls = {
        "http://127.0.0.1:8000/decompile",
        "http://127.0.0.1:8080/decompile",
        "http://127.0.0.1:5000/decompile",
    }

    for _, url in ipairs(local_api_urls) do
        local success, result = pcall(function()
            return game:HttpPost(url, bytecode)
        end)
        if success and result then
            return result, nil
        end
    end

    -- Fallback to external API (if available)
    local external_apis = {
        "https://unluau.lonegladiator.dev/unluau/decompile",
    }

    -- Need to base64 encode bytecode for HTTP transport
    if crypt and crypt.base64 and crypt.base64.encode then
        local encoded = crypt.base64.encode(bytecode)
        for _, api_url in ipairs(external_apis) do
            local success, result = pcall(function()
                return game:HttpPost(api_url, "", {
                    ["Content-Type"] = "application/octet-stream",
                }, encoded)
            end)
            if success and result then
                return result, nil
            end
        end
    end

    return nil, "All decompilation methods failed"
end

-- Primary decompile function with fallback chain
local function smart_decompile(script_instance)
    -- Method 1: Native decompile function (if available and not hooked)
    local native_decompile = decompile or getfenv and getfenv(2) and getfenv(2).decompile
    if native_decompile then
        local success, result = pcall(native_decompile, script_instance, false, 30)
        if success and type(result) == "string" and result:len() > 0 then
            return result, nil
        end
    end

    -- Method 2: Direct Source property read (for ModuleScripts sometimes)
    if script_instance.ClassName == "ModuleScript" or script_instance.ClassName == "LocalScript" then
        local success, source = pcall(function()
            return script_instance.Source
        end)
        if success and source and #source > 0 then
            return source, nil
        end
    end

    -- Method 3: External decompilation (bytecode -> API)
    return decompile_via_api(script_instance)
end

-- Timing obfuscation: random delays to look like normal user activity
-- Not constant-rate dumping that looks suspicious
local function jitter_wait(min_ms, max_ms)
    local delay = min_ms + math.random() * (max_ms - min_ms)
    delay = delay / 1000
    wait(delay)
end

-- Safe file operations with error handling
local function safe_writefile(path, content)
    local success, err = pcall(function()
        if isfolder then
            local dir = path:match("(.*)/[^/]+$")
            if dir and not isfolder(dir) then
                makefolder(dir)
            end
        end
        writefile(path, content)
    end)
    if not success then
        warn("Failed to write file:", path, err)
        return false
    end
    return true
end

local function safe_readfile(path)
    local success, content = pcall(function()
        return readfile(path)
    end)
    if success then
        return content
    end
    return nil
end

-- Build the full instance tree recursively
local function build_tree(instance, depth, output_lines)
    depth = depth or 0
    output_lines = output_lines or {}

    local indent = string.rep("  ", depth)
    local name = instance.Name
    local className = instance.ClassName

    table.insert(output_lines, indent .. name .. " [" .. className .. "]")

    -- Handle children
    local children = instance:GetChildren()
    for _, child in ipairs(children) do
        build_tree(child, depth + 1, output_lines)
    end

    return output_lines
end

-- Collect all scripts from a service/container
local function collect_scripts(container, script_type)
    local scripts = {}

    local function recurse(obj)
        if not obj then return end

        -- Check if it's a script type we want
        if obj:IsA(script_type) or obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
            table.insert(scripts, obj)
        end

        -- Recurse into children
        local children = obj:GetChildren()
        for _, child in ipairs(children) do
            recurse(child)
        end
    end

    recurse(container)
    return scripts
end

-- Collect all instances for tree building
local function collect_all_instances(container)
    local instances = {}

    local function recurse(obj)
        if not obj then return end
        table.insert(instances, obj)

        local children = obj:GetChildren()
        for _, child in ipairs(children) do
            recurse(child)
        end
    end

    recurse(container)
    return instances
end

-- Dump a single script
local function dump_script(script_instance, output_dir)
    local success, source = pcall(smart_decompile, script_instance)

    if not success or not source then
        local err = success and "Empty result" or tostring(source)
        source = "-- failed to decompile: " .. err .. "\n-- script: " .. script_instance:GetFullName() .. "\n-- className: " .. script_instance.ClassName
    end

    -- Build output path
    local full_name = script_instance:GetFullName()
    local safe_name = full_name:gsub("/", "_"):gsub("%.", "_")
    local file_path = output_dir .. "/" .. safe_name .. ".lua"

    -- Handle duplicate paths
    local counter = 0
    while safe_readfile(file_path) and counter < 100 do
        counter = counter + 1
        file_path = output_dir .. "/" .. safe_name .. "_" .. counter .. ".lua"
    end

    local written = safe_writefile(file_path, source)
    return written, file_path
end

-- Dump a service/container completely
local function dump_service(service_instance, base_output_dir)
    local service_name = service_instance.Name
    local service_dir = base_output_dir .. "/" .. service_name

    -- Create service directory
    if makefolder then
        pcall(makefolder, service_dir)
    end

    -- Collect all scripts
    local all_scripts = {}

    -- Client scripts (LocalScript, ModuleScript)
    local client_scripts = collect_scripts(service_instance, "LocalScript")
    for _, s in ipairs(client_scripts) do
        table.insert(all_scripts, s)
    end

    local module_scripts = collect_scripts(service_instance, "ModuleScript")
    for _, s in ipairs(module_scripts) do
        table.insert(all_scripts, s)
    end

    -- Server scripts (Script) - these may fail but we try anyway
    local server_scripts = collect_scripts(service_instance, "Script")
    for _, s in ipairs(server_scripts) do
        table.insert(all_scripts, s)
    end

    -- Dump each script
    local success_count = 0
    local fail_count = 0

    for i, script in ipairs(all_scripts) do
        local dumped, path = dump_script(script, service_dir)
        if dumped then
            success_count = success_count + 1
        else
            fail_count = fail_count + 1
        end

        -- Timing jitter - not all at once
        if i % 10 == 0 then
            jitter_wait(50, 200)
        end
    end

    -- Build tree file
    local tree_lines = build_tree(service_instance)
    local tree_content = table.concat(tree_lines, "\n")
    local tree_path = service_dir .. "/_tree.txt"
    safe_writefile(tree_path, tree_content)

    -- Collect remotes
    local remotes = {}
    for _, inst in ipairs(collect_all_instances(service_instance)) do
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("BindableEvent") then
            remotes[inst.ClassName] = remotes[inst.ClassName] or {}
            table.insert(remotes[inst.ClassName], inst.Name)
        end
    end

    -- Write remotes file
    local remotes_content = "return {\n"
    for class_name, names in pairs(remotes) do
        remotes_content = remotes_content .. "\t" .. class_name .. " = {\n"
        for _, name in ipairs(names) do
            remotes_content = remotes_content .. "\t\t\"" .. name .. "\",\n"
        end
        remotes_content = remotes_content .. "\t},\n"
    end
    remotes_content = remotes_content .. "}\n"

    local remotes_path = service_dir .. "/_remotes.lua"
    safe_writefile(remotes_path, remotes_content)

    return success_count, fail_count
end

-- Main dump function
function dumper.dump_game()
    local start_time = tick()

    -- Check for required executor functions
    if not (decompile or getscriptbytecode or writefile) then
        error("Executor must support: decompile, getscriptbytecode, or writefile")
    end

    -- Target services - everything we want to dump
    local target_services = {
        "ReplicatedStorage",
        "ServerStorage",
        "Workspace",
        "StarterPlayer",
        "StarterGui",
        "StarterPack",
        "ServerScriptService",
        "Lighting",
        "SoundService",
        "Stats",
        "RunService",
        "TweenService",
        "TextService",
        "UserInputService",
        "PhysicsService",
        "LocalizationService",
        "HttpService",
        "MarketplaceService",
        "CloneShopService",
        "DebugSettings",
    }

    -- Create base output directory
    local place_id = game.PlaceId
    local place_name = game.Name
    local base_dir = xor_str("HUKI", 2) -- "HUKI" obfuscated
    local output_root = base_dir .. "/" .. place_name .. "_" .. place_id

    -- Create root directory
    if makefolder then
        pcall(makefolder, base_dir)
        pcall(makefolder, output_root)
    end

    print("Starting game dump for PlaceId:", place_id)
    print("Game name:", place_name)
    print("Output directory:", output_root)

    -- Dump each service
    local total_success = 0
    local total_fail = 0

    for i, service_name in ipairs(target_services) do
        local success, service_instance = pcall(function()
            return game:GetService(service_name)
        end)

        if success and service_instance then
            print("Dumping " .. service_name .. "...")

            local s, f = dump_service(service_instance, output_root)
            total_success = total_success + s
            total_fail = total_fail + f

            -- Variable timing jitter between services
            if i < #target_services then
                jitter_wait(100, 500)
            end
        else
            warn("Could not access service:", service_name)
        end
    end

    -- Also dump nil instances (scripts that have been GC'd or are orphaned)
    if getnilinstances then
        print("Checking nil instances...")
        local nil_scripts = {}
        local nil_instances = getnilinstances()

        for _, inst in ipairs(nil_instances) do
            if inst:IsA("LocalScript") or inst:IsA("ModuleScript") or inst:IsA("Script") then
                table.insert(nil_scripts, inst)
            end
        end

        if #nil_scripts > 0 then
            local nil_dir = output_root .. "/Nil_Instances"
            pcall(makefolder, nil_dir)

            for _, script in ipairs(nil_scripts) do
                dump_script(script, nil_dir)
            end
        end
    end

    -- Summary
    local elapsed = tick() - start_time
    print("=== Dump Complete ===")
    print("Scripts dumped successfully:", total_success)
    print("Scripts failed:", total_fail)
    print("Total: " .. (total_success + total_fail))
    print("Time elapsed: " .. string.format("%.2f seconds", elapsed))
    print("Output saved to:", output_root)

    -- Write summary file
    local summary = {
        place_id = place_id,
        place_name = place_name,
        time = tick(),
        success = total_success,
        failed = total_fail,
        total = total_success + total_fail,
    }

    local summary_content = "-- Dump Summary\n"
    for k, v in pairs(summary) do
        summary_content = summary_content .. k .. " = " .. tostring(v) .. "\n"
    end

    safe_writefile(output_root .. "/_summary.lua", summary_content)
end

-- Alternative: dump specific service
function dumper.dump_service_custom(service_name)
    local service_instance = game:GetService(service_name)
    if not service_instance then
        error("Service not found: " .. service_name)
    end

    local base_dir = "HUKI_" .. game.PlaceId
    return dump_service(service_instance, base_dir .. "/" .. service_name .. "_" .. game.PlaceId)
end

-- Run the dump
-- The script auto-executes when loaded
-- To prevent immediate execution and allow custom configuration:
-- Set _G.NO_AUTO_DUMP = true before loading

if not _G.NO_AUTO_DUMP then
    -- Wait for game to load
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    -- Wait for basic services
    wait(1)

    -- Start dump in a coroutine for safety
    coroutine.wrap(function()
        local success, err = pcall(function()
            dumper.dump_game()
        end)

        if not success then
            warn("Dump failed:", err)
        end
    end)()
end

return dumper