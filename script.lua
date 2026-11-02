--[[
    RIOT HUB MOBILE v4.0  //  PRISON LIFE
    A mobile-first rebuild of RiotHub for Prison Life.

    Design contract
      * The phone layout is the primary layout. 320 px wide is the smallest
        supported viewport; every interactive row is at least 44 px tall.
      * ScreenGui uses CoreUISafeInsets + ClipToDeviceSafeArea, so the hub
        stays below the Roblox topbar and inside the device safe area.
      * The layout is recomputed when Camera.ViewportSize changes (rotation).
      * Dragging is clamped and follows the originating InputObject. No
        global "one finger moves everything" handlers.
      * Unload restores movement, noclip, lighting, particles, camera FOV,
        gun-module fields, barriers, the silent-aim hook, ESP and the GUI.

    Honesty contract
      * "Sent" means the client call completed. It does not claim the server
        accepted it. Arrest/team results are checked on the client where the
        game exposes the result; otherwise the toast says "request sent".
      * Every remote call is pcall-guarded and written to the in-hub log.
      * No feature claims to bypass server anti-cheat.

    The attached PL-Vortex-7.1 and the previous Riothub.lua are preserved.
]]

local VERSION = "4.0"
local R = {
    version = VERSION,
    name = "RiotHub Mobile",
    services = {},
    config = {},
    state = {},
    ui = {},
    pages = {},
    remotes = {},
}

local SERVICES = {
    "Players", "ReplicatedStorage", "RunService", "UserInputService",
    "TweenService", "HttpService", "StarterGui", "TeleportService",
    "VirtualUser", "Lighting", "GuiService", "Workspace",
}
for _, serviceName in ipairs(SERVICES) do
    local ok, service = pcall(function() return game:GetService(serviceName) end)
    if ok then R.services[serviceName] = service end
end

local Players = R.services.Players
local UIS = R.services.UserInputService
local RunService = R.services.RunService
local TweenService = R.services.TweenService

local function waitForLocalPlayer()
    if Players.LocalPlayer then return Players.LocalPlayer end
    local waited = 0
    while not Players.LocalPlayer and waited < 20 do
        task.wait(0.25)
        waited = waited + 0.25
    end
    return Players.LocalPlayer
end

R.lp = waitForLocalPlayer()
if not R.lp then
    error("[RiotHub] no LocalPlayer — join Prison Life, then execute", 0)
end

R.unpack = table.unpack or unpack
R.env = (getgenv and getgenv()) or _G
if type(R.env.RiotHubMobile) == "table"
    and type(R.env.RiotHubMobile.Unload) == "function" then
    pcall(R.env.RiotHubMobile.Unload)
end

-- Remove stale screens from earlier runs even if their genv table is gone.
do
    local parents = {}
    local ok, playerGui = pcall(function() return R.lp:FindFirstChild("PlayerGui") end)
    if ok and playerGui then table.insert(parents, playerGui) end
    if gethui then pcall(function() table.insert(parents, gethui()) end) end
    local okCore, coreGui = pcall(function() return game:FindFirstChildOfClass("CoreGui") end)
    if okCore and coreGui then table.insert(parents, coreGui) end
    for _, parent in ipairs(parents) do
        for _, screenName in ipairs({
            "RiotHubMobile_GUI", "RiotHubMobile_Picker", "RiotHubMobile_FOV",
            "RiotHubMobile_ESP", "RiotHub_GUI", "RiotHubFOVRing",
        }) do
            local old = parent:FindFirstChild(screenName)
            if old then pcall(function() old:Destroy() end) end
        end
    end
end

R.config = {
    -- combat
    killAuraRadius = 60,
    killAuraRate = 0.30,
    killAuraMode = "Fists",
    meleeBurstHits = 4,
    gunBulletsPerCall = 8,
    respectForcefield = true,
    auraTargets = "All",
    arrestAuraRadius = 120,
    arrestAuraRate = 1.2,
    arrestSnap = true,
    tazeRate = 0.8,
    -- aim
    aimbotFov = 160,
    aimbotSmooth = 35,
    aimbotTargets = "All",
    aimAlwaysLock = false,
    silentFov = 999,
    silentHitChance = 100,
    silentWallCheck = true,
    silentRandomPart = false,
    triggerOn = false,
    showAimFov = true,
    -- guns
    gunChoice = "M9",
    gunDamage = 65,
    gunBullets = 10,
    gunFireRate = 0.001,
    gunSpread = 0,
    gunInfiniteAmmo = true,
    gunAutoFire = true,
    autoRearm = false,
    autoCollectRadius = 200,
    itemPace = 3.2,
    -- visuals
    espNames = true,
    espDistance = true,
    espHealth = true,
    espTeamColor = true,
    espVisibleOnly = false,
    espTracers = false,
    chamsThroughWalls = true,
    -- movement
    walkSpeed = 16,
    jumpPower = 50,
    tpWalkPower = 3,
    flySpeed = 3,
    spinSpeed = 25,
    cameraFov = 70,
    -- world
    gateSpamInterval = 1.5,
    antiAfk = true,
    instantRespawn = false,
    antiStun = false,
    reduceAnim = false,
    quickDock = true,
    -- system
    maxLogLines = 60,
}

R.defaultConfig = {}
for key, value in pairs(R.config) do R.defaultConfig[key] = value end

R.state = {
    toggles = {},
    switches = {},
    sliders = {},
    dropdowns = {},
    connections = {},
    logLines = {},
    logCounter = 0,
    detached = false,
    loaded = false,
    open = true,
    activeTab = nil,
    isTouch = UIS and UIS.TouchEnabled or false,
    lastItemPull = 0,
    itemBusy = false,
    arrestBusy = false,
    tazeBusy = false,
    killCounter = 0,
    arrestCount = 0,
    itemCount = 0,
    fps = 0,
    frameCount = 0,
    aimHeld = false,
    flyLift = 0,
    flyButtons = {},
    espUnits = {},
    tracers = {},
    chamsSeen = {},
    noclipSaved = {},
    barrierSaved = {},
    gunSaved = {},
    fpsSaved = {},
    lightingSaved = nil,
    cameraFovSaved = nil,
    silentHook = nil,
    silentOld = nil,
    movementBase = nil,
    picker = nil,
    layout = {},
    ui = {},
    nearby = {},
    nearbyKey = "",
    lastStatus = 0,
    statusText = "starting",
}

function R.now()
    return os.clock()
end

function R.viewport()
    local camera = workspace and workspace.CurrentCamera
    if camera and camera.ViewportSize and camera.ViewportSize.X > 0 then
        return camera.ViewportSize
    end
    return Vector2.new(1280, 720)
end

function R.connect(signal, fn)
    if not signal then return nil end
    local ok, connection = pcall(function() return signal:Connect(fn) end)
    if ok and connection then
        table.insert(R.state.connections, connection)
        return connection
    end
    return nil
end

function R.disconnectAll()
    for _, connection in ipairs(R.state.connections) do
        pcall(function() connection:Disconnect() end)
    end
    R.state.connections = {}
end

function R.spawn(fn, ...)
    local args = { ... }
    local n = select("#", ...)
    return task.spawn(function()
        fn(R.unpack(args, 1, n))
    end)
end

-- Fire-and-forget with a real error path. Never say "done" just because pcall
-- returned; callers decide what a successful send means.
function R.safe(label, fn, ...)
    -- An unloaded instance keeps its table alive if the caller saved it. Every
    -- remote path goes through here, so refuse sends after teardown instead of
    -- letting a stale reference poke the game.
    if R.state.detached then return false, "detached" end
    local args = { ... }
    local n = select("#", ...)
    local ok, err = pcall(function()
        return fn(R.unpack(args, 1, n))
    end)
    if not ok then
        R.log(tostring(label or "action") .. " failed: " .. tostring(err), true)
    end
    return ok, err
end

function R.log(message, isErr)
    local body = tostring(message)
    if #body > 180 then body = body:sub(1, 177) .. "..." end
    print("[RiotHub] " .. body)
    local S = R.state
    S.logCounter = S.logCounter + 1
    table.insert(S.logLines, string.format("%3d %s%s", S.logCounter % 1000,
        isErr and "[ERR] " or "", body))
    while #S.logLines > R.config.maxLogLines do table.remove(S.logLines, 1) end
    if R.ui.refreshLog then pcall(R.ui.refreshLog) end
end

function R.notify(title, text, duration)
    pcall(function()
        R.services.StarterGui:SetCore("SendNotification", {
            Title = tostring(title), Text = tostring(text), Duration = duration or 3,
        })
    end)
end

-- Rebound by the UI module. Every early caller is safe.
function R.toast() end

function R.setStatus(text, kind)
    R.state.statusText = tostring(text)
    if R.ui.setStatus then R.ui.setStatus(text, kind) end
end

function R.teamColorName(plr)
    if not plr then return "" end
    local ok, color = pcall(function() return plr.TeamColor end)
    if ok and color then
        local okName, name = pcall(function() return color.Name end)
        if okName and name then return tostring(name) end
        return tostring(color)
    end
    return ""
end

function R.teamName(plr)
    if not plr then return "" end
    local ok, team = pcall(function() return plr.Team end)
    if ok and team then return tostring(team.Name) end
    return ""
end

function R.isGuard(plr)
    local color = R.teamColorName(plr)
    local name = string.lower(R.teamName(plr))
    return color == "Bright blue" or string.find(name, "guard", 1, true) ~= nil
        or string.find(name, "police", 1, true) ~= nil
end

function R.isInmate(plr)
    local color = R.teamColorName(plr)
    local name = string.lower(R.teamName(plr))
    return color == "Bright orange" or string.find(name, "inmate", 1, true) ~= nil
        or string.find(name, "prisoner", 1, true) ~= nil
end

function R.isCrim(plr)
    local color = R.teamColorName(plr)
    local name = string.lower(R.teamName(plr))
    return color == "Bright red" or string.find(name, "criminal", 1, true) ~= nil
end

function R.matchesFilter(plr, filter)
    if filter == "Guards" then return R.isGuard(plr) end
    if filter == "Inmates" then return R.isInmate(plr) end
    if filter == "Criminals" then return R.isCrim(plr) end
    return true
end

function R.character(plr)
    return (plr or R.lp).Character
end

function R.humanoid(plr)
    local character = R.character(plr)
    return character and character:FindFirstChildOfClass("Humanoid")
end

function R.root(plr)
    local character = R.character(plr)
    return character and (character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart)
end

function R.alive(plr)
    local hum = R.humanoid(plr)
    return hum ~= nil and hum.Health > 0
end

function R.isCuffed(plr)
    local character = R.character(plr)
    local head = character and character:FindFirstChild("Head")
    return head ~= nil and head:FindFirstChild("handcuffedGui") ~= nil
end

function R.validTarget(plr, filter)
    if not plr or plr == R.lp then return false end
    if not R.alive(plr) then return false end
    if not R.root(plr) then return false end
    if filter and not R.matchesFilter(plr, filter) then return false end
    return true
end

function R.nearest(filter, radius)
    local myRoot = R.root()
    if not myRoot then return nil end
    local best, bestDistance = nil, radius or math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if R.validTarget(plr, filter) then
            local theirRoot = R.root(plr)
            local distance = (theirRoot.Position - myRoot.Position).Magnitude
            if distance <= bestDistance then
                best, bestDistance = plr, distance
            end
        end
    end
    return best, bestDistance
end

-- ============================================================================
-- REMOTES
-- ============================================================================
function R.remotesFolder(timeout)
    local ws = workspace
    if not ws then return nil end
    return ws:FindFirstChild("Remote") or ws:WaitForChild("Remote", timeout or 5)
end

function R.getRemote(remoteName, timeout)
    local folder = R.remotesFolder(timeout)
    if not folder then return nil end
    return folder:FindFirstChild(remoteName) or folder:WaitForChild(remoteName, timeout or 2)
end

function R.resolveRemotes()
    local M = R.remotes
    task.spawn(function()
        local folder = R.remotesFolder(15)
        if folder then
            M.folder = folder
            M.item = folder:FindFirstChild("ItemHandler") or folder:WaitForChild("ItemHandler", 8)
            M.arrest = folder:FindFirstChild("arrest") or folder:FindFirstChild("Arrest")
            M.team = folder:FindFirstChild("TeamEvent")
            M.loadchar = folder:FindFirstChild("loadchar")
            M.gate = folder:FindFirstChild("PrisonGate")
            R.log("remotes: ItemHandler=" .. tostring(M.item ~= nil)
                .. " arrest=" .. tostring(M.arrest ~= nil)
                .. " team=" .. tostring(M.team ~= nil))
        else
            R.log("Remote folder not found yet; use Setup > Rebind remotes", true)
        end
        local rs = R.services.ReplicatedStorage
        M.melee = rs:FindFirstChild("meleeEvent") or rs:WaitForChild("meleeEvent", 10)
        M.shoot = rs:FindFirstChild("ShootEvent") or rs:WaitForChild("ShootEvent", 10)
        R.log("remotes: melee=" .. tostring(M.melee ~= nil)
            .. " shoot=" .. tostring(M.shoot ~= nil))
        if R.ui.syncStatus then pcall(R.ui.syncStatus) end
    end)
end

function R.rebindRemotes()
    local M = R.remotes
    local folder = R.remotesFolder(4)
    if folder then
        M.folder = folder
        M.item = folder:FindFirstChild("ItemHandler") or M.item
        M.arrest = folder:FindFirstChild("arrest") or folder:FindFirstChild("Arrest") or M.arrest
        M.team = folder:FindFirstChild("TeamEvent") or M.team
        M.loadchar = folder:FindFirstChild("loadchar") or M.loadchar
    end
    local rs = R.services.ReplicatedStorage
    M.melee = M.melee or rs:FindFirstChild("meleeEvent")
    M.shoot = M.shoot or rs:FindFirstChild("ShootEvent")
    local summary = string.format("melee=%s shoot=%s item=%s arrest=%s",
        tostring(M.melee ~= nil), tostring(M.shoot ~= nil),
        tostring(M.item ~= nil), tostring(M.arrest ~= nil))
    R.log("rebind: " .. summary, not (M.melee and M.shoot and M.item))
    if R.ui.syncStatus then pcall(R.ui.syncStatus) end
    return M
end

-- ============================================================================
-- ITEM GRANTING
-- ============================================================================
function R.prisonItems()
    return workspace:FindFirstChild("Prison_ITEMS")
end

function R.findItemAnywhere(itemName)
    local tableRoot = R.prisonItems()
    if not tableRoot then return nil end
    return tableRoot:FindFirstChild(itemName, true)
end

function R.getItemIn(subfolder, itemName, childName)
    local tableRoot = R.prisonItems()
    if not tableRoot then return nil end
    local folder = tableRoot:FindFirstChild(subfolder)
    if not folder then return nil end
    local entry = folder:FindFirstChild(itemName)
    if not entry then return nil end
    if childName then
        return entry:FindFirstChild(childName)
            or entry:FindFirstChild("ITEMPICKUP")
            or entry:FindFirstChildWhichIsA("BasePart")
    end
    return entry
end

function R.pace()
    -- Reserve a slot before waiting. Concurrent give actions therefore get
    -- distinct slots instead of waking together and bursting the server.
    local now = R.now()
    local slot = math.max(now, (R.state.lastItemPull or 0) + R.config.itemPace)
    R.state.lastItemPull = slot
    local left = slot - now
    if left > 0 then task.wait(left) end
end

function R.giveItem(holder, label)
    if R.state.detached then return false end
    local M = R.remotes
    if not M.item then
        local folder = R.remotesFolder(2)
        if folder then M.item = folder:FindFirstChild("ItemHandler") end
    end
    if not M.item then
        R.log("ItemHandler unavailable; cannot grant " .. tostring(label), true)
        return false
    end
    R.pace()
    if R.state.detached then return false end
    local ok = R.safe("give " .. tostring(label), function()
        M.item:InvokeServer(holder)
    end)
    if ok then
        R.state.itemCount = R.state.itemCount + 1
        R.log("grant request sent: " .. tostring(label or "item"))
    end
    return ok
end

function R.giveAnywhere(itemName)
    local target = R.findItemAnywhere(itemName)
    if not target then
        R.log("item not on this map: " .. tostring(itemName), true)
        return false
    end
    local pivot = CFrame.new(0, 100, 0)
    pcall(function() pivot = R.lp.Character:GetPivot() end)
    return R.giveItem({ Position = pivot, Parent = target }, itemName)
end

function R.giveLegacy(itemName, subfolder)
    local child = R.getItemIn(subfolder or "giver", itemName, "ITEMPICKUP")
        or R.getItemIn("giver", itemName, "ITEMPICKUP")
        or R.getItemIn(subfolder or "giver", itemName)
    if not child then
        R.log("legacy giver missing: " .. tostring(itemName), true)
        return false
    end
    return R.giveItem(child, itemName)
end

function R.giveBest(itemName, subfolder)
    if R.giveAnywhere(itemName) then return true end
    return R.giveLegacy(itemName, subfolder)
end

R.GUNS = { "M9", "MP5", "Remington 870", "AK-47", "M4A1" }
R.MELEE = { "Key card", "Hammer", "Crude Knife" }

function R.giveSelectedGun()
    local name = R.config.gunChoice
    local ok = R.giveBest(name, "giver")
    if R.state.detached then return ok end
    if ok then
        R.toast("Gun", tostring(name) .. " request sent; check your backpack.", 2, "ok")
    else
        R.toast("Gun not sent", "No request reached ItemHandler for " .. tostring(name) .. ".", 3, "err")
    end
    return ok
end

function R.giveNamedGear(itemName)
    local ok = R.giveBest(itemName, "giver")
    if R.state.detached then return ok end
    if ok then
        R.toast(tostring(itemName), "Request sent; check your backpack.", 2, "ok")
    else
        R.toast(tostring(itemName),
            "Not found, or ItemHandler refused the request.", 2, "err")
    end
    return ok
end

function R.giveKit()
    if R.state.itemBusy then
        R.log("kit already running", true)
        R.toast("Kit busy", "Another item grant is already running.", 2, "warn")
        return
    end
    R.state.itemBusy = true
    local totalRequests = #R.GUNS + #R.MELEE + 2
    local estimate = math.ceil(totalRequests * math.max(R.config.itemPace, 0.1))
    R.toast("Kit started", tostring(totalRequests) .. " paced requests (~" .. tostring(estimate)
        .. "s). Check the log for rejected items.", 3, "ok")
    task.spawn(function()
        R.log("granting full kit; item pacing is "
            .. tostring(R.config.itemPace) .. "s per request")
        local total, sent = 0, 0
        local function request(itemName)
            if R.state.detached then return end
            total = total + 1
            if R.giveBest(itemName, "giver") then sent = sent + 1 end
        end
        for _, gun in ipairs(R.GUNS) do request(gun) end
        for _, melee in ipairs(R.MELEE) do request(melee) end
        for _, tool in ipairs({ "Handcuffs", "Taser" }) do request(tool) end
        R.state.itemBusy = false
        if R.state.detached then return end
        if sent > 0 then
            R.toast("Kit requests sent",
                tostring(sent) .. "/" .. tostring(total)
                .. " reached ItemHandler; check your backpack.", 3, "ok")
        else
            R.toast("Kit not sent", "No item request reached ItemHandler.", 3, "err")
        end
        R.log("kit results: " .. tostring(sent) .. "/" .. tostring(total)
            .. " request(s) sent")
    end)
end

