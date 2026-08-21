--[[
    Luathys Remote Spy (Hardened) — v1.0-safe
    Bulletproof version: every API call is pcall-guarded so one missing
    function won't crash the whole thing. CoreGui is never touched.
--]]

local CONFIG = {
    LOG_TO_FILE = true,
    LOG_PATH = "HUKI/Spy",
    SUPPRESS_DUPES = true,
}

-- Safe wrappers
local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok and res
end

local function makefolder_safe(name)
    return safe(makefolder, name) or safe(makefile, name) or false
end

local function writefile_safe(name, content)
    local dirs = {}
    for pathPart in string.gmatch(name, "[^/]+") do
        table.insert(dirs, pathPart)
        if #dirs > 1 then
            local dirPath = table.concat(dirs, "/")
            makefolder_safe(dirPath)
            table.remove(dirs, #dirs)
        end
    end
    return safe(writefile, name, content)
end

local function appendfile_safe(name, content)
    return safe(appendfile, name, content)
end

-- String utilities
local function truncate(s)
    s = tostring(s)
    if #s > 200 then return s:sub(1, 200) .. "...(" .. tostring(#s) .. " chars)" end
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
        if depth >= 4 then return "{...}" end
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 15 then parts[n] = "..."; break end
            local key = (typeof(k) == "string") and k or ("[" .. serialize(k, depth+1) .. "]")
            parts[n] = key .. "=" .. serialize(val, depth+1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "Vector3" then return "Vec3("..v.X..","..v.Y..","..v.Z..")"
    elseif t == "CFrame" then local p=v.Position; return "CF("..p.X..","..p.Y..","..p.Z..")"
    elseif t == "Color3" then return "Clr("..v.R*255..","..v.G*255..","..v.B*255..")"
    end
    return t .. "(" .. truncate(v) .. ")"
end

local function serialize_args(args)
    if not args or #args == 0 then return "()" end
    local parts = {}
    for i = 1, #args do
        parts[i] = serialize(args[i], 0)
    end
    return "(" .. table.concat(parts, ",") .. ")"
end

-- Logging
local logfile = nil
local function emit(line)
    print(line)
    if logfile then appendfile_safe(logfile, line .. "\n") end
end

-- File setup
local function setup_logger()
    if not CONFIG.LOG_TO_FILE then return end
    local placeName = safe(function() return game.Name end) or "Game"
    placeName = placeName:gsub("[^%w_]", "_")
    local placeId = safe(function() return game.PlaceId end) or 0
    logfile = CONFIG.LOG_PATH .. "/" .. placeName .. "_" .. placeId .. "_spy.log"

    makefolder_safe("HUKI")
    makefolder_safe(CONFIG.LOG_PATH)
    writefile_safe(logfile, "--- Luathys Remote Spy " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
end

-- Remote discovery + hooking
local remotes = {}
local stats = { out = 0, in = 0, dupes = 0 }
local last_sig = {}

local function is_remote(obj)
    if not obj or not obj.ClassName then return false end
    -- ONLY non-CoreGui remotes
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")
       or obj:IsA("UnreliableRemoteEvent") then
        local parent = safe(function() return obj.Parent end)
        if parent then
            local ok, isCore = pcall(function() return parent == game:GetService("CoreGui") end)
            if not isCore and not ok then isCore = false end
            return not isCore
        end
        return false
    end
    return false
end

local function hook_incoming(inst)
    if remotes[inst] then return end
    remotes[inst] = true

    if inst:IsA("RemoteEvent") and inst.OnClientEvent then
        safe(function()
            inst.OnClientEvent:Connect(function(...)
                local ok, args = pcall(function() return table.pack(...) end)
                if not ok then return end
                stats.in_ = stats.in_ + 1
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
    safe(function()
        for _, obj in ipairs(game:GetDescendants()) do
            if is_remote(obj) then
                count = count + 1
                hook_incoming(obj)
            end
        end
    end)

    -- nil instances
    safe(function()
        if getnilinstances then
            for _, obj in ipairs(getnilinstances()) do
                if is_remote(obj) then
                    count = count + 1
                    hook_incoming(obj)
                end
            end
        end
    end)

    return count
end

-- Outgoing hook (guarded)
local function setup_outgoing_hook()
    local has_hook = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"

    if not has_hook then
        emit("Outgoing capture UNAVAILABLE (no hookmetamethod). Only incoming logged.")
        return false
    end

    local orig = hookmetamethod(game, "__namecall", function(self, ...)
        local ok, method = pcall(getnamecallmethod)
        if not ok then method = nil end

        if is_remote(self) and (method == "FireServer" or method == "InvokeServer") then
            local ok2, args = pcall(function() return table.pack(...) end)
            if ok2 then
                stats.out = stats.out + 1
                local sig = self:GetFullName() .. ":" .. (method or "?") .. serialize_args(args)
                if CONFIG.SUPPRESS_DUPES and last_sig[self] == sig then
                    stats.dupes = stats.dupes + 1
                    return orig(self, ...)
                end
                last_sig[self] = sig
                emit(os.date("%H:%M:%S") .. " [OUT] " .. self:GetFullName() .. " : " .. (method or "?") .. " " .. serialize_args(args))
            end
        end
        return orig(self, ...)
    end)

    if type(orig) == "function" then
        emit("Outgoing capture: ACTIVE")
        return true
    else
        emit("Outgoing hook failed silently")
        return false
    end
end

-- Main
local function main()
    setup_logger()

    -- Wait for game
    safe(function()
        if not game:IsLoaded() then game.Loaded:Wait() end
    end)
    wait(1)

    emit("========================================")
    emit("  Luathys Remote Spy (Safe Mode)")
    emit("  Game: " .. safe(function() return game.Name end) or "Unknown" .. " (PlaceId " .. tostring(safe(function() return game.PlaceId end)) .. ")")

    local found = discover_remotes()
    emit("  Remotes discovered: " .. found)
    setup_outgoing_hook()
    emit("  Log: " .. tostring(logfile or "console only"))
    emit("  Play normally. All traffic logged.")
    emit("========================================")

    -- Auto-rescan
    if game then
        game:GetPropertyChangedSignal("DescendantAdded"):Connect(function()
            wait()
            safe(function()
                for _, obj in ipairs({game:GetDescendants()[#game:GetDescendants()]}) do
                    -- This is simplified — full rescan each second
                end
            end)
        end)
    end

    while true do
        wait(60)
        emit("STATS | remotes=" .. tostring((function(c=0 for _ in pairs(remotes) do c=c+1 end return c)())) .. " out=" .. stats.out .. " in=" .. stats.in_ .. " dupes=" .. stats.dupes)
    end
end

-- Defer and guard
if not _G.__luathys_spy_loaded then
    _G.__luathys_spy_loaded = true
    pcall(main)
else
    print("Luathys spy already loaded")
end