--[[
    Luathys Enhanced Dumper v2.4
    - Progress output per script (no more silent hangs)
    - External-API fallback DISABLED by default (it had no timeout and
      stalled dumps for minutes) - opt in with _G.LUATHYS_USE_API = true
    - Request timeout of 10s when API fallback is enabled
    - Per-container elapsed timing
    - Everything from v2.2: unique paths, getloadedmodules,
      LocalPlayer containers, nil instances
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

    local USE_API = (_G.LUATHYS_USE_API == true)
    print("=== Luathys Enhanced Dumper v2.4 ===")
    print("Game: " .. game.Name .. " (PlaceId: " .. placeId .. ")")
    print("External API fallback: " .. (USE_API and "ON" or "OFF (set _G.LUATHYS_USE_API=true to enable)"))

    local totalSuccess, totalFail = 0, 0
    local usedPaths = {}
    local seenScripts = setmetatable({}, {__mode = "k"})

    safe(writefile, outRoot .. "/_summary.txt",
        "-- Luathys v2.4 Dump\n-- Game: " .. game.Name .. "\n-- PlaceId: " .. placeId .. "\n-- Time: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")

    local function uniquePath(dir, baseName, cls)
        baseName = baseName:gsub("[^%w _%-]", "_")
        if #baseName > 80 then baseName = baseName:sub(1, 80) end
        local path = dir .. "/" .. baseName .. "_" .. cls .. ".lua"
        local n = 1
        while usedPaths[path] do
            n = n + 1
            path = dir .. "/" .. baseName .. "_" .. cls .. "_" .. n .. ".lua"
        end
        usedPaths[path] = true
        return path
    end

    local function decompileScript(script)
        if typeof(decompile) == "function" then
            local ok, result = pcall(decompile, script)
            if ok and type(result) == "string" and #result > 0 then
                return result
            end
        end
        local ok, src = pcall(function() return script.Source end)
        if ok and type(src) == "string" and #src > 0 then
            return src
        end
        if USE_API and typeof(getscriptbytecode) == "function" and crypt and request then
            local okBc, bc = pcall(getscriptbytecode, script)
            if okBc and bc then
                local encoded = bc
                pcall(function() encoded = crypt.base64.encode(bc) end)
                local okReq, result = pcall(function()
                    local req = request({
                        Url = "https://unluau.lonegladiator.dev/unluau/decompile",
                        Method = "POST",
                        Body = encoded,
                        Headers = {["Content-Type"] = "application/octet-stream"},
                        Timeout = 10,
                    })
                    if req and req.Body and #req.Body > 0 then return req.Body end
                end)
                if okReq and result then return result end
            end
        end
        return nil
    end

    local function dumpOne(script, dir, label, idx, total)
        if seenScripts[script] then return false end
        seenScripts[script] = true

        local fullName = ""
        pcall(function() fullName = script:GetFullName() end)

        if idx and total and idx % 10 == 0 then
            print("    [" .. idx .. "/" .. total .. "] " .. fullName)
        end

        local source = decompileScript(script)
        if not source then
            source = "-- Failed to decompile (server-side or protected)\n-- FullName: " .. fullName
        end

        local header = table.concat({
            "--[[",
            "\tLuathys v2.3",
            "\tContainer: " .. label,
            "\tScript: " .. script.Name,
            "\tPath: " .. fullName,
            "\tClass: " .. script.ClassName,
            "]]",
            "",
        }, "\n")

        local path = uniquePath(dir, script.Name, script.ClassName)
        if #path > 240 then
            path = dir .. "/s_" .. tostring(math.floor(tick() * 1000) % 100000000) .. ".lua"
        end

        if safe(writefile, path, header .. source) then
            return true
        end
        return false
    end

    local function collectInto(container, dir, label)
        if not container then return 0, 0 end
        local t0 = tick()
        local sOk, fail = 0, 0

        local scripts = {}
        local function walk(obj)
            local cls = obj.ClassName
            if cls == "LocalScript" or cls == "ModuleScript" or cls == "Script" then
                if not seenScripts[obj] then
                    scripts[#scripts + 1] = obj
                end
            end
            local kids = safe(function() return obj:GetChildren() end)
            if kids then
                for _, child in ipairs(kids) do walk(child) end
            end
        end
        pcall(walk, container)

        print("  [" .. label .. "] found " .. #scripts .. " scripts")
        for i, s in ipairs(scripts) do
            if dumpOne(s, dir, label, i, #scripts) then sOk = sOk + 1 else fail = fail + 1 end
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

        print("  [" .. label .. "] done: " .. sOk .. " ok, " .. fail .. " failed (" .. string.format("%.1fs", tick() - t0) .. ")")
        return sOk, fail
    end

    -- Pass 1: services
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
            totalSuccess, totalFail = totalSuccess + s, totalFail + f
            task.wait(0.1)
        end
    end

    -- Pass 2: LocalPlayer runtime containers
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
                totalSuccess, totalFail = totalSuccess + s, totalFail + f
            end
        end
    end

    -- Pass 3: ALL loaded modules
    if typeof(getloadedmodules) == "function" then
        print("Dumping all loaded modules (getloadedmodules)...")
        local dir = outRoot .. "/LoadedModules"
        safe(makefolder, dir)
        local mods = safe(getloadedmodules) or {}
        print("  found " .. #mods .. " loaded modules")
        local s, f = 0, 0
        for i, m in ipairs(mods) do
            if dumpOne(m, dir, "LoadedModule", i, #mods) then s = s + 1 else f = f + 1 end
        end
        print("  [LoadedModules] done: " .. s .. " ok, " .. f .. " failed")
        totalSuccess, totalFail = totalSuccess + s, totalFail + f
    else
        print("getloadedmodules not available on this executor")
    end

    -- Pass 4: nil/orphaned instances
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
        print("  dumped " .. s .. " scripts from " .. #insts .. " nil instances")
        totalSuccess, totalFail = totalSuccess + s, totalFail + f
    end

    safe(writefile, outRoot .. "/_summary.txt",
        "-- Luathys v2.4 Dump Complete\n"
        .. "-- Game: " .. game.Name .. "\n"
        .. "-- PlaceId: " .. placeId .. "\n"
        .. "-- Success: " .. totalSuccess .. "\n"
        .. "-- Failed: " .. totalFail .. "\n"
        .. "-- Time: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")

    print("")
    print("=== Dump Complete ===")
    print("Success: " .. totalSuccess .. " | Failed: " .. totalFail)
    print("Output: " .. outRoot)
end)

if not success then
    warn("Luathys error: " .. tostring(err))
end