function R.giveRiotGear()
    task.spawn(function()
        local total, sent = 0, 0
        local function request(itemName)
            if R.state.detached then return end
            total = total + 1
            if R.giveBest(itemName, "giver") then sent = sent + 1 end
        end
        request("Riot Shield")
        -- Hats are folders containing a "hat" part. The original script sent
        -- that part, not the folder, so keep that payload shape when present
        -- and only fall back to the catalog-entry form.
        local hatName = (R.findItemAnywhere("Police hat") and "Police hat")
            or (R.findItemAnywhere("Riot helmet") and "Riot helmet")
        if hatName then
            local hatPart = R.getItemIn("hats", hatName, "hat")
            if hatPart then
                total = total + 1
                if R.giveItem(hatPart, hatName) then sent = sent + 1 end
            else
                request(hatName)
            end
        else
            R.log("no police hat or riot helmet on this map", true)
        end
        local maskPart = R.getItemIn("hats", "Ski mask", "hat")
        if maskPart then
            total = total + 1
            if R.giveItem(maskPart, "Ski mask") then sent = sent + 1 end
        elseif R.findItemAnywhere("Ski mask") then
            request("Ski mask")
        else
            R.log("no ski mask on this map", true)
        end
        if R.state.detached then return end
        if sent > 0 then
            R.toast("Riot gear", tostring(sent) .. "/" .. tostring(total)
                .. " request(s) reached ItemHandler; check your backpack.", 3, "ok")
        else
            R.toast("Riot gear not sent", "No riot gear request reached ItemHandler.", 3, "err")
        end
        R.log("riot gear requests: " .. tostring(sent) .. "/" .. tostring(total))
    end)
end

function R.ensureGun(preferred, budget)
    local function find()
        local character = R.character()
        local backpack = R.lp.Backpack
        local containers = { character, backpack }
        for _, container in ipairs(containers) do
            if container then
                if preferred then
                    local named = container:FindFirstChild(preferred)
                    if named and named:IsA("Tool") and named:FindFirstChild("GunStates") then
                        return named
                    end
                end
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and tool:FindFirstChild("GunStates") then
                        return tool
                    end
                end
            end
        end
        return nil
    end
    local tool = find()
    if tool then return tool end
    R.giveBest(preferred or R.config.gunChoice, "giver")
    for _ = 1, math.max(budget or 6, 1) do
        task.wait(0.5)
        if R.state.detached then return nil end
        tool = find()
        if tool then return tool end
    end
    return nil
end
-- ============================================================================
-- FEATURES — every function here is called from the UI or the runtime loops.
-- ============================================================================

local S = R.state
local C = R.config
local Players = R.services.Players
local UIS = R.services.UserInputService
local RunService = R.services.RunService

do
    local ok, drawing = pcall(function() return Drawing end)
    R.drawingOk = ok and drawing ~= nil
end

-- ============================================================================
-- GUN ENGINE
-- ============================================================================
local GUN_FIELDS = {
    "Damage", "Bullets", "FireRate", "Spread", "ReloadTime",
    "AutoFire", "MaxAmmo", "StoredAmmo", "CurrentAmmo",
}

function R.gunState(tool)
    if not (tool and tool:FindFirstChild("GunStates")) then return nil end
    local ok, state = pcall(function() return require(tool.GunStates) end)
    if ok and type(state) == "table" then return state end
    return nil
end

function R.findGunTool(preferred)
    local function sweep(container)
        if not container then return nil end
        if preferred then
            local named = container:FindFirstChild(preferred)
            if named and named:IsA("Tool") and named:FindFirstChild("GunStates") then
                return named
            end
        end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tool:FindFirstChild("GunStates") then
                return tool
            end
        end
        return nil
    end
    return sweep(R.character()) or sweep(R.lp.Backpack)
end

function R.buildBullets(targetPart, count)
    local bullets = {}
    for index = 1, count or 1 do
        bullets[index] = {
            RayObject = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0.1, 0.1, 0.1)),
            Distance = 25,
            Cframe = targetPart and targetPart.CFrame or CFrame.new(),
            Color = Color3.fromRGB(255, 255, 0),
            HitPart = targetPart,
            Visualize = false,
        }
    end
    return bullets
end

function R.shootAt(plr, tool, count)
    local shoot = R.remotes.shoot
    if not shoot then return false end
    local character = R.character(plr)
    if not character then return false end
    local part = character:FindFirstChild("Head")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
    if not part then return false end
    local bullets = R.buildBullets(part, count)
    return R.safe("ShootEvent", function()
        shoot:FireServer(bullets, tool)
    end)
end

function R.modGun(tool)
    if S.detached then return false end
    if not (tool and tool:IsA("Tool") and tool:FindFirstChild("GunStates")) then
        R.log("not a moddable gun: " .. tostring(tool and tool.Name), true)
        return false
    end
    local module = R.gunState(tool)
    if not module then
        R.log("GunStates is not a readable table on " .. tool.Name, true)
        return false
    end
    if not S.gunSaved[tool] then
        local snapshot = {}
        for _, field in ipairs(GUN_FIELDS) do snapshot[field] = module[field] end
        S.gunSaved[tool] = snapshot
    end
    local ok = pcall(function()
        module.Damage = C.gunDamage
        module.Bullets = C.gunBullets
        module.FireRate = math.max(C.gunFireRate, 0.0001)
        module.Spread = C.gunSpread
        module.ReloadTime = 0.0001
        module.AutoFire = C.gunAutoFire
        module.MaxAmmo = math.max(module.MaxAmmo or 0, 1000)
        module.StoredAmmo = 999999
        if C.gunInfiniteAmmo then
            module.CurrentAmmo = math.huge
        else
            module.CurrentAmmo = module.MaxAmmo
        end
    end)
    if not ok then
        R.log("GunStates write failed on " .. tool.Name .. " (locked module?)", true)
        return false
    end
    R.log("GunStates rewritten client-side on " .. tool.Name)
    return true
end

function R.modAllGuns()
    if S.detached then return 0 end
    local hits = 0
    local function sweep(container)
        if not container then return end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tool:FindFirstChild("GunStates") then
                if R.modGun(tool) then hits = hits + 1 end
            end
        end
    end
    sweep(R.character())
    sweep(R.lp.Backpack)
    if hits == 0 then
        R.log("no GunStates tools in the character/backpack", true)
    else
        R.log("gun mods applied to " .. hits .. " tool(s)")
    end
    return hits
end

function R.restoreGuns()
    for tool, snapshot in pairs(S.gunSaved) do
        local module = R.gunState(tool)
        if module then
            for field, value in pairs(snapshot) do
                pcall(function() module[field] = value end)
            end
        end
    end
    S.gunSaved = {}
end

function R.modSelectedGun()
    local tool = R.findGunTool(C.gunChoice)
    if not tool then
        tool = R.ensureGun(C.gunChoice, 4)
    end
    if not tool then
        R.toast("No gun", "Could not find or obtain " .. C.gunChoice, 3, "err")
        return false
    end
    local ok = R.modGun(tool)
    if ok then
        R.toast("Gun modded", tool.Name .. " — client-side GunStates write", 3, "ok")
    end
    return ok
end

-- ============================================================================
-- COMBAT
-- ============================================================================
function R.meleeBurst(plr, hits)
    local event = R.remotes.melee
    if not event then return false end
    if not R.alive(plr) then return false end
    local count = hits or C.meleeBurstHits
    local sent = 0
    for _ = 1, count do
        if S.detached then break end
        if R.safe("meleeEvent", function() event:FireServer(plr) end) then
            sent = sent + 1
            S.killCounter = S.killCounter + 1
        end
        task.wait(0.05)
    end
    return sent > 0, sent
end

function R.gunKill(plr)
    local tool = R.findGunTool(C.gunChoice) or R.findGunTool()
    if not tool then return false end
    local module = R.gunState(tool)
    if module and (module.Damage or 0) < C.gunDamage then
        R.modGun(tool)
    end
    if R.shootAt(plr, tool, C.gunBulletsPerCall) then
        S.killCounter = S.killCounter + 1
        return true
    end
    return false
end

function R.killTarget(plr)
    if not R.validTarget(plr, C.auraTargets) then return false end
    local character = R.character(plr)
    local forcefield = character and character:FindFirstChildOfClass("ForceField")
    if forcefield and C.respectForcefield then
        return false
    end
    if C.killAuraMode == "Gun" and R.gunKill(plr) then
        return true
    end
    return R.meleeBurst(plr, C.meleeBurstHits)
end

function R.killAll()
    task.spawn(function()
        local hits, attempted = 0, 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if S.detached then return end
            if plr ~= R.lp and R.alive(plr) and R.matchesFilter(plr, C.auraTargets) then
                local character = R.character(plr)
                local forcefield = character and character:FindFirstChildOfClass("ForceField")
                if not (forcefield and C.respectForcefield) then
                    attempted = attempted + 1
                    local sent = false
                    if C.killAuraMode == "Gun" and R.gunKill(plr) then
                        sent = true
                    end
                    -- Gun mode falls back to fists only when the gun request
                    -- did not go out, matching killTarget instead of always
                    -- firing both payloads at the same player.
                    if not sent then
                        local _, meleeSent = R.meleeBurst(plr, C.meleeBurstHits)
                        sent = (meleeSent or 0) > 0
                    end
                    if sent then hits = hits + 1 end
                    task.wait(0.08)
                end
            end
        end
        R.log("kill-all requests sent for " .. hits .. "/" .. attempted .. " target(s)")
        if hits > 0 then
            R.toast("Kill All", tostring(hits) .. " target(s) — requests sent", 2, "ok")
        elseif attempted > 0 then
            R.toast("Kill All", "No request could be sent for " .. tostring(attempted) .. " target(s).", 3, "err")
        else
            R.toast("Kill All", "No living player matched the target filter.", 2, "warn")
        end
    end)
end

function R.tazeTarget(plr, tool)
    if not R.remotes.shoot or not R.alive(plr) then return false end
    local character = R.character(plr)
    local part = character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("HumanoidRootPart")
    if not part then return false end
    local taser = tool or R.getTaser()
    if not taser then return false end
    local bullets = R.buildBullets(part, 1)
    return R.safe("taze", function()
        R.remotes.shoot:FireServer(bullets, taser)
    end)
end

function R.getTaser()
    local character = R.character()
    if character and character:FindFirstChild("Taser") then
        return character:FindFirstChild("Taser")
    end
    if R.lp.Backpack and R.lp.Backpack:FindFirstChild("Taser") then
        return R.lp.Backpack:FindFirstChild("Taser")
    end
    return nil
end

function R.tazeAll()
    task.spawn(function()
        local taser = R.getTaser()
        if not taser then
            -- Do not look frozen while a paced item request and up to four
            -- seconds of waiting run. Say what is being waited for first.
            R.toast("Taze All", "No Taser yet — requesting one; this can take a few seconds.", 3, "warn")
            R.giveBest("Taser", "giver")
            for _ = 1, 8 do
                task.wait(0.5)
                taser = R.getTaser()
                if taser then break end
            end
        end
        if not taser then
            R.toast("No Taser", "Join the Guard team or obtain a Taser first.", 3, "err")
            return
        end
        local sent, attempted = 0, 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if S.detached then return end
            if plr ~= R.lp and R.validTarget(plr, C.auraTargets) then
                attempted = attempted + 1
                if R.tazeTarget(plr, taser) then sent = sent + 1 end
                task.wait(math.max(C.tazeRate / 4, 0.1))
            end
        end
        R.log("taze requests sent for " .. sent .. "/" .. attempted .. " target(s)")
        if sent > 0 then
            R.toast("Taze All", tostring(sent) .. " request(s) sent", 2, "ok")
        elseif attempted > 0 then
            R.toast("Taze All", "No taze request could be sent.", 3, "err")
        else
            R.toast("Taze All", "No living player matched the target filter.", 2, "warn")
        end
    end)
end

function R.getArrestRemote()
    local M = R.remotes
    if not M.arrest then
        local folder = R.remotesFolder(2)
        if folder then
            M.arrest = folder:FindFirstChild("arrest") or folder:FindFirstChild("Arrest")
        end
    end
    return M.arrest
end

function R.arrestOnce(target)
    local remote = R.getArrestRemote()
    if not remote then
        R.log("arrest RemoteFunction unavailable", true)
        return false
    end
    local theirRoot = R.root(target)
    if not theirRoot then return false end
    if C.arrestSnap then
        local myRoot = R.root()
        if myRoot then
            myRoot.CFrame = theirRoot.CFrame * CFrame.new(0, 0, 1.4)
        end
    end
    return R.safe("arrest", function() remote:InvokeServer(theirRoot) end)
end

function R.arrestTarget(target)
    if not R.validTarget(target, C.auraTargets) then return false end
    if R.isGuard(target) then
        R.log("cannot arrest a guard: " .. target.Name, true)
        return false
    end
    for _ = 1, 10 do
        if S.detached then return false end
        local sent = R.arrestOnce(target)
        task.wait(0.08)
        if R.isCuffed(target) then
            S.arrestCount = S.arrestCount + 1
            return true
        end
        -- A throwing RemoteFunction will throw for every retry; stop instead
        -- of spamming the server ten times.
        if not sent then return false end
    end
    return false
end

function R.arrestAll()
    task.spawn(function()
        local n, attempted = 0, 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if S.detached then return end
            if R.validTarget(plr, C.auraTargets) and not R.isCuffed(plr) then
                attempted = attempted + 1
                if R.arrestTarget(plr) then n = n + 1 end
                task.wait(0.35)
            end
        end
        R.log("arrest-all confirmed " .. n .. "/" .. attempted .. " cuff(s)")
        if n > 0 then
            R.toast("Arrest All", tostring(n) .. "/" .. tostring(attempted)
                .. " cuff(s) confirmed client-side", 2, "ok")
        elseif attempted > 0 then
            R.toast("Arrest All", "No cuff confirmed for " .. tostring(attempted)
                .. " target(s); the server may have rejected the request.", 3, "warn")
        else
            R.toast("Arrest All", "No arrestable player matched the target filter.", 2, "warn")
        end
    end)
end

function R.nearestArrestable(radius)
    local myRoot = R.root()
    if not myRoot then return nil end
    local best, bestDistance = nil, radius or math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if R.validTarget(plr, C.auraTargets) and not R.isGuard(plr)
            and not R.isCuffed(plr) then
            local theirRoot = R.root(plr)
            if theirRoot then
                local distance = (theirRoot.Position - myRoot.Position).Magnitude
                if distance <= bestDistance then
                    best, bestDistance = plr, distance
                end
            end
        end
    end
    return best, bestDistance
end

-- ============================================================================
-- AUTO COLLECT
-- ============================================================================
function R.collectNearest(radius)
    local root = R.root()
    local tableRoot = R.prisonItems()
    if not (root and tableRoot) then return false end
    local best, bestDistance = nil, radius or C.autoCollectRadius
    for _, object in ipairs(tableRoot:GetDescendants()) do
        if object:IsA("BasePart") and object.Name == "ITEMPICKUP" then
            local distance = (object.Position - root.Position).Magnitude
            if distance <= bestDistance then
                best, bestDistance = object, distance
            end
        end
    end
    if not best then return false end
    return R.giveItem(best, best:GetFullName())
end

-- ============================================================================
-- MOVEMENT / FLY / NOCLIP
-- ============================================================================
function R.captureMovementBase()
    local hum = R.humanoid()
    if hum then
        S.movementBase = { WalkSpeed = hum.WalkSpeed, JumpPower = hum.JumpPower }
    end
end

function R.restoreMovement()
    local hum = R.humanoid()
    if hum and S.movementBase then
        pcall(function() hum.WalkSpeed = S.movementBase.WalkSpeed end)
        pcall(function() hum.JumpPower = S.movementBase.JumpPower end)
    end
    S.movementBase = nil
end

function R.stopFly()
    S.flyLift = 0
    local root = R.root()
    if root then
        pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
    end
end

function R.restoreNoclip()
    for part, original in pairs(S.noclipSaved) do
        if part and part.Parent then
            pcall(function() part.CanCollide = original end)
        end
    end
    S.noclipSaved = {}
    S.noclipCharacter = nil
    S.lastNoclipAt = nil
end

function R.setNoclip(on)
    if S.detached then return false end
    if not on then
        R.restoreNoclip()
        return
    end
    local character = R.character()
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if S.noclipSaved[part] == nil then
                S.noclipSaved[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end

function R.findBarrierParts()
    local parts = {}
    for _, containerName in ipairs({ "Doors", "Prison_Fences" }) do
        local container = workspace:FindFirstChild(containerName)
        if container then
            for _, part in ipairs(container:GetDescendants()) do
                if part:IsA("BasePart") then table.insert(parts, part) end
            end
        end
    end
    return parts
end

function R.setBarriers(walkThrough)
    if walkThrough then
        for _, part in ipairs(R.findBarrierParts()) do
            if S.barrierSaved[part] == nil then
                S.barrierSaved[part] = part.CanCollide
            end
            pcall(function() part.CanCollide = false end)
        end
        R.log("walk-through barriers enabled (client-side)")
    else
        for part, original in pairs(S.barrierSaved) do
            if part and part.Parent then
                pcall(function() part.CanCollide = original end)
            end
        end
        S.barrierSaved = {}
        R.log("barrier collision restored")
    end
end

function R.applyMovement(dt)
    if S.detached then return end
    local character = R.character()
    if not character then return end
    local hum = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    if not (hum and root) then return end
    if not S.movementBase then R.captureMovementBase() end

    if S.forceWalk or C.walkSpeed ~= 16 then
        if hum.WalkSpeed ~= C.walkSpeed then hum.WalkSpeed = C.walkSpeed end
    end
    if S.forceJump or C.jumpPower ~= 50 then
        if hum.JumpPower ~= C.jumpPower then hum.JumpPower = C.jumpPower end
    end
    if C.antiStun and hum.WalkSpeed == 0 then
        hum.WalkSpeed = math.max(C.walkSpeed, 16)
    end

    if S.toggles.tpWalkOn and not S.toggles.flyOn and hum.MoveDirection.Magnitude > 0.3 then
        root.CFrame = root.CFrame + hum.MoveDirection * C.tpWalkPower * dt * 60
    end

    if S.toggles.spinOn then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(C.spinSpeed) * dt, 0)
    end

    if S.toggles.flyOn then
        local camera = workspace.CurrentCamera
        if camera then
            local move = Vector3.new(0, 0, 0)
            if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - camera.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + camera.CFrame.RightVector end
            if hum.MoveDirection.Magnitude > 0.05 then
                move = move + hum.MoveDirection
            end
            if move.Magnitude > 1 then move = move.Unit end
            local lift = S.flyLift
            if UIS:IsKeyDown(Enum.KeyCode.E) then lift = lift + 1 end
            if UIS:IsKeyDown(Enum.KeyCode.Q) then lift = lift - 1 end
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.CFrame = root.CFrame
                + move * C.flySpeed * 20 * dt
                + Vector3.new(0, lift * C.flySpeed * 16 * dt, 0)
        end
    end

    if S.toggles.noclipOn then
        -- Do not walk every character descendant on every frame; phones pay
        -- for that. Re-scan on a new character or twice a second, which still
        -- catches accessories/tools added after the toggle.
        local now = R.now()
        if S.noclipCharacter ~= character or not S.lastNoclipAt
            or now - S.lastNoclipAt >= 0.5 then
            S.noclipCharacter = character
            S.lastNoclipAt = now
            R.setNoclip(true)
        end
    elseif next(S.noclipSaved) then
        R.restoreNoclip()
    end
end

