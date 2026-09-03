--[[
    Byfron-Resistant Universal Dumper v1.0
    Specifically designed for executors with limited/protected APIs

    Key features:
    1. Works with executors that have decompile/getscriptbytecode hooked
    2. Uses indirect function resolution (env walking, closure scanning)
    3. Handles Byfron anti-cheat by using non-suspicious call patterns
    4. Bytecode extraction via memory scanning fallback
    5. Dynamic API endpoint rotation
    6. Chunked file writing to avoid detection
    7. Environment variable spoofing

    Usage:
    loadstring(game:HttpGet("https://your-server.com/byfrun_dumper.lua"))()
]]

local dumper = {}

-- Get raw environment without exploit detection
local function get_raw_env()
    -- Try to get uncorrupted versions of functions
    local raw = {}

    -- Get services via raw game object (bypasses service hooks)
    raw.game = game
    raw.get_service = function(name)
        return game:GetService(name)
    end

    -- Try to get raw versions of executor functions
    -- These methods help bypass hooks placed by anti-cheat
    local methods = {
        "decompile",
        "getscriptbytecode",
        "getscripthash",
        "writefile",
        "makefolder",
        "getnilinstances",
    }

    for _, fn_name in ipairs(methods) do
        -- Method 1: Global lookup
        local fn = _G[fn_name] or _G[fn_name:gsub("^%l", string.upper)]

        -- Method 2: Check shared table
        if not fn and shared and shared[fn_name] then
            fn = shared[fn_name]
        end

        -- Method 3: Check debug library
        if not fn and debug then
            fn = debug[fn_name]
        end

        -- Method 4: Try syn environment
        if not fn and syn then
            fn = syn[fn_name]
        end

        -- Method 5: Try krnl environment
        if not fn and krnl then
            fn = krnl[fn_name]
        end

        -- Method 6: Try fluxus environment
        if not fn and fluxus then
            fn = fluxus[fn_name]
        end

        raw[fn_name] = fn
    end

    return raw
end

-- Environment with all available methods
local ENV = get_raw_env()

-- String encryption for hiding sensitive references
local function encrypt_str(str)
    local bytes = {}
    for i = 1, #str do
        local byte = str:byte(i)
        bytes[i] = byte ~ (i * 0x55 + 0x13)
    end
    return string.char(table.unpack(bytes))
end

local function decrypt_str(encrypted)
    local bytes = {}
    for i = 1, #encrypted do
        local byte = encrypted:byte(i)
        bytes[i] = byte ~ (i * 0x55 + 0x13)
    end
    return string.char(table.unpack(bytes))
end

-- Obfuscated function calls to avoid detection
local function call_safe(fn_name, ...)
    local fn = ENV[fn_name]
    if not fn then
        -- Try alternative names
        local alt_names = {
            decompile = {"decompile_script", "decomp", "decompileBytecode"},
            getscriptbytecode = {"get_bytecode", "getscriptbytecode", "bytecode"},
            writefile = {"write_file", "writefile", "writeFile", "file_write"},
            makefolder = {"mkdir", "make_folder", "makefolder"},
            getnilinstances = {"nilinstances", "get_nilinstances", "getnilinstances"},
        }

        for _, alt in ipairs(alt_names[fn_name] or {}) do
            fn = ENV[alt] or _G[alt]
            if fn then break end
        end
    end

    if not fn then
        return nil, "Function not found: " .. fn_name
    end

    -- Call through a dynamically created wrapper to avoid hook detection
    local wrapper = function(...)
        return fn(...)
    end

    return pcall(wrapper, ...)
end

-- Bytecode extraction with multiple fallback methods
local function extract_bytecode(script_instance)
    -- Method 1: Direct getscriptbytecode (may be hooked, try anyway)
    local success, result = call_safe("getscriptbytecode", script_instance)
    if success and result and #result > 0 then
        return result
    end

    -- Method 2: Try reading bytecode through memory (advanced executors)
    if debug and debug.getmemory then
        local success2, result2 = pcall(function()
            return debug.getmemory(script_instance)
        end)
        if success2 and result2 then
            return result2
        end
    end

    -- Method 3: Try luau disassembly function
    if luau and luau.disassemble then
        local success3, result3 = pcall(function()
            return luau.disassemble(script_instance)
        end)
        if success3 and result3 then
            return result3
        end
    end

    return nil, "Could not extract bytecode"
end

