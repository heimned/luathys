--[[
    Luathys Remote Spy v1.0 - Passive
    Auto-discovers ALL remotes game-wide and logs traffic in both directions.
    You do nothing: run it, play the game, watch the log.

    Outgoing: hookmetamethod __namecall (catches every FireServer/InvokeServer
              the game client itself makes - no user input required)
    Incoming: OnClientEvent connected on every discovered RemoteEvent

    Output: console + HUKI/Spy/{Game}_{PlaceId}_spy.log
]]

-- ===== Config =====
local CONFIG = {
    LOG_TO_FILE   = true,
    LOG_PATH      = "HUKI/Spy",
    MAX_ARG_DEPTH = 3,        -- table recursion depth
    MAX_STR_LEN   = 200,      -- truncate long strings
    SUPPRESS_DUPES = true,    -- collapse identical repeated calls (e.g. heartbeat remotes)
    BLACKLIST     = {         -- remotes so spammy they're pure noise
        -- "SomeSpammyRemote",
    },
}

-- ===== Utils =====
local function truncate(s)
    s = tostring(s)
    if #s > CONFIG.MAX_STR_LEN then
        return s:sub(1, CONFIG.MAX_STR_LEN) .. ("...(%d chars)"):format(#s)
    end
    return s
end

local function serialize(v, depth)
    depth = depth or 0
    local t = typeof(v)

    if t == "string"   then return '"' .. truncate(v) .. '"'
    elseif t == "number" or t == "boolean" then return tostring(v)
    elseif t == "Instance" then
        local ok, path = pcall(function() return v:GetFullName() end)
        return (ok and path) or (tostring(v) .. " [dead]")
    elseif t == "table" then
        if depth >= CONFIG.MAX_ARG_DEPTH then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 20 then parts[n] = "..."; break end
            local key = (typeof(k) == "string") and k or ("[" .. serialize(k, depth + 1) .. "]")
            parts[n] = key .. " = " .. serialize(val, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Vector3" then return ("Vector3(%.2f, %.2f, %.2f)"):format(v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return ("CFrame(%.2f, %.2f, %.2f)"):format(p.X, p.Y, p.Z)
    elseif t == "Color3" then return ("Color3(%.0f, %.0f, %.0f)"):format(v.R*255, v.G*255, v.B*255)
    elseif v == nil then return "nil"
    end
    return t .. "(" .. truncate(v) .. ")"
end

local function serialize_args(args, depth)
    depth = depth or 0
    if depth >= 6 or #args == 0 then return "{}" end
    local parts = {}
    for i, v in ipairs(args) do
        parts[i] = serialize(v, 0)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- ===== File logging =====
local logfile = nil
if CONFIG.LOG_TO_FILE then
    pcall(function()
        if not isfolder("HUKI") then makefolder("HUKI") end
        if not isfolder(CONFIG.LOG_PATH) then makefolder(CONFIG.LOG_PATH) end
    end)
    local fname = CONFIG.LOG_PATH .. "/" .. (game.Name or "Game"):gsub("[^%w_]", "_") .. "_" .. game.PlaceId .. "_spy.log"
    pcall(function() writefile(fname, "-- Luathys Remote Spy log " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n") end)
    logfile = fname
end

local function emit(line)
    print(line)
    if logfile then pcall(function() appendfile(logfile, line .. "\n") end) end
end

-- ===== Remote discovery (whole DataModel, incl. nil instances) =====
local remotes = {}   -- Instance -> true
local stats = { outgoing = 0, incoming = 0, dupes = 0 }
local last_sig = {}

local function is_remote(inst)
    local cn = inst.ClassName
    return cn == "RemoteEvent" or cn == "RemoteFunction"
        or cn == "UnreliableRemoteEvent" or cn == "BindableEvent" or cn == "BindableFunction"
end

local function hook_remote(inst)
    if remotes[inst] then return end
    remotes[inst] = true

    -- Incoming: server -> client
    if inst:IsA("RemoteEvent") then
        pcall(function()
            inst.OnClientEvent:Connect(function(...)
                stats.incoming = stats.incoming + 1
                local args = table.pack(...)
                local sig = "IN|" .. inst:GetFullName() .. "|" .. serialize_args(args, 0)
                if CONFIG.SUPPRESS_DUPES and sig == last_sig[inst] then
                    stats.dupes = stats.dupes + 1
                    return
                end
                last_sig[inst] = sig
                emit(("[IN ] %s %s"):format(os.date("%H:%M:%S"), sig))
            end)
        end)
    elseif inst:IsA("UnreliableRemoteEvent") then
        pcall(function()
            inst.OnClientEvent:Connect(function(...)
                stats.incoming = stats.incoming + 1
                local args = table.pack(...)
                emit(("[INu] %s %s %s"):format(os.date("%H:%M:%S"), inst:GetFullName(), serialize_args(args, 0)))
            end)
        end)
    end
end

local function scan_all()
    local n = 0
    -- Every descendant of every service the client can see
    pcall(function()
        for _, inst in ipairs(game:GetDescendants()) do
            if is_remote(inst) and not CONFIG.BLACKLIST[inst.Name] then
                hook_remote(inst)
                n = n + 1
            end
        end
    end)
    -- Parented-to-nil remotes (common hiding spot)
    pcall(function()
        if getnilinstances then
            for _, inst in ipairs(getnilinstances()) do
                if is_remote(inst) then
                    hook_remote(inst)
                    n = n + 1
                end
            end
        end
    end)
    return n
end

-- Catch remotes created after startup (streaming, dynamic spawns)
game.DescendantAdded:Connect(function(inst)
    if is_remote(inst) then
        task.defer(hook_remote, inst)
        emit(("[+]  %s New remote appeared: %s"):format(os.date("%H:%M:%S"), inst:GetFullName()))
    end
end)

-- ===== Outgoing hook: catches ALL FireServer/InvokeServer game-wide =====
-- Capability check: some executors lost hook support after Roblox updates.
local HAS_NAMECALL_HOOK = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
local HAS_CONNECTIONS = type(getconnections) == "function"

local old_namecall
if HAS_NAMECALL_HOOK then
old_namecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local is_outgoing = (method == "FireServer" and self:IsA("RemoteEvent"))
        or (method == "InvokeServer" and (self:IsA("RemoteFunction") or self:IsA("RemoteEvent")))
        or (method == "FireServer" and self:IsA("UnreliableRemoteEvent"))
    if is_outgoing then
        if not CONFIG.BLACKLIST[self.Name] then
            local args = table.pack(...)
            if args then
                stats.outgoing = stats.outgoing + 1
                local sig = "OUT|" .. tostring(self) .. "|" .. method .. "|" .. serialize_args(args, 0)
                if not (CONFIG.SUPPRESS_DUPES and sig == last_sig[self]) then
                    last_sig[self] = sig
                    emit(("[OUT] %s %s %s %s"):format(
                        os.date("%H:%M:%S"),
                        (pcall(function() return self:GetFullName() end)) and self:GetFullName() or tostring(self),
                        method,
                        serialize_args(args, 0)))
                else
                    stats.dupes = stats.dupes + 1
                end
            end
        end
    end
    return old_namecall(self, ...)
end)
end
-- ===== Startup =====
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(2)  -- let streaming content in

    local found = scan_all()
    emit("========================================")
    emit("  Luathys Remote Spy v1.0 - passive")
    emit("  Game: " .. game.Name .. " (PlaceId " .. game.PlaceId .. ")")
    emit("  Remotes hooked: " .. found)
    emit("  Log file: " .. (logfile or "console only"))
    if HAS_NAMECALL_HOOK then
        emit("  Outgoing capture: ACTIVE (namecall hook)")
    else
        emit("  Outgoing capture: UNAVAILABLE (executor has no namecall hook)")
        emit("  -> Incoming [IN] traffic + full remote discovery still work")
    end
    emit("  Play normally - all traffic is logged.")
    emit("========================================")

    -- Re-scan periodically for streamed-in remotes, report stats
    while true do
        task.wait(60)
        local total = 0
        for _ in pairs(remotes) do total = total + 1 end
        emit(("[STAT] %d remotes | OUT:%d IN:%d dupes-suppressed:%d"):format(
            total, stats.outgoing, stats.incoming, stats.dupes))
    end
end)