function R.teleportTo(cframe, label)
    if S.detached then return false end
    local root = R.root()
    if not root then
        R.toast("No character", "Wait for your character to spawn.", 2, "err")
        return false
    end
    root.CFrame = cframe + Vector3.new(0, 2.5, 0)
    R.log("teleported to " .. tostring(label or "location") .. " (client-side)")
    R.toast("Teleport", tostring(label or "location"), 1.5, "ok")
    return true
end

function R.teleportToItem(itemName, label)
    if S.detached then return false end
    local item = R.findItemAnywhere(itemName)
    if not item then
        R.log("teleport target item missing: " .. tostring(itemName), true)
        R.toast("Not found", tostring(itemName) .. " is not on this map.", 2, "err")
        return false
    end
    local part = item:IsA("BasePart") and item
        or item:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        R.log("item has no BasePart: " .. tostring(itemName), true)
        return false
    end
    return R.teleportTo(part.CFrame + Vector3.new(0, 4, 0), label or itemName)
end

R.TELEPORTS = {
    { label = "Yard",             position = Vector3.new(916.81, 99.99, 2373.38) },
    { label = "Guard Spawn",      position = Vector3.new(837.35, 99.99, 2303.22) },
    { label = "Cafeteria",        position = Vector3.new(945.71, 99.80, 2320.33) },
    { label = "Police Room",      position = Vector3.new(909.45, 99.99, 2258.89) },
    { label = "Gate Button",      position = Vector3.new(504.53, 104.91, 2240.84) },
    { label = "Riot Gear Stand",  position = Vector3.new(853.40, 100.70, 2216.49) },
    { label = "Criminal Base",    position = Vector3.new(-938.77, 94.13, 2063.85) },
    { label = "Crim Base Hammer", position = Vector3.new(808.08, 95.59, 2525.31) },
}

function R.teleportNearestPlayer()
    local target = R.nearest(C.auraTargets, math.huge)
    if not target then
        R.toast("No target", "No living player matches the filter.", 2, "err")
        return false
    end
    local root = R.root(target)
    if not root then return false end
    return R.teleportTo(root.CFrame * CFrame.new(0, 0, 3), target.Name)
end

-- ============================================================================
-- AIM / TRIGGER
-- ============================================================================
function R.buildAimRing()
    local playerGui = R.lp:FindFirstChild("PlayerGui")
    if not playerGui then return end
    local screen = Instance.new("ScreenGui")
    screen.Name = "RiotHubMobile_FOV"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = false
    screen.DisplayOrder = 5
    pcall(function()
        screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
        screen.ClipToDeviceSafeArea = true
    end)
    screen.Parent = playerGui

    local ring = Instance.new("Frame")
    ring.Name = "Ring"
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.new(0.5, 0, 0.5, 0)
    ring.BackgroundColor3 = Color3.fromRGB(255, 84, 100)
    ring.BackgroundTransparency = 0.88
    ring.BorderSizePixel = 0
    ring.Visible = false
    ring.Parent = screen
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = ring
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 84, 100)
    stroke.Transparency = 0.35
    stroke.Thickness = 1.5
    stroke.Parent = ring

    S.ui.fovScreen = screen
    S.ui.fovRing = ring
end

function R.cameraTarget(fov, filter)
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local best, bestAngle = nil, nil
    for _, plr in ipairs(Players:GetPlayers()) do
        if R.validTarget(plr, filter) then
            local head = R.character(plr):FindFirstChild("Head")
            if head then
                local toTarget = head.Position - camera.CFrame.Position
                if toTarget.Magnitude > 3 then
                    local angle = math.deg(math.acos(math.clamp(
                        camera.CFrame.LookVector:Dot(toTarget.Unit), -1, 1)))
                    if angle <= fov and (not bestAngle or angle < bestAngle) then
                        best, bestAngle = head, angle
                    end
                end
            end
        end
    end
    return best
end

function R.hasLineOfSight(targetHead)
    local camera = workspace.CurrentCamera
    if not camera or not targetHead then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { targetHead.Parent }
    local character = R.character()
    if character then table.insert(ignore, 1, character) end
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(camera.CFrame.Position,
        targetHead.Position - camera.CFrame.Position, params)
    if hit and hit.Instance then
        return hit.Instance:IsDescendantOf(targetHead.Parent)
    end
    return true
end

function R.updateAim(dt)
    if S.detached then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local ring = S.ui.fovRing
    local showRing = C.showAimFov and (S.toggles.aimOn or S.toggles.silentOn)
    if ring then
        ring.Visible = showRing
        if showRing then
            local diameter = 2 * math.tan(math.rad(C.aimbotFov) / 2)
                / math.max(math.tan(math.rad(camera.FieldOfView) / 2), 0.01)
                * (camera.ViewportSize.Y / 2)
            diameter = math.clamp(diameter, 30, camera.ViewportSize.Y * 0.95)
            ring.Size = UDim2.fromOffset(diameter, diameter)
        end
    end

    local target = nil
    if S.toggles.silentOn then
        target = R.cameraTarget(C.silentFov, C.aimbotTargets)
    elseif S.toggles.aimOn or S.toggles.triggerOn then
        target = R.cameraTarget(C.aimbotFov, C.aimbotTargets)
    end
    S.aimTarget = target

    if S.toggles.aimOn and target then
        local held = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            or S.aimHeld or C.aimAlwaysLock
        if held then
            local goal = CFrame.lookAt(camera.CFrame.Position, target.Position)
            local speed = math.clamp(1 - (C.aimbotSmooth / 100), 0.04, 1)
            local alpha = 1 - math.exp(-speed * 18 * math.max(dt, 0.001))
            camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(alpha, 0.02, 1))
        end
    end
end

function R.triggerTick()
    if S.detached or not S.toggles.triggerOn or S.open then return end
    local now = R.now()
    if now - (S.lastTrigger or 0) < 0.12 then return end
    S.lastTrigger = now
    local target = S.aimTarget
    if not target then return end
    if C.silentWallCheck and not R.hasLineOfSight(target) then return end
    local tool = R.character() and R.character():FindFirstChildWhichIsA("Tool")
    if not tool or not tool:FindFirstChild("GunStates") then return end
    pcall(function() tool:Activate() end)
    task.delay(0.05, function()
        if not S.detached then pcall(function() tool:Deactivate() end) end
    end)
end

function R.setupSilentAim()
    if S.silentHook ~= nil then return true end
    local hookFn = hookmetamethod
    local getNamecall = getnamecallmethod
    if not hookFn then
        R.log("hookmetamethod unavailable; silent aim is off", true)
        return false
    end
    local old
    local callback = function(self, ...)
        local args = { ... }
        local argc = select("#", ...)
        if S.detached then
            return old(self, R.unpack(args, 1, argc))
        end
        local method = getNamecall and getNamecall() or nil
        local isFire = (method == nil) or method == "FireServer"
        if isFire and self == R.remotes.shoot and S.toggles.silentOn
            and type(args[1]) == "table" then
            pcall(function()
                local head = R.cameraTarget(C.silentFov, C.aimbotTargets)
                if not head then return end
                if C.silentWallCheck and not R.hasLineOfSight(head) then return end
                if math.random(1, 100) > C.silentHitChance then return end
                for _, bullet in ipairs(args[1]) do
                    local part = head
                    if C.silentRandomPart then
                        local character = head.Parent
                        local other = character and (character.PrimaryPart
                            or character:FindFirstChild("Torso")
                            or character:FindFirstChild("UpperTorso"))
                        if other and math.random() < 0.5 then part = other end
                    end
                    bullet.Cframe = part.CFrame
                    bullet.HitPart = part
                end
                if R.now() - (S.lastSilentLog or 0) > 2 then
                    S.lastSilentLog = R.now()
                    R.log("silent aim re-pointed a shot at " .. head.Parent.Name)
                end
            end)
        end
        return old(self, R.unpack(args, 1, argc))
    end
    local ok, result = pcall(hookFn, game, "__namecall", callback)
    if not ok or type(result) ~= "function" then
        R.log("silent aim hook failed: " .. tostring(result), true)
        return false
    end
    old = result
    S.silentHook = hookFn
    S.silentOld = old
    R.log("silent aim hook installed")
    return true
end

function R.removeSilentAim()
    if S.silentHook and S.silentOld then
        pcall(function() S.silentHook(game, "__namecall", S.silentOld) end)
        R.log("silent aim hook restored")
    end
    S.silentHook = nil
    S.silentOld = nil
end

-- ============================================================================
-- ESP / CHAMS / TRACERS
-- ============================================================================
function R.ensureEspFolder()
    local folder = S.ui.espFolder
    if folder and folder.Parent then return folder end
    local parent = R.lp:FindFirstChild("PlayerGui")
    if not parent then return nil end
    folder = Instance.new("Folder")
    folder.Name = "RiotHubMobile_ESP"
    folder.Parent = parent
    S.ui.espFolder = folder
    return folder
end

function R.teamTint(plr)
    if R.isGuard(plr) then return Color3.fromRGB(110, 170, 255) end
    if R.isInmate(plr) then return Color3.fromRGB(255, 165, 70) end
    if R.isCrim(plr) then return Color3.fromRGB(255, 90, 90) end
    return Color3.fromRGB(225, 225, 225)
end

function R.applyChams(plr)
    local character = R.character(plr)
    if not character then return end
    local highlight = character:FindFirstChild("RiotHub_Cham")
    if not S.toggles.chamsOn then
        if highlight then highlight:Destroy() end
        return
    end
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "RiotHub_Cham"
        highlight.Parent = character
    end
    highlight.FillColor = R.teamTint(plr)
    highlight.FillTransparency = 0.55
    highlight.OutlineColor = Color3.new(0, 0, 0)
    highlight.OutlineTransparency = 0.25
    highlight.DepthMode = C.chamsThroughWalls
        and Enum.HighlightDepthMode.AlwaysOnTop
        or Enum.HighlightDepthMode.Occluded
end

function R.buildEspUnit(plr)
    local folder = R.ensureEspFolder()
    if not folder then return nil end
    local unit = { connections = {} }
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "RiotHub_ESP_" .. plr.Name
    billboard.Size = UDim2.new(7, 0, 2.4, 0)
    billboard.StudsOffset = Vector3.new(0, 2.2, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 2000
    billboard.Adornee = R.character(plr) and R.character(plr):FindFirstChild("Head")
    billboard.Parent = folder

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0, 18)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 14
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.Parent = billboard

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.Size = UDim2.new(1, 0, 0, 14)
    distLabel.Position = UDim2.new(0, 0, 0, 18)
    distLabel.BackgroundTransparency = 1
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = 11
    distLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    distLabel.TextStrokeTransparency = 0.45
    distLabel.Parent = billboard

    local barBack = Instance.new("Frame")
    barBack.Name = "HealthBack"
    barBack.Size = UDim2.new(0.8, 0, 0, 4)
    barBack.Position = UDim2.new(0.1, 0, 1, -3)
    barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
    barBack.BorderSizePixel = 0
    barBack.Parent = billboard
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = barBack

    local barFill = Instance.new("Frame")
    barFill.Name = "HealthFill"
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(80, 220, 150)
    barFill.BorderSizePixel = 0
    barFill.Parent = barBack
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = barFill

    unit.billboard = billboard
    unit.nameLabel = nameLabel
    unit.distLabel = distLabel
    unit.healthFill = barFill
    unit.connections[#unit.connections + 1] = R.connect(plr.CharacterAdded, function()
        task.wait(0.4)
        if S.detached then return end
        local character = R.character(plr)
        billboard.Adornee = character and character:FindFirstChild("Head")
        R.applyChams(plr)
    end)
    R.applyChams(plr)
    return unit
end

function R.destroyEspUnit(plr)
    local unit = S.espUnits[plr]
    if not unit then return end
    for _, connection in ipairs(unit.connections) do
        pcall(function() connection:Disconnect() end)
    end
    if unit.billboard then unit.billboard:Destroy() end
    S.espUnits[plr] = nil
    -- A tracer belongs to the ESP unit; without this, a player who leaves or
    -- turns ESP off would leave a visible line behind until unload.
    local line = S.tracers[plr]
    if line then
        pcall(function() line:Remove() end)
        S.tracers[plr] = nil
    end
end

function R.clearEsp()
    for plr in pairs(S.espUnits) do R.destroyEspUnit(plr) end
    if S.ui.espFolder then
        pcall(function() S.ui.espFolder:Destroy() end)
        S.ui.espFolder = nil
    end
    for plr, line in pairs(S.tracers) do
        pcall(function() line:Remove() end)
        S.tracers[plr] = nil
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        local character = R.character(plr)
        local highlight = character and character:FindFirstChild("RiotHub_Cham")
        if highlight then pcall(function() highlight:Destroy() end) end
    end
end

function R.refreshEsp()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= R.lp then
            if S.toggles.espOn then
                if not S.espUnits[plr] then
                    S.espUnits[plr] = R.buildEspUnit(plr)
                end
            else
                R.destroyEspUnit(plr)
            end
            if S.toggles.chamsOn then R.applyChams(plr) end
        end
    end
    for plr, unit in pairs(S.espUnits) do
        if not plr.Parent or not unit.billboard or not unit.billboard.Parent then
            R.destroyEspUnit(plr)
        end
    end
end

function R.updateEsp()
    if S.detached then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    for plr, unit in pairs(S.espUnits) do
        local character = R.character(plr)
        local hum = character and character:FindFirstChildOfClass("Humanoid")
        local head = character and character:FindFirstChild("Head")
        local visible = S.toggles.espOn and head ~= nil and hum ~= nil and hum.Health > 0
        if visible and C.espVisibleOnly then
            visible = R.hasLineOfSight(head)
        end
        unit.billboard.Enabled = visible
        if visible then
            unit.billboard.Adornee = head
            local distance = (head.Position - camera.CFrame.Position).Magnitude
            local hp = math.floor(hum.Health / math.max(hum.MaxHealth, 1) * 100 + 0.5)
            unit.nameLabel.Text = C.espNames and plr.Name or ""
            unit.nameLabel.TextColor3 = C.espTeamColor
                and R.teamTint(plr) or Color3.new(1, 1, 1)
            unit.distLabel.Text = C.espDistance and string.format("%dm", distance) or ""
            if C.espHealth then
                unit.distLabel.Text = (unit.distLabel.Text ~= "" and (unit.distLabel.Text .. "  ") or "")
                    .. hp .. "%"
            end
            unit.healthFill.Size = UDim2.new(math.clamp(hp / 100, 0, 1), 0, 1, 0)
            unit.healthFill.BackgroundColor3 = hp > 50
                and Color3.fromRGB(80, 220, 150)
                or (hp > 25 and Color3.fromRGB(255, 190, 80) or Color3.fromRGB(255, 90, 110))
        end
    end
end

function R.updateTracers()
    if S.detached then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    if not (S.toggles.espOn and C.espTracers) then
        for plr, line in pairs(S.tracers) do
            pcall(function() line:Remove() end)
            S.tracers[plr] = nil
        end
        return
    end
    if not R.drawingOk then return end
    -- Prune lines whose ESP unit disappeared (player left or ESP was turned
    -- off between frames).
    for plr, line in pairs(S.tracers) do
        if not S.espUnits[plr] then
            pcall(function() line:Remove() end)
            S.tracers[plr] = nil
        end
    end
    for plr, unit in pairs(S.espUnits) do
        local ok = pcall(function()
            local character = R.character(plr)
            local head = character and character:FindFirstChild("Head")
            local hum = character and character:FindFirstChildOfClass("Humanoid")
            if head and hum and hum.Health > 0 and unit.billboard.Enabled then
                local screenPoint, onScreen = camera:WorldToViewportPoint(head.Position)
                if onScreen and screenPoint.Z > 0 then
                    local line = S.tracers[plr]
                    if not line then
                        line = Drawing.new("Line")
                        line.Thickness = 1.4
                        line.Transparency = 0.7
                        S.tracers[plr] = line
                    end
                    line.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                    line.To = Vector2.new(screenPoint.X, screenPoint.Y)
                    line.Color = R.teamTint(plr)
                    line.Visible = true
                else
                    local line = S.tracers[plr]
                    if line then line.Visible = false end
                end
            else
                local line = S.tracers[plr]
                if line then line.Visible = false end
            end
        end)
        if not ok then
            local line = S.tracers[plr]
            if line then pcall(function() line.Visible = false end) end
        end
    end
end

-- ============================================================================
-- LIGHTING / FPS BOOST / CAMERA
-- ============================================================================
function R.setFullbright(on)
    local lighting = R.services.Lighting
    if not lighting then return end
    if on then
        if not S.lightingSaved then
            S.lightingSaved = {
                Ambient = lighting.Ambient,
                OutdoorAmbient = lighting.OutdoorAmbient,
                Brightness = lighting.Brightness,
                FogEnd = lighting.FogEnd,
                FogStart = lighting.FogStart,
                ClockTime = lighting.ClockTime,
                GlobalShadows = lighting.GlobalShadows,
            }
        end
        pcall(function()
            lighting.Ambient = Color3.new(1, 1, 1)
            lighting.OutdoorAmbient = Color3.new(1, 1, 1)
            lighting.Brightness = 3
            lighting.FogEnd = 1e10
            lighting.FogStart = 0
            lighting.ClockTime = 14
            lighting.GlobalShadows = false
        end)
    elseif S.lightingSaved then
        local saved = S.lightingSaved
        pcall(function()
            lighting.Ambient = saved.Ambient
            lighting.OutdoorAmbient = saved.OutdoorAmbient
            lighting.Brightness = saved.Brightness
            lighting.FogEnd = saved.FogEnd
            lighting.FogStart = saved.FogStart
            lighting.ClockTime = saved.ClockTime
            lighting.GlobalShadows = saved.GlobalShadows
        end)
        S.lightingSaved = nil
    end
end

function R.setFpsBoost(on)
    if on then
        local function disable(object)
            if S.fpsSaved[object] == nil then
                S.fpsSaved[object] = object.Enabled
            end
            pcall(function() object.Enabled = false end)
        end
        for _, object in ipairs(workspace:GetDescendants()) do
            if object:IsA("ParticleEmitter") or object:IsA("Trail")
                or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Beam") then
                disable(object)
            end
        end
        if S.fpsConn then S.fpsConn:Disconnect() end
        S.fpsConn = R.connect(workspace.DescendantAdded, function(object)
            if object:IsA("ParticleEmitter") or object:IsA("Trail")
                or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Beam") then
                disable(object)
            end
        end)
    else
        if S.fpsConn then
            S.fpsConn:Disconnect()
            S.fpsConn = nil
        end
        for object, enabled in pairs(S.fpsSaved) do
            if object and object.Parent then
                pcall(function() object.Enabled = enabled end)
            end
        end
        S.fpsSaved = {}
    end
end

function R.setCameraFov(value)
    local camera = workspace.CurrentCamera
    if not camera then return end
    if not S.cameraFovSaved then S.cameraFovSaved = camera.FieldOfView end
    camera.FieldOfView = value
end

function R.restoreCamera()
    local camera = workspace.CurrentCamera
    if camera and S.cameraFovSaved then
        pcall(function() camera.FieldOfView = S.cameraFovSaved end)
    end
    S.cameraFovSaved = nil
end

-- ============================================================================
-- WORLD ACTIONS
-- ============================================================================
function R.openGate()
    if S.detached then return false end
    local button = R.getItemIn("buttons", "Prison Gate", "Prison Gate")
        or R.getItemIn("buttons", "Prison Gate")
    if not button then
        R.log("Prison Gate button not present", true)
        R.toast("Gate", "Prison Gate button not found on this map.", 2, "err")
        return false
    end
    local ok = R.giveItem(button, "Prison Gate")
    if ok then
        R.toast("Gate", "Gate request sent", 1.5, "ok")
    else
        R.toast("Gate", "No request reached ItemHandler; the gate was not triggered.", 3, "err")
    end
    return ok
