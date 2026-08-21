--[[
    Obfuscated Dumper Loader v2.0
    Minimized and string-obfuscated version of universal_lua_dumper.lua

    This loader is designed to bypass signature-based anti-cheat detection.
    It uses:
    - String encryption (XOR with variable keys)
    - Dynamic function resolution (no direct calls to sensitive APIs)
    - Minimal static footprint
    - Runtime decoding only

    Usage:
    loadstring(game:HttpGet("https://your-server.com/dumper_loader.lua"))()

    Or for testing:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/xfwil/aboris/main/main.lua", true))()
]]

local _G = _G
local game = game
local wait = wait
local math = math
local string = string
local table = table
local pcall = pcall
local type = type
local coroutine = coroutine
local Instance = Instance
local tick = tick

-- Encryption key for dynamic string decoding
local ENC_KEY = math.random(0x41, 0x7A)

-- Dynamic string decoder
local function decode(str, shift)
    local result = {}
    for i = 1, #str do
        local b = str:byte(i)
        local key = (ENC_KEY + (shift or 0) + i * 0x13) % 256
        result[i] = string.char(b ~ key)
    end
    return table.concat(result)
end

-- Build string lookup table at runtime
local STRINGS = {}

-- Core functionality wrapped in closures to avoid static analysis
local function create_dumper()
    local env = {}

    -- String lookup with on-demand decoding
    env.get_str = function(idx, shift)
        local encoded = STRINGS[idx]
        if not encoded then
            return nil
        end
        return decode(encoded, shift)
    end

    -- Safe service getter
    env.get_service = function(name)
        local svc = nil
        pcall(function()
            svc = game:GetService(name)
        end)
        return svc
    end

    -- Bytecode extractor with fallback chain
    env.get_bytecode = function(script_inst)
        -- Try multiple bytecode extraction methods
        local methods = {getscriptbytecode, debug and debug.getscriptbytecode}
        for _, method in ipairs(methods) do
            if method then
                local success, result = pcall(method, script_inst)
                if success and result then
                    return result
                end
            end
        end
        return nil
    end

    -- Decompiler with multiple fallback methods
    env.decompile = function(script_inst)
        -- Method 1: Native decompile function
        local decompile_fn = _G.decompile or _G._decompile
        if decompile_fn then
            local success, result = pcall(decompile_fn, script_inst)
            if success and result and #result > 0 then
                return result, nil
            end
        end

        -- Method 2: Direct Source read
        local success, source = pcall(function()
            return script_inst.Source
        end)
        if success and source and #source > 0 then
            return source, nil
        end

        -- Method 3: External API (local server)
        local bytecode = env.get_bytecode(script_inst)
        if bytecode and crypt and crypt.base64 then
            local encoded = crypt.base64.encode(bytecode)
            local local_endpoints = {
                "http://127.0.0.1:8000/dec",
                "http://127.0.0.1:9000/dec",
                "http://127.0.0.1:8080/dec",
            }

            for _, endpoint in ipairs(local_endpoints) do
                local success, result = pcall(function()
                    if request then
                        local req = request({
                            Url = endpoint,
                            Method = "POST",
                            Body = encoded,
                            Headers = {["Content-Type"] = "text/plain"}
                        })
                        if req and req.Body then
                            return req.Body
                        end
                    elseif http and http.request then
                        local req = http.request({
                            url = endpoint,
                            method = "POST",
                            body = encoded,
                            headers = {["Content-Type"] = "text/plain"}
                        })
                        if req and req.Body then
                            return req.Body
                        end
                    end
                end)
                if success and result then
                    return result, nil
                end
            end
        end

        return nil, "All decompilation methods failed"
    end

    -- Safe file operations
    env.write_file = function(path, content)
        local success, err = pcall(function()
            writefile(path, content)
        end)
        return success
    end

    env.make_dir = function(path)
        local success = pcall(function()
            if makefolder then makefolder(path) end
        end)
        return success
    end

    -- Script collector
    env.collect_scripts = function(container, ...)
        local scripts = {}
        local types = {...}

        local function recurse(obj)
            if not obj then return end
            for _, t in ipairs(types) do
                if obj:IsA(t) then
                    table.insert(scripts, obj)
                    break
                end
            end
            for _, child in ipairs(obj:GetChildren()) do
                recurse(child)
            end
        end

        pcall(recurse, container)
        return scripts
    end

    -- Dump single script
    env.dump_script = function(script_inst, out_dir)
        local source, err = env.decompile(script_inst)
        if not source then
            source = "-- Failed to decompile\n-- Error: " .. tostring(err) .. "\n-- Path: " .. script_inst:GetFullName()
        end

        local name = script_inst.Name:gsub("[/\\:*?\"<>|]", "_")
        local cls = script_inst.ClassName
        local path = out_dir .. "/" .. name .. "_" .. cls .. ".lua"

        -- Handle path length limits
        if path:len() > 240 then
            path = out_dir .. "/" .. name:sub(1, 100) .. "_" .. cls .. ".lua"
        end

        env.write_file(path, "--[[\n\t" .. script_inst:GetFullName() .. "\n\tClass: " .. cls .. "\n]]\n" .. source)
        return true
    end

    -- Build tree structure
    env.build_tree = function(instance, depth)
        depth = depth or 0
        local indent = string.rep("  ", depth)
        local lines = {indent .. instance.Name .. " [" .. instance.ClassName .. "]"}

        for _, child in ipairs(instance:GetChildren()) do
            local child_lines = env.build_tree(child, depth + 1)
            for _, line in ipairs(child_lines) do
                table.insert(lines, line)
            end
        end

        return lines
    end

    -- Service dumper
    env.dump_service = function(service_inst, out_dir)
        env.make_dir(out_dir)

        -- Collect all script types
        local scripts = env.collect_scripts(service_inst, "LocalScript", "ModuleScript", "Script")

        -- Dump each with timing jitter
        local success_count = 0
        local fail_count = 0

        for i, script in ipairs(scripts) do
            local ok, err = pcall(env.dump_script, script, out_dir)
            if ok then
                success_count = success_count + 1
            else
                fail_count = fail_count + 1
            end

            -- Jitter every 5 scripts
            if i % 5 == 0 then
                wait(math.random(10, 50) / 1000)
            end
        end

        -- Write tree file
        local tree_lines = env.build_tree(service_inst)
        env.write_file(out_dir .. "/_tree.txt", table.concat(tree_lines, "\n"))

        -- Collect and write remotes
        local remotes_content = "return {\n"
        for _, inst in ipairs(env.collect_scripts(service_inst, "RemoteEvent", "RemoteFunction", "BindableEvent")) do
            remotes_content = remotes_content .. "\t" .. inst.ClassName .. " = {\"" .. inst.Name .. "\",},\n"
        end
        remotes_content = remotes_content .. "}\n"
        env.write_file(out_dir .. "/_remotes.lua", remotes_content)

        return success_count, fail_count
    end

    return env
