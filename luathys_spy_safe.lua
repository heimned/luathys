-- Luathys Remote Spy (Safe Mode) v1.1
-- For executors with hookfunction but no hookmetamethod.
-- Hooks RemoteEvent.FireServer and RemoteFunction.InvokeServer directly.

local CONFIG = {
    LOG_TO_FILE = true,
    LOG_PATH = "HUKI/Spy",
    MAX_ARG_DEPTH = 4,
    SUPPRESS_DUPES = true,
}

local function truncate(s)
    s = tostring(s)
    if #s > 300 then return s:sub(1, 300) .. "...(" .. #s .. " chars)" end
    return s
end

local function serialize(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then return '"' .. truncate(v) .. '"'
    elseif t == "number" or t == "boolean" then return tostring(v)
    elseif t == "Instance" then
        local ok, path = pcall(function() return v:GetFullName() end)
        return (ok and path) or "Instance(dead)"
    elseif t == "table" then
        if depth >= CONFIG.MAX_ARG_DEPTH then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 20 then parts[n] = "..."; break end
            local key = (typeof(k) == "string") and k or ("[" .. tostring(k) .. "]")
            parts[n] = key .. "=" .. serialize(val, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "Vector3" then return "Vec3(" .. tostring(v.X) .. "," .. tostring(v.Y) .. "," .. tostring(v.Z) .. ")"
    elseif t == "CFrame" then local p = v.Position; return "CF(" .. tostring(p.X) .. "," .. tostring(p.Y) .. "," .. tostring(p.Z) .. ")"
    elseif t == "Color3" then return "Clr(" .. tostring(v.R*255) .. "," .. tostring(v.G*255) .. "," .. tostring(v.B*255) .. ")"
    elseif t == "nil" then return "nil"
    end
    return t .. "(" .. truncate(v) .. ")"
end

local function serialize_args(args)
    if not args then return "()" end
    local parts = {}
    for i = 1, math.min(#args, 12) do
        parts[i] = serialize(args[i], 0)
    end
    if #args > 12 then parts[#parts+1] = "..." end
    return "(" .. table.concat(parts, ",") .. ")"
end

local logfile = nil
local function emit(line)
    print(line)
    if logfile then
        pcall(function() appendfile(logfile, line .. "\n") end)
    end
end

local function setup_logger()
    if not CONFIG.LOG_TO_FILE then return end
    local placeName = "Game"
    local placeId = 0
    pcall(function()
        placeName = game.Name:gsub("[^%w_]", "_")
        placeId = game.PlaceId
    end)
    logfile = CONFIG.LOG_PATH .. "/" .. placeName .. "_" .. placeId .. "_spy.log"

    pcall(function() makefolder("HUKI") end)
    pcall(function() makefolder(CONFIG.LOG_PATH) end)
    pcall(function()
        writefile(logfile, "--- Luathys Remote Spy " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
    end)
end

-- State
local remotes = {}
local stats = { outgoing = 0, incoming = 0, dupes = 0 }
local last_sig = {}

local function is_game_remote(obj)
    if not obj or not obj.ClassName then return false end
    local cn = obj.ClassName
    if cn ~= "RemoteEvent" and cn ~= "RemoteFunction" and cn ~= "UnreliableRemoteEvent" then
        return false
    end
    local exclude = false
    pcall(function()
        local parent = obj
        while parent do
            if parent == game:GetService("CoreGui") then
                exclude = true
                break
            end
            parent = parent.Parent
        end
    end)
    return not exclude
end

local function hook_incoming(inst)
    if remotes[inst] then return end
    remotes[inst] = true

    if inst:IsA("RemoteEvent") and inst.OnClientEvent then
        pcall(function()
            inst.OnClientEvent:Connect(function(...)
                local ok, args = pcall(function() return table.pack(...) end)
                if not ok then return end
                stats.incoming = stats.incoming + 1
                local sig = inst:GetFullName() .. serialize_args(args)
                if CONFIG.SUPPRESS_DUPES and last_sig[inst] == sig then
                    stats.dupes = stats.dupes + 1
                    return
                end
                last_sig[inst] = sig
                emit(os.date("%H:%M:%S") .. " [IN] " .. inst:GetFullName() .. serialize_args(args))
            end)
        end)
    end
end

local function discover_remotes()
    local count = 0
    pcall(function()
        for _, obj in ipairs(game:GetDescendants()) do
            if is_game_remote(obj) then
                count = count + 1
                hook_incoming(obj)
            end
        end
    end)
    pcall(function()
        if getnilinstances then
            for _, obj in ipairs(getnilinstances()) do
                if is_game_remote(obj) then
                    count = count + 1
                    hook_incoming(obj)
                end
            end
        end
    end)
    return count
end

-- Outgoing capture via hookfunction on class methods
local function setup_outgoing_hook()
    if typeof(hookfunction) ~= "function" then
        emit("hookfunction NOT available - outgoing capture disabled")
        return false
    end

    local ok_re = false
    local ok_rf = false

    -- Hook RemoteEvent.FireServer (class-wide, self identifies the remote)
    pcall(function()
        local probe = Instance.new("RemoteEvent")
        local old = hookfunction(probe.FireServer, function(self, ...)
            if typeof(self) == "Instance" and is_game_remote(self) then
                local ok, args = pcall(function() return table.pack(...) end)
                if ok then
                    stats.outgoing = stats.outgoing + 1
                    local sig = self:GetFullName() .. serialize_args(args)
                    if CONFIG.SUPPRESS_DUPES and last_sig[self] == sig then
                        stats.dupes = stats.dupes + 1
                    else
                        last_sig[self] = sig
                        emit(os.date("%H:%M:%S") .. " [OUT] " .. self:GetFullName() .. " FireServer " .. serialize_args(args))
                    end
                end
            end
            return old(self, ...)
        end)
        ok_re = typeof(old) == "function"
        probe:Destroy()
    end)

    -- Hook RemoteFunction.InvokeServer
    pcall(function()
        local probe = Instance.new("RemoteFunction")
        local old = hookfunction(probe.InvokeServer, function(self, ...)
            if typeof(self) == "Instance" and is_game_remote(self) then
                local ok, args = pcall(function() return table.pack(...) end)
                if ok then
                    stats.outgoing = stats.outgoing + 1
                    local sig = self:GetFullName() .. ":InvokeServer"
                    if CONFIG.SUPPRESS_DUPES and last_sig[self] == sig then
                        stats.dupes = stats.dupes + 1
                    else
                        last_sig[self] = sig
                        emit(os.date("%H:%M:%S") .. " [OUT] " .. self:GetFullName() .. " InvokeServer " .. serialize_args(args))
                    end
                end
            end
            return old(self, ...)
        end)
        ok_rf = typeof(old) == "function"
        probe:Destroy()
    end)

    if ok_re then emit("Outgoing RemoteEvent.FireServer: hooked") end
    if ok_rf then emit("Outgoing RemoteFunction.InvokeServer: hooked") end

    if not (ok_re or ok_rf) then
        emit("Outgoing capture: hookfunction hooks rejected")
        emit("  -> Incoming + discovery still fully active")
    end
    return ok_re or ok_rf
end

local function setup_autoscan()
    pcall(function()
        game.DescendantAdded:Connect(function(obj)
            task.defer(function()
                pcall(function()
                    if is_game_remote(obj) then
                        hook_incoming(obj)
                        emit(os.date("%H:%M:%S") .. " [+] New remote: " .. obj:GetFullName())
                    end
                end)
            end)
        end)
    end)
end

local function main()
    setup_logger()

    pcall(function()
        if not game:IsLoaded() then game.Loaded:Wait() end
    end)
    task.wait(2)

    emit("========================================")
    emit("  Luathys Remote Spy (Safe Mode) v1.1")
    local placeName = "Unknown"
    pcall(function() placeName = game.Name end)
    emit("  Game: " .. placeName .. " (PlaceId " .. tostring(game.PlaceId) .. ")")

    local found = discover_remotes()
    emit("  Remotes discovered: " .. found)
    setup_outgoing_hook()
    setup_autoscan()
    emit("  Log: " .. tostring(logfile or "console only"))
    emit("  Play normally. All traffic is logged.")
    emit("========================================")

    while true do
        task.wait(60)
        local total = 0
        for _ in pairs(remotes) do total = total + 1 end
        emit("STATS | remotes=" .. total .. " outgoing=" .. stats.outgoing .. " incoming=" .. stats.incoming .. " dupes=" .. stats.dupes)
    end
end

if not _G.__luathys_spy_loaded then
    _G.__luathys_spy_loaded = true
    pcall(main)
else
    print("Luathys spy already loaded")
end