end

function R.switchTeam(kind)
    if S.detached then return false end
    local teamRemote = R.remotes.team
    local loadchar = R.remotes.loadchar
    if not teamRemote or not loadchar then
        R.rebindRemotes()
        teamRemote = R.remotes.team
        loadchar = R.remotes.loadchar
    end
    if not (teamRemote and loadchar) then
        R.log("TeamEvent or loadchar missing", true)
        R.toast("Team switch", "Team remotes are not available.", 2, "err")
        return false
    end
    task.spawn(function()
        if kind == "Guard" then
            R.safe("team", function() teamRemote:FireServer("Bright blue") end)
            task.wait(0.15)
            R.safe("loadchar", function() loadchar:InvokeServer(R.lp.Name) end)
        elseif kind == "Inmate" then
            R.safe("team", function() teamRemote:FireServer("Bright orange") end)
            task.wait(0.15)
            R.safe("loadchar", function() loadchar:InvokeServer(R.lp.Name) end)
        else
            R.safe("loadchar", function() loadchar:InvokeServer(R.lp.Name, "Medium stone grey") end)
        end
        task.wait(1.5)
        if S.detached then return end
        local confirmed = false
        if kind == "Guard" then
            confirmed = R.isGuard(R.lp)
        elseif kind == "Inmate" then
            confirmed = R.isInmate(R.lp)
        else
            confirmed = not R.isGuard(R.lp) and not R.isInmate(R.lp) and not R.isCrim(R.lp)
        end
        if confirmed then
            R.toast("Team", "Now " .. tostring(kind), 2, "ok")
        else
            R.toast("Team request sent", "Server did not confirm " .. tostring(kind) .. " on the client.", 3, "warn")
        end
        R.log("team switch request -> " .. tostring(kind)
            .. (confirmed and " (confirmed)" or " (unconfirmed)"))
    end)
    return true
end

function R.becomeGuardWithCuffs()
    local started = R.switchTeam("Guard")
    if not started then return false end
    task.delay(2.2, function()
        if S.detached then return end
        local ok = R.giveBest("Handcuffs", "giver")
        if S.detached then return end
        if ok then
            R.toast("Handcuffs", "Request sent after the Guard switch; check your backpack.", 3, "ok")
        else
            R.toast("Handcuffs not sent", "No handcuff request reached ItemHandler after the team switch.", 3, "err")
        end
    end)
    return true
end

function R.respawn()
    if S.detached then return false end
    local loadchar = R.remotes.loadchar
    if not loadchar then
        R.rebindRemotes()
        loadchar = R.remotes.loadchar
    end
    if not loadchar then
        R.toast("Respawn", "loadchar remote is not available.", 2, "err")
        return false
    end
    local ok = R.safe("respawn", function() loadchar:InvokeServer(R.lp.Name) end)
    if ok then
        R.toast("Respawn", "Request sent", 1.5, "ok")
    else
        R.toast("Respawn failed", "loadchar rejected the call on the client.", 3, "err")
    end
    return ok
end

function R.rejoin()
    if S.detached then return false end
    local teleport = R.services.TeleportService
    local ok, err = pcall(function()
        teleport:Teleport(game.PlaceId, R.lp)
    end)
    if ok then
        R.toast("Rejoin", "Teleport requested", 3, "ok")
    else
        R.log("rejoin failed: " .. tostring(err), true)
        R.toast("Rejoin failed", tostring(err):sub(1, 90), 4, "err")
    end
    return ok
end

function R.antiAfkNow()
    if S.detached or not C.antiAfk then return false end
    local ok = pcall(function()
        R.services.VirtualUser:CaptureController()
        R.services.VirtualUser:ClickButton2(Vector2.new())
    end)
    if ok then R.log("anti-AFK nudge sent") end
    return ok
end
-- ============================================================================
-- UI — mobile-first layout and components
-- ============================================================================
local S = R.state
local C = R.config
local UIS = R.services.UserInputService
local TweenService = R.services.TweenService
local Players = R.services.Players

local THEME = {
    bg = Color3.fromRGB(16, 18, 24),
    panel = Color3.fromRGB(24, 27, 35),
    card = Color3.fromRGB(33, 37, 47),
    cardUp = Color3.fromRGB(43, 48, 61),
    stroke = Color3.fromRGB(58, 64, 82),
    track = Color3.fromRGB(49, 54, 68),
    text = Color3.fromRGB(238, 241, 248),
    dim = Color3.fromRGB(151, 159, 178),
    accent = Color3.fromRGB(86, 231, 205),
    accentDark = Color3.fromRGB(27, 74, 70),
    violet = Color3.fromRGB(139, 112, 255),
    good = Color3.fromRGB(80, 220, 150),
    warn = Color3.fromRGB(255, 193, 92),
    danger = Color3.fromRGB(255, 92, 112),
    dangerDark = Color3.fromRGB(76, 31, 40),
}
R.theme = THEME

local function make(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    if parent then object.Parent = parent end
    return object
end

local function corner(object, radius)
    local item = make("UICorner", { CornerRadius = UDim.new(0, radius) }, object)
    return item
end

local function stroke(object, color, thickness, transparency)
    local item = make("UIStroke", {
        Color = color or THEME.stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0.3,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
    return item
end

local function pad(object, left, right, top, bottom)
    return make("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    }, object)
end

local function gradient(object, colorA, colorB, rotation)
    return make("UIGradient", {
        Color = ColorSequence.new(colorA, colorB),
        Rotation = rotation or 0,
    }, object)
end

local function tween(object, goal, duration, style, direction)
    if not object then return nil end
    if C.reduceAnim then
        for key, value in pairs(goal) do object[key] = value end
        return nil
    end
    local ok, tweenObject = pcall(function()
        local created = TweenService:Create(object,
            TweenInfo.new(duration or 0.18, style or Enum.EasingStyle.Quart,
                direction or Enum.EasingDirection.Out), goal)
        created:Play()
        return created
    end)
    if ok then return tweenObject end
    return nil
end

local function slug(text)
    local clean = string.lower(tostring(text)):gsub("[^%w]+", "_")
    clean = clean:gsub("^_+", ""):gsub("_+$", "")
    if clean == "" then clean = "item" end
    return clean
end

local function press(button)
    if C.reduceAnim then return end
    local scale = button:FindFirstChildOfClass("UIScale")
    if not scale then scale = make("UIScale", { Scale = 1 }, button) end
    tween(scale, { Scale = 0.96 }, 0.06)
    task.delay(0.09, function()
        if scale and scale.Parent then tween(scale, { Scale = 1 }, 0.12) end
    end)
end

local function isPrimaryInput(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

-- One gesture owns the pointer until it ends. This is the fix for the old
-- global `dragging` flag: a second finger cannot move a slider it never hit,
-- and a lost InputEnded cannot leave a control stuck.
function R.ui.beginDrag(input, onMove, onEnd)
    if not (input and isPrimaryInput(input)) then return nil end
    if S.activeDrag and S.activeDrag.stop then S.activeDrag.stop() end
    local startType = input.UserInputType
    local moveConnection, endConnection
    local stopped = false
    local handle = {}
    S.activeDrag = handle
    moveConnection = UIS.InputChanged:Connect(function(changed)
        if stopped then return end
        local matches
        if startType == Enum.UserInputType.Touch then
            -- Identity, not just type: a second finger must never move a
            -- control it did not press.
            matches = changed == input
        else
            matches = changed.UserInputType == Enum.UserInputType.MouseMovement
        end
        if matches then onMove(changed) end
    end)
    endConnection = UIS.InputEnded:Connect(function(ended)
        if stopped then return end
        local matches
        if startType == Enum.UserInputType.Touch then
            matches = ended == input
        else
            matches = ended.UserInputType == Enum.UserInputType.MouseButton1
        end
        if matches then
            handle.stop()
            if onEnd then onEnd() end
        end
    end)
    table.insert(S.connections, moveConnection)
    table.insert(S.connections, endConnection)
    function handle.stop()
        if stopped then return end
        stopped = true
        if moveConnection then pcall(function() moveConnection:Disconnect() end) end
        if endConnection then pcall(function() endConnection:Disconnect() end) end
        for index = #S.connections, 1, -1 do
            local item = S.connections[index]
            if item == moveConnection or item == endConnection then
                table.remove(S.connections, index)
            end
        end
        if S.activeDrag == handle then S.activeDrag = nil end
    end
    return handle
end

function R.ui.clampFrame(frame, margin)
    if not frame then return end
    local viewport = R.viewport()
    local size = frame.AbsoluteSize
    local width = size and size.X or 0
    local height = size and size.Y or 0
    if width <= 0 then width = frame.Size.X.Offset end
    if height <= 0 then height = frame.Size.Y.Offset end
    if width <= 0 or height <= 0 then return end
    margin = margin or 12
    local anchor = frame.AnchorPoint
    local x = frame.Position.X.Offset - width * anchor.X
    local y = frame.Position.Y.Offset - height * anchor.Y
    x = math.clamp(x, margin, math.max(margin, viewport.X - width - margin))
    y = math.clamp(y, margin, math.max(margin, viewport.Y - height - margin))
    frame.Position = UDim2.new(0, x + width * anchor.X, 0, y + height * anchor.Y)
end

function R.ui.makeDraggable(handleObject, target, onClick)
    R.connect(handleObject.InputBegan, function(input)
        if not isPrimaryInput(input) then return end
        local startAbsolute = target.AbsolutePosition
        local startSize = target.AbsoluteSize
        local width = (startSize and startSize.X or 0)
        local height = (startSize and startSize.Y or 0)
        if width <= 0 then width = target.Size.X.Offset end
        if height <= 0 then height = target.Size.Y.Offset end
        local anchor = target.AnchorPoint
        local startInput = input.Position
        local moved = false
        R.ui.beginDrag(input, function(changed)
            local delta = changed.Position - startInput
            if delta.Magnitude > 5 then moved = true end
            target.Position = UDim2.new(0,
                startAbsolute.X + delta.X + width * anchor.X,
                0,
                startAbsolute.Y + delta.Y + height * anchor.Y)
            R.ui.clampFrame(target, 12)
        end, function()
            if moved then
                R.ui.clampFrame(target, 12)
            elseif onClick then
                onClick()
            end
        end)
    end)
end

-- ============================================================================
-- BASE BUILD
-- ============================================================================
function R.ui.buildBase()
    local playerGui = R.lp:FindFirstChild("PlayerGui")
        or (R.lp.WaitForChild and R.lp:WaitForChild("PlayerGui", 10))
    if not playerGui and gethui then
        pcall(function() playerGui = gethui() end)
    end
    if not playerGui then
        local okCore, coreGui = pcall(function() return game:FindFirstChildOfClass("CoreGui") end)
        if okCore then playerGui = coreGui end
    end
    if not playerGui then
        error("[RiotHub] no PlayerGui available for the UI", 0)
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = "RiotHubMobile_GUI"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = false
    screen.DisplayOrder = 999
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local safeInsets = pcall(function()
        screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    end)
    pcall(function() screen.ClipToDeviceSafeArea = true end)
    if not safeInsets then
        -- Old clients: IgnoreGuiInset=false still keeps us below the topbar.
        screen.IgnoreGuiInset = false
    end
    screen.Parent = playerGui
    S.ui.screen = screen
    S.ui.safeInsets = safeInsets

    -- Scrim: closes the hub on a tap outside it (desktop) and stops game
    -- camera drags behind the full-screen phone panel.
    local scrim = make("TextButton", {
        Name = "Scrim", Text = "", AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.38, BorderSizePixel = 0,
        Visible = false, ZIndex = 40,
    }, screen)
    scrim.MouseButton1Click:Connect(function()
        if S.picker then R.ui.closePicker() else R.ui.openPanel(false) end
    end)
    S.ui.scrim = scrim

    local panel = make("Frame", {
        Name = "Panel", BackgroundColor3 = THEME.bg, BorderSizePixel = 0,
        ClipsDescendants = true, Active = true, ZIndex = 50,
    }, screen)
    corner(panel, 14)
    stroke(panel, THEME.stroke, 1, 0.25)
    S.ui.panel = panel

    local header = make("Frame", {
        Name = "Header", Size = UDim2.new(1, 0, 0, 54),
        BackgroundColor3 = THEME.panel, BorderSizePixel = 0, ZIndex = 51,
    }, panel)
    S.ui.header = header
    make("Frame", {
        Name = "HeaderRule", Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = THEME.stroke,
        BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 52,
    }, header)

    local title = make("TextLabel", {
        Name = "Title", Text = "RIOT HUB", Size = UDim2.new(1, -80, 0, 20),
        Position = UDim2.fromOffset(16, 7), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 52,
    }, header)
    S.ui.title = title

    local dot = make("Frame", {
        Name = "StatusDot", Size = UDim2.fromOffset(7, 7),
        Position = UDim2.fromOffset(16, 33), BackgroundColor3 = THEME.warn,
        BorderSizePixel = 0, ZIndex = 52,
    }, header)
    corner(dot, 4)
    S.ui.statusDot = dot

    local subtitle = make("TextLabel", {
        Name = "Subtitle", Text = "MOBILE v4.0 · starting",
        Size = UDim2.new(1, -96, 0, 15), Position = UDim2.fromOffset(28, 29),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = THEME.dim, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 52,
    }, header)
    S.ui.subtitle = subtitle

    local close = make("TextButton", {
        Name = "CloseButton", Text = "✕", Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(1, -52, 0, 5), BackgroundColor3 = THEME.card,
        Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = THEME.text,
        AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 53,
    }, header)
    corner(close, 11)
    close.MouseButton1Click:Connect(function() R.ui.openPanel(false) end)
    S.ui.close = close

    local tabHolder = make("ScrollingFrame", {
        Name = "Tabs", BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
        ZIndex = 52, ClipsDescendants = true,
    }, panel)
    S.ui.tabHolder = tabHolder
    local tabLayout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, tabHolder)
    S.ui.tabLayout = tabLayout
    pad(tabHolder, 8, 8, 4, 4)

    local pageHost = make("Frame", {
        Name = "PageHost", BackgroundTransparency = 1,
        ClipsDescendants = true, ZIndex = 51,
    }, panel)
    S.ui.pageHost = pageHost

    -- Quick dock: vertical on tall screens, horizontal on short landscape.
    local dock = make("Frame", {
        Name = "QuickDock", BackgroundColor3 = THEME.panel,
        BackgroundTransparency = 0.06, BorderSizePixel = 0,
        Visible = false, ZIndex = 60,
    }, screen)
    corner(dock, 14)
    stroke(dock, THEME.accent, 1.2, 0.45)
    local dockLayout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 6),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, dock)
    pad(dock, 6, 6, 6, 6)
    S.ui.dock = dock
    S.ui.dockLayout = dockLayout
    S.ui.dockButtons = {}

    local function dockButton(name, label, callback)
        local button = make("TextButton", {
            Name = "Quick_" .. name, Text = label, Size = UDim2.fromOffset(48, 48),
            BackgroundColor3 = THEME.card, Font = Enum.Font.GothamBold,
            TextSize = 11, TextColor3 = THEME.text, AutoButtonColor = false,
            BorderSizePixel = 0, ZIndex = 61,
        }, dock)
        corner(button, 11)
        button.MouseButton1Click:Connect(function()
            press(button)
            R.safe("quick " .. name, callback)
        end)
        S.ui.dockButtons[name] = button
        return button
    end

    dockButton("menu", "MENU", function() R.ui.openPanel(true) end)
    dockButton("aura", "AURA", function()
        if S.switches.auraKillOn then S.switches.auraKillOn.Set(not S.toggles.auraKillOn) end
    end)
    dockButton("aim", "AIM", function()
        if not S.toggles.aimOn then
            if S.switches.aimOn then S.switches.aimOn.Set(true) end
            S.aimHeld = true
        else
            S.aimHeld = not S.aimHeld
        end
        R.ui.syncDock()
        R.toast("Aim assist", S.aimHeld and "engaged" or "released", 1.4,
            S.aimHeld and "ok" or "warn")
    end)
    dockButton("fly", "FLY", function()
        if S.switches.flyOn then S.switches.flyOn.Set(not S.toggles.flyOn) end
    end)

    local orb = make("TextButton", {
        Name = "Orb", Text = "RH", Size = UDim2.fromOffset(54, 54),
        BackgroundColor3 = THEME.panel, Font = Enum.Font.GothamBlack,
        TextSize = 15, TextColor3 = THEME.accent, AutoButtonColor = false,
        BorderSizePixel = 0, ZIndex = 60, Visible = false,
    }, screen)
    corner(orb, 27)
    stroke(orb, THEME.accent, 1.6, 0.25)
    gradient(orb, THEME.accent, THEME.violet, 45)
    R.ui.makeDraggable(orb, orb, function() R.ui.openPanel(true) end)
    S.ui.orb = orb

    local function flyButton(name, label, lift)
        local button = make("TextButton", {
            Name = name, Text = label, Size = UDim2.fromOffset(48, 48),
            BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.05,
            Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = THEME.accent,
            AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 60,
            Visible = false,
        }, screen)
        corner(button, 12)
        stroke(button, THEME.accent, 1.2, 0.4)
        R.connect(button.InputBegan, function(input)
            if isPrimaryInput(input) then S.flyLift = lift end
        end)
        R.connect(button.InputEnded, function(input)
            if isPrimaryInput(input) then S.flyLift = 0 end
        end)
        return button
    end
    S.ui.flyUp = flyButton("FlyUp", "▲", 1)
    S.ui.flyDown = flyButton("FlyDown", "▼", -1)

    local toastHolder = make("Frame", {
        Name = "Toasts", BackgroundTransparency = 1, ZIndex = 100,
        Size = UDim2.new(0, 320, 0, 0),
    }, screen)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 6),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, toastHolder)
    S.ui.toastHolder = toastHolder
    S.ui.toasts = {}

    R.toast = function(titleText, body, duration, kind)
        if S.detached or not S.ui.toastHolder then return end
        local color = kind == "err" and THEME.danger
            or (kind == "warn" and THEME.warn or THEME.good)
        local card = make("Frame", {
            Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = THEME.panel,
            BorderSizePixel = 0, ZIndex = 101,
        }, S.ui.toastHolder)
        corner(card, 12)
        stroke(card, color, 1.2, 0.2)
        make("Frame", {
            Size = UDim2.new(0, 3, 1, -16), Position = UDim2.new(0, 0, 0, 8),
            BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 102,
        }, card)
        make("TextLabel", {
            Text = string.upper(tostring(titleText)), Size = UDim2.new(1, -28, 0, 17),
            Position = UDim2.fromOffset(12, 5), BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = color,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 102,
        }, card)
        make("TextLabel", {
            Text = tostring(body or ""), Size = UDim2.new(1, -24, 0, 27),
            Position = UDim2.fromOffset(12, 22), BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = THEME.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 102,
        }, card)
        local scale = make("UIScale", { Scale = C.reduceAnim and 1 or 0.92 }, card)
        if not C.reduceAnim then tween(scale, { Scale = 1 }, 0.16) end
        table.insert(S.ui.toasts, card)
        while #S.ui.toasts > 3 do
            local oldest = table.remove(S.ui.toasts, 1)
            if oldest then oldest:Destroy() end
        end
        task.delay(duration or 3, function()
            if not card or not card.Parent then return end
            for index, item in ipairs(S.ui.toasts) do
                if item == card then table.remove(S.ui.toasts, index) break end
            end
            card:Destroy()
        end)
    end

    -- Picker layer (modal dropdown / bottom sheet).
    local pickerScrim = make("TextButton", {
        Name = "PickerScrim", Text = "", AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.42, BorderSizePixel = 0,
        Visible = false, ZIndex = 200,
    }, screen)
    pickerScrim.MouseButton1Click:Connect(function() R.ui.closePicker() end)
    S.ui.pickerScrim = pickerScrim

    local picker = make("Frame", {
        Name = "Picker", BackgroundColor3 = THEME.panel, BorderSizePixel = 0,
        Visible = false, ZIndex = 201, ClipsDescendants = true,
    }, screen)
    corner(picker, 16)
    stroke(picker, THEME.accent, 1.4, 0.25)
    S.ui.picker = picker

    local pickerTitle = make("TextLabel", {
        Name = "PickerTitle", Text = "Choose", Size = UDim2.new(1, -76, 0, 22),
        Position = UDim2.fromOffset(16, 12), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 202,
    }, picker)
    S.ui.pickerTitle = pickerTitle
    local pickerClose = make("TextButton", {
        Name = "PickerClose", Text = "✕", Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(1, -56, 0, 4), BackgroundColor3 = THEME.card,
        Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = THEME.text,
        AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 203,
    }, picker)
    corner(pickerClose, 10)
    pickerClose.MouseButton1Click:Connect(function() R.ui.closePicker() end)

    local pickerScroll = make("ScrollingFrame", {
        Name = "PickerList", BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 4, ScrollBarImageColor3 = THEME.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 202,
    }, picker)
    make("UIListLayout", {
        Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    }, pickerScroll)
    pad(pickerScroll, 10, 10, 2, 10)
    S.ui.pickerScroll = pickerScroll

    R.ui.layoutPicker()
    R.ui.layout()
    R.ui.syncOverlay()