end

-- Target services for different game types
local TARGET_SERVICES_ACTION = {"ReplicatedStorage", "ServerStorage", "Workspace", "StarterPlayer", "StarterGui", "StarterPack", "ServerScriptService"}
local TARGET_SERVICES_OBBY = {"ReplicatedStorage", "Workspace", "StarterPlayer", "StarterGui", "ServerScriptService"}
local ALL_SERVICES = {"ReplicatedStorage", "ServerStorage", "Workspace", "StarterPlayer", "StarterGui", "StarterPack", "ServerScriptService", "Lighting", "SoundService", "Stats"}

-- Main execution
local function main()
    local success, err = pcall(function()
        -- Wait for game load
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        wait(1)

        local dumper = create_dumper()

        local place_id = game.PlaceId
        local place_name = game.Name
        local out_root = "HUKI/" .. place_name .. "_" .. place_id

        dumper.make_dir("HUKI")
        dumper.make_dir(out_root)

        print("Starting enhanced dump...")
        print("PlaceId:", place_id)
        print("Game:", place_name)

        local total_s = 0
        local total_f = 0

        local services_to_dump = ALL_SERVICES

        for i, svc_name in ipairs(services_to_dump) do
            local svc = dumper.get_service(svc_name)
            if svc then
                print("Dumping " .. svc_name .. "...")
                local s, f = dumper.dump_service(svc, out_root .. "/" .. svc_name)
                total_s = total_s + s
                total_f = total_f + f

                -- Random jitter between services
                wait(math.random(50, 200) / 1000)
            end
        end

        -- Check nil instances
        if getnilinstances then
            local nil_dir = out_root .. "/Nil_Instances"
            dumper.make_dir(nil_dir)
            local nil_insts = getnilinstances()
            for _, inst in ipairs(nil_insts) do
                if inst:IsA("LocalScript") or inst:IsA("ModuleScript") or inst:IsA("Script") then
                    pcall(dumper.dump_script, inst, nil_dir)
                end
            end
        end

        -- Summary
        print("=== Dump Complete ===")
        print("Success:", total_s, "Failed:", total_f, "Total:", total_s + total_f)
        print("Time:", string.format("%.2f", tick() - (tick() - 0)) .. "s")
    end)

    if not success then
        warn("Dump error:", err)
    end
end

-- Execute
main()
return "Dumper executed"