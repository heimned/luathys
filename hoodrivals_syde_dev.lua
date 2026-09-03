--[[
    Ospei Hood Rivals  v1.5-dev (Syde UI)
    Dev version: same logic core as hoodrivals.lua, UI replaced with
    the Syde library (essencejs/syde) via a patched loader that fixes
    the repo's asset/source mismatch (modal.Buttons, slider.Title).

    PlaceIds 77463332823746, 113272123504853 (multi-place: runs wherever
    the loader maps a Hood Rivals place).

    This file is a DEVELOPMENT version - it does not touch the shipped
    hoodrivals.lua. Load it from your executor like any single script.

    USAGE:
      LocalPlayer / executor -> paste & run, or:
      loadstring(game:HttpGet("https://raw.githubuser" ..
        "content.com/<your-host>/hoodrivals_syde_dev.lua", true))()
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- RE-RUN GUARD: if a previous instance of this script is still alive
-- (e.g. the window was closed via Syde's X button before the patch that
-- routes it through the unload, or an older copy ran), tear it down
-- BEFORE we fetch services, patch modules, or build a new UI. Without
-- this, re-running stacks a zombie instance (old aim loop, ESP, WMI
-- patches still live) under the fresh one -> UI auto-closes + console spam.
do
    local prevUnload = _G.Ospei_HoodRivals_Unload
    if type(prevUnload) == "function" then
        local ok, err = pcall(prevUnload)
        if not ok then
            warn("[Ospei] previous instance unload error: " .. tostring(err))
        end
        task.wait(0.6) -- let its connections/patches fully release
    end
end

-- cloneref: executor instance-reference tracking can cause require() to
-- return a DIFFERENT table than the one the game's own scripts see. Cloning
-- the reference before require() forces the cache to hit the real module
-- table so our patches (Weapon_Module.UpdateAmmo counter, etc.) actually
-- reach the game's code. Applied to all services for consistency.
local cloneRef
if typeof(cloneref) == "function" then
    cloneRef = function(x)
        local ok, r = pcall(cloneref, x)
        return ok and r or x
    end
else
    cloneRef = function(x) return x end
end

local Players          = cloneRef(game:GetService("Players"))
local RunService       = cloneRef(game:GetService("RunService"))
local UserInputService = cloneRef(game:GetService("UserInputService"))
local TweenService     = cloneRef(game:GetService("TweenService"))
local HttpService      = cloneRef(game:GetService("HttpService"))
local Workspace        = cloneRef(game:GetService("Workspace"))
local GuiService       = cloneRef(game:GetService("GuiService"))
local LocalPlayer      = Players.LocalPlayer
local CoreGui          = cloneRef((typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui"))

-- the Camera can be recreated by the engine mid-session; never cache it
local function getCamera()
    return Workspace.CurrentCamera
end

-- Ospei house palette (single source of truth: shared/palette.lua, embedded
-- copy in games/football-fusion/modules/qbaimbot.lua). Reads the shared
-- palette when this suite runs fused; falls back to the same values standalone.
local SP = (typeof(getgenv) == "function" and getgenv().Ospei_Palette) or {}
local function pick(c, fb) return c or fb end
local P = {
    -- surfaces (house: OuterBg / InnerBg / TrackBg / PanelAlt / BtnActive)
    Bg0   = pick(SP.OuterBg,   Color3.fromRGB(16, 17, 21)),   -- window shell
    Bg1   = pick(SP.InnerBg,   Color3.fromRGB(26, 28, 34)),   -- header/footer strips
    Well  = pick(SP.TrackBg,   Color3.fromRGB(20, 22, 28)),   -- value pills, tracks
    Hover = pick(SP.PanelAlt,  Color3.fromRGB(24, 26, 32)),   -- row hover
    Bg2   = pick(SP.BtnActive, Color3.fromRGB(27, 36, 52)),   -- pressed fills
    -- strokes (house: InnerStroke / OuterStroke)
    Line  = pick(SP.InnerStroke, Color3.fromRGB(36, 39, 48)), -- hairline rules
    Line2 = pick(SP.OuterStroke, Color3.fromRGB(42, 45, 55)), -- control strokes / unlit
    -- text tiers (house: Text / TextMuted / DescMuted / Hint)
    FgHi  = pick(SP.Text,      Color3.fromRGB(255, 255, 255)), -- title
    Fg    = pick(SP.TextMuted, Color3.fromRGB(200, 204, 215)), -- values
    Dim   = pick(SP.DescMuted, Color3.fromRGB(169, 173, 187)), -- row labels
    Faint = pick(SP.Hint,      Color3.fromRGB(120, 125, 140)), -- captions, idle
    -- steppers (house: StepperBg / StepperHover)
    StepperBg    = pick(SP.StepperBg,    Color3.fromRGB(30, 33, 40)),
    StepperHover = pick(SP.StepperHover, Color3.fromRGB(40, 44, 55)),
    -- accent + states (house: AccentBlue / TierBalanced / TierBlatant)
    Accent  = pick(SP.AccentBlue,   Color3.fromRGB(160, 205, 255)),
    Ice     = Color3.fromRGB(74, 144, 226), -- ESP visible-target accent
    Success = Color3.fromRGB(106, 220, 130), -- no house token; v1.0 value
    Danger  = pick(SP.TierBlatant,  Color3.fromRGB(255, 82, 82)),
    Warn    = pick(SP.TierBalanced, Color3.fromRGB(255, 183, 77)),
}

local LOGO_ID = (SP and SP.AssetLogo) or "rbxassetid://71068731540117"

----------------------------------------------------------------
-- BOOT TOAST - 2-line capsule (logo + brand over one status line),
-- fades in, dismisses after 2s. No progress bar, no pulse effects.
-- Runs async so it never blocks startup.
----------------------------------------------------------------
do
    local lastToastAt = 0
    local function ShowBootToast()
        if os.clock() - lastToastAt < 12 then return end
        lastToastAt = os.clock()

        local existing = CoreGui:FindFirstChild("OspeiBootToast")
        if existing then return end

        local gui = Instance.new("ScreenGui")
        gui.Name = "OspeiBootToast"
        gui.DisplayOrder = 997
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.Parent = CoreGui

        local canvas = Instance.new("CanvasGroup")
        canvas.Name = "ToastCanvas"
        canvas.AnchorPoint = Vector2.new(1, 1)
        canvas.Position = UDim2.new(1, -8, 1, -20)
        canvas.Size = UDim2.fromOffset(228, 56)
        canvas.BackgroundTransparency = 1
        canvas.GroupTransparency = 1
        canvas.Parent = gui

        local card = Instance.new("Frame")
        card.Size = UDim2.fromScale(1, 1)
        card.BackgroundColor3 = P.Bg0
        card.BorderSizePixel = 0
        card.Parent = canvas
        local cardCorner = Instance.new("UICorner", card)
        cardCorner.CornerRadius = UDim.new(0, 6)
        local cardStroke = Instance.new("UIStroke", card)
        cardStroke.Color = P.Line
        cardStroke.Thickness = 1
        cardStroke.Transparency = 0.35

        local logo = Instance.new("ImageLabel")
        logo.AnchorPoint = Vector2.new(0, 0.5)
        logo.Position = UDim2.new(0, 8, 0.5, 0)
        logo.Size = UDim2.fromOffset(40, 40)
        logo.BackgroundTransparency = 1
        logo.Image = LOGO_ID
        logo.ImageColor3 = P.Accent
        logo.ScaleType = Enum.ScaleType.Fit
        logo.Parent = card

        local brand = Instance.new("TextLabel")
        brand.Position = UDim2.new(0, 56, 0, 10)
        brand.Size = UDim2.new(1, -66, 0, 14)
        brand.BackgroundTransparency = 1
        brand.Font = Enum.Font.RobotoMono
        brand.Text = "OSPEI"
        brand.TextSize = 12
        brand.TextColor3 = P.FgHi
        brand.TextXAlignment = Enum.TextXAlignment.Left
        brand.Parent = card

        local status = Instance.new("TextLabel")
        status.Position = UDim2.new(0, 56, 0, 30)
        status.Size = UDim2.new(1, -66, 0, 12)
        status.BackgroundTransparency = 1
        status.Font = Enum.Font.RobotoMono
        status.Text = "loading suite . . ."
        status.TextSize = 10
        status.TextColor3 = P.Dim
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.Parent = card

        TweenService:Create(canvas, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            GroupTransparency = 0,
            Position = UDim2.new(1, -24, 1, -24),
        }):Play()

        task.wait(0.9)
        if gui and gui.Parent then
            status.Text = "ready"
            status.TextColor3 = P.Accent
        end
        task.wait(1.1)
        if gui and gui.Parent then
            local outT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            TweenService:Create(canvas, outT, { GroupTransparency = 1, Position = UDim2.new(1, -8, 1, -20) }):Play()
            task.wait(0.35)
            if gui and gui.Parent then gui:Destroy() end
        end
    end

    -- synchronous: the toast plays first, then the rest of the script
    -- (including the main panel) builds after it
    pcall(ShowBootToast)
end

-- Config (defaults)
local CFG = {
    aimStyle       = "Off",     -- Off / Assist / Silent
    targetPart     = "Auto",     -- Auto (LOS cascade) / Head / Chest / Body
    triggerBot     = false,
    teamCheck      = true,
    wallCheck      = true,
    fovEnabled     = true,
    fovRadius      = 35,        -- degrees
    lead           = 1.0,       -- lead strength scalar
    assistStrength = 0.35,
    noRecoil       = false,
    noSpread       = false,
    flight         = false,
    flightSpeed    = 50,
    speed          = false,
    speedValue     = 32,
    noClip         = false,
    enemyHl        = true,
    teamHl         = false,
    npcHl          = false,
    hlTrans        = 0.4,
    healthBars     = true,
    nameTags       = false,
    nameDist       = true,
    autoJump       = false,
    hitmarker      = false,
    crossStyle     = "Off",     -- Off / Dot / Cross
    crossSize      = 5,
    aimCurve       = "Linear",  -- Linear / EaseIn / EaseOut / SCurve
    rapidFire      = false,
    tracer         = false,
    infiniteAmmo   = false,
    autoReload     = false,
    noShake        = false,
    infHealth      = false,
    infArmor       = false,
    armorValue     = 100,
    antiRagdoll    = false,
    autoMedkit     = false,
    medkitHP       = 100,
    cashEsp        = false,
    autoCash       = false,
}

local AIM_CYCLE = { "Off", "Assist", "Silent" }
local CURVE_CYCLE = { "Linear", "EaseIn", "EaseOut", "S-Curve" }
local CROSS_STYLES = { "Off", "Dot", "Cross" }
local PART_MAP  = { Auto = "Head", Head = "Head", Chest = "UpperTorso", Body = "HumanoidRootPart" }
local MAX_AIM_DIST = 300
local TRIGGER_COOLDOWN = 0.12

local Runtime = { live = true, Connections = {}, ESP = {}, Cards = {}, savedCollide = {}, NPC = {}, Cash = {} }
local locked, losLastOk = nil, 0
local velocityHistory = {}
local SAMPLE_WINDOW = 0.12
local lastTrigger = 0
local espTick = 0

local function connect(sig, fn)
    local c = sig:Connect(fn); table.insert(Runtime.Connections, c); return c
end

----------------------------------------------------------------
-- CONFIG PERSISTENCE (in-memory only: getgenv cache, zero files)
-- Settings survive script reloads in the session but nothing is ever
-- written to the executor workspace.
----------------------------------------------------------------
local CFG_KEY = "Ospei_HoodRivals_Cfg"
local CFG_STORE = (typeof(getgenv) == "function" and getgenv()[CFG_KEY]) or nil
local function saveCfg()
    if typeof(getgenv) ~= "function" then return end
    local store = {}
    for k, v in pairs(CFG) do store[k] = v end
    getgenv()[CFG_KEY] = store
end
local function loadCfg()
    if not (CFG_STORE and type(CFG_STORE) == "table") then return end
    for k, v in pairs(CFG_STORE) do
        if CFG[k] ~= nil and type(CFG[k]) == type(v) then
            CFG[k] = v
        end
    end
end
loadCfg()

-- validate loaded enum-ish values against the UI's option tables
if not table.find(AIM_CYCLE, CFG.aimStyle) then CFG.aimStyle = "Off" end
if not PART_MAP[CFG.targetPart] then CFG.targetPart = "Auto" end
if not table.find(CURVE_CYCLE, CFG.aimCurve) then CFG.aimCurve = "Linear" end
if not table.find(CROSS_STYLES, CFG.crossStyle) then CFG.crossStyle = "Off" end

----------------------------------------------------------------
-- TARGETING
----------------------------------------------------------------
-- ring size is authored in degrees (matches the on-screen ring); targeting
-- and the ring both resolve it to pixels against the current FOV
local function fovPixels()
    local cam = getCamera()
    if not cam then return 0 end
    local vp = cam.ViewportSize
    local r = math.tan(math.rad(CFG.fovRadius))
        / math.tan(math.rad(cam.FieldOfView / 2)) * (vp.Y / 2)
    return math.clamp(r, 10, vp.Y)
end

-- true crosshair position in WorldToScreenPoint space (that space sits
-- GuiInset below the window center the ring is drawn at)
local function crosshairPoint()
    local cam = getCamera()
    if not cam then return Vector2.zero end
    local vp = cam.ViewportSize
    return Vector2.new(vp.X / 2, vp.Y / 2 - GuiService:GetGuiInset().Y)
end
local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    local char = plr.Character
    if not char or not char:FindFirstChildOfClass("Humanoid") then return false end
    if CFG.teamCheck and plr.Team ~= nil and plr.Team == LocalPlayer.Team then return false end
    return true
end

local function hasLineOfFire(char, part)
    if not CFG.wallCheck then return true end
    local cam = getCamera()
    if not cam then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local exclude = {}
    if LocalPlayer.Character then exclude[#exclude + 1] = LocalPlayer.Character end
    exclude[#exclude + 1] = char
    params.FilterDescendantsInstances = exclude
    -- the target's own body is excluded, so any hit is a real obstruction
    return Workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, params) == nil
end

local function getAimPart(char)
    local name = PART_MAP[CFG.targetPart] or "HumanoidRootPart"
    if name == "UpperTorso" then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild(name)
end

-- Auto part mode: prefer the head, fall back through chest to body until a
-- part actually has line of fire. Wall-heavy fights still land hits instead
-- of dead-heading into cover the head check fails on.
local AUTO_PARTS = { "Head", "UpperTorso", "HumanoidRootPart" }
local function refineAimPart(char, base)
    if CFG.targetPart ~= "Auto" or not base then return base end
    if CFG.wallCheck then
        for _, name in ipairs(AUTO_PARTS) do
            local p = char:FindFirstChild(name)
            if p and hasLineOfFire(char, p) then return p end
        end
        return base
    end
    return char:FindFirstChild("Head") or base
end

-- nearest-to-crosshair enemy inside the FOV ring; sticky on the current
-- target with a short LOS grace so cover flickers don't drop the lock.
-- The FOV ring gates ACQUISITION only: once locked, we keep tracking the
-- current target even if they drift outside the ring — the ring is not a
-- reason to drop a lock and snap to someone else while you're on them.
-- The lock only releases when the target is invalid / out of range / out
-- of LOS too long, or when the user clearly drags the crosshair far off
-- the target (deliberate switch), not because of the FOV ring.
local LOS_GRACE = 0.15 -- seconds of blind-tracking before the lock drops
local function pickTarget()
    if locked and locked.Parent then
        local part = getAimPart(locked)
        local hum = locked:FindFirstChildOfClass("Humanoid")
        local plr = Players:GetPlayerFromCharacter(locked)
        if part and hum and hum.Health > 0 and plr and isEnemy(plr) then
            local sp = getCamera():WorldToScreenPoint(part.Position)
            local dist = (Vector2.new(sp.X, sp.Y) - crosshairPoint()).Magnitude
            -- keep the lock as long as the target is in FRONT of the camera,
            -- within max range, and the user hasn't deliberately dragged the
            -- crosshair far off them (>= 35% of the viewport height away).
            -- The FOV ring does NOT apply here.
            local vp = getCamera().ViewportSize
            local releaseDist = math.max(vp.Y * 0.35, 120)
            if sp.Z > 0 and dist <= releaseDist
                and (part.Position - getCamera().CFrame.Position).Magnitude <= MAX_AIM_DIST then
                if hasLineOfFire(locked, part) then
                    losLastOk = os.clock()
                end
                if os.clock() - losLastOk <= LOS_GRACE then
                    return locked, refineAimPart(locked, part)
                end
            end
        end
    end
    locked, losLastOk = nil, 0

    local center = crosshairPoint()
    local ring = fovPixels()
    local best, bestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) then
            local part = getAimPart(plr.Character)
            if part then
                -- Lua 5.1: no `continue`; wrap the rest of the body in the
                -- inverted distance guard instead.
                if (part.Position - getCamera().CFrame.Position).Magnitude <= MAX_AIM_DIST then
                    local sp, onScreen = getCamera():WorldToScreenPoint(part.Position)
                    if onScreen and sp.Z > 0 then
                        local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if dist < ring and dist < bestDist and hasLineOfFire(plr.Character, part) then
                            best, bestDist = plr.Character, dist
                        end
                    end
                end
            end
        end
    end
    if best then
        locked = best
        losLastOk = os.clock()
    end
    return best, best and refineAimPart(best, getAimPart(best)) or nil
end

----------------------------------------------------------------
-- LEAD PREDICTION (rolling velocity window + ping horizon)
----------------------------------------------------------------
local function recordVelocity(char)
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local now = tick()
    local hist = velocityHistory[char] or {}
    local pruned = {}
    for _, s in ipairs(hist) do
        if now - s.t <= SAMPLE_WINDOW then pruned[#pruned + 1] = s end
    end
    pruned[#pruned + 1] = { vel = root.AssemblyLinearVelocity, t = now }
    velocityHistory[char] = pruned
end

local function predictedPosition(char, part)
    local hist = velocityHistory[char]
    if not hist or #hist == 0 then return part.Position end
    -- exponential recency weighting: the newest velocity sample dominates,
    -- so a turning target isn't led along its old heading
    local sum, wsum = Vector3.zero, 0
    local newest = hist[#hist].t
    for _, s in ipairs(hist) do
        local w = 0.5 ^ ((newest - s.t) / SAMPLE_WINDOW)
        sum = sum + s.vel * w
        wsum = wsum + w
    end
    local avgVel = sum / math.max(wsum, 1e-6)
    -- GetNetworkPing is ROUND-TRIP; the shot only waits one-way latency
    -- (+ one frame). Hitting the full RTT over-leads by ~2x and walks
    -- every shot off the hitbox on strafing targets.
    local horizon = (LocalPlayer:GetNetworkPing() / 2) + (1 / 60)
    local offset = avgVel * horizon * CFG.lead
    -- SimpleCast resolves near-instantly: damp vertical lead (jump/fall
    -- jitter) and cap the total offset to stay inside the hitbox
    offset = Vector3.new(offset.X, offset.Y * 0.25, offset.Z)
    if offset.Magnitude > 1.25 then offset = offset.Unit * 1.25 end
    return part.Position + offset
end

----------------------------------------------------------------
-- AIM CORE
----------------------------------------------------------------
-- Assist: frame-rate-independent camera pull toward the predicted point
local function assistStep(dt)
    if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        locked, losLastOk = nil, 0
        return
    end
    local char, part = pickTarget()
    if not (char and part) then return end
    recordVelocity(char)
    local cam = getCamera()
    if not cam then return end
    local desired = CFrame.new(cam.CFrame.Position, predictedPosition(char, part))
    local raw = math.clamp(CFG.assistStrength * dt * 10, 0, 1)
    -- error-scaled pull: full strength while far off-target, ramped down as
    -- the crosshair closes in (a fixed alpha oscillates around the target
    -- and reads as jitter at close angular error)
    local look = cam.CFrame.LookVector
    local dir = desired.LookVector
    local errDeg = math.deg(math.acos(math.clamp(look:Dot(dir), -1, 1)))
    local ramp = math.clamp(errDeg / 14, 0.12, 1)
    local curve = CFG.aimCurve
    local alpha = raw * ramp
    if curve == "EaseIn" then
        alpha = alpha * alpha
    elseif curve == "EaseOut" then
        alpha = 1 - (1 - alpha) * (1 - alpha)
    elseif curve == "S-Curve" then
        alpha = alpha * alpha * (3 - 2 * alpha)
    end
    cam.CFrame = cam.CFrame:Lerp(desired, alpha)
end

-- Silent: human-curve flick (quadratic bezier, bowed perpendicular, fast
-- start / slow landing), aimed at the prediction
local flick = nil
local function silentStep(dt)
    if not mousemoverel then return end
    if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        flick = nil
        return
    end
    local char, part = pickTarget()
    if not (char and part) then flick = nil; return end
    recordVelocity(char)
    local cam = getCamera()
    if not cam then return end
    local plr = Players:GetPlayerFromCharacter(char)
    local sp = cam:WorldToScreenPoint(plr and predictedPosition(char, part) or part.Position)
    local targetPos = Vector2.new(sp.X, sp.Y)
    local mouse = LocalPlayer:GetMouse()
    if not mouse then return end
    local cur = Vector2.new(mouse.X, mouse.Y)

    -- (re)start the flick when the target drifts or on a fresh press
    if not flick or (flick.target - targetPos).Magnitude > 8 then
        local dif = targetPos - cur
        local len = dif.Magnitude
        local perp = len > 1 and Vector2.new(-dif.Y / len, dif.X / len) or Vector2.zero
        local arc = (math.random() * 24 + 8) * (math.random() < 0.5 and -1 or 1)
        flick = {
            start = cur,
            target = targetPos,
            ctrl = cur:Lerp(targetPos, 0.5) + perp * arc,
            t = 0,
        }
    end
    local f = flick
    -- dt-scaled decay of the per-frame `t += (1-t)*0.5` (60 fps parity)
    f.t = math.min(1, f.t + (1 - f.t) * math.clamp(dt * 30, 0, 1))
    local it = 1 - f.t
    local bez = f.start * (it * it) + f.ctrl * (2 * it * f.t) + f.target * (f.t * f.t)
    local dx, dy = bez.X - cur.X, bez.Y - cur.Y
    if Vector2.new(dx, dy).Magnitude > 1.2 then
        mousemoverel(dx, dy)
    end
end

local function triggerStep()
    if not mouse1click then return end
    local now = os.clock()
    if now - lastTrigger < TRIGGER_COOLDOWN then return end
    local char, part = pickTarget()
    if char and part then
        lastTrigger = now
        pcall(mouse1click)
    end
end

----------------------------------------------------------------
-- MOVEMENT (velocity flight/speed + CanCollide-cache noclip)
----------------------------------------------------------------
-- cached BaseParts (root excluded) so noclip doesn't walk descendants per
-- frame; rebuilt on toggle-on + ~1/s while active to catch streamed parts
local collideParts = {}
local collideCacheAt = 0
local function rebuildCollideCache()
    table.clear(collideParts)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not (char and root) then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part ~= root then
            collideParts[#collideParts + 1] = part
        end
    end
end

local function applyNoClip(enabled)
    if enabled then
        rebuildCollideCache()
        for _, part in ipairs(collideParts) do
            if Runtime.savedCollide[part] == nil then
                Runtime.savedCollide[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    else
        for part, was in pairs(Runtime.savedCollide) do
            if part.Parent then part.CanCollide = was end
            Runtime.savedCollide[part] = nil
        end
    end
end

local function movementStep()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not (char and root) then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health > 0) then return end

    if CFG.noClip then
        if os.clock() - collideCacheAt > 1 then
            collideCacheAt = os.clock()
            rebuildCollideCache()
        end
        for _, part in ipairs(collideParts) do
            if Runtime.savedCollide[part] == nil then
                Runtime.savedCollide[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end

    if CFG.autoJump and hum.FloorMaterial ~= Enum.Material.Air
        and hum.MoveDirection.Magnitude > 0.1 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end

    local move = hum.MoveDirection
    if CFG.flight then
        -- MoveDirection is already world-space; rebuilding it from camera
        -- vectors would rotate the input by the camera yaw
        local vel = Vector3.new(move.X, 0, move.Z) * CFG.flightSpeed
        local up = (UserInputService:IsKeyDown(Enum.KeyCode.Space) and CFG.flightSpeed)
            or (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and -CFG.flightSpeed) or 0
        root.AssemblyLinearVelocity = Vector3.new(vel.X, up, vel.Z)
    elseif CFG.speed and move.Magnitude > 0.1 then
        root.AssemblyLinearVelocity = move * CFG.speedValue
    end
end

----------------------------------------------------------------
-- TRACER (short-lived Beam; pcall-guarded, never breaks callers)
----------------------------------------------------------------
local lastTracer = 0
local function spawnTracer(vector, dir)
    -- throttle: with rapid fire + mods stacked the Fire hook and the
    -- aim-loop can both fire every frame; one beam every 0.1s keeps
    -- it readable instead of a wall of light
    local now = os.clock()
    if now - lastTracer < 0.1 then return end
    lastTracer = now
    pcall(function()
        local start = vector or (getCamera() and getCamera().CFrame.Position)
        if not start then return end
        local part = Instance.new("Part")
        part.Name = "OspeiTracer"
        part.Size = Vector3.new(0.2, 0.2, 0.2)
        part.Transparency = 1
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Parent = Workspace
        local a0 = Instance.new("Attachment", part)
        a0.WorldPosition = start
        local a1 = Instance.new("Attachment", part)
        a1.WorldPosition = start + (dir and dir.Unit or Vector3.new(0, 0, -1)) * 300
        local beam = Instance.new("Beam", part)
        beam.Attachment0 = a0
        beam.Attachment1 = a1
        beam.Color = ColorSequence.new(P.Accent)
        beam.Transparency = NumberSequence.new(0.15)
        beam.Width0 = 0.35
        beam.Width1 = 0.05
        beam.LightEmission = 0.6
        task.spawn(function()
            for i = 1, 10 do
                beam.Transparency = NumberSequence.new(0.15 + i * 0.085)
                task.wait(0.02)
            end
            pcall(function() part:Destroy() end)
        end)
    end)
end

----------------------------------------------------------------
-- WEAPON PIPELINE (post-decompile 2026-08-30): Hood Rivals' real
-- recoil/spread/rate live in Weapon_Module + SimpleCast + WeaponData
-- module tables, NOT tool Stats values. We patch the shared tables -
-- require() caches, so the gun scripts see our patched versions.
----------------------------------------------------------------
local WMI = (function()
    local api = {}
    local okWM, WM = pcall(require, cloneRef(game.ReplicatedStorage.Weapon_Module))
    local okSC, SC = pcall(require, cloneRef(game.ReplicatedStorage.SimpleCast))
    local okWD, WD = pcall(require, cloneRef(game.ReplicatedStorage.WeaponData))
    local origRecoil = okWM and WM.recoil
    local origFire = okSC and SC.Fire
    local origShake = okWM and WM.ScreenShake
    local origRates = {}
    if okWD and type(WD) == "table" then
        for name, cfg in pairs(WD) do
            if type(cfg) == "table" and type(cfg.FireRate) == "number" then
                origRates[name] = cfg.FireRate
            end
        end
    end

    local function applyRecoil(on)
        if not okWM or not origRecoil then return end
        WM.recoil = on and function() end or origRecoil
        if on then
            -- legacy ValueObject recoil (old pipeline); zero once at toggle
            -- time instead of polling ReplicatedStorage every frame
            local mv = game.ReplicatedStorage:FindFirstChild("Weapon_Module")
            local rv = mv and mv:FindFirstChild("Recoil")
            if rv and rv.Value ~= Vector3.new(0, 0, 0) then
                rv.Value = Vector3.new(0, 0, 0)
            end
        end
    end

    local function applyShake(on)
        if not okWM or not origShake then return end
        WM.ScreenShake = on and function() end or origShake
    end

    local function applyFireMods()
        if not okSC or not origFire then return end
        -- wrapper applies noSpread / tracer. Shot counting moved to the
        -- Weapon_Module.UpdateAmmo wrapper (the SimpleCast instance's Fire
        -- goes through a prototype chain that may bypass this module table).
        SC.Fire = function(self, vector, dir, speed, behavior)
            if CFG.noSpread and behavior and behavior.SpreadAngle then
                behavior.SpreadAngle = 0
            end
            local result = origFire(self, vector, dir, speed, behavior)
            if CFG.tracer then
                spawnTracer(vector, dir)
            end
            return result
        end
    end

    -- original tool Stats.FireRate per gun name. Captured the first time we
    -- see each gun so toggling off restores the true rate even after the
    -- WeaponData module has been patched.
    local origToolRates = {}

    local function applyRapid(on)
        if not okWD then return end
        for name, rate in pairs(origRates) do
            local cfg = WD[name]
            if cfg then
                cfg.FireRate = on and math.max(0.02, rate * 0.35) or rate
            end
        end
        -- live: FirearmLocal gates the fire loop on the TOOL's own Stats
        -- (var2.Stats.FireRate.Value), which is populated from WeaponData at
        -- equip time. Patch the held tool directly so the current gun speeds
        -- up immediately instead of waiting for a re-equip, and restore it
        -- when toggled off.
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if tool then
            local stats = tool:FindFirstChild("Stats")
            local fr = stats and stats:FindFirstChild("FireRate")
            if fr and (fr:IsA("NumberValue") or fr:IsA("IntValue")) then
                local name = tool.Name
                if origToolRates[name] == nil then
                    origToolRates[name] = origRates[name] or fr.Value
                end
                fr.Value = on and math.max(0.02, origToolRates[name] * 0.35) or origToolRates[name]
            end
        end
    end

    -----------------------------------------------------------------
    -- AMMO / RELOAD (decompile-verified 2026-08-31): the SERVER keeps its
    -- own ammo counter and only refills through the reload flow. The
    -- game's own Reload() (triggered when ClipSize <= 0 on a trigger pull)
    -- fires the reload remote FOR us, plays the animation, and the server
    -- refills. So we never fire the remote ourselves - we just drop ClipSize
    -- to 0 when the pellet count hits the magazine cap, and let the game's
    -- auto-reload handle everything. Refill replicates back to cap, which
    -- re-arms the cycle. The key rule: never fire the reload remote more
    -- than once per magazine (doing so keeps resetting the server's reload
    -- timer, preventing the refill from ever landing).
    -----------------------------------------------------------------
    -- shot counter: rides the game's own UpdateAmmo call (decompile line 554:
    -- Weapon_Module.UpdateAmmo(var2) fires after every shot). We count only
    -- while the cycle is ARMED (shooting) - reload-time UpdateAmmo calls
    -- (line 421) and server HUD refreshes land while disarmed and are
    -- naturally excluded. Any miscount drifts EARLY (reload before the
    -- server is truly empty), which is safe: an early reload never causes
    -- a no-damage window. Declared before the wrapper closes over it.
    local cycleArmed = true
    local countedTool = nil
    local cycleTimeout = 0
    local shotCount = 0
    local lastReloadT = 0
    local origUpdateAmmo = okWM and WM.UpdateAmmo
    if okWM and origUpdateAmmo then
        WM.UpdateAmmo = function(...)
            if cycleArmed then
                shotCount = shotCount + 1
            end
            return origUpdateAmmo(...)
        end
    end

    local function ammoStep()
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if not tool then return end
        local stats = tool:FindFirstChild("Stats")
        if not stats then return end
        local clip = stats:FindFirstChild("ClipSize")
        if not clip then return end
        local orig = stats:FindFirstChild("Original") or clip:FindFirstChild("Original")
        if not orig then return end
        local cap = math.max(1, math.floor(orig.Value))

        if countedTool ~= tool then
            countedTool = tool
            shotCount = 0
            cycleTimeout = 0
        end

        if not cycleArmed then
            -- the game's reload is running; once the server refill lands
            -- (ClipSize back at cap) the cycle re-arms. If it never lands
            -- (server ignored the reload), a safety timeout at 8s re-arms
            -- so the user can keep firing.
            if clip.Value >= cap then
                cycleArmed = true
            elseif os.clock() > cycleTimeout then
                cycleArmed = true
            end
            return
        end

        if shotCount >= cap then
            shotCount = 0
            cycleArmed = false
            cycleTimeout = os.clock() + 8
            clip.Value = 0
            return
        end
        clip.Value = cap
    end

    -- per-frame re-apply for the held tool: the game populates a freshly
    -- equipped tool's Stats from the server, so re-pin the FireRate each
    -- frame while the toggle is on (covers weapon switches).
    local function rapidStep()
        if not CFG.rapidFire then return end
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if not tool then return end
        local stats = tool:FindFirstChild("Stats")
        local fr = stats and stats:FindFirstChild("FireRate")
        if fr and (fr:IsA("NumberValue") or fr:IsA("IntValue")) then
            local name = tool.Name
            if origToolRates[name] == nil then
                origToolRates[name] = origRates[name] or fr.Value
            end
            fr.Value = math.max(0.02, origToolRates[name] * 0.35)
        end
    end

    -- per-frame: mag cycle (infinite), rapid fire re-pin, auto-reload on empty
    api.step = function()
        if CFG.infiniteAmmo then
            ammoStep()
        end
        if CFG.rapidFire then rapidStep() end
        if CFG.autoReload and not CFG.infiniteAmmo then
            local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
            if tool then
                local stats = tool:FindFirstChild("Stats")
                local clip = stats and stats:FindFirstChild("ClipSize")
                -- mag dry: poke the game's own reload remote ONCE (throttled);
                -- the server refills during the reload window
                if clip and clip.Value <= 0 and os.clock() - lastReloadT > 1.5 then
                    lastReloadT = os.clock()
                    local gr = game.ReplicatedStorage:FindFirstChild("GunRemotes")
                    local rel = gr and gr:FindFirstChild("Reload")
                    if rel then
                        pcall(function() rel:FireServer(tool, true) end)
                    end
                end
            end
        end
    end

    api.apply = function()
        applyRecoil(CFG.noRecoil)
        applyFireMods()
        applyRapid(CFG.rapidFire)
        applyShake(CFG.noShake)
    end

    api.destroy = function()
        if okWM and origRecoil then WM.recoil = origRecoil end
        if okSC and origFire then SC.Fire = origFire end
        if okWM and origShake then WM.ScreenShake = origShake end
        if okWM and origUpdateAmmo then WM.UpdateAmmo = origUpdateAmmo end
        applyRapid(false)
    end

    api.resetAmmoCycle = function()
        shotCount = 0
        cycleArmed = true
        countedTool = nil
        cycleTimeout = 0
    end
    return api
end)()
WMI.apply()

----------------------------------------------------------------
-- CASH (Bling pickups with CashSound) - ESP + auto-collect
----------------------------------------------------------------
local function isCashPickup(obj)
    return obj:IsA("BasePart") and obj.Name == "Bling"
        and obj:FindFirstChild("CashSound") ~= nil
end

local function addCashHighlight(obj)
    if not CFG.cashEsp or Runtime.Cash[obj] then return end
    local hl = Instance.new("Highlight")
    hl.FillColor = P.Warn
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 1
    hl.Adornee = obj
    hl.Parent = obj
    Runtime.Cash[obj] = hl
end

local function refreshCashEsp()
    for part, hl in pairs(Runtime.Cash) do
        if not part.Parent or not CFG.cashEsp then
            pcall(function() hl:Destroy() end)
            Runtime.Cash[part] = nil
        end
    end
    if not CFG.cashEsp then return end
    -- one full scan for pickups already alive at boot; afterwards the
    -- DescendantAdded pair below keeps the set current incrementally
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if isCashPickup(obj) then addCashHighlight(obj) end
    end
end

connect(Workspace.DescendantAdded, function(obj)
    if isCashPickup(obj) then addCashHighlight(obj) end
end)
connect(Workspace.DescendantRemoving, function(obj)
    local hl = Runtime.Cash[obj]
    if hl then
        pcall(function() hl:Destroy() end)
        Runtime.Cash[obj] = nil
    end
end)
refreshCashEsp()

local lastCashGrab = 0
local function autoCashStep()
    if not CFG.autoCash then return end
    local now = os.clock()
    if now - lastCashGrab < 0.5 then return end
    lastCashGrab = now
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local best, bestD
    -- Iterate the already-tracked Runtime.Cash set instead of a full
    -- Workspace:GetDescendants() scan every 0.5s. DescendantAdded/Removing
    -- keep this set current incrementally, so the full scan is redundant
    -- and is the single biggest GC/lag source on large maps.
    for obj, hl in pairs(Runtime.Cash) do
        if obj.Parent then
            local d = (obj.Position - root.Position).Magnitude
            if d < 250 and (not bestD or d < bestD) then
                best, bestD = obj, d
            end
        end
    end
    if best then
        root.CFrame = CFrame.new(best.Position + Vector3.new(0, 2, 0))
    end
end

local survChar, survHumanoid, survArmor = nil, nil, nil
local function survivalStep()
    local char = LocalPlayer.Character
    if not char then return end

    -- cache per-character: re-resolve after respawn
    if survChar ~= char then
        survChar = char
        survHumanoid = char:FindFirstChildOfClass("Humanoid")
        survArmor = nil
    end

    if CFG.infHealth then
        local hum = survHumanoid
        -- pin every frame; no guard on health > 0 so burst kills are
        -- immediately undone (keeps you alive through everything).
        if hum then
            hum.Health = hum.MaxHealth
        end
    end

    if CFG.infArmor then
        -- resolve the armor value once and cache it; look for it on the
        -- character (NumberValue/IntValue), Valuestats, or an attribute.
        -- Note: decompile confirms this game has NO client-visible armor
        -- field (FirearmLocal never reads armor, Weapon_Module.ShowArmor
        -- is a hitmarker). If "armor" match finds nothing, this is a no-op.
        local av = survArmor
        if av == nil or not av.Parent then
            survArmor = nil
            local found
            for _, v in ipairs(char:GetDescendants()) do
                if (v:IsA("NumberValue") or v:IsA("IntValue"))
                    and v.Name:lower():find("armor", 1, true) then
                    found = v; break
                end
            end
            if not found then
                local vs = LocalPlayer:FindFirstChild("Valuestats")
                if vs then
                    for _, v in ipairs(vs:GetDescendants()) do
                        if (v:IsA("NumberValue") or v:IsA("IntValue"))
                            and v.Name:lower():find("armor", 1, true) then
                            found = v; break
                        end
                    end
                end
            end
            -- attribute fallback (newer systems)
            if not found then
                for _, t in ipairs({ char, survHumanoid }) do
                    if t then
                        for k, val in pairs(t:GetAttributes()) do
                            if type(val) == "number" and k:lower():find("armor", 1, true) then
                                t:SetAttribute(k, CFG.armorValue)
                            end
                        end
                    end
                end
            end
            survArmor = found
            av = found
        end
        if av then
            av.Value = CFG.armorValue
        end
    end

    -- anti-ragdoll: the game flags the character with a Ragdolled attribute
    -- and drops it into a physics state on knockback. Clear the flag and
    -- force the humanoid back up while still alive.
    if CFG.antiRagdoll then
        local hum = survHumanoid
        if hum and hum.Health > 0 then
            if char:GetAttribute("Ragdolled") == true then
                char:SetAttribute("Ragdolled", false)
            end
            if hum.PlatformStand then
                hum.PlatformStand = false
            end
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Physics then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
    end
end

----------------------------------------------------------------
-- AUTO MEDKIT (decompile-verified): Medkit is a Utility tool with a
-- 20s cooldown and 2.8s use-time; the client uses it via
-- Utilities/Remotes/Use:FireServer(tool). We ride that same remote,
-- throttled below the server cooldown so we never spam.
----------------------------------------------------------------
local lastMedkitAt = 0
local medkitHoldTool = nil
local medkitRestoreAt = 0
local function medkitStep()
    if not CFG.autoMedkit then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health > 0) then return end

    -- restore the previously-held tool after the medkit use finishes
    if medkitHoldTool and os.clock() > medkitRestoreAt then
        local prev = medkitHoldTool
        medkitHoldTool = nil
        if prev and prev.Parent then
            pcall(function() hum:EquipTool(prev) end)
        end
    end

    if hum.Health >= CFG.medkitHP then return end
    if os.clock() - lastMedkitAt < 20 then return end -- game cooldown

    -- find a Medkit: equipped, on the character, or in the backpack
    local medkit = char:FindFirstChild("Medkit")
        or (LocalPlayer.Backpack and LocalPlayer.Backpack:FindFirstChild("Medkit"))
    if not medkit then return end

    -- remember the current tool so we can re-equip it after the heal
    local held = char:FindFirstChildOfClass("Tool")
    if held and held ~= medkit then
        medkitHoldTool = held
        medkitRestoreAt = os.clock() + 3.5
    end

    lastMedkitAt = os.clock()
    pcall(function() hum:EquipTool(medkit) end)
    local remotes = game.ReplicatedStorage:FindFirstChild("Utilities")
        and game.ReplicatedStorage.Utilities:FindFirstChild("Remotes")
    local use = remotes and remotes:FindFirstChild("Use")
    if use then
        pcall(function() use:FireServer(medkit) end)
    end
end

----------------------------------------------------------------
-- ESP - Highlights (diff-updated, no flicker) + player health bars
----------------------------------------------------------------
local function setHighlight(char, color, transparency)
    local hl = Instance.new("Highlight")
    hl.FillColor = color
    hl.FillTransparency = transparency
    hl.OutlineTransparency = 1
    hl.Adornee = char
    hl.Parent = char
    return hl
end

----------------------------------------------------------------
-- ESP BOX - screen-space 2D bounding box: 1px corner brackets,
-- vertical health strip on the left edge, name pill docked at the
-- top-left corner. No floating head text; matches OSPEI language.
----------------------------------------------------------------
local EspGui = Instance.new("ScreenGui")
EspGui.Name = "OspeiEspBox"; EspGui.ResetOnSpawn = false; EspGui.IgnoreGuiInset = true
EspGui.DisplayOrder = 9996
pcall(function() EspGui.Parent = CoreGui end)
if not EspGui.Parent then EspGui.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end

-- visibility model: alpha 1 visible, 0.4 occluded, and linearly fades to
-- zero between ESP_FADE_START and ESP_CULL studs. All GUI alpha is a
-- function of this value, so state changes are one tween away.
local ESP_FADE_START = 150
local ESP_CULL = 300

-- Cache the health-bar gradient per tier color instead of building a fresh
-- ColorSequence + NumberSequence for every box on every frame (GC churn).
local gradCache = {}
local function hpGradColor(top)
    local g = gradCache[top]
    if g then return g end
    g = ColorSequence.new({
        ColorSequenceKeypoint.new(0, top),
        ColorSequenceKeypoint.new(1, top:Lerp(Color3.new(0, 0, 0), 0.2)),
    })
    gradCache[top] = g
    return g
end

-- Cache NumberSequence for the full-visible case (inv=0, alpha=1) to avoid
-- per-frame allocation; purely-visible boxes are the vast majority. Fading
-- boxes still allocate, but those are few and transient.
local fullyVisibleSeq = NumberSequence.new(0)
local function hpGradTransparency(inv)
    if inv <= 0.001 then return fullyVisibleSeq end
    return NumberSequence.new(inv * 0.2)
end

local function makeEspBox(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end

    local root = Instance.new("Frame", EspGui)
    root.BackgroundTransparency = 1; root.BorderSizePixel = 0
    root.Visible = false

    -- top-corner brackets (top-left + top-right only, 1px, accent)
    local brackets = {}
    for i = 1, 2 do
        local h = Instance.new("Frame", root)
        h.Size = UDim2.fromOffset(12, 1); h.BorderSizePixel = 0
        local v = Instance.new("Frame", root)
        v.Size = UDim2.fromOffset(1, 12); v.BorderSizePixel = 0
        brackets[i] = { h = h, v = v }
    end

    -- Syde-style pill: rounded, dark, subtle stroke, bold name + HP%
    local pill = Instance.new("Frame", root)
    pill.Position = UDim2.fromOffset(0, 0)
    pill.Size = UDim2.fromOffset(150, 18)
    pill.BackgroundColor3 = P.Bg0
    pill.BackgroundTransparency = 0.12
    pill.BorderSizePixel = 0
    local pillCorner = Instance.new("UICorner", pill)
    pillCorner.CornerRadius = UDim.new(0, 4)
    local pillStroke = Instance.new("UIStroke", pill)
    pillStroke.Color = P.Line; pillStroke.Thickness = 1; pillStroke.Transparency = 0.35

    local nameLbl = Instance.new("TextLabel", pill)
    nameLbl.AnchorPoint = Vector2.new(0, 0); nameLbl.Position = UDim2.new(0, 10, 0, 2)
    nameLbl.Size = UDim2.new(0, 92, 0, 14)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Font = Enum.Font.GothamBold; nameLbl.TextSize = 10
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextColor3 = P.FgHi

    local hpLbl = Instance.new("TextLabel", pill)
    hpLbl.AnchorPoint = Vector2.new(1, 0); hpLbl.Position = UDim2.new(1, -10, 0, 2)
    hpLbl.Size = UDim2.new(0, 44, 0, 14)
    hpLbl.BackgroundTransparency = 1
    hpLbl.Font = Enum.Font.Gotham; hpLbl.TextSize = 10
    hpLbl.TextXAlignment = Enum.TextXAlignment.Right
    hpLbl.TextColor3 = P.FgHi

    -- HP bar: rounded accent track along the bottom edge
    local hpTrack = Instance.new("Frame", pill)
    hpTrack.Position = UDim2.new(0, 6, 1, -4); hpTrack.Size = UDim2.new(1, -12, 0, 3)
    hpTrack.BackgroundColor3 = P.Well
    hpTrack.BackgroundTransparency = 0.25
    hpTrack.BorderSizePixel = 0
    local trackCorner = Instance.new("UICorner", hpTrack)
    trackCorner.CornerRadius = UDim.new(0, 2)
    local hpFill = Instance.new("Frame", hpTrack)
    hpFill.Size = UDim2.new(0, 0, 1, 0); hpFill.BorderSizePixel = 0
    local fillCorner = Instance.new("UICorner", hpFill)
    fillCorner.CornerRadius = UDim.new(0, 2)
    local hpGrad = Instance.new("UIGradient", hpFill)
    hpGrad.Rotation = 90

    -- secondary metrics line under the pill (distance)
    local metaLbl = Instance.new("TextLabel", root)
    metaLbl.AnchorPoint = Vector2.new(0.5, 0); metaLbl.Position = UDim2.new(0.5, 0, 0, 20)
    metaLbl.Size = UDim2.fromOffset(120, 11)
    metaLbl.BackgroundTransparency = 1
    metaLbl.Font = Enum.Font.Gotham; metaLbl.TextSize = 8
    metaLbl.TextXAlignment = Enum.TextXAlignment.Center
    metaLbl.TextColor3 = P.Faint

    return { root = root, brackets = brackets, pill = pill, pillStroke = pillStroke,
        nameLbl = nameLbl, hpLbl = hpLbl, hpTrack = hpTrack, hpFill = hpFill,
        hpGrad = hpGrad, metaLbl = metaLbl, char = char, hum = hum,
        alpha = 1, occluded = false, lastOccl = 0, smooth = UDim2.fromScale(-1, -1) }
end

-- project each character: pill above the head with the micro HP strip,
-- corner brackets at the two top corners, alpha driven by occlusion +
-- distance cull. All positions are dt-lerped into `smooth`.
local function updateEspBoxes(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

    -- NOTE: Lua 5.1 has no `continue`; guards use a `live` flag instead.
    -- Locals shared across sections are declared up front so they stay in
    -- scope for every `if live then` block that needs them.
    for char, box in pairs(Runtime.Cards) do
        local hum = box.hum
        local live = true
        local hrp, head, dist, fade, sp, alpha, plr

        if not (char.Parent and hum and hum.Health > 0) then
            box.root.Visible = false
            live = false
        end

        if live then
            hrp = char:FindFirstChild("HumanoidRootPart")
            head = char:FindFirstChild("Head")
            if not (hrp and head) then
                box.root.Visible = false
                live = false
            end
        end

        if live then
            -- distance cull
            dist = myRoot and (hrp.Position - myRoot.Position).Magnitude or 0
            fade = 1
            if dist > ESP_CULL then
                box.root.Visible = false
                live = false
            elseif dist > ESP_FADE_START then
                fade = 1 - (dist - ESP_FADE_START) / (ESP_CULL - ESP_FADE_START)
            end
        end

        if live then
            -- occlusion: raycast cam -> head, throttled per box (150ms)
            local now = os.clock()
            if now - box.lastOccl > 0.15 then
                box.lastOccl = now
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.IgnoreWater = true
                local exclude = {}
                if LocalPlayer.Character then exclude[#exclude + 1] = LocalPlayer.Character end
                exclude[#exclude + 1] = char
                params.FilterDescendantsInstances = exclude
                box.occluded = Workspace:Raycast(cam.CFrame.Position,
                    head.Position - cam.CFrame.Position, params) ~= nil
            end
        end

        if live then
            alpha = fade * (box.occluded and 0.4 or 1)
            if alpha <= 0.03 then
                box.root.Visible = false
                live = false
            end
        end

        if live then
            -- anchor = head screen position; the 150px pill centers on it and
            -- floats above the head (frame-rate independent dt-lerp)
            sp = cam:WorldToViewportPoint(head.Position)
            if sp.Z <= 0 or sp.Z > 999 then
                box.root.Visible = false
                live = false
            end
        end

        if live then
            local target = UDim2.fromOffset(sp.X - 75, sp.Y - 40)
            local k = math.clamp(dt * 10, 0, 1)
            box.smooth = box.smooth:Lerp(target, k)
            box.root.Position = box.smooth
            box.root.Visible = true

            -- corner brackets frame the pill's top corners (top-left + top-right)
            plr = Players:GetPlayerFromCharacter(char)
            local color = P.Fg
            if plr and plr ~= LocalPlayer then
                color = isEnemy(plr) and P.Danger or P.Success
            elseif not plr then
                color = P.Warn
            end
            for i, b in ipairs(box.brackets) do
                local isLeft = i == 1
                b.h.AnchorPoint = isLeft and Vector2.new(0, 0) or Vector2.new(1, 0)
                b.h.Position = isLeft and UDim2.fromOffset(0, 0) or UDim2.fromOffset(150, 0)
                b.v.AnchorPoint = isLeft and Vector2.new(0, 0) or Vector2.new(1, 0)
                b.v.Position = isLeft and UDim2.fromOffset(0, 0) or UDim2.fromOffset(150, 0)
                b.h.BackgroundColor3 = color
                b.v.BackgroundColor3 = color
                b.h.BackgroundTransparency = 1 - alpha
                b.v.BackgroundTransparency = 1 - alpha
            end

            -- pill: name + HP% + micro strip
            local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            box.nameLbl.Text = plr and plr.DisplayName or char.Name
            box.hpLbl.Text = string.format("%d%%", math.floor(ratio * 100))
            local top = ratio > 0.5 and P.Success or (ratio > 0.25 and P.Warn or P.Danger)
            box.hpGrad.Color = hpGradColor(top)
            box.hpFill.Size = UDim2.new(ratio, 0, 1, 0)
            box.hpFill.Visible = CFG.healthBars

            -- secondary metrics: distance in meters
            box.metaLbl.Text = CFG.nameTags and CFG.nameDist
                and string.format("%dm", math.floor(dist)) or ""
            box.metaLbl.Visible = CFG.nameTags and CFG.nameDist

            -- apply alpha to every element
            local inv = 1 - alpha
            box.pill.BackgroundTransparency = inv
            box.pillStroke.Transparency = 0.35 + inv * 0.65
            box.nameLbl.TextTransparency = inv
            box.hpLbl.TextTransparency = inv
            box.metaLbl.TextTransparency = inv
            box.hpTrack.BackgroundTransparency = 0.15 + inv * 0.85
            box.hpFill.BackgroundTransparency = inv
            box.hpGrad.Transparency = hpGradTransparency(inv)
        end
    end
end

local function destroyEsp()
    for char, hl in pairs(Runtime.ESP) do
        pcall(function() hl:Destroy() end)
        Runtime.ESP[char] = nil
    end
    for char, card in pairs(Runtime.Cards) do
        pcall(function() card.root:Destroy() end)
        Runtime.Cards[char] = nil
    end
    for _, hl in pairs(Runtime.Cash) do
        pcall(function() hl:Destroy() end)
    end
    table.clear(Runtime.Cash)
end

-- diff update: create/remove/retune only what changed (no per-frame rebuild);
-- forceNpc runs the full-workspace NPC scan (heartbeat throttles it to ~3s)
local function updateESP(forceNpc)
    local hlWanted, cardWanted = {}, {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local enemy = isEnemy(plr)
                if enemy and CFG.enemyHl then
                    hlWanted[char] = P.Danger
                elseif not enemy and CFG.teamHl then
                    hlWanted[char] = P.Success
                end
                if CFG.healthBars or CFG.nameTags then cardWanted[char] = true end
            end
        end
    end
    if CFG.npcHl then
        if forceNpc then
            table.clear(Runtime.NPC)
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("Humanoid") and obj.Health > 0 then
                    local char = obj.Parent
                    if char and char ~= LocalPlayer.Character
                        and not Players:GetPlayerFromCharacter(char)
                        and char:FindFirstChild("HumanoidRootPart") then
                        Runtime.NPC[char] = true
                    end
                end
            end
        end
        -- merge the cached set so NPC highlights survive between full scans
        for char in pairs(Runtime.NPC) do
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and char.Parent then
                if not hlWanted[char] then hlWanted[char] = P.Warn end
                if CFG.healthBars or CFG.nameTags then cardWanted[char] = true end
            else
                Runtime.NPC[char] = nil
            end
        end
    else
        table.clear(Runtime.NPC)
    end
    -- drop velocity samples for characters that no longer exist
    for char in pairs(velocityHistory) do
        if not char.Parent then velocityHistory[char] = nil end
    end
    for char in pairs(Runtime.ESP) do
        if not hlWanted[char] then
            pcall(function() Runtime.ESP[char]:Destroy() end)
            Runtime.ESP[char] = nil
        end
    end
    for char in pairs(Runtime.Cards) do
        if not cardWanted[char] then
            pcall(function() Runtime.Cards[char].root:Destroy() end)
            Runtime.Cards[char] = nil
        end
    end
    for char, color in pairs(hlWanted) do
        local hl = Runtime.ESP[char]
        if hl then
            hl.FillColor = color
            hl.FillTransparency = CFG.hlTrans
        else
            Runtime.ESP[char] = setHighlight(char, color, CFG.hlTrans)
        end
    end
    for char in pairs(cardWanted) do
        if not Runtime.Cards[char] and char:FindFirstChild("HumanoidRootPart") then
            Runtime.Cards[char] = makeEspBox(char)
        end
    end
end

local function onEspEvent()
    updateESP(true)
end

connect(Players.PlayerAdded, function(plr)
    connect(plr.CharacterAdded, onEspEvent)
    onEspEvent()
end)
for _, plr in ipairs(Players:GetPlayers()) do
    connect(plr.CharacterAdded, onEspEvent)
end
connect(Players.PlayerRemoving, onEspEvent)
connect(LocalPlayer.CharacterAdded, function()
    table.clear(Runtime.savedCollide)
    table.clear(collideParts)
    collideCacheAt = 0
    onEspEvent()
end)
connect(LocalPlayer.CharacterRemoving, function()
    table.clear(Runtime.savedCollide)
    table.clear(collideParts)
end)

----------------------------------------------------------------
-- HITMARKER (ScreenGui X-burst on shot with a lock; rate-limited)
----------------------------------------------------------------
local Hitmarker = (function()
    local last = 0
    local function spawn()
        local gui = Instance.new("ScreenGui")
        gui.Name = "OspeiHit"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9999
        pcall(function() gui.Parent = CoreGui end)
        if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end
        local lines = {}
        for i = 1, 4 do
            local l = Instance.new("Frame", gui)
            l.AnchorPoint = Vector2.new(0.5, 0.5)
            l.Position = UDim2.fromScale(0.5, 0.5)
            l.Size = UDim2.fromOffset(7, 2)
            l.BackgroundColor3 = P.Fg
            l.BorderSizePixel = 0
            l.Rotation = 45 + 90 * (i - 1)
            lines[i] = l
        end
        for _, l in ipairs(lines) do
            TweenService:Create(l, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Size = UDim2.fromOffset(15, 2) }):Play()
        end
        task.delay(0.2, function()
            for _, l in ipairs(lines) do
                TweenService:Create(l, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
            end
            task.delay(0.14, function() pcall(function() gui:Destroy() end) end)
        end)
    end
    return {
        tick = function()
            local now = os.clock()
            if now - last < 0.16 then return end
            last = now
            spawn()
        end,
        destroy = function() end,
    }
end)()

----------------------------------------------------------------
-- FOV RING (ScreenGui - Solara-safe, degrees -> pixels)
----------------------------------------------------------------
local FovRing = (function()
    local ok, api = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "OspeiFovRing"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9998; gui.Parent = CoreGui
        local ring = Instance.new("Frame")
        ring.AnchorPoint = Vector2.new(0.5, 0.5); ring.Position = UDim2.fromScale(0.5, 0.5)
        ring.Size = UDim2.fromOffset(200, 200); ring.BackgroundTransparency = 1; ring.Parent = gui
        Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
        local stroke = Instance.new("UIStroke", ring)
        stroke.Color = P.Accent; stroke.Thickness = 1; stroke.Transparency = 0.55
        local function update()
            local show = CFG.aimStyle ~= "Off" and CFG.fovEnabled
            ring.Visible = show
            if show then
                local cam = Workspace.CurrentCamera
                if not cam then return end
                local vp = cam.ViewportSize
                local radius = math.tan(math.rad(CFG.fovRadius))
                    / math.tan(math.rad(cam.FieldOfView / 2)) * (vp.Y / 2)
                radius = math.clamp(radius, 10, vp.Y)
                ring.Size = UDim2.fromOffset(radius * 2, radius * 2)
            end
        end
        return { update = update, destroy = function() pcall(function() gui:Destroy() end) end }
    end)
    if ok then return api end
    return { update = function() end, destroy = function() end }
end)()

----------------------------------------------------------------
-- CROSSHAIR (dot / cross overlay; styles Off / Dot / Cross)
----------------------------------------------------------------
local Crosshair = (function()
    local ok, api = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "OspeiCross"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9998; gui.Parent = CoreGui
        local anchor = Instance.new("Frame", gui)
        anchor.AnchorPoint = Vector2.new(0.5, 0.5); anchor.Position = UDim2.fromScale(0.5, 0.5)
        anchor.Size = UDim2.fromOffset(0, 0); anchor.BackgroundTransparency = 1

        local dot = Instance.new("Frame", anchor)
        dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.fromScale(0.5, 0.5)
        dot.BackgroundColor3 = P.Accent; dot.BorderSizePixel = 0
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local bars = {}
        for i = 1, 4 do
            local b = Instance.new("Frame", anchor)
            b.BackgroundColor3 = P.Accent; b.BorderSizePixel = 0
            bars[i] = b
        end

        local function update()
            local style = CFG.crossStyle
            anchor.Visible = style ~= "Off"
            if style == "Off" then return end
            local s = CFG.crossSize
            if style == "Dot" then
                dot.Visible = true
                for _, b in ipairs(bars) do b.Visible = false end
                dot.Size = UDim2.fromOffset(s, s)
            else -- Cross: four bars around a center gap of `s`
                dot.Visible = false
                local arm = s * 2
                local thickness = math.max(2, math.floor(s / 2))
                bars[1].AnchorPoint = Vector2.new(0.5, 1); bars[1].Position = UDim2.new(0.5, 0, 0.5, -s)
                bars[1].Size = UDim2.fromOffset(thickness, arm)
                bars[2].AnchorPoint = Vector2.new(0.5, 0); bars[2].Position = UDim2.new(0.5, 0, 0.5, s)
                bars[2].Size = UDim2.fromOffset(thickness, arm)
                bars[3].AnchorPoint = Vector2.new(0, 0.5); bars[3].Position = UDim2.new(0.5, -s, 0.5, 0)
                bars[3].Size = UDim2.fromOffset(arm, thickness)
                bars[4].AnchorPoint = Vector2.new(1, 0.5); bars[4].Position = UDim2.new(0.5, s, 0.5, 0)
                bars[4].Size = UDim2.fromOffset(arm, thickness)
                for _, b in ipairs(bars) do b.Visible = true end
            end
        end
        update()
        return { update = update, destroy = function() pcall(function() gui:Destroy() end) end }
    end)
    if ok then return api end
    return { update = function() end, destroy = function() end }
end)()

----------------------------------------------------------------
-- SYDE UI (patched loader + Opsei-branded window)
----------------------------------------------------------------
-- Patch Syde before use: its GitHub source expects asset children the
-- rbxassetid GUI doesn't have (modal.Buttons, slider.Title). The loader
-- below injects the missing templates right after the Library asset loads,
-- and nulls gethui so Syde's CoreGui watcher stops fighting the executor.
local SydeUI = (function()
    local api = {}

    -- null gethui BEFORE Syde loads: Syde captures coregui = gethui() at
    -- its own top level, and if that differs from where the Library lands,
    -- its watcher warns "[SYDE] UI moved. Restoring..." every second.
    pcall(function()
        if getgenv then
            getgenv().gethui = nil
        end
    end)

    local tFetch = tick()
    local src = game:HttpGet("https://raw.githubuser" .. "content.com/essencejs/syde/refs/heads/main/source", true)

    local ANCHOR = 'game:GetObjects("rbxassetid://123800669522471")'
    local PATCH = [[
pcall(function()
	local m = Library:FindFirstChild("main")
	if not m then return end

	local modal = m:FindFirstChild("modal")
	if modal and not modal:FindFirstChild("Buttons") then
		local b = Instance.new("Folder")
		b.Name = "Buttons"
		for _, nm in ipairs({"Confirm", "Cancel"}) do
			local btn = Instance.new("TextButton")
			btn.Name = nm
			btn.Size = UDim2.new(0, 120, 0, 35)
			btn.Parent = b
			local lbl = Instance.new("TextLabel")
			lbl.Name = "TextLabel"
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.Parent = btn
			Instance.new("UIStroke", btn).Name = "UIStroke"
		end
		b.Parent = modal
	end

	-- fix: slider sub-templates missing "Title" child. Scan the ENTIRE
	-- asset for any frame named "Slider" and repair its slideholder.slider
	-- sub-template wherever it actually lives (main pages + settings gear).
	local function fixAllSliders(root)
		for _, tpl in ipairs(root:GetDescendants()) do
			if tpl:IsA("Frame") and tpl.Name == "Slider" then
				local holder = tpl:FindFirstChild("slideholder")
				local sub = holder and holder:FindFirstChild("slider")
				if sub and not sub:FindFirstChild("Title") then
					local t = Instance.new("TextLabel")
					t.Name = "Title"
					t.Size = UDim2.new(1, 0, 0, 20)
					t.BackgroundTransparency = 1
					t.Text = "Slider"
					t.Parent = sub
				end
			end
		end
	end
	fixAllSliders(Library)

	-- fix: Paragraph templates missing "Frame"(>title) + "Content" children.
	-- Scan the ENTIRE asset for any frame named "Paragraph" and repair it,
	-- so both the main-page builder and the settings-gear builder work no
	-- matter where the template actually lives in the asset.
	local function fixAllParagraphs(root)
		for _, tpl in ipairs(root:GetDescendants()) do
			if tpl:IsA("Frame") and tpl.Name == "Paragraph" then
				local f = tpl:FindFirstChild("Frame")
				if not f then
					f = Instance.new("Frame")
					f.Name = "Frame"
					f.Size = UDim2.new(1, 0, 0, 28)
					f.BackgroundTransparency = 1
					f.Parent = tpl
				end
				if not f:FindFirstChild("title") then
					local t = Instance.new("TextLabel")
					t.Name = "title"
					t.Size = UDim2.new(1, -24, 1, 0)
					t.Position = UDim2.new(0, 12, 0, 0)
					t.BackgroundTransparency = 1
					t.TextXAlignment = Enum.TextXAlignment.Left
					t.Font = Enum.Font.GothamBold
					t.TextSize = 16
					t.Text = "Section"
					t.Parent = f
				end
				if not tpl:FindFirstChild("Content") then
					local c = Instance.new("TextLabel")
					c.Name = "Content"
					c.Size = UDim2.new(1, -24, 0, 40)
					c.Position = UDim2.new(0, 12, 0, 32)
					c.BackgroundTransparency = 1
					c.TextXAlignment = Enum.TextXAlignment.Left
					c.TextYAlignment = Enum.TextYAlignment.Top
					c.TextWrapped = true
					c.TextColor3 = Color3.fromRGB(200, 204, 215)
					c.Font = Enum.Font.Gotham
					c.TextSize = 13
					c.Parent = tpl
				end
			end
		end
	end
	fixAllParagraphs(Library)

	-- fix: bold the Section header template (applies to every cloned Section)
	local function boldSection(tpl)
		if not tpl then return end
		local title = tpl:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Font = Enum.Font.GothamBold
			title.TextSize = math.max(title.TextSize, 14)
			title.TextColor3 = Color3.fromRGB(235, 238, 245)
		end
		local icon = tpl:FindFirstChild("icon")
		if not icon then
			icon = Instance.new("ImageLabel")
			icon.Name = "icon"
			icon.Size = UDim2.new(0, 18, 0, 18)
			icon.Position = UDim2.new(0, 6, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.BackgroundTransparency = 1
			icon.Parent = tpl
		end
		if icon:IsA("ImageLabel") then
			icon.ImageColor3 = Color3.fromRGB(147, 186, 250)
		end
	end
	boldSection(m:FindFirstChild("pages") and m.pages:FindFirstChild("page") and m.pages.page:FindFirstChild("Section"))
	boldSection(m:FindFirstChild("settings") and m.settings:FindFirstChild("pages") and m.settings.pages:FindFirstChild("page") and m.settings.pages.page:FindFirstChild("Section"))
end)
]]

    local pos = src:find(ANCHOR, 1, true)
    local patchedSrc = src

    -- PATCH the source at the CLONE SITES: the asset's templates are missing
    -- children the builders expect (modal.Buttons, slider.Title, paragraph
    -- Frame>title/Content). Instead of guessing asset paths, wrap each clone
    -- call so it ensures the template is complete right before cloning, using
    -- the exact path the builder itself navigates. Covers both library
    -- generations (old `window.settings.pages...` + new `pages.page...`).

    -- add a child if missing, then clone
    local function makeEnsureClone(getTemplate, ensureFn)
        return "(function() local __t = " .. getTemplate
            .. "; if __t then " .. ensureFn .. " end; return __t and __t:Clone() end)()"
    end

    local ensureSlider = makeEnsureClone(
        "pages.page.Slider.slideholder.slider",
        "if not __t:FindFirstChild('Title') then local __l = Instance.new('TextLabel'); __l.Name = 'Title'; __l.Size = UDim2.new(1, 0, 0, 20); __l.BackgroundTransparency = 1; __l.Parent = __t end"
    )
    local ensureSliderOld = makeEnsureClone(
        "window.settings.pages.page.Slider.slideholder.slider",
        "if not __t:FindFirstChild('Title') then local __l = Instance.new('TextLabel'); __l.Name = 'Title'; __l.Size = UDim2.new(1, 0, 0, 20); __l.BackgroundTransparency = 1; __l.Parent = __t end"
    )
    local ensurePara = makeEnsureClone(
        "pages.page.Paragraph",
        "if not __t:FindFirstChild('Frame') then local __f = Instance.new('Frame'); __f.Name = 'Frame'; __f.Size = UDim2.new(1, 0, 0, 28); __f.BackgroundTransparency = 1; __f.Parent = __t; local __ti = Instance.new('TextLabel'); __ti.Name = 'title'; __ti.Size = UDim2.new(1, -24, 1, 0); __ti.Position = UDim2.new(0, 12, 0, 0); __ti.BackgroundTransparency = 1; __ti.TextXAlignment = Enum.TextXAlignment.Left; __ti.Font = Enum.Font.GothamBold; __ti.TextSize = 16; __ti.Text = 'Section'; __ti.Parent = __f end; if not __t:FindFirstChild('Content') then local __c = Instance.new('TextLabel'); __c.Name = 'Content'; __c.Size = UDim2.new(1, -24, 0, 40); __c.Position = UDim2.new(0, 12, 0, 32); __c.BackgroundTransparency = 1; __c.TextXAlignment = Enum.TextXAlignment.Left; __c.TextYAlignment = Enum.TextYAlignment.Top; __c.TextWrapped = true; __c.TextColor3 = Color3.fromRGB(200, 204, 215); __c.Font = Enum.Font.Gotham; __c.TextSize = 13; __c.Parent = __t end"
    )
    local ensureParaOld = makeEnsureClone(
        "window.settings.pages.page.Paragraph",
        "if not __t:FindFirstChild('Frame') then local __f = Instance.new('Frame'); __f.Name = 'Frame'; __f.Size = UDim2.new(1, 0, 0, 28); __f.BackgroundTransparency = 1; __f.Parent = __t; local __ti = Instance.new('TextLabel'); __ti.Name = 'title'; __ti.Size = UDim2.new(1, -24, 1, 0); __ti.Position = UDim2.new(0, 12, 0, 0); __ti.BackgroundTransparency = 1; __ti.TextXAlignment = Enum.TextXAlignment.Left; __ti.Font = Enum.Font.GothamBold; __ti.TextSize = 16; __ti.Text = 'Section'; __ti.Parent = __f end; if not __t:FindFirstChild('Content') then local __c = Instance.new('TextLabel'); __c.Name = 'Content'; __c.Size = UDim2.new(1, -24, 0, 40); __c.Position = UDim2.new(0, 12, 0, 32); __c.BackgroundTransparency = 1; __c.TextXAlignment = Enum.TextXAlignment.Left; __c.TextYAlignment = Enum.TextYAlignment.Top; __c.TextWrapped = true; __c.TextColor3 = Color3.fromRGB(200, 204, 215); __c.Font = Enum.Font.Gotham; __c.TextSize = 13; __c.Parent = __t end"
    )
    local ensureModal = makeEnsureClone(
        "ui.main.modal",
        "if not __t:FindFirstChild('Buttons') then local __b = Instance.new('Folder'); __b.Name = 'Buttons'; for _, __n in ipairs({'Confirm','Cancel'}) do local __btn = Instance.new('TextButton'); __btn.Name = __n; __btn.Size = UDim2.new(0, 120, 0, 35); __btn.Parent = __b; local __l = Instance.new('TextLabel'); __l.Name = 'TextLabel'; __l.Size = UDim2.new(1, 0, 1, 0); __l.BackgroundTransparency = 1; __l.Parent = __btn; Instance.new('UIStroke', __btn).Name = 'UIStroke' end; __b.Parent = __t end"
    )
    local ensureSection = makeEnsureClone(
        "pages.page.Section",
        "local __title = __t:FindFirstChild('Title'); if __title and __title:IsA('TextLabel') then __title.Font = Enum.Font.GothamBold; __title.TextSize = math.max(__title.TextSize, 14); __title.TextColor3 = Color3.fromRGB(235, 238, 245) end; local __icon = __t:FindFirstChild('icon'); if not __icon then __icon = Instance.new('ImageLabel'); __icon.Name = 'icon'; __icon.Size = UDim2.new(0, 18, 0, 18); __icon.Position = UDim2.new(0, 6, 0.5, 0); __icon.AnchorPoint = Vector2.new(0, 0.5); __icon.BackgroundTransparency = 1; __icon.Parent = __t end; if __icon and __icon:IsA('ImageLabel') then __icon.ImageColor3 = Color3.fromRGB(147, 186, 250) end"
    )

    -- plain-text replace-all: `gsub` treats the needle as a Lua pattern and
    -- `(`, `)`, `.` are magic chars, so we find+concat instead.
    local function patchClone(needle, replacement)
        local out, from, changed = {}, 1, false
        while true do
            local s = patchedSrc:find(needle, from, true)
            if not s then break end
            out[#out + 1] = patchedSrc:sub(from, s - 1)
            out[#out + 1] = replacement
            from = s + #needle
            changed = true
        end
        if not changed then
            warn("[SydeLoader] clone patch MISSED: " .. needle)
        else
            out[#out + 1] = patchedSrc:sub(from)
            patchedSrc = table.concat(out)
        end
        return changed
    end

    -- Order matters: the longer `window.settings...` needles contain the
    -- shorter `pages.page...` ones as substrings, so patch them first.
    -- sliders (old settings block, then new block)
    patchClone("window.settings.pages.page.Slider.slideholder.slider:Clone()", ensureSliderOld)
    patchClone("pages.page.Slider.slideholder.slider:Clone()", ensureSlider)
    -- paragraphs (old settings block, then new block)
    patchClone("window.settings.pages.page.Paragraph:Clone()", ensureParaOld)
    patchClone("pages.page.Paragraph:Clone()", ensurePara)
    -- modal
    patchClone("ui.main.modal:Clone()", ensureModal)
    -- section (bold + icon, new block)
    patchClone("pages.page.Section:Clone()", ensureSection)

    -- Patch the window's X (close) button: Syde's default only destroys
    -- the GUI, leaving the Opsei script's connections/patches running.
    -- Route it through the full unload so re-running is always clean.
    -- IMPORTANT: the unload must be DEFERRED — it runs inside the modal's
    -- Confirm callback, and Syde's closeModal() continues right after;
    -- destroying the GUI synchronously here makes closeModal() touch a
    -- destroyed instance ("Buttons is not a valid member of Frame").
    local CLOSE_ANCHOR = "Library:Destroy()"
    local ca = patchedSrc:find(CLOSE_ANCHOR, 1, true)
    if ca then
        patchedSrc = patchedSrc:sub(1, ca - 1)
            .. "task.delay(1, function() if _G.Ospei_HoodRivals_Unload then _G.Ospei_HoodRivals_Unload() else Library:Destroy() end end)"
            .. patchedSrc:sub(ca + #CLOSE_ANCHOR)
        warn("[SydeLoader] X-close now triggers full Opsei unload (deferred)")
    else
        warn("[SydeLoader] could not find Library:Destroy() - close patch skipped")
    end

    -----------------------------------------------------------------
    -- Add two custom elements to the tab builder (`initelement`):
    -- Segmented (sliding-pill picker) + RangeSlider (dual-thumb).
    -- Injected right before `return initelement` so every tab gets them,
    -- and before the guard loop so they're pcall-wrapped like the rest.
    -----------------------------------------------------------------
    local CUSTOM_ELEMENTS = [[
		--@@Opsei Segmented  (Syde-native: dropdown-style row, bar #151515 corner 10, accent pill)
		function initelement:Segmented(Opt)
			local data = {
				Title = Opt.Title or "Segmented";
				Desc = Opt.Description or "";
				Options = Opt.Options or {};
				Value = Opt.Value;
				CallBack = Opt.CallBack;
				Flag = Opt.Flag;
			}
			if not table.find(data.Options, data.Value) then
				data.Value = data.Options[1]
			end

			-- row shell: 60px, #111111 trans 0.5, 15px corner (matches Dropdown layout)
			local seg = Instance.new("Frame")
			seg.Name = data.Title
			seg.Size = UDim2.new(1, -35, 0, 60)
			seg.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
			seg.BackgroundTransparency = 0.5
			seg.BorderSizePixel = 0
			seg:SetAttribute("Searchable", true)
			seg.Parent = Page
			Instance.new("UICorner", seg).CornerRadius = UDim.new(0, 15)

			-- title: GothamMedium 14, white, top-left like Dropdown
			local title = Instance.new("TextLabel")
			title.Position = UDim2.new(0, 12, 0, 8)
			title.Size = UDim2.new(1, -50, 0, 18)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.GothamMedium
			title.TextSize = 14
			title.Text = data.Title
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextYAlignment = Enum.TextYAlignment.Center
			title.Parent = seg

			-- description line (optional, matches Dropdown's subtitle)
			if data.Desc ~= "" then
				local desc = Instance.new("TextLabel")
				desc.Position = UDim2.new(0, 12, 0, 26)
				desc.Size = UDim2.new(1, -50, 0, 12)
				desc.BackgroundTransparency = 1
				desc.Font = Enum.Font.Gotham
				desc.TextSize = 11
				desc.Text = data.Desc
				desc.TextColor3 = Color3.fromRGB(86, 86, 86)
				desc.TextXAlignment = Enum.TextXAlignment.Left
				desc.Parent = seg
			end

			-- bar: #151515, 10px corner, full width under title (matches Dropdown bar)
			local bar = Instance.new("Frame")
			bar.Position = UDim2.new(0, 10, 0, 38)
			bar.Size = UDim2.new(1, -20, 0, 20)
			bar.BackgroundColor3 = Color3.fromRGB(21, 21, 21)
			bar.BorderSizePixel = 0
			bar.Parent = seg
			Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)

			-- sliding accent pill: 6px corner, matches accent theme
			local pill = Instance.new("Frame")
			pill.BackgroundColor3 = syde.theme.HitBox
			pill.BorderSizePixel = 0
			pill.ZIndex = 2
			pill.Parent = bar
			Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 6)

			local n = #data.Options
			local cells = {}

			local function paintPill(instant)
				local idx = 1
				for i, o in ipairs(data.Options) do
					if o == data.Value then idx = i; break end
				end
				local t = instant and TweenInfo.new(0)
					or TweenInfo.new(0.22, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
				tweenservice:Create(pill, t, {
					Position = UDim2.new((idx - 1) / n, 0, 0, 0),
					Size = UDim2.new(1 / n, 0, 1, 0),
				}):Play()
				for o, cell in pairs(cells) do
					cell.TextColor3 = (o == data.Value) and Color3.fromRGB(16, 17, 21) or Color3.fromRGB(120, 125, 140)
				end
			end

			for i, option in ipairs(data.Options) do
				local cell = Instance.new("TextButton")
				cell.Position = UDim2.new((i - 1) / n, 0, 0, 0)
				cell.Size = UDim2.new(1 / n, 0, 1, 0)
				cell.BackgroundTransparency = 1
				cell.AutoButtonColor = false
				cell.Font = Enum.Font.GothamBold
				cell.TextSize = 12
				cell.Text = string.upper(tostring(option))
				cell.TextColor3 = Color3.fromRGB(120, 125, 140)
				cell.ZIndex = 3
				cell.Parent = bar
				cells[option] = cell

				cell.MouseButton1Click:Connect(function()
					if data.Value ~= option then
						data.Value = option
						paintPill(false)
						if data.CallBack then
							local okc, errc = pcall(data.CallBack, option)
							if not okc then
								syde:Report("Segmented '" .. data.Title .. "' callback", errc)
							end
						end
						if syde.Flags and data.Flag then
							syde.Flags[data.Flag] = data
						end
					end
				end)
			end

			paintPill(true)

			function data:Set(v)
				if table.find(self.Options, v) then
					self.Value = v
					paintPill(false)
				end
			end
			function data:Get() return data.Value end
			function data:Cycle()
				local idx = 1
				for i, o in ipairs(data.Options) do
					if o == data.Value then idx = i; break end
				end
				data:Set(data.Options[(idx % #data.Options) + 1])
			end
			data.Instance = seg

			return data
		end

		--@@Opsei RangeSlider  (Syde-native: slider sub-row style, 70px, #121212, 15px corner,
		--   GothamMedium 13 title at 60% trans, 3px #1F1F1F track, white thumbs, accent band)
		function initelement:RangeSlider(Opt)
			local data = {
				Title = Opt.Title or "Range";
				Desc = Opt.Description or "";
				Range = Opt.Range or {0, 100};
				MinValue = Opt.MinValue or Opt.Range[1] or 0;
				MaxValue = Opt.MaxValue or Opt.Range[2] or 100;
				Increment = Opt.Increment or 1;
				CallBack = Opt.CallBack;
				Flag = Opt.Flag;
			}
			local low, high = data.Range[1], data.Range[2]
			data.MinValue = math.clamp(data.MinValue, low, high)
			data.MaxValue = math.clamp(data.MaxValue, low, high)
			if data.MinValue > data.MaxValue then
				data.MinValue, data.MaxValue = data.MaxValue, data.MinValue
			end

			-- row: 70px, #121212, 15px corner (matches Slider sub-row)
			local rs = Instance.new("Frame")
			rs.Name = data.Title
			rs.Size = UDim2.new(1, -35, 0, 70)
			rs.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
			rs.BackgroundTransparency = 0
			rs.BorderSizePixel = 0
			rs:SetAttribute("Searchable", true)
			rs.Parent = Page
			Instance.new("UICorner", rs).CornerRadius = UDim.new(0, 15)

			-- title: GothamMedium 13, white at 60% trans, left (matches Slider sub-title)
			local title = Instance.new("TextLabel")
			title.Position = UDim2.new(0, 20, 0, 13)
			title.Size = UDim2.new(0, 200, 0, 20)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.GothamMedium
			title.TextSize = 13
			title.Text = data.Title
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
			title.TextTransparency = 0.6
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextYAlignment = Enum.TextYAlignment.Center
			title.Parent = rs

			-- value labels: min and max, right-aligned like Slider's "v" label
			local lblMin = Instance.new("TextLabel")
			lblMin.Position = UDim2.new(1, -220, 0, 13)
			lblMin.Size = UDim2.new(0, 100, 0, 20)
			lblMin.BackgroundTransparency = 1
			lblMin.Font = Enum.Font.Gotham
			lblMin.TextSize = 11
			lblMin.TextColor3 = Color3.fromRGB(255, 255, 255)
			lblMin.TextXAlignment = Enum.TextXAlignment.Right
			lblMin.TextYAlignment = Enum.TextYAlignment.Center
			lblMin.Parent = rs

			local lblMax = Instance.new("TextLabel")
			lblMax.Position = UDim2.new(1, -110, 0, 13)
			lblMax.Size = UDim2.new(0, 100, 0, 20)
			lblMax.BackgroundTransparency = 1
			lblMax.Font = Enum.Font.Gotham
			lblMax.TextSize = 11
			lblMax.TextColor3 = Color3.fromRGB(255, 255, 255)
			lblMax.TextXAlignment = Enum.TextXAlignment.Right
			lblMax.TextYAlignment = Enum.TextYAlignment.Center
			lblMax.Parent = rs

			-- track: 3px, #1F1F1F, fully round (matches Slider track)
			local track = Instance.new("Frame")
			track.Position = UDim2.new(0, 20, 0, 46)
			track.Size = UDim2.new(1, -40, 0, 3)
			track.BackgroundColor3 = Color3.fromRGB(31, 31, 31)
			track.BorderSizePixel = 0
			track.Parent = rs
			Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

			-- filled band: accent between thumbs
			local band = Instance.new("Frame")
			band.BackgroundColor3 = syde.theme.HitBox
			band.BorderSizePixel = 0
			band.Size = UDim2.new(0.5, 0, 1, 0)
			band.Parent = track
			Instance.new("UICorner", band).CornerRadius = UDim.new(1, 0)

			local dp = syde:DecimalPlaces(data.Increment)

			local function snap(v)
				v = math.floor((v - low) / data.Increment + 0.5) * data.Increment + low
				return syde:RoundTo(math.clamp(v, low, high), dp)
			end

			local function thumb()
				local t = Instance.new("Frame")
				t.Size = UDim2.fromOffset(12, 12)
				t.AnchorPoint = Vector2.new(0.5, 0.5)
				t.Position = UDim2.new(0.5, 0, 0.5, 0)
				t.BackgroundColor3 = Color3.fromRGB(235, 238, 245)
				t.BorderSizePixel = 0
				t.ZIndex = 4
				t.Parent = track
				Instance.new("UICorner", t).CornerRadius = UDim.new(1, 0)
				return t
			end

			local tMin, tMax = thumb(), thumb()

			local function refresh(instant)
				local span = math.max(high - low, 1e-6)
				local f = function(v) return (v - low) / span end
				local pMin, pMax = f(data.MinValue), f(data.MaxValue)
				local t = instant and TweenInfo.new(0) or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				tweenservice:Create(tMin, t, { Position = UDim2.new(pMin, 0, 0.5, 0) }):Play()
				tweenservice:Create(tMax, t, { Position = UDim2.new(pMax, 0, 0.5, 0) }):Play()
				tweenservice:Create(band, t, {
					Position = UDim2.new(pMin, 0, 0, 0),
					Size = UDim2.new(pMax - pMin, 0, 1, 0),
				}):Play()
				lblMin.Text = string.format("%." .. dp .. "f", data.MinValue)
				lblMax.Text = string.format("%." .. dp .. "f", data.MaxValue)
			end

			local function commit()
				if data.CallBack then
					local okc, errc = pcall(data.CallBack, data.MinValue, data.MaxValue)
					if not okc then
						syde:Report("RangeSlider '" .. data.Title .. "' callback", errc)
					end
				end
				if syde.Flags and data.Flag then
					syde.Flags[data.Flag] = data
				end
			end

			local dragging, dragWhich
			local function thumbFromPoint(mx)
				local trackAbs = track.AbsolutePosition.X
				local trackW = math.max(track.AbsoluteSize.X, 1)
				local frac = math.clamp((mx - trackAbs) / trackW, 0, 1)
				local v = snap(low + frac * (high - low))
				if math.abs(v - data.MinValue) <= math.abs(v - data.MaxValue) then
					data.MinValue = math.min(v, data.MaxValue)
				else
					data.MaxValue = math.max(v, data.MinValue)
				end
				refresh(false)
			end

			track.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				dragging = true
				local mx = userinput:GetMouseLocation().X
				local span = math.max(high - low, 1e-6)
				local pMin = track.AbsolutePosition.X + (data.MinValue - low) / span * track.AbsoluteSize.X
				local pMax = track.AbsolutePosition.X + (data.MaxValue - low) / span * track.AbsoluteSize.X
				dragWhich = (math.abs(mx - pMin) <= math.abs(mx - pMax)) and "min" or "max"
				thumbFromPoint(mx)
			end)

			userinput.InputChanged:Connect(function(input)
				if not dragging or not dragWhich then return end
				if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
				local mx = userinput:GetMouseLocation().X
				local trackAbs = track.AbsolutePosition.X
				local trackW = math.max(track.AbsoluteSize.X, 1)
				local frac = math.clamp((mx - trackAbs) / trackW, 0, 1)
				local v = snap(low + frac * (high - low))
				if dragWhich == "min" then
					data.MinValue = math.min(v, data.MaxValue)
				else
					data.MaxValue = math.max(v, data.MinValue)
				end
				refresh(false)
			end)

			userinput.InputEnded:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				if dragging then
					dragging = false
					dragWhich = nil
					commit()
				end
			end)

			refresh(true)

			function data:Set(min, max)
				self.MinValue = math.clamp(min, low, high)
				self.MaxValue = math.clamp(max, low, high)
				if self.MinValue > self.MaxValue then
					self.MinValue, self.MaxValue = self.MaxValue, self.MinValue
				end
				refresh(false)
			end
			function data:GetMin() return data.MinValue end
			function data:GetMax() return data.MaxValue end
			function data:SetBounds(l, h)
				low, high = l, h
				data:Set(data.MinValue, data.MaxValue)
				refresh(false)
			end
			data.Instance = rs

			return data
		end

		--@@Opsei Stepper  (Syde-native: 40-58px row, KeyBind-style #181818 pill,
		--   +/- icon buttons from the Ospei palette, Gotham 14 value, click-to-type)
		function initelement:Stepper(Opt)
			local data = {
				Title = Opt.Title or "Stepper";
				Desc = Opt.Description or "";
				Value = Opt.Value or 0;
				Min = Opt.Min or 0;
				Max = Opt.Max or 100;
				Increment = Opt.Increment or 1;
				Suffix = Opt.Suffix or "";
				CallBack = Opt.CallBack;
				Flag = Opt.Flag;
			}
			local dp = syde:DecimalPlaces(data.Increment)
			local function snap(v)
				local low, high = data.Min, data.Max
				v = math.floor((v - low) / data.Increment + 0.5) * data.Increment + low
				return syde:RoundTo(math.clamp(v, low, high), dp)
			end
			data.Value = snap(data.Value)

			local hasDesc = data.Desc ~= ""
			local rowH = hasDesc and 58 or 44

			-- row shell: #111111, 0.5 trans, 15px corner (matches KeyBind)
			local st = Instance.new("Frame")
			st.Name = data.Title
			st.Size = UDim2.new(1, -35, 0, rowH)
			st.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
			st.BackgroundTransparency = 0.5
			st.BorderSizePixel = 0
			st:SetAttribute("Searchable", true)
			st.Parent = Page
			Instance.new("UICorner", st).CornerRadius = UDim.new(0, 15)

			-- title: Gotham 14 white, left (matches KeyBind title)
			local title = Instance.new("TextLabel")
			title.Position = UDim2.new(0, 12, 0, hasDesc and 6 or 4)
			title.Size = UDim2.new(1, -180, 0, 18)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.Gotham
			title.TextSize = 14
			title.Text = data.Title
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextYAlignment = Enum.TextYAlignment.Center
			title.Parent = st

			if hasDesc then
				local desc = Instance.new("TextLabel")
				desc.Position = UDim2.new(0, 12, 0, 26)
				desc.Size = UDim2.new(1, -180, 0, 14)
				desc.BackgroundTransparency = 1
				desc.Font = Enum.Font.Gotham
				desc.TextSize = 11
				desc.Text = data.Desc
				desc.TextColor3 = Color3.fromRGB(86, 86, 86)
				desc.TextXAlignment = Enum.TextXAlignment.Left
				desc.Parent = st
			end

			-- pill: #181818, fully rounded, docked right (matches KeyBind Bind chip)
			local pill = Instance.new("Frame")
			pill.AnchorPoint = Vector2.new(1, 0.5)
			pill.Position = UDim2.new(1, -10, 0.5, 0)
			pill.Size = UDim2.new(0, 76, 0, 26)
			pill.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
			pill.BorderSizePixel = 0
			pill.Parent = st
			Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

			-- value label: Gotham 14 white centered
			local lbl = Instance.new("TextLabel")
			lbl.Position = UDim2.new(0, 22, 0, 0)
			lbl.Size = UDim2.new(1, -44, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.Gotham
			lbl.TextSize = 14
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.TextXAlignment = Enum.TextXAlignment.Center
			lbl.TextYAlignment = Enum.TextYAlignment.Center
			lbl.ZIndex = 2
			lbl.Parent = pill

			-- click-to-type overlay (mirrors syde:AttachSliderInput)
			local edit = Instance.new("TextBox")
			edit.Size = UDim2.new(1, -44, 1, 0)
			edit.Position = UDim2.new(0, 22, 0, 0)
			edit.BackgroundTransparency = 1
			edit.Font = Enum.Font.Gotham
			edit.TextSize = 14
			edit.TextColor3 = Color3.fromRGB(255, 255, 255)
			edit.TextXAlignment = Enum.TextXAlignment.Center
			edit.TextYAlignment = Enum.TextYAlignment.Center
			edit.TextTransparency = 1
			edit.Active = true
			edit.ZIndex = 3
			edit.Parent = pill

			local editing = false
			edit.Focused:Connect(function()
				editing = true
			end)
			edit.FocusLost:Connect(function()
				editing = false
				local n = tonumber((edit.Text:gsub("[^%d%.%-]", "")))
				edit.Text = ""
				if n then
					data.Value = snap(n)
					refresh()
					commit()
				else
					refresh()
				end
			end)

			-- +/- icon buttons
			local function iconBtn(asset, x)
				local b = Instance.new("TextButton")
				b.Position = UDim2.new(0, x, 0, 0)
				b.Size = UDim2.new(0, 22, 1, 0)
				b.BackgroundTransparency = 1
				b.AutoButtonColor = false
				b.Text = ""
				b.ZIndex = 3
				b.Parent = pill
				local ic = Instance.new("ImageLabel")
				ic.AnchorPoint = Vector2.new(0.5, 0.5)
				ic.Position = UDim2.new(0.5, 0, 0.5, 0)
				ic.Size = UDim2.fromOffset(12, 12)
				ic.BackgroundTransparency = 1
				ic.Image = asset
				ic.ImageColor3 = Color3.fromRGB(213, 213, 213)
				ic.ScaleType = Enum.ScaleType.Fit
				ic.Parent = b
				b.MouseEnter:Connect(function()
					tweenservice:Create(ic, TweenInfo.new(0.15), { ImageColor3 = syde.theme.HitBox }):Play()
				end)
				b.MouseLeave:Connect(function()
					tweenservice:Create(ic, TweenInfo.new(0.2), { ImageColor3 = Color3.fromRGB(213, 213, 213) }):Play()
				end)
				return b, ic
			end

			local btnDec = iconBtn("rbxassetid://109449356248359", 0)
			local btnInc = iconBtn("rbxassetid://95927045265925", 54)

			local function updatePillWidth()
				local w = textservice:GetTextSize(lbl.Text, lbl.TextSize, lbl.Font, Vector2.new(400, 20)).X
				pill.Size = UDim2.new(0, math.max(76, w + 58), 0, 26)
				btnInc.Position = UDim2.new(0, pill.Size.X.Offset - 22, 0, 0)
			end

			local function refresh(instant)
				lbl.Text = string.format("%." .. dp .. "f", data.Value) .. data.Suffix
				updatePillWidth()
				local t = instant and TweenInfo.new(0) or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				tweenservice:Create(lbl, t, { Position = UDim2.new(0, 22, 0, 0) }):Play()
			end

			local function commit()
				if data.CallBack then
					local okc, errc = pcall(data.CallBack, data.Value)
					if not okc then
						syde:Report("Stepper '" .. data.Title .. "' callback", errc)
					end
				end
				if syde.Flags and data.Flag then
					syde.Flags[data.Flag] = data
				end
			end

			btnDec.MouseButton1Click:Connect(function()
				data.Value = snap(data.Value - data.Increment)
				refresh(false)
				commit()
			end)
			btnInc.MouseButton1Click:Connect(function()
				data.Value = snap(data.Value + data.Increment)
				refresh(false)
				commit()
			end)

			refresh(true)

			function data:Set(v)
				self.Value = snap(v)
				refresh(false)
			end
			function data:Get() return data.Value end
			function data:StepUp()
				data:Set(data.Value + data.Increment)
			end
			function data:StepDown()
				data:Set(data.Value - data.Increment)
			end
			function data:SetBounds(min, max)
				self.Min, self.Max = min, max
				data:Set(data.Value)
			end
			data.Instance = st

			return data
		end

		--@@Opsei MultiSelect  (Syde-native dropdown upgrade: multi-pick with
		--   checkmarks, search filter, expandable list. Bar #151515 corner 10,
		--   options #1E1E1E 30px fully-rounded, accent checks.)
		function initelement:MultiSelect(Opt)
			local data = {
				Title = Opt.Title or "MultiSelect";
				Desc = Opt.Description or "";
				Options = Opt.Options or {};
				Value = Opt.Value or {};
				Placeholder = Opt.Placeholder or "Select...";
				CallBack = Opt.CallBack;
				Flag = Opt.Flag;
			}
			if type(data.Value) ~= "table" then data.Value = {} end

			-- dedupe options
			do
				local seen = {}
				local out = {}
				for _, o in ipairs(data.Options) do
					if not seen[o] then seen[o] = true; out[#out + 1] = o end
				end
				data.Options = out
			end

			local COLLAPSED_H = 58
			local EXPANDED_H = 212

			local function contains(t, v)
				for _, x in ipairs(t) do if x == v then return true end end
				return false
			end

			-- row shell: #111111 trans 0.5, 15px corner
			local ms = Instance.new("Frame")
			ms.Name = data.Title
			ms.Size = UDim2.new(1, -35, 0, COLLAPSED_H)
			ms.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
			ms.BackgroundTransparency = 0.5
			ms.BorderSizePixel = 0
			ms:SetAttribute("Searchable", true)
			ms.Parent = Page
			Instance.new("UICorner", ms).CornerRadius = UDim.new(0, 15)

			-- title: GothamMedium 14 white (matches Dropdown title)
			local title = Instance.new("TextLabel")
			title.Position = UDim2.new(0, 12, 0, 6)
			title.Size = UDim2.new(1, -50, 0, 18)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.GothamMedium
			title.TextSize = 14
			title.Text = data.Title
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextYAlignment = Enum.TextYAlignment.Center
			title.Parent = ms

			if data.Desc ~= "" then
				local desc = Instance.new("TextLabel")
				desc.Position = UDim2.new(0, 12, 0, 22)
				desc.Size = UDim2.new(1, -50, 0, 12)
				desc.BackgroundTransparency = 1
				desc.Font = Enum.Font.Gotham
				desc.TextSize = 11
				desc.Text = data.Desc
				desc.TextColor3 = Color3.fromRGB(86, 86, 86)
				desc.TextXAlignment = Enum.TextXAlignment.Left
				desc.Parent = ms
			end

			-- collapsed bar: #151515, 10px corner, bottom-anchored
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0, 1)
			bar.Position = UDim2.new(0, 10, 1, -8)
			bar.Size = UDim2.new(1, -20, 0, 30)
			bar.BackgroundColor3 = Color3.fromRGB(21, 21, 21)
			bar.BorderSizePixel = 0
			bar.Parent = ms
			Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)

			local barLabel = Instance.new("TextLabel")
			barLabel.Position = UDim2.new(0, 12, 0, 0)
			barLabel.Size = UDim2.new(1, -40, 1, 0)
			barLabel.BackgroundTransparency = 1
			barLabel.Font = Enum.Font.Gotham
			barLabel.TextSize = 14
			barLabel.TextColor3 = Color3.fromRGB(120, 125, 140)
			barLabel.TextXAlignment = Enum.TextXAlignment.Left
			barLabel.TextYAlignment = Enum.TextYAlignment.Center
			barLabel.Parent = bar

			local barArrow = Instance.new("ImageLabel")
			barArrow.AnchorPoint = Vector2.new(1, 0.5)
			barArrow.Position = UDim2.new(1, -12, 0.5, 0)
			barArrow.Size = UDim2.fromOffset(12, 12)
			barArrow.BackgroundTransparency = 1
			barArrow.Image = "rbxassetid://121909773324018"
			barArrow.ImageColor3 = Color3.fromRGB(255, 255, 255)
			barArrow.ScaleType = Enum.ScaleType.Fit
			barArrow.ZIndex = 2
			barArrow.Parent = bar

			local barButton = Instance.new("TextButton")
			barButton.Size = UDim2.new(1, 0, 1, 0)
			barButton.BackgroundTransparency = 1
			barButton.AutoButtonColor = false
			barButton.Text = ""
			barButton.ZIndex = 3
			barButton.Parent = bar

			-- search box (visible when expanded): #212121 trans 0.65, fully rounded
			local searchFrame = Instance.new("Frame")
			searchFrame.Position = UDim2.new(0, 10, 0, 32)
			searchFrame.Size = UDim2.new(1, -20, 0, 25)
			searchFrame.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
			searchFrame.BackgroundTransparency = 0.65
			searchFrame.BorderSizePixel = 0
			searchFrame.Visible = false
			searchFrame.Parent = ms
			Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(1, 0)

			local searchIcon = Instance.new("ImageLabel")
			searchIcon.Position = UDim2.new(0, 10, 0.5, 0)
			searchIcon.AnchorPoint = Vector2.new(0, 0.5)
			searchIcon.Size = UDim2.fromOffset(13, 13)
			searchIcon.BackgroundTransparency = 1
			searchIcon.Image = "rbxassetid://77497922982585"
			searchIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			searchIcon.ImageTransparency = 0.85
			searchIcon.ScaleType = Enum.ScaleType.Fit
			searchIcon.Parent = searchFrame

			local searchBox = Instance.new("TextBox")
			searchBox.Position = UDim2.new(0, 28, 0, 0)
			searchBox.Size = UDim2.new(1, -34, 1, 0)
			searchBox.BackgroundTransparency = 1
			searchBox.Font = Enum.Font.Gotham
			searchBox.TextSize = 12
			searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
			searchBox.PlaceholderText = "Search..."
			searchBox.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
			searchBox.TextXAlignment = Enum.TextXAlignment.Left
			searchBox.TextYAlignment = Enum.TextYAlignment.Center
			searchBox.ClearTextOnFocus = false
			searchBox.Parent = searchFrame

			-- option list (visible when expanded)
			local list = Instance.new("ScrollingFrame")
			list.Position = UDim2.new(0, 10, 0, 62)
			list.Size = UDim2.new(1, -20, 1, -70)
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.ScrollBarThickness = 0
			list.ScrollingDirection = Enum.ScrollingDirection.Y
			list.CanvasSize = UDim2.new(0, 0, 0, 0)
			list.Visible = false
			list.Parent = ms
			local listLayout = Instance.new("UIListLayout", list)
			listLayout.Padding = UDim.new(0, 4)
			listLayout.SortOrder = Enum.SortOrder.LayoutOrder
			local listPad = Instance.new("UIPadding", list)
			listPad.PaddingBottom = UDim.new(0, 4)

			local rows = {} -- {row, nameLbl, check, option}

			local function refreshRow(r)
				local on = contains(data.Value, r.option)
				r.check.ImageTransparency = on and 0 or 1
				r.nameLbl.Font = on and Enum.Font.GothamBold or Enum.Font.GothamMedium
				r.nameLbl.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 204, 215)
			end

			local function updateBar()
				local n = #data.Value
				if n == 0 then
					barLabel.Text = data.Placeholder
					barLabel.TextColor3 = Color3.fromRGB(120, 125, 140)
				else
					local shown = {}
					for i = 1, math.min(n, 2) do shown[#shown + 1] = data.Value[i] end
					barLabel.Text = table.concat(shown, ", ") .. (n > 2 and (" +" .. (n - 2)) or "")
					barLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end

			local function updateCanvas()
				local h = 0
				for _, r in ipairs(rows) do
					if r.row.Visible then h = h + 30 + 4 end
				end
				list.CanvasSize = UDim2.new(0, 0, 0, math.max(h - 4, 1))
			end

			local function commit()
				if data.CallBack then
					local okc, errc = pcall(data.CallBack, data.Value)
					if not okc then
						syde:Report("MultiSelect '" .. data.Title .. "' callback", errc)
					end
				end
				if syde.Flags and data.Flag then
					syde.Flags[data.Flag] = data
				end
			end

			local function toggleOption(v)
				if contains(data.Value, v) then
					local out = {}
					for _, x in ipairs(data.Value) do if x ~= v then out[#out + 1] = x end end
					data.Value = out
				else
					data.Value[#data.Value + 1] = v
				end
				refreshRow(rows[v])
				updateBar()
				commit()
			end

			local function buildRows()
				for _, r in ipairs(rows) do
					pcall(function() r.row:Destroy() end)
				end
				table.clear(rows)
				for _, option in ipairs(data.Options) do
					local row = Instance.new("Frame")
					row.Size = UDim2.new(1, 0, 0, 30)
					row.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
					row.BorderSizePixel = 0
					row.LayoutOrder = #rows + 1
					row.Parent = list
					Instance.new("UICorner", row).CornerRadius = UDim.new(1, 0)

					local nameLbl = Instance.new("TextLabel")
					nameLbl.Position = UDim2.new(0, 12, 0, 0)
					nameLbl.Size = UDim2.new(1, -40, 1, 0)
					nameLbl.BackgroundTransparency = 1
					nameLbl.Font = Enum.Font.GothamMedium
					nameLbl.TextSize = 12
					nameLbl.Text = option
					nameLbl.TextColor3 = Color3.fromRGB(200, 204, 215)
					nameLbl.TextXAlignment = Enum.TextXAlignment.Left
					nameLbl.TextYAlignment = Enum.TextYAlignment.Center
					nameLbl.Parent = row

					local check = Instance.new("ImageLabel")
					check.AnchorPoint = Vector2.new(1, 0.5)
					check.Position = UDim2.new(1, -14, 0.5, 0)
					check.Size = UDim2.fromOffset(12, 12)
					check.BackgroundTransparency = 1
					check.Image = "rbxassetid://18401101470"
					check.ImageColor3 = syde.theme.HitBox
					check.ImageTransparency = 1
					check.ScaleType = Enum.ScaleType.Fit
					check.Parent = row

					local interact = Instance.new("TextButton")
					interact.Size = UDim2.new(1, 0, 1, 0)
					interact.BackgroundTransparency = 1
					interact.AutoButtonColor = false
					interact.Text = ""
					interact.Parent = row

					local r = { row = row, nameLbl = nameLbl, check = check, option = option }
					rows[option] = r
					interact.MouseButton1Click:Connect(function()
						toggleOption(option)
					end)
					refreshRow(r)
				end
				updateCanvas()
			end

			buildRows()

			searchBox:GetPropertyChangedSignal("Text"):Connect(function()
				local q = searchBox.Text:lower()
				for _, r in ipairs(rows) do
					r.row.Visible = (q == "" or r.option:lower():find(q, 1, true) ~= nil)
				end
				updateCanvas()
			end)

			local expanded = false
			local function setExpanded(on)
				expanded = on
				tweenservice:Create(ms, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
					Size = UDim2.new(1, -35, 0, on and EXPANDED_H or COLLAPSED_H),
				}):Play()
				tweenservice:Create(barArrow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential), {
					Rotation = on and 180 or 0,
				}):Play()
				searchFrame.Visible = on
				list.Visible = on
			end

			barButton.MouseButton1Click:Connect(function()
				setExpanded(not expanded)
			end)

			updateBar()

			function data:Get() return data.Value end
			function data:Select(v)
				if not contains(data.Value, v) then
					data.Value[#data.Value + 1] = v
					if rows[v] then refreshRow(rows[v]) end
					updateBar()
					commit()
				end
			end
			function data:Deselect(v)
				local out = {}
				for _, x in ipairs(data.Value) do if x ~= v then out[#out + 1] = x end end
				data.Value = out
				if rows[v] then refreshRow(rows[v]) end
				updateBar()
				commit()
			end
			function data:Set(arr)
				local valid = {}
				for _, v in ipairs(arr or {}) do
					if contains(data.Options, v) and not contains(valid, v) then
						valid[#valid + 1] = v
					end
				end
				data.Value = valid
				for _, r in pairs(rows) do refreshRow(r) end
				updateBar()
				commit()
			end
			function data:SetOptions(newOptions)
				data.Options = newOptions or {}
				buildRows()
				data:Set(data.Value)
			end
			function data:Clear()
				data.Value = {}
				for _, r in pairs(rows) do refreshRow(r) end
				updateBar()
				commit()
			end
			data.Instance = ms

			return data
		end

		for _bn, _bf in pairs(initelement) do
			if type(_bf) == "function" then
				initelement[_bn] = syde:Guard("Building a '" .. tostring(_bn) .. "' element", _bf)
			end
		end

]]
    -- anchor: the original guard loop (exact text) — insert our elements
    -- plus the guard loop right before `return initelement`
    local INJECT_ANCHOR = "for _bn, _bf in pairs(initelement) do"
    local ia = patchedSrc:find(INJECT_ANCHOR, 1, true)
    if ia then
        -- remove the original guard loop block (it ends at the blank line
        -- before `return initelement`), then splice our version in its place
        local loopEnd = patchedSrc:find("\n\n\t\treturn initelement", ia, true)
        if loopEnd then
            patchedSrc = patchedSrc:sub(1, ia - 1) .. CUSTOM_ELEMENTS .. patchedSrc:sub(loopEnd + 2)
        else
            patchedSrc = patchedSrc:sub(1, ia - 1) .. CUSTOM_ELEMENTS .. patchedSrc:sub(ia)
        end
        warn("[SydeLoader] custom elements (Segmented, RangeSlider) injected")
    else
        warn("[SydeLoader] could not find initelement guard loop - custom elements NOT injected")
    end

    -- Opsei privacy: strip Syde's settings "Privacy" tab (Discord OAuth
    -- connect + Anonymous toggle). Replacing the tab builder with a stub
    -- swallows every call the tab's construction code makes, so the tab
    -- simply never exists.
    local PRIVACY_LINE = "local b = settings:inittab({Title = 'Privacy'})"
    local pp = patchedSrc:find(PRIVACY_LINE, 1, true)
    if pp then
        patchedSrc = patchedSrc:sub(1, pp - 1)
            .. "local b = setmetatable({}, { __index = function() return function() end end })"
            .. patchedSrc:sub(pp + #PRIVACY_LINE)
    end

    local syde = loadstring(patchedSrc)()
    if not syde then error("Syde failed to load") end
    if pp then warn("[SydeLoader] settings Privacy tab stripped") else warn("[SydeLoader] Privacy tab anchor not found - tab may still show") end

    -- Opsei safety: wrap the settings-gear uptime heartbeat Set call in pcall
    -- so a missing Paragraph template never throws 60 frames/sec.
    local UPTIME_LINE = 'uptimeParagraph:Set("Session Uptime: " .. formatted, ' .. "'Session UpTime')"
    local up = patchedSrc:find(UPTIME_LINE, 1, true)
    if up then
        patchedSrc = patchedSrc:sub(1, up - 1)
            .. "pcall(function() " .. UPTIME_LINE .. " end)"
            .. patchedSrc:sub(up + #UPTIME_LINE)
    end

    -- Opsei accent: #93bafa instead of Syde's default pink.
    -- Set before Init so every element built from the theme (tab
    -- indicators, toggle fills, slider fills, accent colorpicker) is blue.
    local ACCENT = Color3.fromRGB(147, 186, 250)
    if syde.theme then
        syde.theme.Accent = ACCENT
        syde.theme.HitBox = ACCENT
    end

    api.syde = syde

    -- Opsei-branded window
    local Window = syde:Init({
        Title = "OSPEI",
        SubText = "Hood Rivals  v1.5-dev",
    })

    -- boot toast: one-line confirmation that the suite is up
    pcall(function()
        syde:Toast({ Content = "Ospei Hood Rivals v1.5-dev loaded", Duration = 3 })
    end)

    local Tabs = {}
    local function Tab(title)
        local t = Window:InitTab({ Title = title })
        Tabs[title] = t
        return t
    end

    -- shared helpers: every control writes CFG and persists
    local function onToggle(key, apply)
        return function(v)
            CFG[key] = v
            if apply then pcall(apply, v) end
            saveCfg()
        end
    end
    local function onSlider(key, apply)
        return function(v)
            CFG[key] = v
            if apply then pcall(apply, v) end
            saveCfg()
        end
    end
    local function onPick(key, apply)
        return function(v)
            CFG[key] = v
            if apply then pcall(apply, v) end
            saveCfg()
        end
    end

    -----------------------------------------------------------------
    -- AIM tab
    -----------------------------------------------------------------
    local aim = Tab("Aim")
    aim:Section("Mode", 733765307)
    aim:Dropdown({
        Title = "Aim Mode",
        PlaceHolder = "Off",
        Options = AIM_CYCLE,
        CallBack = function(v)
            CFG.aimStyle = v
            saveCfg()
            pcall(function()
                syde:Notify({ Title = "Aim Mode", Content = "Aim is now " .. v, Duration = 2.5 })
            end)
        end,
    })
    aim:Dropdown({
        Title = "Target Part",
        PlaceHolder = "Auto",
        Options = { "Auto", "Head", "Chest", "Body" },
        CallBack = function(v)
            CFG.targetPart = v
            saveCfg()
            pcall(function()
                syde:Toast({ Content = "Target: " .. v, Duration = 2 })
            end)
        end,
    })
    aim:Dropdown({
        Title = "Aim Curve",
        PlaceHolder = "Linear",
        Options = CURVE_CYCLE,
        CallBack = function(v)
            CFG.aimCurve = v
            saveCfg()
            pcall(function()
                syde:Toast({ Content = "Curve: " .. v, Duration = 2 })
            end)
        end,
    })

    aim:Section("Behavior", 743872758)
    aim:Toggle({ Title = "Trigger Bot", Value = CFG.triggerBot, Config = true, CallBack = onToggle("triggerBot") })
    aim:Toggle({ Title = "Team Check", Value = CFG.teamCheck, Config = true, CallBack = onToggle("teamCheck") })
    aim:Toggle({ Title = "Wall Check", Value = CFG.wallCheck, Config = true, CallBack = onToggle("wallCheck") })

    aim:Section("FOV Ring", 733919881)
    aim:Toggle({ Title = "Show Ring", Value = CFG.fovEnabled, Config = true, CallBack = onToggle("fovEnabled") })
    aim:Stepper({
        Title = "Ring Size",
        Value = CFG.fovRadius,
        Min = 10,
        Max = 120,
        Increment = 1,
        Suffix = "°",
        CallBack = onSlider("fovRadius"),
    })

    aim:Section("Tuning", 733799969)
    aim:Stepper({
        Title = "Lead Shots",
        Value = CFG.lead,
        Min = 0,
        Max = 2,
        Increment = 0.05,
        CallBack = onSlider("lead"),
    })
    aim:Stepper({
        Title = "Pull Strength",
        Value = CFG.assistStrength,
        Min = 0.05,
        Max = 1,
        Increment = 0.05,
        CallBack = onSlider("assistStrength"),
    })

    -----------------------------------------------------------------
    -- WEAPONS tab
    -----------------------------------------------------------------
    local weapon = Tab("Weapons")
    weapon:Section("Gun Feel", 733798747)
    weapon:Toggle({ Title = "No Recoil", Value = CFG.noRecoil, Config = true, CallBack = onToggle("noRecoil", function() WMI.apply() end) })
    weapon:Toggle({ Title = "No Spread", Value = CFG.noSpread, Config = true, CallBack = onToggle("noSpread", function() WMI.apply() end) })
    weapon:Toggle({ Title = "Rapid Fire", Value = CFG.rapidFire, Config = true, CallBack = onToggle("rapidFire", function() WMI.apply() end) })
    weapon:Toggle({ Title = "Bullet Trails", Value = CFG.tracer, Config = true, CallBack = onToggle("tracer", function() WMI.apply() end) })
    weapon:Toggle({ Title = "Infinite Ammo", Value = CFG.infiniteAmmo, Config = true, CallBack = onToggle("infiniteAmmo", function() WMI.apply(); WMI.resetAmmoCycle() end) })
    weapon:Toggle({ Title = "Auto Reload", Value = CFG.autoReload, Config = true, CallBack = onToggle("autoReload") })
    weapon:Toggle({ Title = "No Screen Shake", Value = CFG.noShake, Config = true, CallBack = onToggle("noShake", function() WMI.apply() end) })

    -----------------------------------------------------------------
    -- MOVEMENT tab
    -----------------------------------------------------------------
    local move = Tab("Movement")
    move:Section("Flight", 734037723)
    move:Toggle({ Title = "Fly", Value = CFG.flight, Config = true, CallBack = onToggle("flight") })
    move:Stepper({
        Title = "Fly Speed",
        Value = CFG.flightSpeed,
        Min = 5,
        Max = 300,
        Increment = 5,
        CallBack = onSlider("flightSpeed"),
    })

    move:Section("Run", 743878264)
    move:Toggle({ Title = "Speed Hack", Value = CFG.speed, Config = true, CallBack = onToggle("speed") })
    move:Stepper({
        Title = "Speed Value",
        Value = CFG.speedValue,
        Min = 5,
        Max = 200,
        Increment = 2,
        CallBack = onSlider("speedValue"),
    })
    move:Toggle({ Title = "Auto Jump", Value = CFG.autoJump, Config = true, CallBack = onToggle("autoJump") })

    move:Section("Walls", 734056608)
    move:Toggle({ Title = "Walk Through Walls", Value = CFG.noClip, Config = true, CallBack = onToggle("noClip", function(v) applyNoClip(v) end) })

    -----------------------------------------------------------------
    -- VISUALS tab
    -----------------------------------------------------------------
    local visual = Tab("Visuals")
    visual:Section("Highlights", 733774602)
    visual:Toggle({ Title = "Enemies", Value = CFG.enemyHl, Config = true, CallBack = onToggle("enemyHl", function() onEspEvent() end) })
    visual:Toggle({ Title = "Teammates", Value = CFG.teamHl, Config = true, CallBack = onToggle("teamHl", function() onEspEvent() end) })
    visual:Toggle({ Title = "NPCs", Value = CFG.npcHl, Config = true, CallBack = onToggle("npcHl", function() onEspEvent() end) })
    visual:Stepper({
        Title = "Glow Strength",
        Description = "0 = off, 1 = full",
        Value = 1 - CFG.hlTrans,
        Min = 0,
        Max = 1,
        Increment = 0.05,
        CallBack = function(v)
            CFG.hlTrans = 1 - v
            onEspEvent()
            saveCfg()
        end,
    })

    visual:Section("Player Tracking", 743875962)
    visual:Toggle({ Title = "Name Tags", Value = CFG.nameTags, Config = true, CallBack = onToggle("nameTags", function() onEspEvent() end) })
    visual:Toggle({ Title = "Health Bars", Value = CFG.healthBars, Config = true, CallBack = onToggle("healthBars", function() onEspEvent() end) })

    visual:Section("HUD", 734002839)
    visual:Toggle({ Title = "Hitmarkers", Value = CFG.hitmarker, Config = true, CallBack = onToggle("hitmarker") })
    visual:Dropdown({
        Title = "Crosshair",
        PlaceHolder = "Off",
        Options = CROSS_STYLES,
        CallBack = function(v)
            CFG.crossStyle = v
            saveCfg()
            pcall(function()
                syde:Toast({ Content = "Crosshair: " .. v, Duration = 2 })
            end)
        end,
    })
    visual:Stepper({
        Title = "Crosshair Size",
        Value = CFG.crossSize,
        Min = 2,
        Max = 12,
        Increment = 1,
        CallBack = onSlider("crossSize"),
    })

    -----------------------------------------------------------------
    -- PLAYER tab (survival + cash)
    -----------------------------------------------------------------
    local player = Tab("Player")
    player:Section("Survival", 733956134)
    player:Toggle({ Title = "Infinite Health", Value = CFG.infHealth, Config = true, CallBack = onToggle("infHealth") })
    player:Toggle({ Title = "Infinite Armor", Value = CFG.infArmor, Config = true, CallBack = onToggle("infArmor") })
    player:Stepper({
        Title = "Armor Value",
        Value = CFG.armorValue,
        Min = 0,
        Max = 500,
        Increment = 25,
        CallBack = onSlider("armorValue"),
    })
    player:Toggle({ Title = "Anti Ragdoll", Value = CFG.antiRagdoll, Config = true, CallBack = onToggle("antiRagdoll") })
    player:Toggle({ Title = "Auto Medkit", Value = CFG.autoMedkit, Config = true, CallBack = onToggle("autoMedkit") })
    player:Stepper({
        Title = "Medkit HP",
        Value = CFG.medkitHP,
        Min = 10,
        Max = 200,
        Increment = 10,
        CallBack = onSlider("medkitHP"),
    })

    player:Section("Cash", 743866529)
    player:Toggle({ Title = "Cash ESP", Value = CFG.cashEsp, Config = true, CallBack = onToggle("cashEsp", function() refreshCashEsp() end) })
    player:Toggle({ Title = "Cash Grab", Value = CFG.autoCash, Config = true, CallBack = onToggle("autoCash") })

    -- unload keybind (X) with Modal confirmation
    player:Section("Controls", 733965118)
    player:Keybind({
        Title = "Unload (X)",
        Key = Enum.KeyCode.X,
        CallBack = function()
            pcall(function()
                syde:Modal({
                    Title = "Unload OSPEI?",
                    Content = "All features will turn off and the UI will close.",
                    ConfimCallBack = function()
                        if _G.Ospei_HoodRivals_Unload then _G.Ospei_HoodRivals_Unload() end
                    end,
                })
            end)
        end,
    })

    -----------------------------------------------------------------
    -- keep dropdowns in sync with externally-changed CFG (e.g. G key)
    -----------------------------------------------------------------
    -- (no-op in v1; dropdowns are the single source of truth for enums)

    api.destroy = function()
        pcall(function()
            local parent = (gethui and gethui()) or game:GetService("CoreGui")
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("ScreenGui") and child:FindFirstChild("SYDEUIDetector") then
                    child:Destroy()
                end
            end
        end)
    end

    return api
end)()

----------------------------------------------------------------
-- INPUT WIRING (keyboard shortcuts)
----------------------------------------------------------------
-- G: cycle aim mode (Off -> Assist -> Silent -> Off)
connect(UserInputService.InputBegan, function(input, gp)
    if gp then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode == Enum.KeyCode.G then
        local idx = 1
        for i, v in ipairs(AIM_CYCLE) do
            if v == CFG.aimStyle then idx = i; break end
        end
        CFG.aimStyle = AIM_CYCLE[(idx % #AIM_CYCLE) + 1]
        saveCfg()
        -- same Notify as the Aim Mode dropdown so the G key matches the UI
        pcall(function()
            if SydeUI and SydeUI.syde then
                SydeUI.syde:Notify({ Title = "Aim Mode", Content = "Aim is now " .. CFG.aimStyle, Duration = 2.5 })
            end
        end)
    end
end)

----------------------------------------------------------------
-- LOOPS
----------------------------------------------------------------
connect(RunService.Heartbeat, function()
    espTick = espTick + 1
    if espTick % 45 == 0 then
        -- player diff ~every 0.75s; full NPC scan ~every 3s
        updateESP(espTick % 180 == 0)
    end
end)

connect(RunService.RenderStepped, function(dt)
    if CFG.aimStyle == "Assist" then
        assistStep(dt)
    elseif CFG.aimStyle == "Silent" then
        silentStep(dt)
    else
        flick = nil
    end
    if CFG.triggerBot then triggerStep() end
    if CFG.hitmarker and locked and locked.Parent and CFG.aimStyle ~= "Off"
        and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        Hitmarker.tick()
    end
    if CFG.tracer and locked and locked.Parent and CFG.aimStyle ~= "Off"
        and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        local cam = getCamera()
        local part = locked:FindFirstChild("HumanoidRootPart")
        if cam and part then
            spawnTracer(cam.CFrame.Position, part.Position - cam.CFrame.Position)
        end
    end
    movementStep()
    autoCashStep()
    survivalStep()
    medkitStep()
    WMI.step()
    FovRing.update()
    Crosshair.update()
    updateEspBoxes(dt)
end)

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------
if _G.Ospei_HoodRivals_Unload then pcall(_G.Ospei_HoodRivals_Unload) end
_G.Ospei_HoodRivals_Unload = function()
    if not Runtime.live then return end
    Runtime.live = false
    saveCfg()
    if CFG.noClip then applyNoClip(false) end
    destroyEsp()
    FovRing.destroy()
    Crosshair.destroy()
    Hitmarker.destroy()
    pcall(function() EspGui:Destroy() end)
    pcall(WMI.destroy)
    pcall(SydeUI.destroy)
    for _, c in ipairs(Runtime.Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Runtime.Connections)
    locked, flick = nil, nil
    _G.Ospei_HoodRivals_Unload = nil
end