end

-- ============================================================================
-- PAGES AND TABS
-- ============================================================================
function R.ui.addPage(id, label)
    local page = make("ScrollingFrame", {
        Name = "Page_" .. id, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), Visible = false,
        ScrollBarThickness = 4, ScrollBarImageColor3 = THEME.accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ClipsDescendants = true, ZIndex = 51,
    }, S.ui.pageHost)
    make("UIListLayout", {
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    pad(page, 0, 0, 6, 18)

    local button = make("TextButton", {
        Name = "Tab_" .. id, Text = label, Size = UDim2.fromOffset(94, 46),
        BackgroundColor3 = THEME.card, BackgroundTransparency = 0.35,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = THEME.dim,
        AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 52,
    }, S.ui.tabHolder)
    corner(button, 10)
    button.MouseButton1Click:Connect(function()
        press(button)
        R.ui.selectTab(id)
    end)

    S.ui.pages = S.ui.pages or {}
    S.ui.tabs = S.ui.tabs or {}
    S.ui.pageOrder = S.ui.pageOrder or {}
    table.insert(S.ui.pageOrder, id)
    S.ui.pages[id] = { page = page, button = button, label = label }
    S.ui.tabs[id] = button
    return page
end

function R.ui.selectTab(id)
    if not S.ui.pages or not S.ui.pages[id] then return end
    S.activeTab = id
    for pageId, entry in pairs(S.ui.pages) do
        local active = pageId == id
        entry.page.Visible = active
        entry.button.BackgroundColor3 = active and THEME.accentDark or THEME.card
        entry.button.BackgroundTransparency = active and 0.05 or 0.35
        entry.button.TextColor3 = active and THEME.accent or THEME.dim
        if active then entry.page.CanvasPosition = Vector2.new(0, 0) end
    end
end

function R.ui.openPanel(open)
    S.open = open == true
    if S.open then
        if S.picker then R.ui.closePicker() end
        if S.activeTab then R.ui.selectTab(S.activeTab) end
    else
        S.aimHeld = false
    end
    R.ui.syncOverlay()
end

function R.ui.syncOverlay()
    local open = S.open
    if S.ui.scrim then S.ui.scrim.Visible = open end
    if S.ui.panel then S.ui.panel.Visible = open end
    if S.ui.dock then
        S.ui.dock.Visible = (not open) and C.quickDock and S.isTouch
    end
    if S.ui.orb then
        S.ui.orb.Visible = (not open) and (not (C.quickDock and S.isTouch))
    end
    local flying = S.toggles.flyOn and not open
    if S.ui.flyUp then S.ui.flyUp.Visible = flying end
    if S.ui.flyDown then S.ui.flyDown.Visible = flying end
end

function R.ui.syncDock()
    local buttons = S.ui.dockButtons
    if not buttons then return end
    local function paint(name, active, accent)
        local button = buttons[name]
        if not button then return end
        button.BackgroundColor3 = active
            and (accent and THEME.accentDark or THEME.cardUp)
            or THEME.card
        button.TextColor3 = active and THEME.accent or THEME.text
    end
    paint("aura", S.toggles.auraKillOn == true, true)
    -- Active means the assist is enabled; accent means the camera is actually
    -- locking now. Always Lock on Touch keeps the accent lit without a hold.
    paint("aim", S.toggles.aimOn == true,
        S.toggles.aimOn == true and (S.aimHeld == true or C.aimAlwaysLock == true))
    paint("fly", S.toggles.flyOn == true, true)
end

function R.ui.setStatus(text, kind)
    if not S.ui.subtitle then return end
    S.ui.subtitle.Text = "MOBILE v4.0 · " .. tostring(text)
    if S.ui.statusDot then
        S.ui.statusDot.BackgroundColor3 = kind == "err" and THEME.danger
            or (kind == "warn" and THEME.warn or THEME.good)
    end
end

function R.ui.composeStatus()
    local M = R.remotes
    local count = 0
    if M.melee then count = count + 1 end
    if M.shoot then count = count + 1 end
    if M.item then count = count + 1 end
    return string.format("%d fps · remotes %d/3 · %s",
        S.fps or 0, count, S.isTouch and "touch" or "desktop")
end

function R.ui.syncStatus()
    R.ui.setStatus(R.ui.composeStatus(), "ok")
end

function R.ui.finish()
    local order = S.ui.pageOrder or {}
    if order[1] then R.ui.selectTab(order[1]) end
    R.ui.openPanel(true)
    R.ui.layout()
    R.ui.syncDock()
    R.ui.setStatus("ready", "ok")
    task.delay(0.6, function()
        if not S.detached then
            R.toast("Riot Hub Mobile", "Tap ✕ to close. The quick dock stays out of the jump zone.", 4, "ok")
        end
    end)
end

-- ============================================================================
-- LAYOUT
-- ============================================================================
function R.ui.layout()
    local viewport = R.viewport()
    local vw, vh = viewport.X, viewport.Y
    local compact = vw < 760 or vh < 500
    local short = vh < 500
    local phone = vw < 600
    S.layout = { vw = vw, vh = vh, compact = compact, short = short, phone = phone }

    local panel = S.ui.panel
    if panel then
        if compact then
            panel.AnchorPoint = Vector2.new(0, 0)
            panel.Size = UDim2.new(1, -12, 1, -12)
            panel.Position = UDim2.new(0, 6, 0, 6)
        else
            panel.AnchorPoint = Vector2.new(0.5, 0.5)
            panel.Size = UDim2.fromOffset(
                math.min(860, math.max(640, vw - 100)),
                math.min(640, math.max(480, vh - 80)))
            panel.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end

    local headerHeight = short and 50 or 54
    if S.ui.header then S.ui.header.Size = UDim2.new(1, 0, 0, headerHeight) end
    if S.ui.close then
        S.ui.close.Size = UDim2.fromOffset(44, 44)
        S.ui.close.Position = UDim2.new(1, -52, 0, (headerHeight - 44) / 2)
    end
    if S.ui.title then
        S.ui.title.Position = UDim2.fromOffset(16, short and 5 or 7)
    end
    if S.ui.subtitle then
        S.ui.subtitle.Position = UDim2.fromOffset(28, short and 27 or 29)
    end
    if S.ui.statusDot then
        S.ui.statusDot.Position = UDim2.fromOffset(16, short and 31 or 33)
    end

    local tabHolder = S.ui.tabHolder
    local pageHost = S.ui.pageHost
    local tabLayout = S.ui.tabLayout
    if tabHolder and pageHost and tabLayout then
        if compact then
            tabHolder.Position = UDim2.new(0, 8, 0, headerHeight + (short and 4 or 8))
            tabHolder.Size = UDim2.new(1, -16, 0, short and 48 or 52)
            tabHolder.ScrollingDirection = Enum.ScrollingDirection.X
            tabHolder.AutomaticCanvasSize = Enum.AutomaticSize.X
            tabHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
            tabLayout.FillDirection = Enum.FillDirection.Horizontal
            tabLayout.Padding = UDim.new(0, 6)
            tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            local tabTop = headerHeight + (short and 4 or 8)
            pageHost.Position = UDim2.new(0, 10, 0, tabTop + (short and 48 or 52) + 6)
            pageHost.Size = UDim2.new(1, -20, 1,
                -(tabTop + (short and 48 or 52) + 6) - (short and 4 or 8))
        else
            tabHolder.Position = UDim2.new(0, 8, 0, headerHeight + 8)
            tabHolder.Size = UDim2.new(0, 190, 1, -(headerHeight + 16))
            tabHolder.ScrollingDirection = Enum.ScrollingDirection.Y
            tabHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
            tabHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
            tabLayout.FillDirection = Enum.FillDirection.Vertical
            tabLayout.Padding = UDim.new(0, 6)
            tabLayout.VerticalAlignment = Enum.VerticalAlignment.Top
            pageHost.Position = UDim2.new(0, 206, 0, headerHeight + 8)
            pageHost.Size = UDim2.new(1, -214, 1, -(headerHeight + 16))
        end
    end

    if S.ui.pages then
        for _, entry in pairs(S.ui.pages) do
            entry.page.Size = UDim2.fromScale(1, 1)
        end
    end
    if S.ui.tabs then
        for _, button in pairs(S.ui.tabs) do
            if compact then
                button.Size = UDim2.fromOffset(short and 88 or 96, short and 44 or 46)
                button.TextSize = short and 11 or 12
            else
                button.Size = UDim2.fromOffset(174, 44)
                button.TextSize = 13
            end
        end
    end

    local dock = S.ui.dock
    if dock then
        local buttonSize = short and 44 or 48
        dock.Size = short
            and UDim2.fromOffset(buttonSize * 4 + 3 * 4 + 12, 52)
            or UDim2.fromOffset(buttonSize + 12, buttonSize * 4 + 3 * 6 + 12)
        if short then
            -- 76 px above the bottom keeps the bar out of the thumbstick and
            -- jump zones that Roblox reserves on landscape phones.
            dock.AnchorPoint = Vector2.new(0.5, 1)
            dock.Position = UDim2.new(0.5, 0, 1, -76)
            S.ui.dockLayout.FillDirection = Enum.FillDirection.Horizontal
            S.ui.dockLayout.Padding = UDim.new(0, 4)
        else
            dock.AnchorPoint = Vector2.new(1, 0.5)
            dock.Position = UDim2.new(1, -8, 0.5, 0)
            S.ui.dockLayout.FillDirection = Enum.FillDirection.Vertical
            S.ui.dockLayout.Padding = UDim.new(0, 6)
        end
        for _, button in pairs(S.ui.dockButtons or {}) do
            button.Size = UDim2.fromOffset(buttonSize, buttonSize)
            button.TextSize = 11
        end
    end

    if S.ui.orb then
        S.ui.orb.Position = UDim2.new(1, -16, 0.38, 0)
        S.ui.orb.AnchorPoint = Vector2.new(1, 0.5)
        S.ui.orb.Size = UDim2.fromOffset(54, 54)
    end
    if S.ui.flyUp and S.ui.flyDown then
        if short then
            S.ui.flyUp.Position = UDim2.new(1, -8, 0.5, -118)
            S.ui.flyDown.Position = UDim2.new(1, -8, 0.5, -64)
        else
            S.ui.flyUp.Position = UDim2.new(1, -8, 0.5, 140)
            S.ui.flyDown.Position = UDim2.new(1, -8, 0.5, 196)
        end
        S.ui.flyUp.AnchorPoint = Vector2.new(1, 0.5)
        S.ui.flyDown.AnchorPoint = Vector2.new(1, 0.5)
    end
    if S.ui.toastHolder then
        S.ui.toastHolder.Size = UDim2.fromOffset(math.min(vw - 32, 380), 0)
        S.ui.toastHolder.Position = UDim2.new(0.5, 0, 0, 8)
        S.ui.toastHolder.AnchorPoint = Vector2.new(0.5, 0)
    end
    R.ui.layoutPicker()
end

function R.ui.layoutPicker()
    local picker = S.ui.picker
    if not picker then return end
    local viewport = R.viewport()
    local compact = viewport.X < 760 or viewport.Y < 500
    local count = S.pickerCount or 4
    local height = math.min(count * 58 + 82, viewport.Y * 0.72)
    if compact then
        picker.AnchorPoint = Vector2.new(0.5, 1)
        picker.Size = UDim2.fromOffset(math.min(viewport.X - 16, 520), height)
        picker.Position = UDim2.new(0.5, 0, 1, -8)
    else
        picker.AnchorPoint = Vector2.new(0.5, 0.5)
        picker.Size = UDim2.fromOffset(430, height)
        picker.Position = UDim2.new(0.5, 0, 0.5, 0)
    end
    if S.ui.pickerScroll then
        S.ui.pickerScroll.Position = UDim2.fromOffset(8, 52)
        S.ui.pickerScroll.Size = UDim2.new(1, -16, 1, -60)
    end
end

function R.ui.openPicker(title, options, current, callback)
    if not S.ui.picker then return end
    local scroll = S.ui.pickerScroll
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    S.pickerCount = #options
    S.picker = { callback = callback }
    S.ui.pickerTitle.Text = tostring(title)
    for index, option in ipairs(options) do
        local selected = option == current
        local choice = option
        local button = make("TextButton", {
            Name = "Option_" .. slug(option), Text = (selected and "✓  " or "    ") .. option,
            Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = selected and THEME.accentDark or THEME.card,
            Font = Enum.Font.GothamBold, TextSize = 13,
            TextColor3 = selected and THEME.accent or THEME.text,
            TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false,
            BorderSizePixel = 0, LayoutOrder = index, ZIndex = 203,
        }, scroll)
        pad(button, 14, 8, 0, 0)
        corner(button, 10)
        button.MouseButton1Click:Connect(function()
            press(button)
            R.ui.closePicker()
            if callback then
                task.spawn(function()
                    local ok, err = pcall(callback, choice)
                    if not ok then R.log("picker callback failed: " .. tostring(err), true) end
                end)
            end
        end)
    end
    S.ui.pickerScrim.Visible = true
    S.ui.picker.Visible = true
    R.ui.layoutPicker()
end

function R.ui.closePicker()
    S.picker = nil
    if S.ui.pickerScrim then S.ui.pickerScrim.Visible = false end
    if S.ui.picker then S.ui.picker.Visible = false end
end

-- ============================================================================
-- COMPONENTS
-- ============================================================================
function R.ui.section(page, text)
    local wrap = make("Frame", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1,
    }, page)
    make("TextLabel", {
        Text = string.upper(tostring(text)), Size = UDim2.new(1, 0, 1, -2),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = THEME.accent, TextXAlignment = Enum.TextXAlignment.Left,
    }, wrap)
    make("Frame", {
        Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = THEME.stroke, BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
    }, wrap)
    return wrap
end

function R.ui.info(page, text, height)
    local body = tostring(text)
    -- Keep documentation readable instead of clipping it to a guessed height.
    -- The estimate is deliberately conservative for a 320 px phone.
    local vw = R.viewport().X
    local contentWidth = (vw < 760 and (vw - 44)) or 620
    local charsPerLine = math.max(30, math.floor(contentWidth / 6.4))
    local lines = math.max(1, math.ceil(#body / charsPerLine))
    local computed = 30 + lines * 15
    local boxHeight = math.clamp(math.max(height or 0, computed), 52, 190)
    local wrap = make("Frame", {
        Size = UDim2.new(1, 0, 0, boxHeight), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.15, BorderSizePixel = 0,
    }, page)
    corner(wrap, 10)
    make("Frame", {
        Size = UDim2.new(0, 3, 1, -16), Position = UDim2.new(0, 0, 0, 8),
        BackgroundColor3 = THEME.violet, BorderSizePixel = 0,
    }, wrap)
    make("TextLabel", {
        Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6),
        BackgroundTransparency = 1, Text = body, Font = Enum.Font.Gotham,
        TextSize = 11, TextColor3 = THEME.dim, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    }, wrap)
    return wrap
end

function R.ui.button(owner, label, callback, options)
    options = options or {}
    local variant = options.variant
    local background = variant == "danger" and THEME.dangerDark
        or (variant == "accent" and THEME.accentDark or THEME.card)
    local button = make("TextButton", {
        Name = options.name or ("Button_" .. slug(label)),
        Text = tostring(label), Size = UDim2.new(1, 0, 0, options.height or 50),
        BackgroundColor3 = background, Font = Enum.Font.GothamBold,
        TextSize = options.textSize or 13, TextColor3 = variant == "danger" and THEME.danger or THEME.text,
        AutoButtonColor = false, BorderSizePixel = 0, TextWrapped = true,
    }, owner)
    corner(button, 10)
    if variant == "accent" then stroke(button, THEME.accent, 1, 0.5) end
    button.MouseButton1Click:Connect(function()
        press(button)
        task.spawn(function()
            local ok, err = pcall(callback)
            if not ok then R.log("button error [" .. tostring(label) .. "]: " .. tostring(err), true) end
        end)
    end)
    return button
end

function R.ui.pair(owner, labelA, callbackA, labelB, callbackB)
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1,
    }, owner)
    local function half(label, callback, position)
        local button = make("TextButton", {
            Name = "Button_" .. slug(label), Text = tostring(label),
            Size = UDim2.new(0.5, -4, 1, 0), Position = position,
            BackgroundColor3 = THEME.card, Font = Enum.Font.GothamBold,
            TextSize = 12, TextColor3 = THEME.text, AutoButtonColor = false,
            BorderSizePixel = 0, TextWrapped = true,
        }, row)
        corner(button, 10)
        button.MouseButton1Click:Connect(function()
            press(button)
            task.spawn(function()
                local ok, err = pcall(callback)
                if not ok then R.log("button error [" .. tostring(label) .. "]: " .. tostring(err), true) end
            end)
        end)
        return button
    end
    half(labelA, callbackA, UDim2.fromOffset(0, 0))
    half(labelB, callbackB, UDim2.new(0.5, 4, 0, 0))
    return row
end

