--[[
    Luathys Enhanced Dumper v2.5 - BYTECODE MODE
    All remote decompiler APIs are currently dead (lonegladiator 522,
    cosmic.best DNS-dead = Madium's built-in decompile is broken).
    So this version dumps RAW BYTECODE for every script - guaranteed
    to work since getscriptbytecode functions on your executor -
    plus whatever source/decompile is obtainable locally.

    After dumping, run decompile_all.py (in the same folder as
    unluau.exe) against the output directory to turn every .luac
    into readable .lua offline.

    Optional:
      _G.LUATHYS_API_URL = "https://your-own-decompiler/endpoint"
        -> also tries this single endpoint (10s timeout) per script
]]

local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local success, err = pcall(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(2)

    local placeId = game.PlaceId or 0
    local placeName = (game.Name or "Game"):gsub("[^%w_-]", "_")
    local outRoot = placeName .. "_" .. placeId

    safe(makefolder, outRoot)

    print("=== Luathys Enhanced Dumper v2.5 (bytecode mode) ===")
    print("Game: " .. game.Name .. " (PlaceId: " .. placeId .. ")")

    local apiURL = _G.LUATHYS_API_URL
    if apiURL then
        print("Custom API endpoint: " .. tostring(apiURL))
    else
        print("No API endpoint set - bytecode-only mode")
        print("(all public decompiler APIs are currently dead)")
    end

    local totalOk, totalFail = 0, 0
    local usedPaths = {}
    local seenScripts = setmetatable({}, {__mode = "k"})

    local function uniquePath(dir, baseName, ext)
        baseName = baseName:gsub("[^%w _%-]", "_")
        if #baseName > 80 then baseName = baseName:sub(1, 80) end
        local path = dir .. "/" .. baseName .. ext
        local n = 1
        while usedPaths[path] do
            n = n + 1
            path = dir .. "/" .. baseName .. "_" .. n .. ext
        end
        usedPaths[path] = true
        return path
    end

    local function tryApiDecode(bytecode)
        if not apiURL or typeof(request) ~= "function" then return nil end
        local encoded = bytecode
        pcall(function() encoded = crypt.base64.encode(bytecode) end)
        local ok, result = pcall(function()
            local req = request({
                Url = apiURL,
                Method = "POST",
                Body = encoded,
                Headers = {["Content-Type"] = "application/octet-stream"},
                Timeout = 10,
            })
            if req and req.Body and #req.Body > 0 then return req.Body end
        end)
        if ok and result then return result end
        return nil
    end

    local function dumpOne(script, dir, label, idx, total)
        if seenScripts[script] then return "dup" end
        seenScripts[script] = true

        local fullName = ""
        pcall(function() fullName = script:GetFullName() end)
        if idx and total and idx % 25 == 0 then
            print("    [" .. idx .. "/" .. total .. "] " .. fullName)
        end

        -- 1) best case: readable Source (rare on modern Roblox, but free)
        local src = safe(function() return script.Source end)
        if type(src) == "string" and #src > 0 then
            local p = uniquePath(dir, script.Name, "_" .. script.ClassName .. "_src.lua")
            local header = "--[[" .. label .. " | " .. fullName .. " | SOURCE ]]\n"
            if safe(writefile, p, header .. src) then return true end
        end

        -- 2) bytecode: always save this - it is the durable artifact
        local bc = nil
        if typeof(getscriptbytecode) == "function" then
            local okBc, b = pcall(getscriptbytecode, script)
            if okBc and type(b) == "string" and #b > 0 then bc = b end
        end

        if bc then
            local pb = uniquePath(dir, script.Name, "_" .. script.ClassName .. ".luac")
            safe(writefile, pb, bc)

            -- optional live decode attempt
            local decoded = tryApiDecode(bc)
            if decoded then
                local pl = uniquePath(dir, script.Name, "_" .. script.ClassName .. ".lua")
                safe(writefile, pl, "--[[" .. label .. " | " .. fullName .. "]]\n" .. decoded)
                return true
            end
            return true  -- bytecode saved counts as success
        end

        -- 3) nothing worked - record what we lost
        local pf = uniquePath(dir, script.Name, "_" .. script.ClassName .. "_FAILED.lua")
        local reason = (script.ClassName == "Script")
            and "server Script - bytecode is stripped before replication"
            or "no bytecode and no source available"
        safe(writefile, pf, "-- " .. reason .. \n-- FullName: " .. fullName .. "\n-- Class: " .. script.ClassName)
        return "fail"
    end

    local function collectInto(container, dir, label)
        if not container then return 0, 0 end
        local t0 = tick()
        local ok, fail = 0, 0

        local scripts = {}
        local function walk(obj)
            local cls = obj.ClassName
            if cls == "LocalScript" or cls == "ModuleScript" or cls == "Script" then
                if not seenScripts[obj] then scripts[#scripts + 1] = obj end
            end
            local kids = safe(function() return obj:GetChildren() end)
            if kids then
                for _, child in ipairs(kids) do walk(child) end
            end
        end
        pcall(walk, container)

        print("  [" .. label .. "] found " .. #scripts .. " scripts")
        local dup = 0
        for i, s in ipairs(scripts) do
            local r = dumpOne(s, dir, label, i, #scripts)
            if r == true then ok = ok + 1 elseif r == "dup" then dup = dup + 1 else fail = fail + 1 end
        end

        local function buildTree(inst, depth)
            depth = depth or 0
            local lines = {string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "]"}
            local kids = safe(function() return inst:GetChildren() end)
            if kids then
                for _, child in ipairs(kids) do
                    for _, line in ipairs(buildTree(child, depth + 1)) do
                        lines[#lines + 1] = line
                    end
                end
            end
            return lines
        end
        safe(writefile, dir .. "/_tree.txt", table.concat(buildTree(container), "\n"))

        local remotes = {}
        local all = safe(function() return container:GetDescendants() end)
        if all then
            for _, inst in ipairs(all) do
                local cn = inst.ClassName
                if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
                    remotes[#remotes + 1] = cn .. ": " .. inst.Name
                end
            end
        end
        safe(writefile, dir .. "/_remotes.txt", table.concat(remotes, "\n"))

        print("  [" .. label .. "] done: " .. ok .. " ok, " .. fail .. " failed (" .. string.format("%.1fs", tick() - t0) .. ")")
        return ok, fail
    end

    local services = {
        "ReplicatedStorage", "ServerStorage", "Workspace",
        "StarterPlayer", "StarterGui", "StarterPack",
        "ServerScriptService", "Lighting", "SoundService",
        "ReplicatedFirst", "Teams",
    }
    for _, svcName in ipairs(services) do
        local svc = safe(function() return game:GetService(svcName) end)
        if svc then
            print("Dumping " .. svcName .. "...")
            local svcDir = outRoot .. "/" .. svcName:gsub("[^%w]", "")
            safe(makefolder, svcDir)
            local s, f = collectInto(svc, svcDir, svcName)
            totalOk, totalFail = totalOk + s, totalFail + f
            task.wait(0.1)
        end
    end

    local player = game:GetService("Players").LocalPlayer
    if player then
        print("Dumping LocalPlayer containers...")
        local containers = {
            {"PlayerGui", player.PlayerGui},
            {"Backpack", player.Backpack},
            {"Character", player.Character},
            {"PlayerScripts", safe(function() return player:FindFirstChildOfClass("PlayerScripts") end)},
        }
        for _, pair in ipairs(containers) do
            local label, cont = pair[1], pair[2]
            if cont then
                local dir = outRoot .. "/LocalPlayer_" .. label
                safe(makefolder, dir)
                local s, f = collectInto(cont, dir, label)
                totalOk, totalFail = totalOk + s, totalFail + f
            end
        end
    end

    if typeof(getloadedmodules) == "function" then
        print("Dumping all loaded modules...")
        local dir = outRoot .. "/LoadedModules"
        safe(makefolder, dir)
        local mods = safe(getloadedmodules) or {}
        print("  found " .. #mods .. " loaded modules")
        local s, f, d = 0, 0, 0
        for i, m in ipairs(mods) do
            local r = dumpOne(m, dir, "LoadedModule", i, #mods)
            if r == true then s = s + 1 elseif r == "dup" then d = d + 1 else f = f + 1 end
        end
        print("  [LoadedModules] done: " .. s .. " ok, " .. f .. " failed, " .. tostring(d) .. " duplicates")
        totalOk, totalFail = totalOk + s, totalFail + f
    end

    if typeof(getnilinstances) == "function" then
        print("Dumping nil instances...")
        local dir = outRoot .. "/NilInstances"
        safe(makefolder, dir)
        local insts = safe(getnilinstances) or {}
        local s, f = 0, 0
        for _, inst in ipairs(insts) do
            local cls = inst.ClassName
            if cls == "LocalScript" or cls == "ModuleScript" or cls == "Script" then
                if dumpOne(inst, dir, "NilInstance") then s = s + 1 else f = f + 1 end
            end
        end
        print("  dumped " .. s .. " from " .. #insts .. " nil instances")
        totalOk, totalFail = totalOk + s, totalFail + f
    end

    safe(writefile, outRoot .. "/_README.txt",
        "Bytecode dump complete.\n"
        .. "Files ending in .luac contain raw Luau bytecode.\n"
        .. "Run decompile_all.py (with unluau.exe) on this folder to\n"
        .. "convert every .luac into readable .lua source.\n")

    print("")
    print("=== Bytecode Dump Complete ===")
    print("Success: " .. totalOk .. " | Failed: " .. totalFail)
    print("Next step: run decompile_all.py on:")
    print("  " .. outRoot)
end)

if not success then
    warn("Luathys error: " .. tostring(err))
end