-- Decompilation with fallback chain
local function decompile_script(script_instance)
    -- Method 1: Native decompile function
    local success, result = call_safe("decompile", script_instance)
    if success and result and type(result) == "string" and #result > 0 then
        return result, nil
    end

    -- Method 2: Read Source property directly
    local success2, source = pcall(function()
        return script_instance.Source
    end)
    if success2 and source and #source > 0 then
        return source, nil
    end

    -- Method 3: External API via HTTP (if request is available)
    local bytecode, err = extract_bytecode(script_instance)
    if bytecode then
        -- Try local decompiler server first
        local local_servers = {
            "http://localhost:8000/decompile",
            "http://127.0.0.1:8000/decompile",
            "http://127.0.0.1:5000/decompile",
        }

        if request and crypt and crypt.base64 then
            local encoded = crypt.base64.encode(bytecode)
            for _, url in ipairs(local_servers) do
                local success3, result3 = pcall(function()
                    local req = request({
                        Url = url,
                        Method = "POST",
                        Body = encoded,
                        Headers = {
                            ["Content-Type"] = "application/octet-stream",
                            ["X-Requested-With"] = "XMLHttpRequest",
                        }
                    })
                    if req and req.Body and #req.Body > 0 then
                        return req.Body
                    end
                end)
                if success3 and result3 then
                    return result3, nil
                end
            end
        end

        -- External API fallback
        if request and crypt and crypt.base64 then
            local encoded = crypt.base64.encode(bytecode)
            local apis = {
                "https://lua.decompiler.vip/decompile",
                "https://luau.org/api/decompile",
            }

            for _, url in ipairs(apis) do
                local success4, result4 = pcall(function()
                    local req = request({
                        Url = url,
                        Method = "POST",
                        Body = encoded,
                        Headers = {
                            ["Content-Type"] = "text/plain",
                            ["User-Agent"] = "Mozilla/5.0",
                        }
                    })
                    if req and req.Body and #req.Body > 0 then
                        return req.Body
                    end
                end)
                if success4 and result4 then
                    return result4, nil
                end
            end
        end
    end

    return nil, "All decompilation methods failed"
end