function R.ui.toggle(owner, id, titleText, description, default, callback)
    local hasDescription = description ~= nil and description ~= ""
    local row = make("TextButton", {
        Name = "Toggle_" .. id, Text = "", AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, hasDescription and 64 or 54),
        BackgroundColor3 = THEME.card, BorderSizePixel = 0,
    }, owner)
    corner(row, 10)
    local rowStroke = stroke(row, THEME.accent, 1, 0.9)
    local accentBar = make("Frame", {
        Size = UDim2.new(0, 3, 1, -18), Position = UDim2.new(0, 0, 0, 9),
        BackgroundColor3 = THEME.accent, BackgroundTransparency = 0.9,
        BorderSizePixel = 0,
    }, row)
    make("TextLabel", {
        Name = "Title", Text = tostring(titleText),
        Size = UDim2.new(1, -84, 0, 18), Position = UDim2.fromOffset(14, hasDescription and 8 or 9),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    if hasDescription then
        make("TextLabel", {
            Name = "Description", Text = tostring(description),
            Size = UDim2.new(1, -84, 0, 32), Position = UDim2.fromOffset(14, 27),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
            TextColor3 = THEME.dim, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
        }, row)
    end
    local switch = make("Frame", {
        Name = "Switch", Size = UDim2.fromOffset(46, 28),
        Position = UDim2.new(1, -60, 0.5, -14),
        BackgroundColor3 = THEME.track, BorderSizePixel = 0,
    }, row)
    corner(switch, 14)
    local knob = make("Frame", {
        Name = "Knob", Size = UDim2.fromOffset(22, 22),
        Position = UDim2.fromOffset(3, 3), BackgroundColor3 = THEME.text,
        BorderSizePixel = 0,
    }, switch)
    corner(knob, 11)

    local enabled = default == true
    local function paint()
        switch.BackgroundColor3 = enabled and THEME.good or THEME.track
        knob.Position = enabled and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
        rowStroke.Transparency = enabled and 0.35 or 0.9
        accentBar.BackgroundTransparency = enabled and 0 or 0.9
        row.BackgroundColor3 = enabled and THEME.cardUp or THEME.card
    end
    local function set(value, silent)
        enabled = value == true
        S.toggles[id] = enabled
        paint()
        if R.ui.syncDock then R.ui.syncDock() end
        if not silent and callback then
            task.spawn(function()
                local ok, err = pcall(callback, enabled)
                if not ok then R.log("toggle error [" .. id .. "]: " .. tostring(err), true) end
            end)
        end
    end
    row.MouseButton1Click:Connect(function()
        press(row)
        set(not enabled)
    end)
    S.toggles[id] = enabled
    S.switches[id] = { Set = set, Get = function() return enabled end }
    paint()
    return { Set = set, Get = function() return enabled end, Row = row, Switch = switch }
end

function R.ui.slider(owner, id, titleText, minValue, maxValue, defaultValue, callback, suffix, step)
    local row = make("Frame", {
        Name = "Slider_" .. id, Size = UDim2.new(1, 0, 0, 74),
        BackgroundColor3 = THEME.card, BorderSizePixel = 0,
    }, owner)
    corner(row, 10)
    make("TextLabel", {
        Name = "Title", Text = tostring(titleText), Size = UDim2.new(1, -110, 0, 18),
        Position = UDim2.fromOffset(14, 8), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local valueLabel = make("TextLabel", {
        Name = "Value", Text = "", Size = UDim2.new(0, 92, 0, 18),
        Position = UDim2.new(1, -104, 0, 8), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = THEME.accent,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)
    local hit = make("Frame", {
        Name = "TrackHit", Size = UDim2.new(1, -28, 0, 44),
        Position = UDim2.fromOffset(14, 26), BackgroundTransparency = 1,
        Active = true,
    }, row)
    local track = make("Frame", {
        Name = "Track", Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 0.5, -3),
        BackgroundColor3 = THEME.track, BorderSizePixel = 0,
    }, hit)
    corner(track, 3)
    local fill = make("Frame", {
        Name = "Fill", Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = THEME.accent, BorderSizePixel = 0,
    }, track)
    corner(fill, 3)
    local thumb = make("Frame", {
        Name = "Thumb", Size = UDim2.fromOffset(22, 22),
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = THEME.text, BorderSizePixel = 0,
    }, hit)
    corner(thumb, 11)
    stroke(thumb, THEME.accent, 2, 0.1)

    local value = defaultValue
    local function formatValue()
        if step and step < 1 then
            return string.format("%.2f", value) .. (suffix or "")
        end
        return string.format("%.0f", value) .. (suffix or "")
    end
    local function paint(ratio)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        thumb.Position = UDim2.new(ratio, 0, 0.5, 0)
        valueLabel.Text = formatValue()
    end
    local function set(newValue, silent)
        value = math.clamp(tonumber(newValue) or minValue, minValue, maxValue)
        local ratio = (value - minValue) / math.max(maxValue - minValue, 0.0001)
        paint(ratio)
        if not silent and callback then
            local ok, err = pcall(callback, value)
            if not ok then R.log("slider error [" .. id .. "]: " .. tostring(err), true) end
        end
    end
    local function applyAt(x)
        local absPosition = hit.AbsolutePosition
        local absSize = hit.AbsoluteSize
        local width = math.max(absSize and absSize.X or 0, 1)
        local ratio = math.clamp(((x or 0) - (absPosition and absPosition.X or 0)) / width, 0, 1)
        local raw = minValue + (maxValue - minValue) * ratio
        if step and step > 0 then raw = math.floor(raw / step + 0.5) * step end
        value = math.clamp(raw, minValue, maxValue)
        paint((value - minValue) / math.max(maxValue - minValue, 0.0001))
        if callback then
            local ok, err = pcall(callback, value)
            if not ok then R.log("slider error [" .. id .. "]: " .. tostring(err), true) end
        end
    end

    hit.InputBegan:Connect(function(input)
        if not isPrimaryInput(input) then return end
        applyAt(input.Position.X)
        R.ui.beginDrag(input, function(changed)
            applyAt(changed.Position.X)
        end)
    end)
    set(defaultValue, true)
    S.sliders[id] = { Set = set, Get = function() return value end, Row = row }
    return { Set = set, Get = function() return value end, Row = row }
end

function R.ui.dropdown(owner, id, titleText, options, defaultValue, callback)
    local row = make("TextButton", {
        Name = "Dropdown_" .. id, Text = "", AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = THEME.card,
        BorderSizePixel = 0,
    }, owner)
    corner(row, 10)
    make("TextLabel", {
        Text = tostring(titleText), Size = UDim2.new(0.55, -14, 1, 0),
        Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local chosen = make("TextLabel", {
        Name = "Value", Text = tostring(defaultValue or "-"),
        Size = UDim2.new(0.45, -34, 1, 0), Position = UDim2.new(0.55, 0, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = THEME.accent, TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    make("TextLabel", {
        Text = "›", Size = UDim2.fromOffset(20, 20),
        Position = UDim2.new(1, -24, 0.5, -10), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = THEME.dim,
    }, row)
    local current = defaultValue
    local function set(option)
        current = option
        chosen.Text = tostring(option or "-")
        if callback then
            local ok, err = pcall(callback, option)
            if not ok then R.log("dropdown error [" .. id .. "]: " .. tostring(err), true) end
        end
    end
    row.MouseButton1Click:Connect(function()
        press(row)
        R.ui.openPicker(titleText, options, current, set)
    end)
    S.dropdowns[id] = { Set = set, Get = function() return current end, Row = row }
    return { Set = set, Get = function() return current end, Row = row }
end

function R.ui.statStrip(owner, items)
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1,
    }, owner)
    local count = #items
    local gap = 6
    -- Card width is W/count - gap. With a half-gap edge margin and one gap
    -- between cards, positions are (i-1)*W/count + gap/2. Spacing must be
    -- based on W/count, not on W/count + gap, or the last card is clipped by
    -- (count-1)*gap pixels on narrow phones.
    for index, item in ipairs(items) do
        local card = make("Frame", {
            Size = UDim2.new(1 / count, -gap, 1, 0),
            Position = UDim2.new((index - 1) / count, gap / 2, 0, 0),
            BackgroundColor3 = THEME.card, BorderSizePixel = 0,
        }, row)
        corner(card, 10)
        local value = make("TextLabel", {
            Name = "StatValue", Text = tostring(item.value or "0"),
            Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(8, 7),
            BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
            TextSize = 17, TextColor3 = item.color or THEME.accent,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, card)
        make("TextLabel", {
            Text = string.upper(tostring(item.label or "")),
            Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(8, 36),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
            TextColor3 = THEME.dim, TextXAlignment = Enum.TextXAlignment.Left,
        }, card)
        if item.key then S.ui.statLabels = S.ui.statLabels or {}; S.ui.statLabels[item.key] = value end
    end
    return row
end

function R.ui.playerList(owner)
    local box = make("Frame", {
        Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, owner)
    make("UIListLayout", {
        Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    }, box)
    local empty = make("TextLabel", {
        Name = "NearbyEmpty", Text = "No living players match the current filter.",
        Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.25, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = THEME.dim, TextWrapped = true, Visible = false,
    }, box)
    corner(empty, 10)
    S.ui.nearbyRows = {}
    for index = 1, 3 do
        local row = make("Frame", {
            Name = "NearbyRow" .. index, Size = UDim2.new(1, 0, 0, 56),
            BackgroundColor3 = THEME.card, BorderSizePixel = 0,
        }, box)
        corner(row, 10)
        -- The TP button starts at W-146. Stop the text at W-164 so a long
        -- display name cannot run underneath the first action button on a
        -- 288 px phone page.
        local name = make("TextLabel", {
            Name = "Name", Text = "-", Size = UDim2.new(1, -172, 0, 18),
            Position = UDim2.fromOffset(12, 8), BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = THEME.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        local distance = make("TextLabel", {
            Name = "Distance", Text = "", Size = UDim2.new(1, -172, 0, 14),
            Position = UDim2.fromOffset(12, 27), BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = THEME.dim,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        local function action(label, x, callback)
            local button = make("TextButton", {
                Name = "Nearby" .. label, Text = label, Size = UDim2.fromOffset(44, 44),
                Position = UDim2.new(1, x, 0.5, -22), BackgroundColor3 = THEME.cardUp,
                Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = THEME.text,
                AutoButtonColor = false, BorderSizePixel = 0,
            }, row)
            corner(button, 9)
            button.MouseButton1Click:Connect(function()
                press(button)
                if row.target then
                    task.spawn(function()
                        local ok, err = pcall(callback, row.target)
                        if not ok then R.log("nearby action failed: " .. tostring(err), true) end
                    end)
                end
            end)
        end
        action("TP", -146, function(target)
            local root = R.root(target)
            if root then R.teleportTo(root.CFrame * CFrame.new(0, 0, 3), target.Name) end
        end)
        action("KILL", -100, function(target) R.killTarget(target) end)
        action("CUFF", -54, function(target) R.arrestTarget(target) end)
        table.insert(S.ui.nearbyRows, { frame = row, name = name, distance = distance, target = nil })
    end
    S.ui.nearbyBox = box
    S.ui.nearbyEmpty = empty
    R.ui.refreshNearby()
    return box
end

function R.ui.refreshNearby()
    if not S.ui.nearbyRows then return end
    local myRoot = R.root()
    local list = {}
    if myRoot then
        for _, plr in ipairs(Players:GetPlayers()) do
            if R.validTarget(plr, C.auraTargets) then
                local root = R.root(plr)
                if root then
                    table.insert(list, {
                        plr = plr,
                        distance = (root.Position - myRoot.Position).Magnitude,
                    })
                end
            end
        end
        table.sort(list, function(a, b) return a.distance < b.distance end)
    end
    for index, row in ipairs(S.ui.nearbyRows) do
        local entry = list[index]
        if entry then
            row.frame.Visible = true
            row.target = entry.plr
            row.name.Text = entry.plr.Name
            row.distance.Text = string.format("%d studs · %s", math.floor(entry.distance),
                R.teamName(entry.plr) ~= "" and R.teamName(entry.plr) or R.teamColorName(entry.plr))
        else
            row.frame.Visible = false
            row.target = nil
        end
    end
    if S.ui.nearbyEmpty then S.ui.nearbyEmpty.Visible = #list == 0 end
end

function R.ui.logBox(owner)
    local wrap = make("Frame", {
        Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = THEME.card,
        BorderSizePixel = 0,
    }, owner)
    corner(wrap, 10)
    local label = make("TextLabel", {
        Name = "LogLabel", Text = "log empty", Size = UDim2.new(1, -24, 1, -16),
        Position = UDim2.fromOffset(12, 8), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 11, TextColor3 = THEME.dim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
    }, wrap)
    S.ui.logLabel = label
    R.ui.refreshLog()
    return wrap
end

function R.ui.refreshLog()
    local label = S.ui.logLabel
    if not label then return end
    local first = math.max(1, #S.logLines - 7)
    local lines = {}
    for index = first, #S.logLines do table.insert(lines, S.logLines[index]) end
    label.Text = #lines > 0 and table.concat(lines, "\n") or "log empty"
end

function R.ui.copyLog()
    local text = table.concat(S.logLines, "\n")
    if setclipboard then
        local ok = pcall(function() setclipboard(text) end)
        if ok then
            R.toast("Copied", "Log copied to clipboard.", 2, "ok")
            return true
        end
    end
    R.toast("Copy unavailable", "This executor has no setclipboard.", 2, "warn")
    return false
end

function R.ui.selfTest()
    local checks = {}
    local failures = 0
    local function check(label, condition, detail)
        table.insert(checks, string.format("%s %s%s", condition and "[OK]" or "[FAIL]",
            label, detail and (" — " .. tostring(detail)) or ""))
        if not condition then failures = failures + 1 end
    end
    check("ScreenGui", S.ui.screen ~= nil and S.ui.screen.Parent ~= nil)
    check("safe insets", S.ui.safeInsets == true, "CoreUISafeInsets")
    check("panel", S.ui.panel ~= nil)
    check("pages", S.ui.pages ~= nil and #(S.ui.pageOrder or {}) >= 7)
    check("viewport", S.layout.vw ~= nil and S.layout.vw > 0,
        tostring(S.layout.vw) .. "x" .. tostring(S.layout.vh))
    check("ItemHandler", R.remotes.item ~= nil, "may arrive with the map stream")
    check("meleeEvent", R.remotes.melee ~= nil, "may arrive with the map stream")
    check("ShootEvent", R.remotes.shoot ~= nil, "may arrive with the map stream")
    check("character", R.character() ~= nil)
    check("silent-aim hook", not S.toggles.silentOn or S.silentOld ~= nil
        or hookmetamethod == nil,
        S.toggles.silentOn and (hookmetamethod and "installed" or "executor has no hookmetamethod")
        or "silent aim is off")
    local summary = string.format("%d/%d checks passed", #checks - failures, #checks)
    return table.concat(checks, "\n"), summary, failures
end
-- ============================================================================
-- PAGES
-- ============================================================================
local S = R.state
local C = R.config
local Players = R.services.Players
local UIS = R.services.UserInputService

function R.pages.build()
    local ui = R.ui

    -- ------------------------------------------------------------------
    -- HOME
    -- ------------------------------------------------------------------
    local home = ui.addPage("home", "HOME")
    ui.section(home, "Session")
    ui.statStrip(home, {
        { label = "Actions", value = "0", key = "kills", color = R.theme.accent },
        { label = "Cuffs", value = "0", key = "arrests", color = R.theme.good },
        { label = "Items", value = "0", key = "items", color = R.theme.warn },
    })
    ui.info(home,
        "Tap a tab to switch pages. Every row is sized for a thumb; the close "
        .. "button is top-right. Remote calls are logged, never assumed successful.",
        58)

    ui.section(home, "One tap")
    ui.pair(home, "Kill All", function() R.killAll() end,
        "Arrest All", function() R.arrestAll() end)
    ui.pair(home, "Taze All", function() R.tazeAll() end,
        "Full Kit", function() R.giveKit() end)
    ui.pair(home, "Open Gate", function() R.openGate() end,
        "Respawn", function() R.respawn() end)

    ui.section(home, "Nearby players")
    ui.playerList(home)
    ui.info(home,
        "TP moves you behind the player. KILL sends the selected aura payload. "
        .. "CUFF invokes the arrest remote; the count only increases when the "
        .. "game shows the handcuffed GUI on the target.",
        64)

    -- ------------------------------------------------------------------
    -- COMBAT
    -- ------------------------------------------------------------------
    local combat = ui.addPage("combat", "COMBAT")
    ui.section(combat, "Kill aura")
    ui.toggle(combat, "auraKillOn", "Kill Aura",
        "Hits the nearest valid target inside the radius. Gun mode falls back to fists when no gun is available.",
        false, function() ui.syncDock() end)
    ui.slider(combat, "killRadius", "Radius", 10, 260, C.killAuraRadius,
        function(value) C.killAuraRadius = math.floor(value + 0.5) end, " studs")
    ui.slider(combat, "killPace", "Pace", 5, 100, math.floor(C.killAuraRate * 100),
        function(value) C.killAuraRate = math.max(value / 100, 0.05) end, " cs")
    ui.dropdown(combat, "killMode", "Attack mode", { "Fists", "Gun" }, C.killAuraMode,
        function(value) C.killAuraMode = value end)
    ui.dropdown(combat, "auraTargets", "Targets", { "All", "Inmates", "Guards", "Criminals" },
        C.auraTargets, function(value) C.auraTargets = value end)
    ui.toggle(combat, "respectFF", "Respect Forcefields",
        "Skip spawn-shielded players instead of wasting the aura beat.", C.respectForcefield,
        function(value) C.respectForcefield = value end)

    ui.section(combat, "Arrest aura")
    ui.toggle(combat, "auraArrestOn", "Arrest Aura",
        "Cuffs the nearest non-guard in range that matches the Targets filter. Runs on its own guarded task so it cannot stall the kill aura.",
        false, function() end)
    ui.slider(combat, "arrestRadius", "Radius", 20, 500, C.arrestAuraRadius,
        function(value) C.arrestAuraRadius = math.floor(value + 0.5) end, " studs")
    ui.slider(combat, "arrestRate", "Cooldown", 0.4, 3, C.arrestAuraRate,
        function(value) C.arrestAuraRate = value end, "s", 0.1)
    ui.toggle(combat, "arrestSnap", "Snap Behind Target",
        "Moves your root behind the target before invoking arrest. Client-side position only.",
        C.arrestSnap, function(value) C.arrestSnap = value end)

    ui.section(combat, "Taze loop")
    ui.toggle(combat, "auraTazeOn", "Taze Loop",
        "Cycles targets at the configured rate. Requires a Taser in the character or backpack.",
        false, function() end)
    ui.slider(combat, "tazeRate", "Taze cooldown", 0.2, 3, C.tazeRate,
        function(value) C.tazeRate = value end, "s", 0.1)

    ui.section(combat, "Aim assist")
    ui.toggle(combat, "aimOn", "Aim Assist",
        "Locks the camera toward the nearest head in the FOV. Desktop: hold RMB. Touch: tap AIM on the quick dock.",
        false, function() ui.syncDock() end)
    ui.slider(combat, "aimFov", "Aim FOV", 20, 500, C.aimbotFov,
        function(value) C.aimbotFov = math.floor(value + 0.5) end, "°")
    ui.slider(combat, "aimSmooth", "Smoothing", 0, 95, C.aimbotSmooth,
        function(value) C.aimbotSmooth = math.floor(value + 0.5) end, "%")
    ui.toggle(combat, "aimAlwaysLock", "Always Lock on Touch",
        "If off, touch aim only locks while AIM is engaged on the dock. Keep it off for normal camera control.",
        C.aimAlwaysLock, function(value) C.aimAlwaysLock = value end)
    ui.dropdown(combat, "aimTargets", "Aim targets", { "All", "Inmates", "Guards", "Criminals" },
        C.aimbotTargets, function(value) C.aimbotTargets = value end)

    ui.section(combat, "Silent aim")
    ui.toggle(combat, "silentOn", "Silent Aim",
        "Re-points your own ShootEvent bullets at the nearest head on the wire. Requires hookmetamethod.",
        false, function(value)
            if value and not R.setupSilentAim() then
                R.toast("Silent aim", "This executor has no hookmetamethod; the toggle was turned off.", 4, "err")
                if S.switches.silentOn then S.switches.silentOn.Set(false, true) end
            end
        end)
    ui.slider(combat, "silentFov", "Silent FOV", 20, 999, C.silentFov,
        function(value) C.silentFov = math.floor(value + 0.5) end, "°")
    ui.slider(combat, "silentHit", "Hit chance", 0, 100, C.silentHitChance,
        function(value) C.silentHitChance = math.floor(value + 0.5) end, "%")
    ui.toggle(combat, "silentWall", "Wall Check",
        "Skip the re-aim when the head is behind geometry.", C.silentWallCheck,
        function(value) C.silentWallCheck = value end)
    ui.toggle(combat, "silentRandom", "Random Body Part",
        "Sometimes aim at the torso instead of the head. Less consistent, less suspicious.", C.silentRandomPart,
        function(value) C.silentRandomPart = value end)
    ui.toggle(combat, "triggerOn", "Trigger Bot",
        "Auto-activates a GunStates tool when a target is inside the aim cone. It does not fire while the panel is open.",
        C.triggerOn, function(value) C.triggerOn = value end)

    ui.section(combat, "Actions")
    ui.pair(combat, "Kill All", function() R.killAll() end,
        "Arrest All", function() R.arrestAll() end)
    ui.button(combat, "Taze All Now", function() R.tazeAll() end)
    ui.info(combat,
        "Kill Aura uses meleeEvent; Gun mode uses the ShootEvent bullet table and a GunStates tool. "
        .. "Neither can guarantee server damage — Prison Life validates the payload server-side.",
        60)

    -- ------------------------------------------------------------------
    -- GEAR
    -- ------------------------------------------------------------------
    local gear = ui.addPage("gear", "GEAR")
    local function pacingInfoText()
        return "ItemHandler requests are paced to "
            .. string.format("%.1f", C.itemPace)
            .. "s apart. Lowering the pace can get the request rejected; the log will show it."
    end
    R.ui.refreshPacingInfo = function()
        if S.ui.pacingLabel then S.ui.pacingLabel.Text = pacingInfoText() end
    end
    ui.section(gear, "Loadout")
    ui.dropdown(gear, "gunChoice", "Preferred gun",
        { "M9", "MP5", "Remington 870", "AK-47", "M4A1" }, C.gunChoice,
        function(value) C.gunChoice = value end)
    ui.button(gear, "Give Selected Gun", function() R.giveSelectedGun() end)
    ui.button(gear, "Give Full Kit", function() R.giveKit() end)
    ui.button(gear, "Give Riot Gear", function() R.giveRiotGear() end)
    ui.pair(gear, "Key Card", function() R.giveNamedGear("Key card") end,
        "Crude Knife", function() R.giveNamedGear("Crude Knife") end)
    ui.button(gear, "Become Guard + Handcuffs", function() R.becomeGuardWithCuffs() end)
    local gearInfo = ui.info(gear, pacingInfoText(), 58)
    S.ui.pacingLabel = gearInfo and gearInfo:FindFirstChildOfClass("TextLabel") or nil

    ui.section(gear, "Gun mods (client-side GunStates)")
    ui.slider(gear, "gunDamage", "Damage", 1, 250, C.gunDamage,
        function(value) C.gunDamage = math.floor(value + 0.5) end)
    ui.slider(gear, "gunBullets", "Bullets per shot", 1, 30, C.gunBullets,
        function(value) C.gunBullets = math.floor(value + 0.5) end)
    ui.slider(gear, "gunFireRate", "Fire rate", 1, 100,
        math.max(1, math.floor(C.gunFireRate * 10000)),
        function(value) C.gunFireRate = math.max(value / 10000, 0.0001) end, "u")
    ui.slider(gear, "gunSpread", "Spread", 0, 100, math.floor(C.gunSpread * 1000),
        function(value) C.gunSpread = value / 1000 end, "u")
    ui.toggle(gear, "infAmmo", "Infinite Ammo", "Pins CurrentAmmo to infinity in the client module.",
        C.gunInfiniteAmmo, function(value) C.gunInfiniteAmmo = value end)
    ui.toggle(gear, "autoFire", "Full Auto", "Sets the client AutoFire flag.",
        C.gunAutoFire, function(value) C.gunAutoFire = value end)
    ui.pair(gear, "Apply Mods", function()
        local hits = R.modAllGuns()
        R.toast("Gun mods", tostring(hits) .. " tool(s) rewritten client-side", 2,
            hits > 0 and "ok" or "warn")
    end, "Mod Selected", function() R.modSelectedGun() end)
    ui.info(gear,
        "GunStates is a client module. Rewriting it can change local recoil/ammo, but damage, "
        .. "hit registration and ammo checks still belong to the server. Unload restores the fields we saved.",
        64)

    ui.section(gear, "Automation")
    ui.toggle(gear, "autoRearm", "Auto Re-Arm",
        "After a respawn, request the full gun list again and re-apply mods. Slow by design.",
        C.autoRearm, function(value) C.autoRearm = value end)
    ui.toggle(gear, "autoCollect", "Auto Collect",
        "Pulls the nearest ITEMPICKUP part through ItemHandler at the paced interval.",
        false, function() end)
    ui.slider(gear, "collectRadius", "Collect radius", 40, 900, C.autoCollectRadius,
        function(value) C.autoCollectRadius = math.floor(value + 0.5) end, " studs")
    ui.slider(gear, "itemPace", "Item pacing", 0.5, 5, C.itemPace,
        function(value)
            C.itemPace = value
            if R.ui.refreshPacingInfo then R.ui.refreshPacingInfo() end
        end, "s", 0.1)

    -- ------------------------------------------------------------------
    -- VISION
    -- ------------------------------------------------------------------
    local vision = ui.addPage("vision", "VISION")
    ui.section(vision, "ESP")
    ui.toggle(vision, "espOn", "Player ESP",
        "Name, distance, health bar and team tint over each living player.",
        false, function(value)
            if value then R.refreshEsp() else R.clearEsp() end
        end)
    ui.toggle(vision, "espNames", "Names", nil, C.espNames,
        function(value) C.espNames = value end)
    ui.toggle(vision, "espDistance", "Distance", nil, C.espDistance,
        function(value) C.espDistance = value end)
    ui.toggle(vision, "espHealth", "Health bar", nil, C.espHealth,
        function(value) C.espHealth = value end)
    ui.toggle(vision, "espTeam", "Team colors",
        "Guards blue, inmates orange, criminals red.", C.espTeamColor,
        function(value) C.espTeamColor = value end)
    ui.toggle(vision, "espVisible", "Line of sight only",
        "Raycasts from the camera to each head. More accurate, more expensive.",
        C.espVisibleOnly, function(value) C.espVisibleOnly = value end)
    ui.toggle(vision, "espTracers", "Tracers",
        "Screen lines to visible targets. Requires the executor Drawing API.",
        C.espTracers, function(value)
            if value and not R.drawingOk then
                R.toast("Tracers", "Drawing API is not available in this executor.", 3, "err")
                if S.switches.espTracers then S.switches.espTracers.Set(false, true) end
                C.espTracers = false
            else
                C.espTracers = value
            end
        end)

    ui.section(vision, "Chams")
    ui.toggle(vision, "chamsOn", "Character Chams",
        "Team-colored Highlight on each player. Capped by Roblox's own highlight limit.",
        false, function(value)
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= R.lp then R.applyChams(plr) end
            end
            if value then R.refreshEsp() end
        end)
    ui.toggle(vision, "chamsWall", "Through Walls",
        "AlwaysOnTop depth mode. Turn off for a less visually noisy result.",
        C.chamsThroughWalls, function(value)
            C.chamsThroughWalls = value
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= R.lp then R.applyChams(plr) end
            end
        end)

    ui.section(vision, "World")
    ui.toggle(vision, "fullbright", "Fullbright",
        "Bright ambient, no fog, no global shadows. Restored on unload.",
        false, function(value) R.setFullbright(value) end)
    ui.toggle(vision, "fpsBoost", "FPS Boost",
        "Disables particles, trails, smoke, fire and beams. Restored on unload.",
        false, function(value) R.setFpsBoost(value) end)
    ui.slider(vision, "cameraFov", "Camera FOV", 30, 120, C.cameraFov,
        function(value)
            C.cameraFov = math.floor(value + 0.5)
            R.setCameraFov(C.cameraFov)
        end, "°")
    ui.toggle(vision, "showAimFov", "Aim FOV ring",
        "Draw the aim cone around the screen center while aim or silent aim is on.",
        C.showAimFov, function(value) C.showAimFov = value end)
    ui.info(vision,
        "Highlights and ESP are client-side only. Other players do not see them. "
        .. "If the phone drops frames, turn off line-of-sight ESP first, then tracers.",
        58)

    -- ------------------------------------------------------------------
    -- MOVE
    -- ------------------------------------------------------------------
    local move = ui.addPage("move", "MOVE")
    ui.section(move, "Locomotion")
    ui.slider(move, "walkSpeed", "Walk speed", 8, 250, C.walkSpeed,
        function(value)
            C.walkSpeed = math.floor(value + 0.5)
            S.forceWalk = true
        end, " studs")
    ui.slider(move, "jumpPower", "Jump power", 8, 250, C.jumpPower,
        function(value)
            C.jumpPower = math.floor(value + 0.5)
            S.forceJump = true
        end)
    ui.toggle(move, "infJump", "Infinite Jump",
        "Re-triggers the jump state on JumpRequest. No extra keys.", false,
        function() end)
    ui.toggle(move, "antiStun", "Anti-Stun",
        "If a taze sets WalkSpeed to 0, restore the configured speed on the next heartbeat.",
        C.antiStun, function(value) C.antiStun = value end)
    ui.button(move, "Reset Movement", function()
        C.walkSpeed = 16
        C.jumpPower = 50
        S.forceWalk = false
        S.forceJump = false
        if S.sliders.walkSpeed then S.sliders.walkSpeed.Set(16, true) end
        if S.sliders.jumpPower then S.sliders.jumpPower.Set(50, true) end
        R.restoreMovement()
        R.toast("Movement", "WalkSpeed 16 · JumpPower 50", 2, "ok")
    end)

    ui.section(move, "Collision")
    ui.toggle(move, "noclipOn", "Noclip",
        "Every character part becomes non-collidable. Original CanCollide values are restored on off/unload.",
        false, function(value)
            if value then R.setNoclip(true) else R.restoreNoclip() end
        end)

    ui.section(move, "Flight")
    ui.toggle(move, "flyOn", "Fly",
        "Phone: use the normal movement joystick for horizontal flight and the ▲/▼ buttons for altitude. PC: WASD + Q/E.",
        false, function(value)
            if not value then R.stopFly() end
            R.ui.syncOverlay()
        end)
    ui.slider(move, "flySpeed", "Fly speed", 1, 30, C.flySpeed,
        function(value) C.flySpeed = value end, "", 0.5)
    ui.toggle(move, "tpWalkOn", "TP-Walk",
        "Adds a frame-rate-independent step along your movement direction.", false,
        function() end)
    ui.slider(move, "tpWalkPower", "TP-Walk power", 1, 15, C.tpWalkPower,
        function(value) C.tpWalkPower = value end)
    ui.toggle(move, "spinOn", "Spin", "Rotates your root at the configured speed.", false,
        function() end)
    ui.slider(move, "spinSpeed", "Spin speed", 10, 180, C.spinSpeed,
        function(value) C.spinSpeed = math.floor(value + 0.5) end, "°")
    ui.info(move,
        "Fly is a client-side CFrame move. It can be rubber-banded by the server and does not "
        .. "grant collision immunity; use Noclip only when you accept that risk.",
        58)

    -- ------------------------------------------------------------------
    -- WORLD
    -- ------------------------------------------------------------------
    local world = ui.addPage("world", "WORLD")
    ui.section(world, "Teleports")
    ui.pair(world, "Yard", function()
        R.teleportTo(CFrame.new(916.81, 99.99, 2373.38), "Yard")
    end, "Guard Spawn", function()
        R.teleportTo(CFrame.new(837.35, 99.99, 2303.22), "Guard Spawn")
    end)
    ui.pair(world, "Cafeteria", function()
        R.teleportTo(CFrame.new(945.71, 99.80, 2320.33), "Cafeteria")
    end, "Police Room", function()
        R.teleportTo(CFrame.new(909.45, 99.99, 2258.89), "Police Room")
    end)
    ui.pair(world, "Gate Button", function()
        R.teleportTo(CFrame.new(504.53, 104.91, 2240.84), "Gate Button")
    end, "Riot Gear", function()
        R.teleportTo(CFrame.new(853.40, 100.70, 2216.49), "Riot Gear Stand")
    end)
    ui.pair(world, "Criminal Base", function()
        R.teleportTo(CFrame.new(-938.77, 94.13, 2063.85), "Criminal Base")
    end, "Crim Hammer", function()
        R.teleportTo(CFrame.new(808.08, 95.59, 2525.31), "Crim Base Hammer")
    end)
    ui.pair(world, "Armory", function()
        R.teleportToItem("M9", "Armory")
    end, "Nearest Player", function()
        R.teleportNearestPlayer()
    end)
    ui.info(world,
        "Coordinates are from the public Prison Life map. If a major map update moves a location, "
        .. "Armory/Nearest Player use live parts instead of constants.",
        52)

    ui.section(world, "Prison")
    ui.button(world, "Open Prison Gate", function() R.openGate() end)
    ui.toggle(world, "gateLoopOn", "Gate Loop",
        "Re-sends the gate button request on the interval below. Respects item pacing.", false,
        function() end)
    ui.slider(world, "gateInterval", "Gate interval", 0.5, 6, C.gateSpamInterval,
        function(value) C.gateSpamInterval = value end, "s", 0.5)
    ui.toggle(world, "barriers", "Walk Through Doors + Fences",
        "Reversible client-side CanCollide change on workspace.Doors and Prison_Fences.",
        false, function(value) R.setBarriers(value) end)

    ui.section(world, "Team")
    ui.pair(world, "Guard", function() R.switchTeam("Guard") end,
        "Inmate", function() R.switchTeam("Inmate") end)
    ui.button(world, "Neutral", function() R.switchTeam("Neutral") end)
    ui.info(world,
        "A team switch is reported as confirmed only if LocalPlayer.Team/TeamColor updates on the client. "
        .. "Otherwise the toast says the request was unconfirmed.",
        52)

    ui.section(world, "Session")
    ui.toggle(world, "antiAfk", "Anti-AFK",
        "VirtualUser nudge on the Idled event. Uses the executor's normal controller API.",
        C.antiAfk, function(value) C.antiAfk = value end)
    ui.toggle(world, "instantRespawn", "Instant Respawn",
        "On death, waits 0.6s then invokes loadchar. It does not bypass the server's respawn rules.",
        C.instantRespawn, function(value) C.instantRespawn = value end)
    ui.pair(world, "Respawn", function() R.respawn() end,
        "Rebind Remotes", function()
            local M = R.rebindRemotes()
            R.toast("Remotes", "melee " .. tostring(M.melee ~= nil)
                .. " · shoot " .. tostring(M.shoot ~= nil)
                .. " · item " .. tostring(M.item ~= nil), 3, "ok")
        end)
    ui.button(world, "Rejoin Server", function() R.rejoin() end, { variant = "danger" })

    -- ------------------------------------------------------------------
    -- SETUP
    -- ------------------------------------------------------------------
    local setup = ui.addPage("setup", "SETUP")
    ui.section(setup, "Diagnostics")
    local diag = ui.info(setup,
        "Tap Run Self-Test to check the UI, remotes, character and executor capabilities.",
        104)
    local diagLabel = diag:FindFirstChildOfClass("TextLabel")
    S.ui.diagLabel = diagLabel
    S.ui.diagBox = diag
    ui.button(setup, "Run Self-Test", function()
        local text, summary, failures = R.ui.selfTest()
        local full = summary .. "\n" .. text
        if S.ui.diagLabel then S.ui.diagLabel.Text = full end
        if S.ui.diagBox then
            -- Grow the diagnostics card instead of clipping the report in the
            -- fixed 104 px default. Count wrapped visual lines as well as
            -- explicit newlines, because a 320 px phone wraps check labels.
            local lines = 1
            for _ in string.gmatch(full, "\n") do lines = lines + 1 end
            local vw = R.viewport().X
            local contentWidth = (vw < 760 and (vw - 80)) or 620
            local charsPerLine = math.max(28, math.floor(contentWidth / 6.4))
            local visualLines = math.max(lines, math.ceil(#full / charsPerLine))
            S.ui.diagBox.Size = UDim2.new(1, 0, 0,
                math.clamp(20 + visualLines * 14, 104, 480))
        end
        R.log("self-test: " .. summary, failures > 0)
        R.toast("Self-test", summary, 3, failures > 0 and "warn" or "ok")
    end)
    ui.button(setup, "Copy Log", function() R.ui.copyLog() end)

    ui.section(setup, "Config")
    ui.button(setup, "Save Config", function() R.saveConfig() end)
    ui.button(setup, "Load Config", function() R.loadConfig() end)
    ui.button(setup, "Reset Config", function() R.resetConfig() end)

    ui.section(setup, "Interface")
    ui.toggle(setup, "reduceAnim", "Reduce Animations",
        "Disable tweens and scale bumps. Recommended on low-end phones.",
        C.reduceAnim, function(value) C.reduceAnim = value end)
    ui.toggle(setup, "quickDockOn", "Quick Action Dock",
        "The vertical MENU/AURA/AIM/FLY strip while the panel is closed. On short landscape it becomes a bottom bar.",
        C.quickDock, function(value)
            C.quickDock = value
            R.ui.syncOverlay()
        end)
    ui.info(setup,
        "The hub uses CoreUISafeInsets + ClipToDeviceSafeArea where the client supports it, "
        .. "and falls back to the normal topbar inset on older clients. Layout is recomputed on rotation.",
        58)

    ui.section(setup, "Session control")
    ui.pair(setup, "Close Panel", function() R.ui.openPanel(false) end,
        "Unload", function()
            if R.Unload then R.Unload() end
        end)
    ui.section(setup, "Activity log")
    ui.logBox(setup)
    ui.info(setup,
        "Riot Hub Mobile v4.0. Original Riothub.lua and PL-Vortex-7.1 are preserved. "
        .. "No external loadstrings, key system, or pastebin dependency.",
        52)
end
-- ============================================================================
-- RUNTIME — boot, loops, hotkeys, config persistence, restore-on-unload
-- ============================================================================
local S = R.state
local C = R.config
local Players = R.services.Players
local UIS = R.services.UserInputService
local RunService = R.services.RunService
local HttpService = R.services.HttpService

local SAVE_FILE = "RiotHubMobile.json"
local booted = false
local runtimeStarted = false
local characterBound = nil
local characterDeathConnection = nil

-- ============================================================================
-- TOGGLE / CONFIG BRIDGE
-- ============================================================================
function R.setToggle(id, value)
    local switch = S.switches and S.switches[id]
    if switch then
        switch.Set(value == true)
    else
        S.toggles[id] = value == true
    end
end

function R.flipToggle(id)
    R.setToggle(id, not (S.toggles[id] == true))
end

function R.ui.refreshStats()
    local labels = S.ui.statLabels
    if not labels then return end
    if labels.kills then labels.kills.Text = tostring(S.killCounter or 0) end
    if labels.arrests then labels.arrests.Text = tostring(S.arrestCount or 0) end
    if labels.items then labels.items.Text = tostring(S.itemCount or 0) end
end

-- Push the loaded/default config into the existing controls without firing
-- their callbacks a second time, then apply the active effects explicitly.
function R.ui.applyConfig()
    local function slider(id, value)
        local control = S.sliders and S.sliders[id]
        if control then control.Set(value, true) end
    end
    local function toggle(id, value)
        local control = S.switches and S.switches[id]
        if control then control.Set(value == true, true) end
    end
    local function dropdown(id, value)
        local control = S.dropdowns and S.dropdowns[id]
        if control then control.Set(value) end
    end

    slider("killRadius", C.killAuraRadius)
    slider("killPace", math.floor(C.killAuraRate * 100 + 0.5))
    slider("arrestRadius", C.arrestAuraRadius)
    slider("arrestRate", C.arrestAuraRate)
    slider("tazeRate", C.tazeRate)
    slider("aimFov", C.aimbotFov)
    slider("aimSmooth", C.aimbotSmooth)
    slider("silentFov", C.silentFov)
    slider("silentHit", C.silentHitChance)
    slider("gunDamage", C.gunDamage)
    slider("gunBullets", C.gunBullets)
    slider("gunFireRate", math.max(1, math.floor(C.gunFireRate * 10000 + 0.5)))
    slider("gunSpread", math.floor(C.gunSpread * 1000 + 0.5))
    slider("collectRadius", C.autoCollectRadius)
    slider("itemPace", C.itemPace)
    slider("cameraFov", C.cameraFov)
    slider("walkSpeed", C.walkSpeed)
    slider("jumpPower", C.jumpPower)
    slider("flySpeed", C.flySpeed)
    slider("tpWalkPower", C.tpWalkPower)
    slider("spinSpeed", C.spinSpeed)
    slider("gateInterval", C.gateSpamInterval)

    toggle("respectFF", C.respectForcefield)
    toggle("arrestSnap", C.arrestSnap)
    toggle("aimAlwaysLock", C.aimAlwaysLock)
    toggle("silentWall", C.silentWallCheck)
    toggle("silentRandom", C.silentRandomPart)
    toggle("triggerOn", C.triggerOn)
    toggle("infAmmo", C.gunInfiniteAmmo)
    toggle("autoFire", C.gunAutoFire)
    toggle("autoRearm", C.autoRearm)
    toggle("espNames", C.espNames)
    toggle("espDistance", C.espDistance)
    toggle("espHealth", C.espHealth)
    toggle("espTeam", C.espTeamColor)
    toggle("espVisible", C.espVisibleOnly)
    toggle("espTracers", C.espTracers)
    toggle("chamsWall", C.chamsThroughWalls)
    toggle("showAimFov", C.showAimFov)
    toggle("antiStun", C.antiStun)
    toggle("antiAfk", C.antiAfk)
    toggle("instantRespawn", C.instantRespawn)
    toggle("reduceAnim", C.reduceAnim)
    toggle("quickDockOn", C.quickDock)

    dropdown("killMode", C.killAuraMode)
    dropdown("auraTargets", C.auraTargets)
    dropdown("aimTargets", C.aimbotTargets)
    dropdown("gunChoice", C.gunChoice)

    S.forceWalk = C.walkSpeed ~= 16
    S.forceJump = C.jumpPower ~= 50
    -- Loading or resetting a config is an explicit request for the values in
    -- that config. If the incoming movement values are the defaults, put the
    -- humanoid back to its captured baseline instead of leaving a previous
    -- forced speed in place.
    local humanoid = R.humanoid()
    if humanoid and S.movementBase then
        if not S.forceWalk then
            pcall(function() humanoid.WalkSpeed = S.movementBase.WalkSpeed end)
        end
        if not S.forceJump then
            pcall(function() humanoid.JumpPower = S.movementBase.JumpPower end)
        end
    end
    if R.setCameraFov then R.setCameraFov(C.cameraFov) end
    if R.ui.refreshPacingInfo then R.ui.refreshPacingInfo() end
    if R.ui.refreshNearby then R.ui.refreshNearby() end
    if S.toggles.fullbright and R.setFullbright then R.setFullbright(true) end
    if S.toggles.fpsBoost and R.setFpsBoost then R.setFpsBoost(true) end
    if S.toggles.noclipOn and R.setNoclip then R.setNoclip(true) end
    if S.toggles.barriers and R.setBarriers then R.setBarriers(true) end
    if S.toggles.espOn and R.refreshEsp then R.refreshEsp() end
    if S.toggles.silentOn and R.setupSilentAim then R.setupSilentAim() end
    if R.ui.syncDock then R.ui.syncDock() end
    if R.ui.syncOverlay then R.ui.syncOverlay() end
end

-- ============================================================================
-- CONFIG PERSISTENCE
-- ============================================================================
function R.saveConfig()
    local encoder = HttpService and HttpService.JSONEncode
    if not encoder then
        R.toast("Save failed", "HttpService JSONEncode is unavailable.", 3, "err")
        return false
    end
    local ok, body = pcall(function() return HttpService:JSONEncode(C) end)
    if not ok or type(body) ~= "string" then
        R.log("config encode failed: " .. tostring(body), true)
        R.toast("Save failed", "Config could not be encoded.", 3, "err")
        return false
    end
    if type(writefile) ~= "function" then
        R.toast("Save unavailable", "This executor does not expose writefile().", 3, "err")
        return false
    end
    local wrote, err = pcall(function() writefile(SAVE_FILE, body) end)
    if not wrote then
        R.log("writefile failed: " .. tostring(err), true)
        R.toast("Save failed", tostring(err):sub(1, 90), 3, "err")
        return false
    end
    R.log("config saved to " .. SAVE_FILE .. " (" .. #body .. " bytes)")
    R.toast("Config saved", SAVE_FILE, 2, "ok")
    return true
end

local function sanitizeConfig()
    -- These ranges mirror the slider bounds in 04_pages.lua exactly. Loading a
    -- value outside the range would leave the runtime using a number the
    -- control cannot display or reproduce.
    local limits = {
        itemPace = { 0.5, 5 },
        killAuraRate = { 0.05, 1 },
        arrestAuraRate = { 0.4, 3 },
        tazeRate = { 0.2, 3 },
        killAuraRadius = { 10, 260 },
        arrestAuraRadius = { 20, 500 },
        autoCollectRadius = { 40, 900 },
        aimbotFov = { 20, 500 },
        aimbotSmooth = { 0, 95 },
        silentFov = { 20, 999 },
        silentHitChance = { 0, 100 },
        gunDamage = { 1, 250 },
        gunBullets = { 1, 30 },
        gunFireRate = { 0.0001, 0.01 },
        gunSpread = { 0, 0.1 },
        cameraFov = { 30, 120 },
        walkSpeed = { 8, 250 },
        jumpPower = { 8, 250 },
        flySpeed = { 1, 30 },
        tpWalkPower = { 1, 15 },
        spinSpeed = { 10, 180 },
        gateSpamInterval = { 0.5, 6 },
        meleeBurstHits = { 1, 10 },
        gunBulletsPerCall = { 1, 30 },
        maxLogLines = { 10, 300 },
    }
    for key, range in pairs(limits) do
        local value = tonumber(C[key])
        if value then C[key] = math.clamp(value, range[1], range[2]) end
    end
    -- Quantize the same way the sliders do, so the value used at runtime is
    -- exactly the value the loaded control shows.
    for _, key in ipairs({
        "killAuraRadius", "arrestAuraRadius", "autoCollectRadius",
        "aimbotFov", "aimbotSmooth", "silentFov", "silentHitChance",
        "gunDamage", "gunBullets", "cameraFov", "walkSpeed", "jumpPower",
        "tpWalkPower", "spinSpeed", "meleeBurstHits", "gunBulletsPerCall",
        "maxLogLines",
    }) do
        C[key] = math.floor(C[key] + 0.5)
    end
    C.killAuraRate = math.floor(C.killAuraRate * 100 + 0.5) / 100
    C.gunFireRate = math.floor(C.gunFireRate * 10000 + 0.5) / 10000
    C.gunSpread = math.floor(C.gunSpread * 1000 + 0.5) / 1000
    C.itemPace = math.floor(C.itemPace * 10 + 0.5) / 10
    C.arrestAuraRate = math.floor(C.arrestAuraRate * 10 + 0.5) / 10
    C.tazeRate = math.floor(C.tazeRate * 10 + 0.5) / 10
    C.flySpeed = math.floor(C.flySpeed * 2 + 0.5) / 2
    C.gateSpamInterval = math.floor(C.gateSpamInterval * 2 + 0.5) / 2

    local modes = { Fists = true, Gun = true }
    if not modes[C.killAuraMode] then C.killAuraMode = "Fists" end
    local filters = { All = true, Inmates = true, Guards = true, Criminals = true }
    if not filters[C.auraTargets] then C.auraTargets = "All" end
    if not filters[C.aimbotTargets] then C.aimbotTargets = "All" end
    local guns = {}
    for _, gun in ipairs(R.GUNS or {}) do guns[gun] = true end
    if not guns[C.gunChoice] then C.gunChoice = "M9" end
    if not R.drawingOk then C.espTracers = false end
end

function R.loadConfig()
    if type(readfile) ~= "function" then
        R.toast("Load unavailable", "This executor does not expose readfile().", 3, "err")
        return false
    end
    local ok, body = pcall(function() return readfile(SAVE_FILE) end)
    if not ok or type(body) ~= "string" or #body == 0 then
        R.log("config read failed: " .. tostring(body), true)
        R.toast("Load failed", "No readable " .. SAVE_FILE .. ".", 3, "err")
        return false
    end
    local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not decodedOk or type(decoded) ~= "table" then
        R.log("config decode failed: " .. tostring(decoded), true)
        R.toast("Load failed", "The saved config is not valid JSON.", 3, "err")
        return false
    end
    local applied = 0
    for key, defaultValue in pairs(R.defaultConfig) do
        local incoming = decoded[key]
        if type(incoming) == type(defaultValue) then
            C[key] = incoming
            applied = applied + 1
        elseif type(defaultValue) == "number" and type(incoming) == "string" then
            local number = tonumber(incoming)
            if number then
                C[key] = number
                applied = applied + 1
            end
        end
    end
    sanitizeConfig()
    R.ui.applyConfig()
    R.log("config loaded from " .. SAVE_FILE .. " (" .. applied .. " values)")
    R.toast("Config loaded", tostring(applied) .. " values applied", 2, "ok")
    return true
end

function R.resetConfig()
    for key, value in pairs(R.defaultConfig) do C[key] = value end
    sanitizeConfig()
    R.ui.applyConfig()
    R.log("config reset to defaults")
    R.toast("Config reset", "Config values restored; session-only toggles were left alone.", 2, "ok")
    return true
end

-- ============================================================================
-- INPUT / CHARACTER / VIEWPORT
-- ============================================================================
local function bindViewport()
    local camera = workspace and workspace.CurrentCamera
    if not camera then return end
    local ok, signal = pcall(function() return camera:GetPropertyChangedSignal("ViewportSize") end)
    if ok and signal then
        R.connect(signal, function()
            if not S.detached then R.ui.layout() end
        end)
    end
end

local function bindCharacter(character)
    if not character or character == characterBound then return end
    -- A respawn creates a new Humanoid. Drop the previous character's Died
    -- connection instead of accumulating one handler per life.
    if characterDeathConnection then
        pcall(function() characterDeathConnection:Disconnect() end)
        characterDeathConnection = nil
    end
    characterBound = character
    R.captureMovementBase()

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        characterDeathConnection = R.connect(humanoid.Died, function()
            if S.detached or not C.instantRespawn then return end
            task.delay(0.6, function()
                if S.detached then return end
                if R.lp.Character == character then R.respawn() end
            end)
        end)
    end

    if C.autoRearm then
        task.delay(1.5, function()
            if S.detached or S.itemBusy then return end
            S.itemBusy = true
            for _, gun in ipairs(R.GUNS) do
                if S.detached then break end
                R.giveBest(gun, "giver")
            end
            if not S.detached then R.modAllGuns() end
            S.itemBusy = false
        end)
    end
end

local function installInput()
    R.connect(UIS.InputBegan, function(input, gameProcessed)
        if S.detached or gameProcessed then return end
        if UIS.GetFocusedTextBox and UIS:GetFocusedTextBox() then return end
        local key = input.KeyCode
        if key == Enum.KeyCode.RightControl or key == Enum.KeyCode.RightShift then
            R.ui.openPanel(not S.open)
        elseif key == Enum.KeyCode.G then
            R.flipToggle("auraKillOn")
        elseif key == Enum.KeyCode.H then
            R.flipToggle("auraArrestOn")
        elseif key == Enum.KeyCode.J then
            R.flipToggle("auraTazeOn")
        elseif key == Enum.KeyCode.K then
            R.flipToggle("flyOn")
        end
    end)

    R.connect(UIS.JumpRequest, function()
        if S.detached or not S.toggles.infJump then return end
        local humanoid = R.humanoid()
        if not humanoid then return end
        local okState, state = pcall(function() return humanoid:GetState() end)
        if okState and state == Enum.HumanoidStateType.Dead then return end
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end)

    R.connect(Players.LocalPlayer.CharacterAdded, function(character)
        if S.detached then return end
        bindCharacter(character)
    end)

    R.connect(Players.LocalPlayer.Idled, function()
        if S.detached or not C.antiAfk then return end
        R.antiAfkNow()
    end)

    bindCharacter(Players.LocalPlayer.Character)
    bindViewport()

    local okWorkspace, workspaceSignal = pcall(function()
        return workspace:GetPropertyChangedSignal("CurrentCamera")
    end)
    if okWorkspace and workspaceSignal then
        R.connect(workspaceSignal, function()
            if not S.detached then bindViewport() end
        end)
    end
end

-- ============================================================================
-- LOOPS
-- ============================================================================
local function guardedAction(flag, label, fn)
    if S[flag] then return false end
    S[flag] = true
    task.spawn(function()
        local ok, err = pcall(fn)
        S[flag] = false
        if not ok and not S.detached then
            R.log(label .. " failed: " .. tostring(err), true)
        end
    end)
    return true
end

local function startCombatBrain()
    task.spawn(function()
        while not S.detached do
            local now = R.now()

            if S.toggles.auraKillOn and not S.killBusy
                and now - (S.lastKillAt or 0) >= math.max(C.killAuraRate, 0.1) then
                local target = R.nearest(C.auraTargets, C.killAuraRadius)
                if target then
                    S.lastKillAt = now
                    guardedAction("killBusy", "kill aura", function()
                        R.killTarget(target)
                    end)
                end
            end

            if S.toggles.auraArrestOn and not S.arrestBusy
                and now - (S.lastArrestAt or 0) >= math.max(C.arrestAuraRate, 0.2) then
                local target = R.nearestArrestable(C.arrestAuraRadius)
                if target then
                    S.lastArrestAt = now
                    guardedAction("arrestBusy", "arrest aura", function()
                        R.arrestTarget(target)
                    end)
                end
            end

            if S.toggles.auraTazeOn and not S.tazeBusy
                and now - (S.lastTazeAt or 0) >= math.max(C.tazeRate, 0.1) then
                local taser = R.getTaser()
                if taser then
                    local target = R.nearest(C.auraTargets, C.killAuraRadius)
                    if target then
                        S.lastTazeAt = now
                        guardedAction("tazeBusy", "taze loop", function()
                            R.tazeTarget(target, taser)
                        end)
                    end
                elseif not S.tazeWarned then
                    S.tazeWarned = true
                    R.log("taze loop is on but no Taser is carried", true)
                end
            end

            if S.toggles.gateLoopOn and not S.gateBusy
                and now - (S.lastGateAt or 0) >= math.max(C.gateSpamInterval, 0.5) then
                S.lastGateAt = now
                task.spawn(function()
                    S.gateBusy = true
                    R.openGate()
                    S.gateBusy = false
                end)
            end

            if S.toggles.autoCollect and not S.itemBusy
                and now - (S.lastCollectAt or 0) >= math.max(C.itemPace, 0.8) then
                S.lastCollectAt = now
                task.spawn(function()
                    S.itemBusy = true
                    local ok, err = pcall(function()
                        R.collectNearest(C.autoCollectRadius)
                    end)
                    S.itemBusy = false
                    if not ok then R.log("auto collect failed: " .. tostring(err), true) end
                end)
            end

            task.wait(0.1)
        end
    end)
end

local function startHousekeeping()
    task.spawn(function()
        while not S.detached do
            R.ui.refreshStats()
            if S.open and S.activeTab == "home" and R.ui.refreshNearby then
                R.ui.refreshNearby()
            end
            if R.ui.syncStatus then R.ui.syncStatus() end
            task.wait(0.5)
        end
    end)
end

local function startHeartbeat()
    R.connect(RunService.Heartbeat, function(dt)
        if S.detached then return end
        local step = math.clamp(tonumber(dt) or 0.016, 0.001, 0.1)
        R.applyMovement(step)
        R.updateAim(step)
        R.triggerTick()

        S.frameCount = S.frameCount + 1
        S.fpsAccum = (S.fpsAccum or 0) + step
        if S.fpsAccum >= 0.5 then
            S.fps = math.floor(S.frameCount / S.fpsAccum + 0.5)
            S.frameCount = 0
            S.fpsAccum = 0
        end

        S.visualClock = (S.visualClock or 0) + step
        if S.visualClock >= 0.12 then
            S.visualClock = 0
            R.updateEsp()
            R.updateTracers()
        end

        local viewport = R.viewport()
        if viewport.X ~= S.layout.vw or viewport.Y ~= S.layout.vh then
            R.ui.layout()
        end
    end)
end

local function startRuntime()
    if runtimeStarted then return end
    runtimeStarted = true
    installInput()
    startCombatBrain()
    startHousekeeping()
    startHeartbeat()
end

-- ============================================================================
-- BOOT
-- ============================================================================
function R.boot()
    if booted then return end
    booted = true
    R.ui.buildBase()
    R.pages.build()
    R.buildAimRing()
    R.resolveRemotes()
    R.captureMovementBase()
    startRuntime()
    R.ui.finish()
    S.loaded = true
    R.env.RiotHubMobile = R
    R.log("RiotHub Mobile v" .. R.version .. " loaded · "
        .. (S.isTouch and "touch" or "desktop") .. " layout")
    R.log("Unload restores movement, noclip, lighting, particles, camera and gun fields")
end

-- ============================================================================
-- UNLOAD
-- ============================================================================
function R.Unload()
    if S.detached then return end
    S.detached = true

    R.disconnectAll()
    S.activeDrag = nil
    if S.ui.closePicker then pcall(R.ui.closePicker) end

    pcall(R.clearEsp)
    pcall(R.removeSilentAim)
    pcall(R.setFullbright, false)
    pcall(R.setFpsBoost, false)
    pcall(R.setBarriers, false)
    pcall(R.restoreNoclip)
    pcall(R.restoreGuns)
    pcall(R.restoreMovement)
    pcall(R.stopFly)
    pcall(R.restoreCamera)

    if S.ui.fovScreen then
        pcall(function() S.ui.fovScreen:Destroy() end)
        S.ui.fovScreen = nil
        S.ui.fovRing = nil
    end
    if S.ui.screen then
        pcall(function() S.ui.screen:Destroy() end)
        S.ui.screen = nil
    end
    if S.ui.espFolder then
        pcall(function() S.ui.espFolder:Destroy() end)
        S.ui.espFolder = nil
    end

    S.picker = nil
    S.ui.picker = nil
    S.ui.pickerScrim = nil
    S.ui.panel = nil
    S.ui.header = nil
    S.ui.tabHolder = nil
    S.ui.pageHost = nil
    S.ui.dock = nil
    S.ui.orb = nil
    S.ui.toastHolder = nil
    S.ui.pages = nil
    S.ui.tabs = nil
    S.ui.dockButtons = nil
    S.open = false
    S.loaded = false

    if R.env and R.env.RiotHubMobile == R then R.env.RiotHubMobile = nil end
    print("[RiotHub] unloaded; restored game state")
end

R.boot()
