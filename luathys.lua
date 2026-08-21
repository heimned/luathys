--[[
    Luathys Enhanced Dumper v2.1
    Compatible with restricted executors and anti-cheat environments
]]

local success, err = pcall(function()
    if not game or not game.IsLoaded then return end
    if not game:IsLoaded() then game.Loaded:Wait() end
    wait(1)

    local placeId = game.PlaceId or 0
    local placeName = game.Name or "Game"
    local outRoot = "HUKI/" .. placeName .. "_" .. placeId
    
    local ok = pcall(function()
        makefolder("HUKI")
        makefolder(outRoot)
    end)
    if not ok then warn("Could not create output directory") return end

    print("=== Luathys Enhanced Dumper v2.1 ===")
    print("Game: " .. placeName .. " (PlaceId: " .. placeId .. ")")

    local services = {
        "ReplicatedStorage", "ServerStorage", "Workspace",
        "StarterPlayer", "StarterGui", "StarterPack",
        "ServerScriptService", "Lighting", "SoundService"
    }

    local totalSuccess, totalFail = 0, 0
    local summary = "-- Luathys Dump Summary\n-- Game: " .. placeName .. "\n-- PlaceId: " .. placeId .. "\n-- Time: " .. tostring(tick()) .. "\n"
    writefile(outRoot .. "/_summary.txt", summary)

    for i, svcName in ipairs(services) do
        local svcOk, svc = pcall(function() return game:GetService(svcName) end)
        if not svcOk or not svc then
            print("Service not available: " .. svcName)
            continue
        end

        print("Dumping " .. svcName .. "...")
        local svcDir = outRoot .. "/" .. svcName
        pcall(function() makefolder(svcDir) end)

        local scripts = {}
        local function collect(obj)
            if not obj then return end
            local cls = obj.ClassName
            if cls == "LocalScript" or cls == "ModuleScript" or cls == "Script" then
                table.insert(scripts, obj)
            end
            for _, child in ipairs(obj:GetChildren()) do
                collect(child)
            end
        end
        pcall(collect, svc)

        local successCount, failCount = 0, 0
        for _, script in ipairs(scripts) do
            local scriptName = script.Name:gsub("[/\:*?\"<>|]", "_")
            local cls = script.ClassName
            local path = svcDir .. "/" .. scriptName .. "_" .. cls .. ".lua"

            local source
            if decompile then
                local ok2, result = pcall(decompile, script)
                if ok2 and result and #result > 0 then source = result end
            end
            if not source then
                local ok2, src = pcall(function() return script.Source end)
                if ok2 and src and #src > 0 then source = src end
            end
            if not source and getscriptbytecode and crypt and crypt.base64 and request then
                local ok2, bc = pcall(getscriptbytecode, script)
                if ok2 and bc then
                    local encoded = crypt.base64.encode(bc)
                    local ok3, result = pcall(function()
                        local req = request({Url="https://unluau.lonegladiator.dev/unluau/decompile", Method="POST", Body=encoded, Headers={["Content-Type"]="application/octet-stream"}})
                        if req and req.Body and #req.Body > 0 then return req.Body end
                    end)
                    if ok3 and result then source = result end
                end
            end

            if not source then
                source = "-- Failed to decompile\n-- FullName: " .. script:GetFullName()
            end

            local header = "--[[\n\tLuathys v2.1\n\tService: " .. svcName .. "\n\tScript: " .. script.Name .. "\n\tPath: " .. script:GetFullName() .. "\n\tClass: " .. cls .. "\n]]\n\n"
            local writeOk = pcall(function() writefile(path, header .. source) end)
            if writeOk then successCount = successCount + 1 else failCount = failCount + 1 end
        end

        totalSuccess = totalSuccess + successCount
        totalFail = totalFail + failCount

        -- Tree
        local function build_tree(inst, depth)
            depth = depth or 0
            local indent = string.rep("  ", depth)
            local lines = {indent .. inst.Name .. " [" .. inst.ClassName .. "]"}
            for _, child in ipairs(inst:GetChildren()) do
                for _, line in ipairs(build_tree(child, depth + 1)) do
                    table.insert(lines, line)
                end
            end
            return lines
        end
        pcall(function() writefile(svcDir .. "/_tree.txt", table.concat(build_tree(svc), "\n")) end)

        -- Remotes
        local remotes = {RemoteEvent={}, RemoteFunction={}, BindableEvent={}, BindableFunction={}}
        local allOk, all = pcall(function() return svc:GetDescendants() end)
        if allOk then
            for _, inst in ipairs(all) do
                if remotes[inst.ClassName] then table.insert(remotes[inst.ClassName], inst.Name) end
            end
        end
        local rc = "return {\n"
        for cls, names in pairs(remotes) do
            if #names > 0 then
                rc = rc .. "    " .. cls .. " = {\n"
                for _, name in ipairs(names) do rc = rc .. "        \"" .. name .. "\",\n" end
                rc = rc .. "    },\n"
            end
        end
        rc = rc .. "}\n"
        pcall(function() writefile(svcDir .. "/_remotes.lua", rc) end)

        print("  -> " .. successCount .. " ok, " .. failCount .. " failed")
        wait(0.2)
    end

    print("\n=== Dump Complete ===")
    print("Total: " .. (totalSuccess + totalFail) .. " (Success: " .. totalSuccess .. ", Failed: " .. totalFail .. ")")
    print("Output: " .. outRoot)
end)

if not success then
    warn("Luathys error: " .. tostring(err))
end