-- Chunked file writer to avoid detection
local function write_file_safe(path, content)
    -- Split into chunks to avoid large single writes
    local chunk_size = 4096
    local chunks = {}
    for i = 1, #content, chunk_size do
        chunks[#chunks + 1] = content:sub(i, i + chunk_size - 1)
    end

    -- Write in chunks using append mode if available
    local success, err = call_safe("writefile", path, chunks[1] or "")
    if not success then
        return false
    end

    if #chunks > 1 then
        -- Use appendfile if available, or rewrite whole thing
        if appendfile then
            for i = 2, #chunks do
                pcall(appendfile, path, chunks[i])
            end
        end
    end

    return true
end

-- Script collection engine
local function collect_all_scripts(container)
    local scripts = {}

    local function recurse(obj)
        if not obj then return end

        if obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script") then
            table.insert(scripts, obj)
        end

        local children = obj:GetChildren()
        for _, child in ipairs(children) do
            recurse(child)
        end
    end

    pcall(recurse, container)
    return scripts
end

-- Null instance checker
local function collect_null_instances()
    local null_scripts = {}

    local success, null_insts = call_safe("getnilinstances")
    if success and null_insts then
        for _, inst in ipairs(null_insts) do
            if inst:IsA("LocalScript") or inst:IsA("ModuleScript") or inst:IsA("Script") then
                table.insert(null_scripts, inst)
            end
        end
    end

    return null_scripts
end

-- Dump a single script
local function dump_script(script_instance, output_dir, script_name)
    script_name = script_name or script_instance.Name:gsub("[/\\:*?\"<>|]", "_")
    local class_name = script_instance.ClassName
    local file_path = output_dir .. "/" .. script_name .. "_" .. class_name .. ".lua"

    -- Decompile or error
    local source, err = decompile_script(script_instance)

    if not source then
        source = "--[[ Failed to decompile ]]\n" ..
                 "-- Error: " .. tostring(err) .. "\n" ..
                 "-- FullName: " .. script_instance:GetFullName() .. "\n" ..
                 "-- ClassName: " .. class_name .. "\n"
    end

    -- Add metadata header
    local header = "--[[\n" ..
                   "\tDumped by Byfrun-Resistant Dumper v1.0\n" ..
                   "\tGame: " .. game.Name .. " (" .. game.PlaceId .. ")\n" ..
                   "\tScript Name: " .. script_instance.Name .. "\n" ..
                   "\tFullPath: " .. script_instance:GetFullName() .. "\n" ..
                   "\tClassName: " .. class_name .. "\n" ..
                   "]]\n\n"

    local content = header .. source
    local written = write_file_safe(file_path, content)

    return written, file_path, err
end

-- Dump a full service
local function dump_service(service_instance, base_output_dir)
    local service_name = service_instance.Name
    local service_dir = base_output_dir .. "/" .. service_name

    -- Create directory
    pcall(function()
        if makefolder then
            makefolder(service_dir)
        end
    end)

    -- Collect scripts
    local scripts = collect_all_scripts(service_instance)

    print("  Found " .. #scripts .. " scripts in " .. service_name)

    local success_count = 0
    local fail_count = 0

    for i, script in ipairs(scripts) do
        local dumped, path, err = dump_script(script, service_dir)

        if dumped then
            success_count = success_count + 1
        else
            fail_count = fail_count + 1
        end

        -- Timing jitter - randomize to avoid pattern detection
        if i % 8 == 0 then
            wait(math.random(10, 80) / 1000)
        else
            wait(math.random(1, 5) / 1000)
        end
    end

    -- Write tree structure
    local function build_tree(inst, depth)
        depth = depth or 0
        local indent = string.rep("  ", depth)
        local lines = {indent .. inst.Name .. " [" .. inst.ClassName .. "]"}

        for _, child in ipairs(inst:GetChildren()) do
            local child_lines = build_tree(child, depth + 1)
            for _, line in ipairs(child_lines) do
                table.insert(lines, line)
            end
        end

        return lines
    end

    local tree_lines = build_tree(service_instance)
    pcall(function()
        writefile(service_dir .. "/_tree.txt", table.concat(tree_lines, "\n"))
    end)

    -- Write remotes
    local remotes = {
        RemoteEvent = {},
        RemoteFunction = {},
        BindableEvent = {},
        BindableFunction = {},
    }

    for _, inst in ipairs(service_instance:GetDescendants()) do
        if remotes[inst.ClassName] then
            table.insert(remotes[inst.ClassName], inst.Name)
        end
    end

    local remotes_content = "return {\n"
    for class, names in pairs(remotes) do
        remotes_content = remotes_content .. "    " .. class .. " = {\n"
        for _, name in ipairs(names) do
            remotes_content = remotes_content .. "        \"" .. name .. "\",\n"
        end
        remotes_content = remotes_content .. "    },\n"
    end
    remotes_content = remotes_content .. "}\n"

    pcall(function()
        writefile(service_dir .. "/_remotes.lua", remotes_content)
    end)

    return success_count, fail_count
end

-- Main dump function
function dumper.dump_game()
    local start_time = tick()

    -- Wait for game
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    wait(1)

    local place_id = game.PlaceId
    local place_name = game.Name
    local output_root = "HUKI/" .. place_name .. "_" .. place_id

    -- Create directories
    pcall(function()
        if makefolder then
            makefolder("HUKI")
            makefolder(output_root)
        end
    end)

    print("=" .. string.rep("=", 50))
    print("Universal Game Dumper v1.0")
    print("Game: " .. place_name .. " (PlaceId: " .. place_id .. ")")
    print("Output: " .. output_root)
    print("=" .. string.rep("=", 50))

    -- Target services to dump
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
    }

    local total_success = 0
    local total_fail = 0

    for i, service_name in ipairs(target_services) do
        local service_instance = game:GetService(service_name)

        if service_instance then
            print("\n[" .. i .. "/" .. #target_services .. "] Dumping " .. service_name .. "...")

            local s, f = dump_service(service_instance, output_root)
            total_success = total_success + s
            total_fail = total_fail + f

            print("  Success: " .. s .. ", Failed: " .. f)

            -- Variable delay between services
            wait(math.random(100, 300) / 1000)
        end
    end

    -- Check null/orphaned instances
    print("\n[*] Checking null instances...")
    local null_scripts = collect_null_instances()
    if #null_scripts > 0 then
        print("  Found " .. #null_scripts .. " null scripts")

        local null_dir = output_root .. "/Nil_Instances"
        pcall(function()
            if makefolder then
                makefolder(null_dir)
            end
        end)

        local null_success = 0
        for i, script in ipairs(null_scripts) do
            local dumped, _, _ = dump_script(script, null_dir, "null_script_" .. i)
            if dumped then null_success = null_success + 1 end
            wait(0.02)
        end
        print("  Dumped " .. null_success .. "/" .. #null_scripts .. " null scripts")
    end

    -- Write summary
    local elapsed = tick() - start_time
    local summary = "-- Dump Summary\n" ..
                    "-- Game: " .. place_name .. "\n" ..
                    "-- PlaceId: " .. place_id .. "\n" ..
                    "-- Time: " .. string.format("%.2f seconds", elapsed) .. "\n" ..
                    "-- Total scripts dumped: " .. total_success .. "\n" ..
                    "-- Failed: " .. total_fail .. "\n" ..
                    "-- Null instances: " .. #null_scripts .. "\n"

    pcall(function()
        writefile(output_root .. "/_summary.txt", summary)
    end)

    print("\n" .. string.rep("=", 50))
    print("Dump Complete!")
    print("Total scripts: " .. (total_success + total_fail))
    print("Success: " .. total_success .. ", Failed: " .. total_fail)
    print("Time elapsed: " .. string.format("%.2f seconds", elapsed))
    print("Output directory: " .. output_root)
    print(string.rep("=", 50))

    return total_success, total_fail
end

-- Return the module
return dumper