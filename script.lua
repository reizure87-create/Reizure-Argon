--[[
	RiotHub v4.0 — Prison Life (Latest 2025/2026 Edition)
	All-in-One GUI + Admin Command Engine · Keyless · Single File
	Compatible with Delta / Solara / Codex / Xeno / Wave / Krnl / Potassium / Mobile & PC

	WHAT'S NEW IN v4.0 (LATEST PRISON LIFE PATCH READY):
	  - Smart ItemHandler Bypass: Supports CFrame Snap-Back + Position Table Spoof
	    so grabbing guns, keycards, and opening gates works even on distance-checked servers.
	  - True Server ShootEvent Engine: Sends the exact {Hit, Cframe, RayObject, Distance}
	    bullet structure the server validates, auto-equips the weapon, and fires
	    ReloadEvent so server-side ammo never runs dry.
	  - TP-Punch Kill & Super Punch (One-Punch KO): Instant weaponless kills using
	    distance-validated meleeEvent bursts.
	  - Target Manager & Troll Suite: Target selector, Loopkill, Fling (SkidFling
	    velocity launcher), Orbit/Annoy, Spectate/View, Arrest, Taze, Goto.
	  - Vehicle Spawner & Car Mods: Remote-spawn Police/Squad cars directly to your
	    character, Car Fly, Car Speed/Torque boost, and Car Noclip.
	  - Full Protection Suite: Anti-Taze (restores WalkSpeed + Backpack UI),
	    Anti-Arrest (auto-breaks cuffs & returns to position), Anti-Shield,
	    Anti-Criminal Pad (Guards can enter Crim Base), Respawn Where You Died.
	  - Built-in PrizzLife/Tiger-style Chat Commands (:kill, :loopkill, :fling,
	    :arrest, :taze, :car, :guns, :mod, :crim, :guard, :inmate, :re, :gate, etc.)

	CONTROLS
	  - Mobile: Tap the draggable "RH" button on the left edge to toggle the hub.
	  - PC Keys: RightCtrl / U = Toggle UI | G = Kill Aura | H = Arrest Aura
	             J = Taze Loop | F = Super Punch | Z = Fly | F3 = Open Gate
]]

-- ============================================================================
-- SERVICES & ENVIRONMENT
-- ============================================================================
local plrs        = game:GetService("Players")
local rs          = game:GetService("ReplicatedStorage")
local runSvc      = game:GetService("RunService")
local uis         = game:GetService("UserInputService")
local tweSvc      = game:GetService("TweenService")
local httpSvc     = game:GetService("HttpService")
local starterGui  = game:GetService("StarterGui")
local teleportSvc = game:GetService("TeleportService")
local virtualUser = game:GetService("VirtualUser")
local lighting    = game:GetService("Lighting")

local lp = plrs.LocalPlayer
if not lp then
	local waited = 0
	while not plrs.LocalPlayer and waited < 20 do
		task.wait(0.25)
		waited = waited + 0.25
	end
	lp = plrs.LocalPlayer
end
if not lp then
	error("[RiotHub] No LocalPlayer present — join Prison Life first, then execute.", 0)
end

local mouse = lp:GetMouse()

local function currentCam()
	return workspace.CurrentCamera
end

local function getGenv()
	if getgenv then return getgenv() end
	if not _G.__RiotHubGenv then _G.__RiotHubGenv = {} end
	return _G.__RiotHubGenv
end

-- Cleanly unload any previous instance so re-execution never duplicates hooks/UI
pcall(function()
	if getGenv().RiotHub and getGenv().RiotHub.Unload then
		getGenv().RiotHub.Unload()
	end
end)
pcall(function()
	local parents = {}
	if gethui then pcall(function() table.insert(parents, gethui()) end) end
	table.insert(parents, game:FindFirstChildOfClass("CoreGui"))
	table.insert(parents, lp and lp:FindFirstChild("PlayerGui"))
	for _, parent in ipairs(parents) do
		if parent then
			for _, name in ipairs({
				"RiotHub_GUI", "RiotHubFOVRing", "RiotHubEspOverlays",
				"RiotHub_FlyPad", "RiotHub_Toasts", "RiotHub_PunchBtn",
			}) do
				local old = parent:FindFirstChild(name)
				if old then old:Destroy() end
			end
		end
	end
end)

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG = {
	-- Combat & Auras
	killAuraRadius    = 50,
	killAuraRate      = 0.25,
	killAuraIgnoreFF  = true,
	killAuraMode      = "Smart (Gun + Fists)", -- "Smart (Gun + Fists)" | "Fists" | "Gun"
	meleeBurstHits    = 14,
	gunBulletsPerCall = 10,
	arrestAuraRadius  = 100,
	arrestAuraRate    = 0.9,
	arrestSnap        = true,
	tazeRate          = 0.6,
	auraTargets       = "All",
	aimbotTargets     = "All",
	triggerTargets    = "All",
	superPunch        = false,

	-- Hitbox Expander
	hitboxEnabled     = false,
	hitboxSize        = 12,
	hitboxPart        = "Head", -- "Head" | "HumanoidRootPart"
	hitboxTransparency = 0.65,

	-- Aimbot & Silent Aim
	aimbotFov         = 150,
	aimbotSmooth      = 30,
	showAimFov        = true,
	silentFov         = 360,
	silentHitChance   = 100,
	silentWallCheck   = false,
	silentRandomPart  = false,

	-- Guns & Item Handler
	gunChoice         = "Remington 870",
	pickupMethod      = "Smart Snap + Spoof", -- "Smart Snap + Spoof" | "CFrame Snap-Back" | "Remote Spoof Only"
	modTarget         = "All Tools",
	gunDamage         = 100,
	gunBullets        = 12,
	gunFireRate       = 0.001,
	gunSpread         = 0,
	gunInfiniteAmmo   = true,
	gunAutoFire       = true,
	autoRearm         = false,
	autoReloadServer  = true,

	-- Visuals & ESP
	espNames          = true,
	espDistance       = true,
	espHealthBar      = true,
	espTeamColor      = true,
	espVisibleOnly    = false,
	espTracers        = false,
	chamsThroughWalls = true,

	-- Movement & Flight
	walkSpeed         = 16,
	jumpPower         = 50,
	tpWalkPower       = 3,
	flySpeed          = 4,
	spinSpeed         = 30,

	-- Vehicles
	carSpeedMult      = 2.0,
	carFlySpeed       = 4,

	-- Protections & World
	noStayStunned     = true,
	antiArrest        = false,
	antiShield        = false,
	antiCrimPad       = false,
	respawnAtDeath    = false,
	instantRespawn    = false,
	gateSpamInterval  = 1.5,
	autoCollectRadius = 200,

	-- System
	safePacing        = false, -- Snap-back works rapidly; enable pacing only on strict custom servers
	itemPace          = 0.35,
	maxLogLines       = 45,
	clickArrest       = false,
	clickTp           = false,
	reduceAnim        = false,
	antiAfk           = true,
	chatCmds          = true,
	waypoints         = {},
}

-- ============================================================================
-- RUNTIME STATE
-- ============================================================================
local state = {
	toggles         = {},
	switches        = {},
	espUnits        = {},
	tracers         = {},
	killCounter     = 0,
	arrestCount     = 0,
	itemCount       = 0,
	fps             = 60,
	detached        = false,
	logCounter      = 0,
	lastItemPull    = 0,
	touchMove       = { fwd = 0, back = 0, up = 0, down = 0 },
	noclipSaved     = {},
	hitboxSaved     = {},
	carNoclipSaved  = {},
	uiAnim          = 0.14,
	selectedTarget  = nil,
	loopKillTargets = {}, -- [playerName] = true
	loopTazeTargets = {}, -- [playerName] = true
	lastDeathCF     = nil,
	preArrestCF     = nil,
	hiddenWorld     = nil,
	flinging        = false,
}

local connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

-- ============================================================================
-- UTILITIES, LOGGING & NOTIFICATIONS
-- ============================================================================
local function spread(t)
	if unpack then return unpack(t) end
	return table.unpack(t)
end

local function packArgs(...)
	local n, t = select("#", ...), {}
	for i = 1, n do t[i] = select(i, ...) end
	return t
end

local log
local function vsafe(fn, ...)
	local args = packArgs(...)
	local ok, err = pcall(function() fn(spread(args)) end)
	if not ok then
		log("remote err: " .. tostring(err):sub(1, 100), true)
	end
	return ok
end

local toast = function() end
local logScroll, logText

log = function(msg, isErr)
	local body = tostring(msg)
	if #body > 150 then body = body:sub(1, 150) .. "..." end
	print("[RiotHub] " .. body)
	if logText then
		state.logCounter = state.logCounter + 1
		logText.Text = logText.Text .. "\n" .. string.format("%3d) %s%s",
			state.logCounter % 1000, isErr and "[ERR] " or "", body)
		local n = 0
		for _ in string.gmatch(logText.Text, "[^\n]+") do n = n + 1 end
		while n > CONFIG.maxLogLines do
			local _, rest = string.match(logText.Text, "([^\n]-\n)(.+)$")
			if not rest then break end
			logText.Text = rest
			n = n - 1
		end
		if logScroll then
			logScroll.CanvasSize = UDim2.new(0, 0, 0, n * 14 + 24)
			logScroll.CanvasPosition = Vector2.new(0, n * 14 + 24)
		end
	end
end

local function notify(title, text, dur)
	pcall(function()
		starterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = dur or 3 })
	end)
end

local function pace()
	local now = tick()
	if CONFIG.safePacing then
		local left = state.lastItemPull + CONFIG.itemPace - now
		if left > 0 then task.wait(left) end
	end
	state.lastItemPull = tick()
end

-- ============================================================================
-- CHARACTER & PLAYER HELPERS
-- ============================================================================
local function charHumanoid(plr)
	plr = plr or lp
	local ch = plr and plr.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function charRoot(plr)
	plr = plr or lp
	local ch = plr and plr.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
		or ch:FindFirstChild("Torso")
		or ch:FindFirstChild("UpperTorso")
		or ch.PrimaryPart
end

local function charTorso(plr)
	plr = plr or lp
	local ch = plr and plr.Character
	if not ch then return nil end
	return ch:FindFirstChild("Torso")
		or ch:FindFirstChild("UpperTorso")
		or ch:FindFirstChild("HumanoidRootPart")
end

local function charHead(plr)
	plr = plr or lp
	local ch = plr and plr.Character
	return ch and ch:FindFirstChild("Head")
end

local function findPlayerByQuery(q)
	if not q or q == "" then return nil end
	local low = string.lower(tostring(q))
	if low == "me" or low == "self" then return lp end
	for _, p in ipairs(plrs:GetPlayers()) do
		if string.lower(p.Name) == low or string.lower(p.DisplayName) == low then
			return p
		end
	end
	for _, p in ipairs(plrs:GetPlayers()) do
		if string.sub(string.lower(p.Name), 1, #low) == low
			or string.sub(string.lower(p.DisplayName), 1, #low) == low then
			return p
		end
	end
	return nil
end

local function getActiveTarget()
	if state.selectedTarget and state.selectedTarget.Parent == plrs then
		return state.selectedTarget
	end
	return nil
end

-- ============================================================================
-- REMOTE RESOLUTION (ASYNC + ON-DEMAND REBIND)
-- ============================================================================
local function remoteFolder()
	return workspace:FindFirstChild("Remote")
end

local function getRemote(name, timeout)
	local folder = remoteFolder()
	if not folder then return nil end
	return folder:FindFirstChild(name) or (timeout and folder:WaitForChild(name, timeout) or nil)
end

local ItemHandler, shootingEvent, meleeEvent, reloadEvent, soundEvent

local function resolveRemotesAsync()
	task.spawn(function()
		local folder = remoteFolder() or workspace:WaitForChild("Remote", 15)
		if folder then
			ItemHandler = folder:FindFirstChild("ItemHandler") or folder:WaitForChild("ItemHandler", 10)
		end
		log("remotes — ItemHandler: " .. tostring(not not ItemHandler))
	end)
	task.spawn(function()
		meleeEvent = rs:FindFirstChild("meleeEvent") or rs:WaitForChild("meleeEvent", 15)
	end)
	task.spawn(function()
		shootingEvent = rs:FindFirstChild("ShootEvent") or rs:WaitForChild("ShootEvent", 15)
	end)
	task.spawn(function()
		reloadEvent = rs:FindFirstChild("ReloadEvent") or rs:WaitForChild("ReloadEvent", 15)
		soundEvent  = rs:FindFirstChild("SoundEvent")
	end)
end
task.spawn(resolveRemotesAsync)

local function rebindRemotes(timeout)
	local folder = remoteFolder() or workspace:WaitForChild("Remote", timeout or 6)
	if folder then ItemHandler = folder:FindFirstChild("ItemHandler") or ItemHandler end
	meleeEvent    = meleeEvent or rs:FindFirstChild("meleeEvent")
	shootingEvent = shootingEvent or rs:FindFirstChild("ShootEvent")
	reloadEvent   = reloadEvent or rs:FindFirstChild("ReloadEvent")
	local found = {
		melee  = not not meleeEvent,
		shoot  = not not shootingEvent,
		reload = not not reloadEvent,
		item   = not not ItemHandler,
		arrest = not not getRemote("arrest"),
	}
	log("rebind — melee=" .. tostring(found.melee)
		.. " shoot=" .. tostring(found.shoot)
		.. " reload=" .. tostring(found.reload)
		.. " item=" .. tostring(found.item)
		.. " arrest=" .. tostring(found.arrest))
	return found
end

local function prisonTable()
	return workspace:FindFirstChild("Prison_ITEMS")
end

local function getItemIn(subfolder, itemName, childName)
	local t = prisonTable()
	if not t then return nil end
	local folder = t:FindFirstChild(subfolder)
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

local function findItemAnywhere(itemName)
	local t = prisonTable()
	if not t then return nil end
	-- Prefer giver folder first, then single, then recursive search
	local giver = t:FindFirstChild("giver")
	if giver and giver:FindFirstChild(itemName) then
		return giver:FindFirstChild(itemName)
	end
	local single = t:FindFirstChild("single")
	if single and single:FindFirstChild(itemName) then
		return single:FindFirstChild(itemName)
	end
	return t:FindFirstChild(itemName, true)
end

local function findPickupPart(itemModelOrPart)
	if not itemModelOrPart then return nil end
	if itemModelOrPart:IsA("BasePart") then return itemModelOrPart end
	return itemModelOrPart:FindFirstChild("ITEMPICKUP", true)
		or itemModelOrPart:FindFirstChildWhichIsA("BasePart", true)
end

-- ============================================================================
-- TEAM LOOKUPS & CHECKS
--   Bright blue = Guards · Bright orange = Inmates · Bright red = Criminals
-- ============================================================================
local function teamColor(plr)
	local ok, col = pcall(function() return plr.TeamColor end)
	if not ok or not col then return "White" end
	return tostring(col.Name)
end
local function isGuard(plr)  return teamColor(plr) == "Bright blue"   end
local function isInmate(plr) return teamColor(plr) == "Bright orange" end
local function isCrim(plr)   return teamColor(plr) == "Bright red"    end

local function selTarget(plr, cfgKey)
	local want = CONFIG[cfgKey] or "All"
	if want == "All" then return true end
	if want == "Guards" then return isGuard(plr) end
	if want == "Inmates" then return isInmate(plr) end
	if want == "Criminals" then return isCrim(plr) end
	if want == "Non-Friends" then
		local ok, fr = pcall(function() return lp:IsFriendsWith(plr.UserId) end)
		return not (ok and fr)
	end
	return true
end

local function isCuffed(target)
	local ch = target and target.Character
	if not ch then return false end
	local head = ch:FindFirstChild("Head")
	return (head and head:FindFirstChild("handcuffedGui")) ~= nil
end

local function arrestables()
	local out = {}
	for _, plr in ipairs(plrs:GetPlayers()) do
		if plr ~= lp and not isGuard(plr) then
			local ch = plr.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if ch and charRoot(plr) and hum and hum.Health > 0 and not isCuffed(plr) then
				table.insert(out, plr)
			end
		end
	end
	return out
end

-- ============================================================================
-- SMART ITEM HANDLER (BYPASSES LATEST PRISON LIFE DISTANCE CHECKS)
-- ============================================================================
local pullingLock = false

local function invokeItemHandlerSmart(targetModelOrPart, label)
	if not ItemHandler then
		local folder = remoteFolder()
		if folder then
			ItemHandler = folder:FindFirstChild("ItemHandler") or folder:WaitForChild("ItemHandler", 4)
		end
	end
	if not ItemHandler then
		log("ItemHandler missing on this server", true)
		return false
	end
	if not targetModelOrPart then return false end

	pace()

	local pickupPart = findPickupPart(targetModelOrPart)
	local modelTarget = targetModelOrPart:IsA("Model") and targetModelOrPart
		or (pickupPart and pickupPart.Parent) or targetModelOrPart
	local myRoot = charRoot()
	local method = CONFIG.pickupMethod or "Smart Snap + Spoof"

	-- 1) Remote Spoof Only
	if method == "Remote Spoof Only" or not myRoot or not pickupPart then
		local pivot = myRoot and myRoot.CFrame or CFrame.new(0, 100, 0)
		local ok = vsafe(function()
			ItemHandler:InvokeServer(pickupPart or targetModelOrPart)
		end)
		if not ok then
			ok = vsafe(function()
				ItemHandler:InvokeServer({ Position = pivot, Parent = modelTarget })
			end)
		end
		if ok then
			state.itemCount = state.itemCount + 1
			log("granted (spoof): " .. tostring(label or modelTarget.Name))
		end
		return ok
	end

	-- 2) Smart Snap + Spoof / CFrame Snap-Back (Bypasses server distance check!)
	local dist = (pickupPart.Position - myRoot.Position).Magnitude
	local needSnap = (method == "CFrame Snap-Back") or (dist > 13)

	while pullingLock do task.wait(0.03) end
	pullingLock = true

	local savedCF = myRoot.CFrame
	local savedCamCF = currentCam() and currentCam().CFrame
	local ok = false

	pcall(function()
		if needSnap and myRoot and myRoot.Parent then
			myRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			myRoot.CFrame = pickupPart.CFrame * CFrame.new(0, 2.2, 0)
			task.wait(0.07)
		end

		-- Invoke with literal ITEMPICKUP BasePart first (what standard & updated PL servers expect)
		local s1 = pcall(function()
			ItemHandler:InvokeServer(pickupPart)
		end)
		-- Also invoke with table format for hybrid/custom PL servers
		if not s1 then
			s1 = pcall(function()
				ItemHandler:InvokeServer({
					Position = pickupPart.CFrame,
					Parent = modelTarget,
				})
			end)
		end
		ok = s1
		task.wait(0.04)
	end)

	-- Restore player back to exact starting spot
	pcall(function()
		local r = charRoot()
		if needSnap and r and savedCF then
			r.CFrame = savedCF
			r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			if savedCamCF and currentCam() then
				currentCam().CFrame = savedCamCF
			end
		end
	end)

	pullingLock = false

	if ok then
		state.itemCount = state.itemCount + 1
		log("granted: " .. tostring(label or modelTarget.Name))
	end
	return ok
end

local function giveAnywhere(itemName)
	local target = findItemAnywhere(itemName)
	if not target then
		log("item not currently on map: " .. tostring(itemName), true)
		return false
	end
	return invokeItemHandlerSmart(target, itemName)
end

local function giveLegacy(itemName, subfolder)
	local child = getItemIn(subfolder or "giver", itemName, "ITEMPICKUP")
		or getItemIn("single", itemName, "ITEMPICKUP")
		or getItemIn(subfolder or "giver", itemName)
	if not child then
		log("giver not found for " .. tostring(itemName), true)
		return false
	end
	return invokeItemHandlerSmart(child, itemName)
end

local GIVEN_GUNS  = { "Remington 870", "AK-47", "M9", "M4A1" }
local GIVEN_MELEE = { "Key card", "Hammer", "Crude Knife" }

local function modAllGuns() end -- forward declaration; bound in Gun Engine below

local function giveAllLoot(autoMod)
	task.spawn(function()
		log("pulling full weapon kit...")
		local savedRoot = charRoot() and charRoot().CFrame
		for _, g in ipairs(GIVEN_GUNS) do
			if state.detached then return end
			local item = findItemAnywhere(g)
			if item then invokeItemHandlerSmart(item, g) end
		end
		for _, m in ipairs(GIVEN_MELEE) do
			if state.detached then return end
			local item = findItemAnywhere(m)
			if item then invokeItemHandlerSmart(item, m) end
		end
		local shield = findItemAnywhere("Riot Shield")
		if shield then invokeItemHandlerSmart(shield, "Riot Shield") end
		if savedRoot and charRoot() then
			pcall(function() charRoot().CFrame = savedRoot end)
		end
		if autoMod then
			task.wait(0.25)
			modAllGuns()
		end
		toast("Full Kit Granted", "All catalogued weapons pulled to backpack", 2.5, "ok")
	end)
end

local function giveRiotGear()
	task.spawn(function()
		giveAnywhere("Riot Shield")
		local hat = getItemIn("hats", "Riot helmet", "hat") or getItemIn("hats", "Police hat", "hat")
		if hat then invokeItemHandlerSmart(hat, "Riot Helmet") end
		local mask = getItemIn("hats", "Ski mask", "hat")
		if mask then invokeItemHandlerSmart(mask, "Ski Mask") end
		toast("Riot Gear", "Shield & headgear requested", 2, "ok")
	end)
end

-- ============================================================================
-- GUN ENGINE — TRUE SHOOTEVENT + RELOADEVENT + GUNSTATES MODDING
-- ============================================================================
local function gunState(tool)
	if not (tool and tool:FindFirstChild("GunStates")) then return nil end
	local gs
	pcall(function() gs = require(tool.GunStates) end)
	return gs
end

local function findGunTool(preferredName)
	local function sweep(container)
		if not container then return nil end
		if preferredName then
			local t = container:FindFirstChild(preferredName)
			if t and t:IsA("Tool") and t:FindFirstChild("GunStates") then return t end
		end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t:FindFirstChild("GunStates") and t.Name ~= "Taser" then
				return t
			end
		end
		return nil
	end
	return sweep(lp.Character) or sweep(lp.Backpack)
end

local function ensureGunTool(waitBudget)
	local tool = findGunTool(CONFIG.gunChoice) or findGunTool()
	if tool then return tool end
	if giveAnywhere(CONFIG.gunChoice) or giveAnywhere("Remington 870") or giveAnywhere("M9") then
		for _ = 1, math.max(waitBudget or 6, 1) do
			task.wait(0.15)
			if state.detached then return nil end
			tool = findGunTool(CONFIG.gunChoice) or findGunTool()
			if tool then return tool end
		end
	end
	return nil
end

-- Equips the gun onto LocalPlayer.Character if it's currently in Backpack
-- (Prison Life's server checks tool.Parent == Character on ShootEvent!)
local function equipToolFast(tool)
	if not tool or not lp.Character then return false end
	if tool.Parent == lp.Character then return true end
	pcall(function()
		local hum = charHumanoid()
		if hum then
			hum:EquipTool(tool)
		else
			tool.Parent = lp.Character
		end
	end)
	return tool.Parent == lp.Character
end

-- Exact bullet payload validated by Prison Life's server GunServer script:
-- MUST include ["Hit"] = targetPart (as well as Cframe, RayObject, Distance)
local function buildBullets(targetPart, count)
	local bullets = {}
	local myPos = (charHead() and charHead().Position)
		or (charRoot() and charRoot().Position)
		or Vector3.new(0, 100, 0)
	local targetPos = targetPart and targetPart.Position or Vector3.new(0, 100, 0)
	local diff = targetPos - myPos
	local dist = math.max(diff.Magnitude, 1)
	local dir = diff.Unit * math.max(dist + 10, 100)

	for i = 1, count or 1 do
		bullets[i] = {
			["RayObject"] = Ray.new(myPos, dir),
			["Distance"]  = dist,
			["Cframe"]    = targetPart and targetPart.CFrame or CFrame.new(),
			["Hit"]       = targetPart, -- Primary key read by Prison Life server script!
			["HitPart"]   = targetPart, -- Compatibility key for modded servers
			["Color"]     = Color3.fromRGB(255, 255, 0),
		}
	end
	return bullets
end

local function reloadToolServer(tool)
	if not tool then return end
	if not reloadEvent then reloadEvent = rs:FindFirstChild("ReloadEvent") end
	if reloadEvent then
		pcall(function() reloadEvent:FireServer(tool) end)
	end
end

local function bulletKill(plr, tool, count)
	if not shootingEvent then
		shootingEvent = rs:FindFirstChild("ShootEvent")
		if not shootingEvent then return false end
	end
	local ch = plr and plr.Character
	if not ch then return false end
	if not (tool and tool:FindFirstChild("GunStates")) then return false end

	-- Strip Riot Shield if Anti-Shield is enabled so rays/hits never get blocked
	if CONFIG.antiShield then
		pcall(function()
			local sh = ch:FindFirstChild("Riot Shield")
			if sh then sh:Destroy() end
		end)
	end

	local part = ch:FindFirstChild("Head")
		or ch:FindFirstChild("Torso")
		or ch:FindFirstChild("UpperTorso")
		or ch:FindFirstChild("HumanoidRootPart")
	if not part then return false end

	equipToolFast(tool)
	local bullets = buildBullets(part, count or CONFIG.gunBulletsPerCall)
	local ok = vsafe(function()
		shootingEvent:FireServer(bullets, tool)
	end)
	reloadToolServer(tool)
	return ok
end

local function modGun(tool)
	if not (tool and tool:IsA("Tool") and tool:FindFirstChild("GunStates")) then
		return false
	end
	local ok = pcall(function()
		local gs = require(tool.GunStates)
		gs.Damage      = CONFIG.gunDamage
		gs.Bullets     = CONFIG.gunBullets
		gs.FireRate    = math.max(CONFIG.gunFireRate, 0.0001)
		gs.Spread      = CONFIG.gunSpread
		gs.ReloadTime  = 0.0001
		gs.AutoFire    = CONFIG.gunAutoFire
		gs.Range       = 9999
		gs.MaxAmmo     = math.max(gs.MaxAmmo or 0, 9999)
		gs.StoredAmmo  = 999999
		if CONFIG.gunInfiniteAmmo then
			gs.CurrentAmmo = math.huge
		else
			gs.CurrentAmmo = gs.MaxAmmo
		end
	end)
	if not ok then
		-- Fallback via getgc/debug.setupvalue if GunStates table is read-only
		log("GunStates write failed on " .. tostring(tool.Name), true)
		return false
	end
	reloadToolServer(tool)
	log("modded " .. tool.Name)
	return true
end

modAllGuns = function()
	task.spawn(function()
		local hits = 0
		local function sweep(container)
			if not container then return end
			for _, tool in ipairs(container:GetChildren()) do
				if tool:IsA("Tool") and tool:FindFirstChild("GunStates") then
					if modGun(tool) then hits = hits + 1 end
				end
			end
		end
		sweep(lp.Backpack)
		sweep(lp.Character)
		log("gun mods applied to " .. hits .. " weapon(s)")
		if hits > 0 then
			toast("Guns Modded", "Applied stats to " .. hits .. " weapon(s)", 2, "ok")
		end
	end)
end

local function modNamed(name)
	task.spawn(function()
		local tool = (lp.Character and lp.Character:FindFirstChild(name))
			or (lp.Backpack and lp.Backpack:FindFirstChild(name))
		if not tool and name ~= "Taser" then
			giveAnywhere(name)
			for _ = 1, 10 do
				task.wait(0.15)
				tool = (lp.Character and lp.Character:FindFirstChild(name))
					or (lp.Backpack and lp.Backpack:FindFirstChild(name))
				if tool then break end
			end
		end
		if tool then
			modGun(tool)
			toast("Gun Modded", name .. " upgraded", 2, "ok")
		else
			log(name .. " not in inventory", true)
		end
	end)
end

-- ============================================================================
-- COMBAT CORES — MELEE / TP-PUNCH / GUN KILL / TAZE / ARREST
-- ============================================================================
-- Standard in-range melee burst (fires all hits in 1 frame for instant KO)
local function meleeBurst(plr, hits)
	if not meleeEvent then
		meleeEvent = rs:FindFirstChild("meleeEvent")
		if not meleeEvent then return false end
	end
	local hum = charHumanoid(plr)
	if not (hum and hum.Health > 0) then return false end
	local count = hits or CONFIG.meleeBurstHits
	for _ = 1, count do
		if state.detached then return false end
		pcall(function() meleeEvent:FireServer(plr) end)
	end
	state.killCounter = state.killCounter + 1
	return true
end

-- TP-Punch Kill: Snaps within melee range of target, fires 15 meleeEvent hits
-- in one frame (instant 100->0 kill with NO weapon required), and snaps back!
local function tpPunchKill(plr, skipReturn)
	if not meleeEvent then
		meleeEvent = rs:FindFirstChild("meleeEvent")
		if not meleeEvent then return false end
	end
	local myRoot = charRoot()
	local theirRoot = charRoot(plr)
	local hum = charHumanoid(plr)
	if not (myRoot and theirRoot and hum and hum.Health > 0) then return false end
	local ff = plr.Character and plr.Character:FindFirstChildOfClass("ForceField")
	if ff and CONFIG.killAuraIgnoreFF then return false end

	local savedCF = myRoot.CFrame
	myRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	myRoot.CFrame = theirRoot.CFrame * CFrame.new(0, 0, 2.2)
	task.wait(0.06)

	for _ = 1, 15 do
		pcall(function() meleeEvent:FireServer(plr) end)
	end
	state.killCounter = state.killCounter + 1
	task.wait(0.03)

	if not skipReturn and charRoot() then
		pcall(function()
			charRoot().CFrame = savedCF
			charRoot().AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end)
	end
	return true
end

-- Super Punch: Instantly punches everyone within 15 studs 15 times (1-hit KO)
local function triggerSuperPunch()
	local myRoot = charRoot()
	if not myRoot then return end
	local hitCount = 0
	for _, plr in ipairs(plrs:GetPlayers()) do
		if plr ~= lp and plr.Character then
			local theirRoot = charRoot(plr)
			local hum = charHumanoid(plr)
			if theirRoot and hum and hum.Health > 0 then
				if (theirRoot.Position - myRoot.Position).Magnitude <= 16 then
					meleeBurst(plr, 15)
					hitCount = hitCount + 1
				end
			end
		end
	end
	if hitCount > 0 then
		log("super punch KO'd " .. hitCount .. " target(s)")
	end
end

local function gunKill(plr)
	local tool = findGunTool(CONFIG.gunChoice)
		or findGunTool()
		or ensureGunTool(4)
	if not tool then return false end
	pcall(function()
		local gs = gunState(tool)
		if gs and (gs.Damage or 0) < CONFIG.gunDamage then
			modGun(tool)
		end
	end)
	-- Fire 2 bursts of 10 bullets to guarantee instant death even on 100 HP + Riot Shield
	local ok = bulletKill(plr, tool, math.max(CONFIG.gunBulletsPerCall, 10))
	if ok then
		bulletKill(plr, tool, 6)
		state.killCounter = state.killCounter + 1
	end
	return ok
end

local function killTarget(plr)
	if not (plr and plr.Character) then return false end
	local hum = charHumanoid(plr)
	if not (hum and hum.Health > 0) then return false end
	local ff = plr.Character:FindFirstChildOfClass("ForceField")
	if ff and CONFIG.killAuraIgnoreFF then return false end

	local myRoot = charRoot()
	local theirRoot = charRoot(plr)
	local dist = (myRoot and theirRoot) and (theirRoot.Position - myRoot.Position).Magnitude or 999

	local mode = CONFIG.killAuraMode
	if mode == "Fists" then
		if dist <= 15 then
			return meleeBurst(plr, CONFIG.meleeBurstHits)
		else
			return tpPunchKill(plr)
		end
	elseif mode == "Gun" then
		if gunKill(plr) then return true end
		return (dist <= 15) and meleeBurst(plr, CONFIG.meleeBurstHits) or tpPunchKill(plr)
	else
		-- "Smart (Gun + Fists)": Instant melee burst if close, Gun if holding/have gun, else TP-Punch
		if dist <= 14 then
			meleeBurst(plr, CONFIG.meleeBurstHits)
		end
		local tool = findGunTool(CONFIG.gunChoice) or findGunTool()
		if tool then
			return bulletKill(plr, tool, math.max(CONFIG.gunBulletsPerCall, 10))
		elseif dist > 14 then
			return tpPunchKill(plr)
		end
		return true
	end
end

local function killAll(kind)
	task.spawn(function()
		local mode = kind or CONFIG.killAuraMode
		local myRoot = charRoot()
		local savedCF = myRoot and myRoot.CFrame

		local tool = nil
		if mode ~= "Fists" then
			tool = findGunTool(CONFIG.gunChoice) or findGunTool() or ensureGunTool(4)
		end

		local killed = 0
		for _, plr in ipairs(plrs:GetPlayers()) do
			if state.detached then return end
			if plr ~= lp and plr.Character and selTarget(plr, "auraTargets") then
				local hum = charHumanoid(plr)
				local ff = plr.Character:FindFirstChildOfClass("ForceField")
				if hum and hum.Health > 0 and not (ff and CONFIG.killAuraIgnoreFF) then
					if tool and mode ~= "Fists" then
						bulletKill(plr, tool, 12)
						killed = killed + 1
						state.killCounter = state.killCounter + 1
						task.wait(0.05)
					else
						tpPunchKill(plr, true)
						killed = killed + 1
					end
				end
			end
		end

		if savedCF and charRoot() then
			pcall(function()
				charRoot().CFrame = savedCF
				charRoot().AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end)
		end
		log("kill-all finished (" .. killed .. " targets attacked)")
		toast("Kill All", "Attacked " .. killed .. " player(s)", 2, "ok")
	end)
end

-- ============================================================================
-- TAZE & ARREST ENGINE
-- ============================================================================
local function getTaser()
	return (lp.Character and lp.Character:FindFirstChild("Taser"))
		or (lp.Backpack and lp.Backpack:FindFirstChild("Taser"))
end

local function tazeTarget(plr, taserTool)
	if not shootingEvent then return false end
	taserTool = taserTool or getTaser()
	if not taserTool then return false end
	local part = charTorso(plr) or charHead(plr)
	if not part then return false end
	equipToolFast(taserTool)
	local bullets = buildBullets(part, 1)
	local ok = vsafe(function()
		shootingEvent:FireServer(bullets, taserTool)
	end)
	reloadToolServer(taserTool)
	return ok
end

local function tazeAll()
	task.spawn(function()
		local taser = getTaser()
		if not taser then
			toast("No Taser", "Become a Guard first to receive a Taser", 2.5, "err")
			log("Taser missing — switch to Guard team first", true)
			return
		end
		local count = 0
		for _, plr in ipairs(plrs:GetPlayers()) do
			if state.detached then return end
			if plr ~= lp and not isGuard(plr) and charHumanoid(plr) and charHumanoid(plr).Health > 0 then
				tazeTarget(plr, taser)
				count = count + 1
				task.wait(0.06)
			end
		end
		log("tazed " .. count .. " player(s)")
		toast("Taze All", "Shocked " .. count .. " player(s)", 2, "ok")
	end)
end

local function getArrestRemote()
	return getRemote("arrest") or getRemote("Arrest")
end

-- Prison Life's server arrest RemoteFunction checks distance to Torso
local function arrestOnce(target)
	local remote = getArrestRemote()
	if not remote then return false end
	local theirTorso = charTorso(target)
	if not theirTorso then return false end
	if CONFIG.arrestSnap then
		local myRoot = charRoot()
		if myRoot then
			myRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			myRoot.CFrame = theirTorso.CFrame * CFrame.new(0, 0, 1.5)
		end
	end
	vsafe(function() remote:InvokeServer(theirTorso) end)
	return true
end

local function arrestTarget(target, skipReturn)
	if not target or target == lp then return false end
	local myRoot = charRoot()
	local savedCF = myRoot and myRoot.CFrame
	local cuffed = false
	for _ = 1, 10 do
		if state.detached then break end
		if not charHumanoid(target) or charHumanoid(target).Health <= 0 then break end
		arrestOnce(target)
		task.wait(0.07)
		if isCuffed(target) then
			cuffed = true
			break
		end
	end
	if not skipReturn and savedCF and charRoot() then
		pcall(function()
			charRoot().CFrame = savedCF
			charRoot().AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end)
	end
	return cuffed
end

local function arrestAll()
	task.spawn(function()
		local myRoot = charRoot()
		local savedCF = myRoot and myRoot.CFrame
		local n = 0
		for _, plr in ipairs(arrestables()) do
			if state.detached then return end
			if arrestTarget(plr, true) then n = n + 1 end
			task.wait(0.15)
		end
		if savedCF and charRoot() then
			pcall(function()
				charRoot().CFrame = savedCF
				charRoot().AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end)
		end
		state.arrestCount = state.arrestCount + n
		log("arrest-all cuffed " .. n .. " player(s)")
		toast("Arrest All", "Cuffed " .. n .. " player(s)", 2, "ok")
	end)
end

-- ============================================================================
-- VELOCITY FLING ENGINE (SKIDFLING / PHYSICS LAUNCHER)
-- ============================================================================
local function flingTarget(target, duration)
	if state.flinging then return end
	local myCh = lp.Character
	local myRoot = charRoot()
	local myHum = charHumanoid()
	local theirRoot = charRoot(target)
	if not (myCh and myRoot and myHum and theirRoot) then
		toast("Fling Failed", "Target has no root part", 2, "err")
		return
	end

	state.flinging = true
	local savedCF = myRoot.CFrame
	local oldFall = workspace.FallenPartsDestroyHeight
	pcall(function() workspace.FallenPartsDestroyHeight = 0 / 0 end)

	local bv = Instance.new("BodyVelocity")
	bv.Name = "RiotHub_FlingBV"
	bv.Velocity = Vector3.new(9e7, 9e7, 9e7)
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Parent = myRoot

	myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	local startT = tick()
	local maxDur = duration or 1.6
	local angle = 0

	while tick() - startT < maxDur and not state.detached do
		local tRoot = charRoot(target)
		local tHum = charHumanoid(target)
		if not tRoot or not tHum or tHum.Health <= 0 then break end
		-- Stop early once target is launched away at high speed
		if tRoot.Velocity.Magnitude > 450 then break end

		angle = angle + 100
		local pred = tRoot.Velocity * 0.12
		myRoot.CFrame = CFrame.new(tRoot.Position + pred) * CFrame.Angles(math.rad(angle), math.rad(angle), 0)
		myRoot.Velocity = Vector3.new(9e7, 9e7, 9e7)
		myRoot.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
		runSvc.Heartbeat:Wait()
	end

	pcall(function() bv:Destroy() end)
	pcall(function() myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
	pcall(function() workspace.FallenPartsDestroyHeight = oldFall end)

	-- Stabilize local character back at original position
	if charRoot() and savedCF then
		for _ = 1, 8 do
			local r = charRoot()
			if not r then break end
			r.CFrame = savedCF
			r.Velocity = Vector3.new(0, 0, 0)
			r.RotVelocity = Vector3.new(0, 0, 0)
			r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			r.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			runSvc.Heartbeat:Wait()
		end
	end

	state.flinging = false
	log("flung " .. tostring(target.Name))
end

local function flingAll()
	task.spawn(function()
		for _, plr in ipairs(plrs:GetPlayers()) do
			if state.detached then return end
			if plr ~= lp and charRoot(plr) and charHumanoid(plr) and charHumanoid(plr).Health > 0 then
				local ff = plr.Character and plr.Character:FindFirstChildOfClass("ForceField")
				if not ff then
					flingTarget(plr, 1.1)
					task.wait(0.15)
				end
			end
		end
		toast("Fling All", "Finished flinging server", 2, "ok")
	end)
end

-- ============================================================================
-- VEHICLE SPAWNER & CAR MODS
-- ============================================================================
local function getSeatedVehicle()
	local hum = charHumanoid()
	local seat = hum and hum.SeatPart
	if seat and seat:IsA("VehicleSeat") then
		return seat:FindFirstAncestorOfClass("Model"), seat
	end
	return nil, nil
end

local function spawnCarHere(preferredType)
	task.spawn(function()
		local myRoot = charRoot()
		if not myRoot then return end
		local savedCF = myRoot.CFrame

		local buttons = prisonTable() and prisonTable():FindFirstChild("buttons")
		if not buttons then
			log("Prison_ITEMS.buttons not found", true)
			return
		end

		local chosenBtn = nil
		for _, ch in ipairs(buttons:GetChildren()) do
			if ch.Name == "Car Spawner" then
				local part = ch:FindFirstChild("Car Spawner") or ch:FindFirstChildWhichIsA("BasePart")
				if part then
					chosenBtn = part
					if preferredType == "Police" and (part.Position - Vector3.new(616, 98, 2490)).Magnitude < 250 then
						break
					elseif preferredType == "Sedan" and (part.Position - Vector3.new(-910, 95, 2060)).Magnitude < 350 then
						break
					end
				end
			end
		end

		if not chosenBtn then
			toast("Car Spawner", "No Car Spawner button found on map", 2, "err")
			return
		end

		local carContainer = workspace:FindFirstChild("CarContainer")
		local existing = {}
		if carContainer then
			for _, c in ipairs(carContainer:GetChildren()) do
				existing[c] = true
			end
		end

		invokeItemHandlerSmart(chosenBtn, "Car Spawner")
		task.wait(0.35)

		local newCar = nil
		if carContainer then
			for _, c in ipairs(carContainer:GetChildren()) do
				if not existing[c] then
					newCar = c
					break
				end
			end
			if not newCar then
				local children = carContainer:GetChildren()
				newCar = children[#children]
			end
		end

		if newCar then
			pcall(function()
				if charRoot() then charRoot().CFrame = savedCF end
				newCar:PivotTo(savedCF * CFrame.new(0, 3.5, 0))
				local seat = newCar:FindFirstChildWhichIsA("VehicleSeat", true)
				if seat and charHumanoid() then
					seat:Sit(charHumanoid())
				end
			end)
			toast("Car Spawned", "Vehicle brought to your position!", 2, "ok")
			log("spawned & brought vehicle: " .. tostring(newCar.Name))
		else
			toast("Car Triggered", "Car spawned at pad", 2, "ok")
		end
	end)
end

local function modCurrentCar()
	local car, seat = getSeatedVehicle()
	if not seat then
		toast("Sit in a Car", "Sit in a vehicle driver seat first", 2, "err")
		return
	end
	pcall(function()
		seat.MaxSpeed = 60 * CONFIG.carSpeedMult
		seat.Torque = 40000 * CONFIG.carSpeedMult
		seat.TurnSpeed = 4
	end)
	toast("Car Modded", string.format("Speed %.1fx applied!", CONFIG.carSpeedMult), 2, "ok")
end

-- ============================================================================
-- WORLD — GATE / REVERSIBLE DOORS & FENCES / ANTI-CRIM PAD
-- ============================================================================
local function openGate()
	task.spawn(function()
		local gateBtn = getItemIn("buttons", "Prison Gate", "Prison Gate")
		if not gateBtn then
			log("Prison Gate button not found", true)
			return
		end
		local ok = invokeItemHandlerSmart(gateBtn, "Prison Gate")
		if ok then
			toast("Gate Opened", "Prison main gate triggered", 1.8, "ok")
		end
	end)
end

local function ensureHiddenWorld()
	if state.hiddenWorld and state.hiddenWorld.Parent then
		return state.hiddenWorld
	end
	local f = rs:FindFirstChild("RiotHub_HiddenWorld")
	if not f then
		f = Instance.new("Folder")
		f.Name = "RiotHub_HiddenWorld"
		f.Parent = rs
	end
	state.hiddenWorld = f
	return f
end

local function setDoorsRemoved(remove)
	local store = ensureHiddenWorld()
	if remove then
		local count = 0
		for _, name in ipairs({ "Doors", "Prison_Fences", "Cellblock_Doors" }) do
			local obj = workspace:FindFirstChild(name)
			if obj then
				pcall(function() obj.Parent = store end)
				count = count + 1
			end
		end
		-- Also strip cell bars if present inside Prison_Cellblock
		local cb = workspace:FindFirstChild("Prison_Cellblock")
		if cb and cb:FindFirstChild("doors") then
			pcall(function() cb.doors.Parent = store end)
			count = count + 1
		end
		log("stashed " .. count .. " door/fence folder(s) (reversible)")
		toast("Doors & Fences", "Removed! Toggle OFF anytime to restore", 2, "ok")
	else
		local count = 0
		for _, obj in ipairs(store:GetChildren()) do
			pcall(function()
				if obj.Name == "doors" and workspace:FindFirstChild("Prison_Cellblock") then
					obj.Parent = workspace.Prison_Cellblock
				else
					obj.Parent = workspace
				end
				count = count + 1
			end)
		end
		log("restored " .. count .. " door/fence folder(s)")
		toast("Doors Restored", "All doors and fences returned", 2, "ok")
	end
end

local savedTouchInterests = {}
local function setAntiCrimPad(on)
	pcall(function()
		local crimSpawn = workspace:FindFirstChild("Criminals Spawn")
		if not crimSpawn then return end
		if on then
			for _, d in ipairs(crimSpawn:GetDescendants()) do
				if d:IsA("TouchTransmitter") then
					table.insert(savedTouchInterests, { obj = d, parent = d.Parent })
					d.Parent = nil
				end
			end
			toast("Anti-Crim Pad", "Guards can now enter Criminal Base safely!", 2, "ok")
		else
			for _, item in ipairs(savedTouchInterests) do
				if item.obj and item.parent then
					pcall(function() item.obj.Parent = item.parent end)
				end
			end
			savedTouchInterests = {}
		end
	end)
end

-- ============================================================================
-- TEAM SWITCHING & INSTANT REFRESH (RE)
-- ============================================================================
local function switchTeam(kind, preservePos)
	task.spawn(function()
		local myRoot = charRoot()
		local savedCF = preservePos and myRoot and myRoot.CFrame
		local teamR = getRemote("TeamEvent")
		local loadChar = getRemote("loadchar")

		if kind == "Inmate" then
			if teamR then vsafe(function() teamR:FireServer("Bright orange") end) end
			task.wait(0.1)
			if loadChar then vsafe(function() loadChar:InvokeServer(lp.Name) end) end
		elseif kind == "Guard" then
			if teamR then vsafe(function() teamR:FireServer("Bright blue") end) end
			task.wait(0.1)
			if loadChar then vsafe(function() loadChar:InvokeServer(lp.Name) end) end
		elseif kind == "Neutral" then
			if teamR then vsafe(function() teamR:FireServer("Medium stone grey") end) end
			if loadChar then vsafe(function() loadChar:InvokeServer(lp.Name, "Medium stone grey") end) end
		elseif kind == "Criminal" then
			local crimSpawn = workspace:FindFirstChild("Criminals Spawn")
			local pad = crimSpawn and (crimSpawn:FindFirstChildWhichIsA("SpawnLocation", true)
				or crimSpawn:FindFirstChildWhichIsA("BasePart", true))
			local padCF = pad and pad.CFrame or CFrame.new(-920.5, 95.3, 2138.3)
			if myRoot then
				myRoot.CFrame = padCF + Vector3.new(0, 2.5, 0)
				task.wait(0.35)
			end
		end

		if savedCF then
			task.wait(0.35)
			local newRoot = charRoot()
			if newRoot then
				pcall(function() newRoot.CFrame = savedCF end)
			end
		end
		log("team -> " .. tostring(kind))
		toast("Team Switched", "Now on " .. tostring(kind), 2, "ok")
	end)
end

local function refreshCharacterInPlace()
	task.spawn(function()
		local myRoot = charRoot()
		local savedCF = myRoot and myRoot.CFrame
		local savedCam = currentCam() and currentCam().CFrame
		local loadChar = getRemote("loadchar")
		if not loadChar then
			log("loadchar remote unavailable", true)
			return
		end
		vsafe(function() loadChar:InvokeServer(lp.Name) end)
		local ch = lp.CharacterAdded:Wait()
		local newRoot = ch:WaitForChild("HumanoidRootPart", 5)
		task.wait(0.08)
		if newRoot and savedCF then
			newRoot.CFrame = savedCF
			if savedCam and currentCam() then
				currentCam().CFrame = savedCam
			end
		end
		toast("Character Refreshed", "Respawned at your exact spot", 1.8, "ok")
	end)
end

-- ============================================================================
-- MOVEMENT, ANTI-TAZE, HITBOX EXPANDER & ORBIT ENGINE
-- ============================================================================
local orbitAngle = 0

local function applyMovementFrame(dt)
	local ch = lp.Character
	if not ch then return end
	local rootPart = charRoot()
	local hum = charHumanoid()
	if not (rootPart and hum) then return end

	-- Save non-cell position periodically for Anti-Arrest return
	if not isCuffed(lp) and hum.Health > 0 then
		state.preArrestCF = rootPart.CFrame
	end

	-- Anti-Arrest: if handcuffedGui appears on Head, instant loadchar & snap back!
	if CONFIG.antiArrest and isCuffed(lp) then
		local loadChar = getRemote("loadchar")
		local returnCF = state.preArrestCF
		if loadChar then
			task.spawn(function()
				vsafe(function() loadChar:InvokeServer(lp.Name) end)
				task.wait(0.35)
				if returnCF and charRoot() then
					pcall(function() charRoot().CFrame = returnCF end)
				end
				toast("Anti-Arrest", "Broke handcuffs & restored position!", 2, "ok")
			end)
		end
	end

	-- Anti-Taze / Anti-Stun: restore WalkSpeed, PlatformStand, and Backpack GUI
	if CONFIG.noStayStunned then
		if hum.PlatformStand then hum.PlatformStand = false end
		if hum.Sit and not hum.SeatPart then hum.Sit = false end
		if hum.WalkSpeed < 16 then
			hum.WalkSpeed = math.max(CONFIG.walkSpeed, 16)
			pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
		end
	end

	-- Enforce chosen WalkSpeed & JumpPower
	if CONFIG.walkSpeed ~= 16 and hum.WalkSpeed ~= CONFIG.walkSpeed then
		hum.WalkSpeed = CONFIG.walkSpeed
	end
	if CONFIG.jumpPower ~= 50 then
		hum.UseJumpPower = true
		if hum.JumpPower ~= CONFIG.jumpPower then
			hum.JumpPower = CONFIG.jumpPower
		end
	end

	-- TP-Walk
	if state.toggles.tpWalkOn and hum.MoveDirection.Magnitude > 0.2 then
		rootPart.CFrame = rootPart.CFrame + hum.MoveDirection * (CONFIG.tpWalkPower * dt * 22)
	end

	-- Spinbot
	if state.toggles.spinOn and not state.flinging then
		rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(CONFIG.spinSpeed * 12) * dt, 0)
	end

	-- Orbit Selected Target
	if state.toggles.orbitTargetOn and not state.flinging then
		local t = getActiveTarget()
		local tRoot = t and charRoot(t)
		if tRoot then
			orbitAngle = orbitAngle + dt * 8
			local offset = Vector3.new(math.cos(orbitAngle) * 6, 0.5, math.sin(orbitAngle) * 6)
			rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			rootPart.CFrame = CFrame.lookAt(tRoot.Position + offset, tRoot.Position)
		end
	end

	-- Character Flight & Car Flight
	local carModel, carSeat = getSeatedVehicle()
	if state.toggles.flyOn or (state.toggles.carFlyOn and carSeat) then
		local camera = currentCam()
		if camera then
			local moveDir = Vector3.new(0, 0, 0)
			if uis:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camera.CFrame.LookVector end
			if uis:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camera.CFrame.LookVector end
			if uis:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camera.CFrame.RightVector end
			if uis:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camera.CFrame.RightVector end
			local tm = state.touchMove
			moveDir = moveDir + camera.CFrame.LookVector * (tm.fwd - tm.back)
			local lift = tm.up - tm.down
			if uis:IsKeyDown(Enum.KeyCode.E) or uis:IsKeyDown(Enum.KeyCode.Space) then lift = lift + 1 end
			if uis:IsKeyDown(Enum.KeyCode.Q) or uis:IsKeyDown(Enum.KeyCode.LeftControl) then lift = lift - 1 end

			local spd = (carSeat and CONFIG.carFlySpeed or CONFIG.flySpeed) * 28
			local delta = (moveDir * spd * dt) + Vector3.new(0, lift * spd * 0.75 * dt, 0)

			if carModel and state.toggles.carFlyOn then
				pcall(function()
					carSeat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					carModel:PivotTo(carModel:GetPivot() + delta)
				end)
			else
				rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				rootPart.CFrame = rootPart.CFrame + delta
			end
		end
	end

	-- Car Noclip
	if state.toggles.carNoclipOn and carModel then
		for _, p in ipairs(carModel:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide and p ~= carSeat then
				state.carNoclipSaved[p] = true
				p.CanCollide = false
			end
		end
	elseif next(state.carNoclipSaved) then
		for p in pairs(state.carNoclipSaved) do
			if p and p.Parent then pcall(function() p.CanCollide = true end) end
		end
		state.carNoclipSaved = {}
	end

	-- Character Noclip
	if state.toggles.noclipOn or state.flinging then
		for _, p in ipairs(ch:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				state.noclipSaved[p] = true
				p.CanCollide = false
			end
		end
	elseif next(state.noclipSaved) then
		for p in pairs(state.noclipSaved) do
			if p and p.Parent then pcall(function() p.CanCollide = true end) end
		end
		state.noclipSaved = {}
	end

	-- Hitbox Expander
	if CONFIG.hitboxEnabled then
		for _, plr in ipairs(plrs:GetPlayers()) do
			if plr ~= lp and plr.Character and selTarget(plr, "auraTargets") then
				local hum2 = charHumanoid(plr)
				local part = plr.Character:FindFirstChild(CONFIG.hitboxPart)
					or plr.Character:FindFirstChild("Head")
				if part and part:IsA("BasePart") and hum2 and hum2.Health > 0 then
					if not state.hitboxSaved[part] then
						state.hitboxSaved[part] = {
							Size = part.Size,
							Transparency = part.Transparency,
							CanCollide = part.CanCollide,
						}
					end
					part.Size = Vector3.new(CONFIG.hitboxSize, CONFIG.hitboxSize, CONFIG.hitboxSize)
					part.Transparency = CONFIG.hitboxTransparency
					part.CanCollide = false
				end
			end
		end
	elseif next(state.hitboxSaved) then
		for part, orig in pairs(state.hitboxSaved) do
			if part and part.Parent then
				pcall(function()
					part.Size = orig.Size
					part.Transparency = orig.Transparency
					part.CanCollide = orig.CanCollide
				end)
			end
		end
		state.hitboxSaved = {}
	end
end
connect(runSvc.Heartbeat, applyMovementFrame)

connect(uis.JumpRequest, function()
	if not state.toggles.infJump then return end
	local hum = charHumanoid()
	if hum then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

-- ============================================================================
-- TELEPORTS
-- ============================================================================
local TELEPORTS = {
	{ name = "Prison Yard",        fn = function() return CFrame.new(779.87, 98.00, 2458.93) end },
	{ name = "Nexus / Hallway",    fn = function() return CFrame.new(879.00, 99.99, 2373.38) end },
	{ name = "Guard Armory",       fn = function() return CFrame.new(836.13, 99.99, 2270.45) end },
	{ name = "Criminal Base",      fn = function() return CFrame.new(-943.46, 94.13, 2063.63) end },
	{ name = "Cafeteria",          fn = function() return CFrame.new(918.99, 99.99, 2291.60) end },
	{ name = "Cellblock",          fn = function() return CFrame.new(918.97, 99.99, 2440.78) end },
	{ name = "Gate Control Room",  fn = function() return CFrame.new(504.53, 102.04, 2242.40) end },
	{ name = "Prison Roof",        fn = function() return CFrame.new(827.42, 118.99, 2329.62) end },
	{ name = "Guard Tower",        fn = function() return CFrame.new(823.25, 125.04, 2588.50) end },
	{ name = "Sewer Escape",       fn = function() return CFrame.new(917.12, 78.70, 2426.35) end },
}

local function teleportTo(cframe)
	local myRoot = charRoot()
	if not myRoot or not cframe then return end
	myRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	myRoot.CFrame = cframe + Vector3.new(0, 2.5, 0)
	log("teleported")
end

-- ============================================================================
-- AIMBOT & SILENT AIM
-- ============================================================================
local fovRing
local function buildFovRing()
	fovRing = Instance.new("ScreenGui")
	fovRing.Name = "RiotHubFOVRing"
	fovRing.IgnoreGuiInset = true
	fovRing.ResetOnSpawn = false
	fovRing.Parent = lp:WaitForChild("PlayerGui")

	local ringHolder = Instance.new("Frame")
	ringHolder.Name = "Ring"
	ringHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	ringHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
	ringHolder.BackgroundTransparency = 1
	ringHolder.Size = UDim2.fromOffset(CONFIG.aimbotFov * 2, CONFIG.aimbotFov * 2)
	ringHolder.Visible = false
	ringHolder.Parent = fovRing

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.new(0.5, 0, 0.5, 0)
	circle.Size = UDim2.new(1, 0, 1, 0)
	circle.BackgroundColor3 = Color3.fromRGB(255, 73, 90)
	circle.BackgroundTransparency = 0.90
	circle.BorderSizePixel = 0
	circle.Parent = ringHolder
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(1, 0)
	uc.Parent = circle
	local us = Instance.new("UIStroke")
	us.Color = Color3.fromRGB(255, 73, 90)
	us.Transparency = 0.35
	us.Thickness = 1.5
	us.Parent = circle
end

local function setupAimbot()
	connect(runSvc.RenderStepped, function()
		if state.detached then return end
		local camera = currentCam()
		if not camera then return end
		if fovRing then
			local ring = fovRing:FindFirstChild("Ring")
			if ring then
				local show = CONFIG.showAimFov and (state.toggles.aimOn or state.toggles.silentOn)
				ring.Visible = show
				if show then
					local diameter = math.clamp(CONFIG.aimbotFov * 2, 40, 900)
					ring.Size = UDim2.fromOffset(diameter, diameter)
				end
			end
		end
		if not state.toggles.aimOn then return end
		local best, bestAng
		for _, plr in ipairs(plrs:GetPlayers()) do
			if plr ~= lp and plr.Character and plr.Character:FindFirstChild("Head") then
				local hum = charHumanoid(plr)
				if hum and hum.Health > 0 and selTarget(plr, "aimbotTargets") then
					local head = plr.Character.Head
					local to = head.Position - camera.CFrame.Position
					if to.Magnitude > 2 then
						local ang = math.deg(math.acos(math.clamp(
							camera.CFrame.LookVector:Dot(to.Unit), -1, 1)))
						if ang <= CONFIG.aimbotFov then
							if not bestAng or ang < bestAng then best, bestAng = head, ang end
						end
					end
				end
			end
		end
		if best then
			local goal = CFrame.lookAt(camera.CFrame.Position, best.Position)
			local smooth = math.clamp(1 - (CONFIG.aimbotSmooth / 100), 0.06, 1)
			camera.CFrame = camera.CFrame:Lerp(goal, smooth)
		end
	end)
end

local hookInstalled = false
local function setupSilentAim()
	task.spawn(function()
		local hookFn = hookmetamethod
		if not hookFn or hookInstalled then return end
		hookInstalled = true
		local oldNamecall
		oldNamecall = hookFn(game, "__namecall", function(self, ...)
			local method = getnamecallmethod and getnamecallmethod() or ""
			local args = packArgs(...)
			if self == shootingEvent and (method == "FireServer" or method == "")
				and state.toggles.silentOn and type(args[1]) == "table" then
				pcall(function()
					local camera = currentCam()
					if not camera then return end
					local best, bestAng
					for _, plr in ipairs(plrs:GetPlayers()) do
						if plr ~= lp and plr.Character and plr.Character:FindFirstChild("Head") then
							local hum = charHumanoid(plr)
							if hum and hum.Health > 0 and selTarget(plr, "aimbotTargets") then
								local head = plr.Character.Head
								local to = head.Position - camera.CFrame.Position
								if to.Magnitude > 2 then
									local ang = math.deg(math.acos(math.clamp(
										camera.CFrame.LookVector:Dot(to.Unit), -1, 1)))
									if ang <= CONFIG.silentFov then
										if not bestAng or ang < bestAng then best, bestAng = head, ang end
									end
								end
							end
						end
					end
					if best then
						if CONFIG.silentWallCheck then
							local params = RaycastParams.new()
							params.FilterType = Enum.RaycastFilterType.Exclude
							params.FilterDescendantsInstances = { lp.Character, best.Parent }
							local hit = workspace:Raycast(
								camera.CFrame.Position,
								best.Position - camera.CFrame.Position, params)
							if hit and hit.Instance and not hit.Instance:IsDescendantOf(best.Parent) then
								return
							end
						end
						if math.random(1, 100) <= CONFIG.silentHitChance then
							for _, b in ipairs(args[1]) do
								local aimPart = best
								if CONFIG.silentRandomPart and math.random() < 0.4 then
									aimPart = best.Parent:FindFirstChild("Torso") or best
								end
								b["Cframe"]  = aimPart.CFrame
								b["Hit"]     = aimPart
								b["HitPart"] = aimPart
							end
						end
					end
				end)
			end
			return oldNamecall(self, spread(args))
		end)
		log("silent aim hooked onto ShootEvent")
	end)
end

-- ============================================================================
-- TRIGGERBOT
-- ============================================================================
local function triggerFire()
	pcall(function()
		if mouse1press then
			mouse1press()
			task.wait(0.01)
			if mouse1release then mouse1release() end
		else
			local tool = lp.Character and lp.Character:FindFirstChildWhichIsA("Tool")
			if tool then
				tool:Activate()
				task.delay(0.03, function() pcall(function() tool:Deactivate() end) end)
			end
		end
	end)
end

local function setupTriggerBot()
	connect(runSvc.RenderStepped, function()
		if state.detached or not state.toggles.triggerOn then return end
		local t = mouse.Target
		if not (t and t.Parent) then return end
		local hum = t.Parent:FindFirstChildOfClass("Humanoid")
		if not (hum and hum.Health > 0) then return end
		local plr = plrs:GetPlayerFromCharacter(t.Parent)
		if not plr or plr == lp then return end
		if not selTarget(plr, "triggerTargets") then return end
		local tool = lp.Character and lp.Character:FindFirstChildWhichIsA("Tool")
		if tool and tool:FindFirstChild("GunStates") then triggerFire() end
	end)
end

-- ============================================================================
-- VISUALS — ESP, CHAMS, TRACERS, FULLBRIGHT, FPS BOOST
-- ============================================================================
local espContainer
local function ensureEspContainer()
	if espContainer and espContainer.Parent then return espContainer end
	espContainer = Instance.new("Folder")
	espContainer.Name = "RiotHubEspOverlays"
	espContainer.Parent = lp:WaitForChild("PlayerGui", 10)
		or (gethui and gethui())
		or game:FindFirstChildOfClass("CoreGui")
	return espContainer
end

local function teamTint(plr)
	return isGuard(plr) and Color3.fromRGB(100, 165, 255)
		or isInmate(plr) and Color3.fromRGB(255, 160, 65)
		or isCrim(plr) and Color3.fromRGB(255, 80, 85)
		or Color3.fromRGB(220, 220, 220)
end

local function applyChams(plr)
	pcall(function()
		local ch = plr.Character
		if not ch then return end
		local hil = ch:FindFirstChild("RiotHub_Cham")
		if not state.toggles.chamsOn then
			if hil then hil:Destroy() end
			return
		end
		if not hil then
			hil = Instance.new("Highlight")
			hil.Name = "RiotHub_Cham"
			hil.Parent = ch
		end
		hil.FillColor = teamTint(plr)
		hil.FillTransparency = 0.55
		hil.DepthMode = CONFIG.chamsThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop
			or Enum.HighlightDepthMode.Occluded
		hil.OutlineColor = Color3.new(0, 0, 0)
		hil.OutlineTransparency = 0.2
	end)
end

local function clearChams(plr)
	pcall(function()
		local ch = plr and plr.Character
		if ch then
			local hil = ch:FindFirstChild("RiotHub_Cham")
			if hil then hil:Destroy() end
		end
	end)
end

local function buildEspUnit(plr)
	local unit = { conns = {} }
	local bb = Instance.new("BillboardGui")
	bb.Name = "RiotHub_ESP"
	bb.Size = UDim2.new(7, 0, 2.2, 0)
	bb.StudsOffset = Vector3.new(0, 1.8, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2500
	bb.Adornee = plr.Character and plr.Character:FindFirstChild("Head")
	bb.Parent = ensureEspContainer()

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.25
	nameLabel.Parent = bb

	local distLabel = Instance.new("TextLabel")
	distLabel.Name = "DistLabel"
	distLabel.Size = UDim2.new(1, 0, 0.5, 0)
	distLabel.Position = UDim2.new(0, 0, 0.5, 0)
	distLabel.BackgroundTransparency = 1
	distLabel.Font = Enum.Font.Gotham
	distLabel.TextSize = 11
	distLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	distLabel.TextStrokeTransparency = 0.4
	distLabel.Parent = bb

	unit.billboard = bb
	unit.nameLabel = nameLabel
	unit.distLabel = distLabel

	table.insert(unit.conns, connect(plr.CharacterAdded, function()
		task.wait(0.3)
		bb.Adornee = plr.Character and plr.Character:FindFirstChild("Head")
		applyChams(plr)
	end))
	applyChams(plr)
	return unit
end

local function destroyEspUnit(plr)
	local unit = state.espUnits[plr]
	if not unit then return end
	for _, c in ipairs(unit.conns) do pcall(function() c:Disconnect() end) end
	if unit.billboard then unit.billboard:Destroy() end
	state.espUnits[plr] = nil
end

local function refreshEsp()
	for _, plr in ipairs(plrs:GetPlayers()) do
		if plr ~= lp then
			if state.toggles.espOn then
				if not state.espUnits[plr] then state.espUnits[plr] = buildEspUnit(plr) end
			else
				destroyEspUnit(plr)
			end
			applyChams(plr)
		end
	end
	for plr, _ in pairs(state.espUnits) do
		if not plr.Parent then destroyEspUnit(plr) end
	end
end

local drawingOk = pcall(function() return Drawing end) and Drawing ~= nil
local function destroyTracer(plr)
	local line = state.tracers[plr]
	if line then
		pcall(function() line:Remove() end)
		state.tracers[plr] = nil
	end
end

local function setupEspFrame()
	connect(runSvc.RenderStepped, function()
		if state.detached then return end
		local camera = currentCam()
		if not camera then return end
		for plr, unit in pairs(state.espUnits) do
			local ch = plr.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local head = ch and ch:FindFirstChild("Head")
			local visible = (state.toggles.espOn == true) and (head ~= nil) and (hum ~= nil)
			if visible and hum.Health <= 0 then visible = false end
			if visible and CONFIG.espVisibleOnly then
				local ok, vis = pcall(function()
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { lp.Character, ch }
					local hit = workspace:Raycast(camera.CFrame.Position,
						head.Position - camera.CFrame.Position, params)
					if hit and hit.Instance then
						return hit.Instance:IsDescendantOf(ch)
					end
					return true
				end)
				visible = (not ok) and true or vis
			end
			unit.billboard.Enabled = visible
			if visible then
				unit.billboard.Adornee = head
				local dist = (head.Position - camera.CFrame.Position).Magnitude
				local hpTxt = ""
				if CONFIG.espHealthBar then
					hpTxt = string.format(" [%d%%]",
						math.floor(hum.Health / math.max(hum.MaxHealth, 1) * 100 + 0.5))
				end
				local tool = ch:FindFirstChildWhichIsA("Tool")
				local toolTxt = tool and (" · " .. tool.Name) or ""
				unit.nameLabel.Text = (CONFIG.espNames and (plr.Name .. hpTxt) or "")
				unit.distLabel.Text = (CONFIG.espDistance and string.format("%dm%s", dist, toolTxt) or toolTxt)
				unit.nameLabel.TextColor3 = CONFIG.espTeamColor and teamTint(plr) or Color3.new(1, 1, 1)
			end
			if drawingOk and CONFIG.espTracers and visible then
				pcall(function()
					local vp = camera:WorldToViewportPoint(head.Position)
					if vp.Z <= 0 then
						destroyTracer(plr)
						return
					end
					local line = state.tracers[plr]
					if not line then
						line = Drawing.new("Line")
						line.Thickness = 1.4
						line.Transparency = 0.75
						state.tracers[plr] = line
					end
					line.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
					line.To = Vector2.new(vp.X, vp.Y)
					line.Color = teamTint(plr)
					line.Visible = true
				end)
			else
				destroyTracer(plr)
			end
		end
	end)
end

local savedLighting = nil
local function setFullbright(on)
	pcall(function()
		if on then
			if not savedLighting then
				savedLighting = {
					Ambient = lighting.Ambient, OutdoorAmbient = lighting.OutdoorAmbient,
					Brightness = lighting.Brightness, FogEnd = lighting.FogEnd,
					ClockTime = lighting.ClockTime, GlobalShadows = lighting.GlobalShadows,
				}
			end
			lighting.Ambient = Color3.new(1, 1, 1)
			lighting.OutdoorAmbient = Color3.new(1, 1, 1)
			lighting.Brightness = 2.8
			lighting.FogEnd = 1e10
			lighting.ClockTime = 14
			lighting.GlobalShadows = false
		elseif savedLighting then
			lighting.Ambient = savedLighting.Ambient
			lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
			lighting.Brightness = savedLighting.Brightness
			lighting.FogEnd = savedLighting.FogEnd
			lighting.ClockTime = savedLighting.ClockTime
			lighting.GlobalShadows = savedLighting.GlobalShadows
		end
	end)
end

local fpsBoostConn
local function setFpsBoost(on)
	if fpsBoostConn then
		fpsBoostConn:Disconnect()
		fpsBoostConn = nil
	end
	if not on then return end
	pcall(function()
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke")
				or d:IsA("Fire") or d:IsA("Beam") then
				pcall(function() d.Enabled = false end)
			end
		end
		fpsBoostConn = connect(workspace.DescendantAdded, function(d)
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke")
				or d:IsA("Fire") or d:IsA("Beam") then
				pcall(function() d.Enabled = false end)
			end
		end)
	end)
end

-- ============================================================================
-- UI ENGINE v4 — RESPONSIVE, ANIMATED, MOBILE + PC READY
-- ============================================================================
if CONFIG.reduceAnim then state.uiAnim = 0 end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RiotHub_GUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local uiParent = lp:WaitForChild("PlayerGui", 10)
if not uiParent and gethui then pcall(function() uiParent = gethui() end) end
if not uiParent then uiParent = game:FindFirstChildOfClass("CoreGui") end
screenGui.Parent = uiParent

local THEME = {
	bg        = Color3.fromRGB(12, 13, 18),
	surface   = Color3.fromRGB(18, 20, 27),
	card      = Color3.fromRGB(26, 29, 38),
	cardUp    = Color3.fromRGB(36, 40, 52),
	stroke    = Color3.fromRGB(48, 52, 66),
	text      = Color3.fromRGB(238, 240, 246),
	textDim   = Color3.fromRGB(142, 148, 164),
	accent    = Color3.fromRGB(255, 68, 92),
	accentDk  = Color3.fromRGB(130, 34, 48),
	green     = Color3.fromRGB(72, 219, 142),
	amber     = Color3.fromRGB(255, 188, 76),
}

local function make(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	if parent then obj.Parent = parent end
	return obj
end
local function corner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end
local function pad(el, l, r, t, b)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
		PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
	}, el)
end
local function stroke(o, color, thickness)
	return make("UIStroke", {
		Color = color or THEME.stroke, Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end
local function tw(obj, goal, dur)
	local ti = TweenInfo.new(dur or state.uiAnim, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local t = tweSvc:Create(obj, ti, goal)
	t:Play()
	return t
end

local view = currentCam() and currentCam().ViewportSize or Vector2.new(1280, 720)
local winW = math.clamp(view.X - 24, 340, 680)
local winH = math.clamp(view.Y - 110, 300, 480)

local window = make("Frame", {
	Name = "Window",
	Size = UDim2.fromOffset(winW, winH),
	Position = UDim2.new(0.5, -winW / 2, 0.5, -winH / 2),
	BackgroundColor3 = THEME.bg, BorderSizePixel = 0, ZIndex = 6,
}, screenGui)
corner(window, 14)
stroke(window, THEME.stroke, 1)
local windowScale = make("UIScale", { Scale = 1 }, window)

local function enableDrag(frame, handle)
	local dragging, dragStart, startPos = false, nil, nil
	handle.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1
			or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = io.Position
			startPos = frame.Position
		end
	end)
	local function onChange(io)
		if not dragging then return end
		if io.UserInputType == Enum.UserInputType.MouseMovement
			or io.UserInputType == Enum.UserInputType.Touch then
			local delta = Vector2.new(io.Position.X - dragStart.X, io.Position.Y - dragStart.Y)
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end
	handle.InputChanged:Connect(onChange)
	connect(uis.InputChanged, onChange)
	connect(uis.InputEnded, function() dragging = false end)
end

local function pingButton(btn)
	local from = btn.BackgroundColor3
	tw(btn, { BackgroundColor3 = THEME.cardUp }, 0.06)
	task.delay(0.07, function()
		pcall(function() tw(btn, { BackgroundColor3 = from }, 0.12) end)
	end)
end

local function popWindow()
	if not windowScale then return end
	windowScale.Scale = 0.955
	tw(windowScale, { Scale = 1 }, 0.16)
end

-- FLY PAD (MOBILE FLIGHT CONTROLS)
local flyPad = make("Frame", {
	Name = "FlyPad", Visible = false, BackgroundTransparency = 1,
	Size = UDim2.fromOffset(232, 150),
	Position = UDim2.new(1, -248, 1, -164), ZIndex = 2,
}, screenGui)
local function flyButton(label, prop, amount)
	local btn = make("TextButton", {
		Text = label, Font = Enum.Font.GothamBold, TextSize = 15,
		TextColor3 = THEME.text, BackgroundColor3 = THEME.card,
		BackgroundTransparency = 0.25, BorderSizePixel = 0, AutoButtonColor = false,
	}, flyPad)
	corner(btn, 10)
	stroke(btn, THEME.stroke)
	local function set(onoff)
		state.touchMove[prop] = onoff and amount or 0
		tw(btn, { BackgroundTransparency = onoff and 0 or 0.25 }, 0.08)
	end
	btn.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1
			or io.UserInputType == Enum.UserInputType.Touch then set(true) end
	end)
	btn.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1
			or io.UserInputType == Enum.UserInputType.Touch then set(false) end
	end)
	btn.MouseLeave:Connect(function() set(false) end)
	return btn
end
local btnFwd = flyButton("FWD", "fwd", 1)
btnFwd.Size = UDim2.fromOffset(68, 40); btnFwd.Position = UDim2.new(0, 82, 0, 0)
local btnBack = flyButton("BCK", "back", 1)
btnBack.Size = UDim2.fromOffset(68, 40); btnBack.Position = UDim2.new(0, 82, 0, 108)
local btnUp = flyButton("UP", "up", 1)
btnUp.Size = UDim2.fromOffset(68, 40); btnUp.Position = UDim2.new(0, 0, 0, 54)
local btnDown = flyButton("DN", "down", 1)
btnDown.Size = UDim2.fromOffset(68, 40); btnDown.Position = UDim2.new(0, 164, 0, 54)

-- FLOATING SUPER PUNCH BUTTON (FOR MOBILE WHEN SUPER PUNCH IS ON)
local punchFab = make("TextButton", {
	Name = "RiotHub_PunchBtn", Text = "PUNCH", Visible = false,
	Size = UDim2.fromOffset(66, 42),
	Position = UDim2.new(1, -84, 0.55, 0),
	BackgroundColor3 = THEME.accent, BorderSizePixel = 0,
	Font = Enum.Font.GothamBold, TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, ZIndex = 35,
}, screenGui)
corner(punchFab, 10)
stroke(punchFab, Color3.new(1, 1, 1), 1)
enableDrag(punchFab, punchFab)
punchFab.MouseButton1Click:Connect(function()
	triggerSuperPunch()
end)

-- TOASTS
local toastHost = make("Frame", {
	Name = "ToastHost", BackgroundTransparency = 1,
	Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 240, 1, -32),
	AnchorPoint = Vector2.new(1, 0), ZIndex = 20,
}, screenGui)
make("UIListLayout", {
	Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
}, toastHost)

toast = function(title, body, dur, kind)
	if state.detached then return end
	pcall(function()
		local card = make("Frame", {
			BackgroundColor3 = THEME.card, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 54), ZIndex = 50,
		}, toastHost)
		corner(card, 10)
		stroke(card, kind == "err" and THEME.accentDk
			or kind == "ok" and Color3.fromRGB(40, 95, 65) or THEME.stroke)
		local bar = make("Frame", {
			Size = UDim2.new(0, 4, 1, -12), Position = UDim2.new(0, 6, 0, 6),
			BackgroundColor3 = kind == "err" and THEME.accent
				or kind == "ok" and THEME.green or THEME.accent, BorderSizePixel = 0,
		}, card)
		corner(bar, 2)
		make("TextLabel", {
			Text = title, Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = THEME.text, BackgroundTransparency = 1,
			Size = UDim2.new(1, -24, 0, 16), Position = UDim2.new(0, 16, 0, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		make("TextLabel", {
			Text = body or "", Font = Enum.Font.Gotham, TextSize = 11,
			TextColor3 = THEME.textDim, BackgroundTransparency = 1,
			Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 16, 0, 25),
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
		}, card)
		card.Position = UDim2.new(1, 20, 0, 0)
		tw(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.2)
		task.delay(math.max((dur or 2.4), 0.3), function()
			if card.Parent then
				tw(card, { BackgroundTransparency = 1, Position = UDim2.new(1, 20, 0, 0) }, 0.2)
				task.wait(0.24)
				pcall(function() card:Destroy() end)
			end
		end)
	end)
end

-- FLOATING MOBILE HUB TOGGLE ("RH")
local toggleFab = make("TextButton", {
	Name = "ToggleFab", Text = "RH",
	Size = UDim2.fromOffset(46, 46),
	Position = UDim2.new(0, 12, 0.5, -23),
	BackgroundColor3 = THEME.card, BorderSizePixel = 0,
	Font = Enum.Font.GothamBold, TextSize = 15,
	TextColor3 = THEME.accent,
	Active = true, AutoButtonColor = false, ZIndex = 40,
}, screenGui)
corner(toggleFab, 23)
stroke(toggleFab, THEME.accent, 1.5)
do
	local dragging, moved = false, 0
	local dragStart, startPos
	toggleFab.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1
			or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = 0
			dragStart = io.Position
			startPos = toggleFab.Position
		end
	end)
	local function onChange(io)
		if not dragging then return end
		if io.UserInputType == Enum.UserInputType.MouseMovement
			or io.UserInputType == Enum.UserInputType.Touch then
			local d = Vector2.new(io.Position.X - dragStart.X, io.Position.Y - dragStart.Y)
			moved = d.Magnitude
			toggleFab.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end
	toggleFab.InputChanged:Connect(onChange)
	connect(uis.InputChanged, onChange)
	connect(uis.InputEnded, function()
		if dragging and moved <= 6 then
			pingButton(toggleFab)
			window.Visible = not window.Visible
			if window.Visible then popWindow() end
		end
		dragging = false
	end)
end

-- TOP BAR
local topBar = make("Frame", {
	Name = "TopBar", Size = UDim2.new(1, 0, 0, 42),
	BackgroundColor3 = THEME.surface, BorderSizePixel = 0,
}, window)
corner(topBar, 14)
make("Frame", {
	Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10),
	BackgroundColor3 = THEME.surface, BorderSizePixel = 0,
}, topBar)
local accentBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2),
	BackgroundColor3 = THEME.accent, BorderSizePixel = 0,
}, topBar)
make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.accent),
		ColorSequenceKeypoint.new(0.6, THEME.accentDk),
		ColorSequenceKeypoint.new(1, THEME.bg),
	}),
}, accentBar)
make("TextLabel", {
	Text = "RIOTHUB v4.0 · PRISON LIFE (LATEST)", Font = Enum.Font.GothamBold, TextSize = 14,
	TextColor3 = THEME.text, BackgroundTransparency = 1,
	Size = UDim2.new(1, -96, 1, 0), Position = UDim2.new(0, 14, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
}, topBar)
local hideBtn = make("TextButton", {
	Text = "-", Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(1, -84, 0, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = THEME.textDim, TextSize = 18,
}, topBar)
local closeBtn = make("TextButton", {
	Text = "X", Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(1, -44, 0, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = THEME.accent, TextSize = 15,
}, topBar)
hideBtn.MouseButton1Click:Connect(function() window.Visible = false end)
closeBtn.MouseButton1Click:Connect(function()
	window.Visible = false
	toast("Hub Hidden", "Tap the RH button or press RightCtrl to reopen", 2)
end)
enableDrag(window, topBar)

-- SIDEBAR + CONTENT
local tabsRail = make("ScrollingFrame", {
	Size = UDim2.new(0, 124, 1, -42 - 26), Position = UDim2.new(0, 0, 0, 42),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 340), ScrollBarThickness = 2,
}, window)
make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, tabsRail)
pad(tabsRail, 6, 3, 6)

local contentHolder = make("ScrollingFrame", {
	Size = UDim2.new(1, -136, 1, -42 - 30),
	Position = UDim2.new(0, 130, 0, 42),
	BackgroundColor3 = THEME.surface, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, window)
corner(contentHolder, 10)
pad(contentHolder, 4, 10, 6)

-- FOOTER + SESSION LOG
local statusRow = make("Frame", {
	Name = "StatusRow", Size = UDim2.new(1, 0, 0, 24),
	Position = UDim2.new(0, 0, 1, -24), BackgroundTransparency = 1, ZIndex = 5,
}, window)
local statusLabel = make("TextLabel", {
	Text = "ready...", Font = Enum.Font.Gotham, TextSize = 11,
	TextColor3 = THEME.textDim, BackgroundTransparency = 1,
	Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 10, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
}, statusRow)
local logBtn = make("TextButton", {
	Text = "LOG +", Font = Enum.Font.GothamBold, TextSize = 11,
	TextColor3 = THEME.text, BackgroundColor3 = THEME.card, BorderSizePixel = 0,
	Size = UDim2.new(0, 70, 0, 18), Position = UDim2.new(1, -78, 0, 3),
	AutoButtonColor = false,
}, statusRow)
corner(logBtn, 6)
local logPanel = make("Frame", {
	Name = "LogPanel", Size = UDim2.new(1, 0, 0, 80),
	Position = UDim2.new(0, 0, 1, -80), BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0, Visible = false, ZIndex = 15,
}, window)
pad(logPanel, 6, 6, 2)
logScroll = make("ScrollingFrame", {
	Name = "LogScroll", Size = UDim2.new(1, -8, 1, -4),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 40), ScrollBarThickness = 2, ZIndex = 16,
}, logPanel)
logText = make("TextLabel", {
	Name = "LogText", Text = "RiotHub v4.0 — session log",
	Size = UDim2.new(1, -8, 0, 20), BackgroundTransparency = 1,
	Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(120, 235, 170),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextSize = 12, ZIndex = 17,
}, logScroll)
local logOpen = false
logBtn.MouseButton1Click:Connect(function()
	logOpen = not logOpen
	logBtn.Text = logOpen and "LOG -" or "LOG +"
	logPanel.Visible = logOpen
end)

-- TAB FRAMEWORK (FIXED REGISTRATION SO HOME OPENS AUTOMATICALLY)
local tabButtons = {}
local activeTabEntry = nil

local function newTab(label)
	local btn = make("TextButton", {
		Text = label, Size = UDim2.new(1, 0, 0, 29),
		BackgroundColor3 = THEME.bg,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = THEME.textDim,
		AutoButtonColor = false, BorderSizePixel = 0,
	}, tabsRail)
	pad(btn, 10)
	corner(btn, 8)
	local bar = make("Frame", {
		Size = UDim2.new(0, 3, 0, 14), Position = UDim2.new(0, 4, 0.5, -7),
		BackgroundColor3 = THEME.accent, BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, btn)
	corner(bar, 2)

	local page = make("Frame", {
		Name = label:gsub("[^%a]", "") .. "Page",
		Size = UDim2.new(1, -10, 1, 0),
		BackgroundTransparency = 1, Visible = false,
	}, contentHolder)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, page)

	local entry = { txt = btn, page = page, bar = bar }
	tabButtons[label] = entry

	btn.MouseButton1Click:Connect(function()
		if activeTabEntry == entry then return end
		if activeTabEntry then
			activeTabEntry.page.Visible = false
			activeTabEntry.txt.BackgroundColor3 = THEME.bg
			activeTabEntry.txt.TextColor3 = THEME.textDim
			activeTabEntry.bar.BackgroundTransparency = 1
		end
		activeTabEntry = entry
		btn.BackgroundColor3 = THEME.card
		btn.TextColor3 = THEME.text
		entry.bar.BackgroundTransparency = 0
		page.Visible = true
		local list = page:FindFirstChildOfClass("UIListLayout")
		contentHolder.CanvasSize = UDim2.new(0, 0, 0,
			(list and list.AbsoluteContentSize.Y or 0) + 24)
		contentHolder.CanvasPosition = Vector2.new(0, 0)
	end)
	return page
end

local function ensureCanvas(page)
	local list = page:FindFirstChildOfClass("UIListLayout")
	if list then
		local function sync()
			if activeTabEntry and activeTabEntry.page == page then
				contentHolder.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 24)
			end
		end
		connect(list:GetPropertyChangedSignal("AbsoluteContentSize"), sync)
		if activeTabEntry and activeTabEntry.page == page then sync() end
	end
end

-- ============================================================================
-- UI WIDGET BUILDERS
-- ============================================================================
local function section(page, label)
	local row = make("Frame", {
		Size = UDim2.new(1, -8, 0, 24), BackgroundTransparency = 1,
	}, page)
	make("TextLabel", {
		Text = string.upper(label), Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = THEME.accent, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = THEME.stroke, BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, row)
end

local function infoRow(owner, text, height)
	local row = make("TextLabel", {
		Text = text, Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = THEME.textDim, BackgroundColor3 = THEME.card,
		Size = UDim2.new(1, -8, 0, height or 42), TextWrapped = true, BorderSizePixel = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, owner)
	corner(row, 8)
	pad(row, 10, 10, 6, 6)
	return row
end

local function toggleRow(owner, id, label, desc, default, callback)
	local row = make("TextButton", {
		Size = UDim2.new(1, -8, 0, desc and desc ~= "" and 48 or 34),
		BackgroundColor3 = THEME.card, BorderSizePixel = 0, Text = "",
		AutoButtonColor = false, Parent = owner,
	}, owner)
	corner(row, 8)
	local rowStroke = make("UIStroke", {
		Color = THEME.accent, Thickness = 1.3, Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, row)
	local body = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -56, 1, 0) }, row)
	pad(body, 11)
	make("TextLabel", {
		Text = label, Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, (desc and desc ~= "") and 4 or 8),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
	}, body)
	if desc and desc ~= "" then
		make("TextLabel", {
			Text = desc, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 22),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10,
			TextColor3 = THEME.textDim, TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
		}, body)
	end
	local switch = make("Frame", {
		Size = UDim2.new(0, 40, 0, 22), Position = UDim2.new(1, -50, 0.5, -11),
		BackgroundColor3 = default and THEME.green or Color3.fromRGB(52, 55, 66),
		BorderSizePixel = 0,
	}, row)
	corner(switch, 11)
	local knob = make("Frame", {
		Size = UDim2.new(0, 16, 0, 16),
		Position = default and UDim2.new(1, -19, 0, 3) or UDim2.new(0, 3, 0, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, switch)
	corner(knob, 8)

	local enabled = (default == true)
	local function set(v)
		enabled = v == true
		state.toggles[id] = enabled
		switch.BackgroundColor3 = enabled and THEME.green or Color3.fromRGB(52, 55, 66)
		rowStroke.Transparency = enabled and 0.35 or 1
		knob.Position = enabled and UDim2.new(1, -19, 0, 3) or UDim2.new(0, 3, 0, 3)
		tw(knob, { Position = knob.Position }, 0.1)
		if statusLabel then
			statusLabel.Text = label .. "  ->  " .. (enabled and "ON" or "OFF")
		end
		if callback then
			task.spawn(function()
				local ok, err = pcall(callback, enabled)
				if not ok then log("toggle error [" .. id .. "]: " .. tostring(err), true) end
			end)
		end
	end
	row.MouseButton1Click:Connect(function() set(not enabled) end)
	state.toggles[id] = enabled
	state.switches[id] = { Set = set }
	rowStroke.Transparency = enabled and 0.35 or 1
	return { Set = set }
end

local function sliderRow(owner, label, minV, maxV, default, callback, suffix)
	local row = make("Frame", {
		Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = THEME.card,
		BorderSizePixel = 0,
	}, owner)
	corner(row, 8)
	pad(row, 11, 12, 5)
	make("TextLabel", {
		Text = label, Size = UDim2.new(0.62, 0, 0, 16), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local valueLabel = make("TextLabel", {
		Text = tostring(default) .. (suffix or ""), Size = UDim2.new(0.38, 0, 0, 16),
		Position = UDim2.new(0.62, 0, 0, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = THEME.accent, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	local bar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 22),
		BackgroundTransparency = 1, Active = true,
	}, row)
	local track = make("Frame", {
		Size = UDim2.new(1, 0, 0, 7), Position = UDim2.new(0, 0, 0.5, -3.5),
		BackgroundColor3 = Color3.fromRGB(45, 48, 58), BorderSizePixel = 0,
	}, bar)
	corner(track, 3)
	local ratio0 = math.clamp((default - minV) / math.max(maxV - minV, 0.001), 0, 1)
	local fill = make("Frame", {
		Size = UDim2.new(ratio0, 0, 1, 0),
		BackgroundColor3 = THEME.accent, BorderSizePixel = 0,
	}, track)
	corner(fill, 3)
	local knobDot = make("Frame", {
		Size = UDim2.new(0, 12, 0, 12), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(ratio0, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, track)
	corner(knobDot, 6)
	local dragging = false
	local function apply(x)
		local a, s = bar.AbsolutePosition, bar.AbsoluteSize
		local ratio = math.clamp((x - a.X) / math.max(s.X, 1), 0, 1)
		local value = minV + (maxV - minV) * ratio
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knobDot.Position = UDim2.new(ratio, 0, 0.5, 0)
		valueLabel.Text = string.format("%.0f%s", value, suffix or "")
		if callback then
			local ok, err = pcall(callback, value)
			if not ok then log("slider error [" .. label .. "]: " .. tostring(err), true) end
		end
	end
	bar.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1
			or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			apply(io.Position.X)
		end
	end)
	connect(uis.InputChanged, function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement
			or io.UserInputType == Enum.UserInputType.Touch) then
			apply(io.Position.X)
		end
	end)
	connect(uis.InputEnded, function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1
			or io.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function buttonRow(owner, label, callback, accent)
	local btn = make("TextButton", {
		Text = label, Size = UDim2.new(1, -8, 0, 34),
		BackgroundColor3 = accent and Color3.fromRGB(48, 24, 34) or THEME.card,
		Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = accent and THEME.accent or THEME.text,
		AutoButtonColor = false, BorderSizePixel = 0,
	}, owner)
	corner(btn, 8)
	if accent then stroke(btn, THEME.accentDk, 1) end
	btn.MouseButton1Click:Connect(function()
		pingButton(btn)
		if statusLabel then statusLabel.Text = label .. "  ->  fired" end
		task.spawn(function()
			local ok, err = pcall(callback)
			if not ok then log("button error [" .. label .. "]: " .. tostring(err), true) end
		end)
	end)
	return btn
end

local function pairRow(owner, labelA, cbA, labelB, cbB)
	local rowWrap = make("Frame", {
		Size = UDim2.new(1, -8, 0, 34), BackgroundTransparency = 1,
	}, owner)
	local a = make("TextButton", {
		Text = labelA, Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = THEME.card, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = THEME.text,
		AutoButtonColor = false,
	}, rowWrap)
	corner(a, 8)
	a.MouseButton1Click:Connect(function()
		pingButton(a)
		task.spawn(function()
			local ok, err = pcall(cbA)
			if not ok then log("button error [" .. labelA .. "]: " .. tostring(err), true) end
		end)
	end)
	local b = make("TextButton", {
		Text = labelB, Size = UDim2.new(0.5, -4, 1, 0), Position = UDim2.new(0.5, 4, 0, 0),
		BackgroundColor3 = THEME.card, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = THEME.text,
		AutoButtonColor = false,
	}, rowWrap)
	corner(b, 8)
	b.MouseButton1Click:Connect(function()
		pingButton(b)
		task.spawn(function()
			local ok, err = pcall(cbB)
			if not ok then log("button error [" .. labelB .. "]: " .. tostring(err), true) end
		end)
	end)
end

-- FIXED DROPDOWN (Y-OFFSET POSITIONING + DYNAMIC REBUILD FOR PLAYER LISTS)
local function dropdownRow(owner, label, options, default, callback)
	local baseH = 34
	local row = make("TextButton", {
		Size = UDim2.new(1, -8, 0, baseH), BackgroundColor3 = THEME.card,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 4,
	}, owner)
	corner(row, 8)
	pad(row, 11)
	make("TextLabel", {
		Text = label, Size = UDim2.new(0.55, -8, 0, baseH),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local chosen = make("TextLabel", {
		Text = (default or "-"), Size = UDim2.new(0.45, -12, 0, baseH),
		Position = UDim2.new(0.55, 0, 0, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = THEME.accent, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	local list = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = Color3.fromRGB(32, 35, 45), BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, baseH + 4), Visible = false, ZIndex = 12,
		ScrollBarThickness = 2, CanvasSize = UDim2.new(0, 0, 0, 0),
	}, row)
	corner(list, 8)
	stroke(list, THEME.stroke)

	local openTgl = false
	local currentOpts = options or {}

	local function setOpen(open)
		openTgl = open
		local listH = math.min(#currentOpts, 6) * 26 + 6
		list.Size = UDim2.new(1, 0, 0, listH)
		list.CanvasSize = UDim2.new(0, 0, 0, #currentOpts * 26 + 6)
		list.Visible = open
		row.Size = UDim2.new(1, -8, 0, baseH + (open and (listH + 8) or 0))
		row.ZIndex = open and 11 or 4
	end

	local function rebuildOptions(newOpts)
		currentOpts = newOpts or {}
		for _, ch in ipairs(list:GetChildren()) do
			if ch:IsA("TextButton") then ch:Destroy() end
		end
		for idx, opt in ipairs(currentOpts) do
			local optBtn = make("TextButton", {
				Text = tostring(opt), Size = UDim2.new(1, -8, 0, 24),
				Position = UDim2.new(0, 4, 0, (idx - 1) * 26 + 3), -- FIXED Y-OFFSET!
				BackgroundColor3 = Color3.fromRGB(40, 44, 56),
				Font = Enum.Font.Gotham, TextSize = 11,
				TextColor3 = THEME.text, AutoButtonColor = false,
				BorderSizePixel = 0, ZIndex = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, list)
			pad(optBtn, 8, 0, 0)
			corner(optBtn, 6)
			optBtn.MouseButton1Click:Connect(function()
				chosen.Text = tostring(opt)
				if callback then callback(opt) end
				setOpen(false)
			end)
		end
	end

	rebuildOptions(currentOpts)
	row.MouseButton1Click:Connect(function()
		setOpen(not openTgl)
	end)
	return { Text = chosen, SetOptions = rebuildOptions, SetValue = function(v) chosen.Text = tostring(v) end }
end

-- ============================================================================
-- TABS CREATION
-- ============================================================================
local pageHome   = newTab("HOME")
local pageCombat = newTab("COMBAT")
local pageTarget = newTab("TARGET")
local pageGun    = newTab("GUNS")
local pageMov    = newTab("MOVE & CAR")
local pageVis    = newTab("VISUALS")
local pageTele   = newTab("TELEPORT")
local pageSrv    = newTab("WORLD")
local pageCfg    = newTab("SETUP")

for _, p in ipairs({
	pageHome, pageCombat, pageTarget, pageGun,
	pageMov, pageVis, pageTele, pageSrv, pageCfg
}) do
	ensureCanvas(p)
end

-- Activate HOME tab immediately on launch
do
	local first = tabButtons["HOME"]
	if first then
		activeTabEntry = first
		first.txt.BackgroundColor3 = THEME.card
		first.txt.TextColor3 = THEME.text
		first.bar.BackgroundTransparency = 0
		first.page.Visible = true
	end
end

-- ============================================================================
-- 1) HOME PAGE
-- ============================================================================
section(pageHome, "One-Tap Power Actions")
pairRow(pageHome, "Get All Guns + Mod", function() giveAllLoot(true) end,
	"Kill All (Server)", function() killAll(CONFIG.killAuraMode) end)
pairRow(pageHome, "Arrest All", function() arrestAll() end,
	"Taze All", function() tazeAll() end)
pairRow(pageHome, "Open Prison Gate", function() openGate() end,
	"Spawn Car Here", function() spawnCarHere("Sedan") end)
pairRow(pageHome, "Refresh In Place (:re)", function() refreshCharacterInPlace() end,
	"Fling All Players", function() flingAll() end)

section(pageHome, "Quick Team Switch")
pairRow(pageHome, "Become Guard", function() switchTeam("Guard") end,
	"Become Inmate", function() switchTeam("Inmate") end)
pairRow(pageHome, "Become Criminal", function() switchTeam("Criminal") end,
	"Solo Neutral", function() switchTeam("Neutral") end)

section(pageHome, "Live Session Telemetry")
local statFrame = make("Frame", {
	Size = UDim2.new(1, -8, 0, 42), BackgroundColor3 = THEME.card, BorderSizePixel = 0,
}, pageHome)
corner(statFrame, 8)
local statKills = make("TextLabel", {
	Text = "0 kills/hits", Font = Enum.Font.GothamBold, TextSize = 12,
	TextColor3 = THEME.accent, BackgroundTransparency = 1,
	Size = UDim2.new(0.34, 0, 1, 0),
}, statFrame)
local statArrests = make("TextLabel", {
	Text = "0 cuffs", Font = Enum.Font.GothamBold, TextSize = 12,
	TextColor3 = THEME.green, BackgroundTransparency = 1,
	Size = UDim2.new(0.33, 0, 1, 0), Position = UDim2.new(0.34, 0, 0, 0),
}, statFrame)
local statItems = make("TextLabel", {
	Text = "0 items", Font = Enum.Font.GothamBold, TextSize = 12,
	TextColor3 = THEME.amber, BackgroundTransparency = 1,
	Size = UDim2.new(0.33, 0, 1, 0), Position = UDim2.new(0.67, 0, 0, 0),
}, statFrame)

infoRow(pageHome, "CHAT COMMANDS ACTIVE! Type in Roblox Chat:\n"
	.. ":kill [plr/all] · :loopkill [plr] · :unloopkill [plr] · :fling [plr/all] · :arrest [plr/all]\n"
	.. ":taze [plr/all] · :goto [plr] · :view [plr] · :unview · :guns · :mod · :car · :re · :crim · :guard", 62)

-- ============================================================================
-- 2) COMBAT PAGE
-- ============================================================================
section(pageCombat, "Kill Aura & Super Punch")
toggleRow(pageCombat, "auraKillOn", "Kill Aura (Key: G)", "Auto-kills every target in radius using Smart/Gun/Fists",
	false, function(v) if v then toast("Kill Aura", "Active (" .. CONFIG.killAuraMode .. ")", 2, "ok") end end)
toggleRow(pageCombat, "superPunchOn", "Super Punch / One-Punch (Key: F)", "1-hit KO with bare fists (shows PUNCH button on mobile)",
	false, function(v)
		CONFIG.superPunch = v
		punchFab.Visible = v
		if v then toast("Super Punch", "Press F or tap PUNCH to 1-hit KO nearby players!", 2.5, "ok") end
	end)
sliderRow(pageCombat, "Kill Aura Radius", 10, 260, CONFIG.killAuraRadius,
	function(v) CONFIG.killAuraRadius = math.floor(v + 0.5) end, " studs")
sliderRow(pageCombat, "Kill Aura Pace", 5, 100, math.floor(CONFIG.killAuraRate * 100),
	function(v) CONFIG.killAuraRate = math.max(v / 100, 0.05) end, " cs")
dropdownRow(pageCombat, "Kill Engine Mode", { "Smart (Gun + Fists)", "Gun", "Fists" }, CONFIG.killAuraMode,
	function(choice) CONFIG.killAuraMode = choice end)
dropdownRow(pageCombat, "Aura Target Filter", { "All", "Inmates", "Guards", "Criminals", "Non-Friends" }, CONFIG.auraTargets,
	function(choice) CONFIG.auraTargets = choice end)
toggleRow(pageCombat, "skipFF", "Ignore Spawn ForceFields", "Skip freshly spawned shielded players",
	CONFIG.killAuraIgnoreFF, function(v) CONFIG.killAuraIgnoreFF = v end)

section(pageCombat, "Hitbox Expander")
toggleRow(pageCombat, "hitboxOn", "Expand Enemy Hitboxes", "Enlarges enemy heads/roots so every shot & punch lands",
	false, function(v) CONFIG.hitboxEnabled = v end)
sliderRow(pageCombat, "Hitbox Size", 2, 25, CONFIG.hitboxSize,
	function(v) CONFIG.hitboxSize = math.floor(v + 0.5) end, " studs")
dropdownRow(pageCombat, "Hitbox Target Part", { "Head", "HumanoidRootPart" }, CONFIG.hitboxPart,
	function(choice) CONFIG.hitboxPart = choice end)

section(pageCombat, "Aimbot & Silent Aim")
toggleRow(pageCombat, "aimOn", "Camera Aimbot", "Locks camera onto nearest head inside FOV ring",
	false, function() end)
sliderRow(pageCombat, "Aimbot FOV", 20, 450, CONFIG.aimbotFov,
	function(v) CONFIG.aimbotFov = math.floor(v + 0.5) end)
sliderRow(pageCombat, "Aimbot Smoothing", 0, 95, CONFIG.aimbotSmooth,
	function(v) CONFIG.aimbotSmooth = v end, "%")
toggleRow(pageCombat, "silentOn", "Silent Aim (ShootEvent Hook)", "Redirects your gun bullets directly to the nearest enemy Head",
	false, function() end)
sliderRow(pageCombat, "Silent Aim Hit Chance", 0, 100, CONFIG.silentHitChance,
	function(v) CONFIG.silentHitChance = math.floor(v + 0.5) end, "%")
toggleRow(pageCombat, "silentWall", "Silent Aim Wall Check", "Only redirect bullets when target is in line of sight",
	CONFIG.silentWallCheck, function(v) CONFIG.silentWallCheck = v end)
toggleRow(pageCombat, "triggerOn", "TriggerBot", "Auto-fires held weapon when crosshair passes over an enemy",
	false, function() end)
dropdownRow(pageCombat, "Aim Target Filter", { "All", "Inmates", "Guards", "Criminals", "Non-Friends" }, CONFIG.aimbotTargets,
	function(choice) CONFIG.aimbotTargets = choice; CONFIG.triggerTargets = choice end)

section(pageCombat, "Arrest & Taze Auras")
toggleRow(pageCombat, "auraArrestOn", "Arrest Aura (Key: H)", "Auto-snaps behind & cuffs any arrestable player in range",
	false, function(v) if v then toast("Arrest Aura", "Active — cuffs inmates & criminals", 2, "ok") end end)
sliderRow(pageCombat, "Arrest Radius", 15, 400, CONFIG.arrestAuraRadius,
	function(v) CONFIG.arrestAuraRadius = math.floor(v + 0.5) end, " studs")
toggleRow(pageCombat, "clickArrestOn", "Click Arrest", "Tap/click any player on screen to cuff them",
	CONFIG.clickArrest, function(v) CONFIG.clickArrest = v end)
toggleRow(pageCombat, "auraTazeOn", "Taze Loop Aura (Key: J)", "Continuously remote-tazes non-guards across the server",
	false, function() end)

-- ============================================================================
-- 3) TARGET PLAYER MANAGER & TROLL SUITE
-- ============================================================================
section(pageTarget, "Select Player")
local function buildPlayerNames()
	local names = {}
	for _, p in ipairs(plrs:GetPlayers()) do
		if p ~= lp then table.insert(names, p.Name) end
	end
	if #names == 0 then table.insert(names, "(No other players)") end
	return names
end

local targetDropdown = dropdownRow(pageTarget, "Target Player", buildPlayerNames(), "-", function(choice)
	local p = plrs:FindFirstChild(choice)
	if p then
		state.selectedTarget = p
		toast("Target Selected", p.Name .. " (" .. tostring(p.Team and p.Team.Name or "Neutral") .. ")", 1.8, "ok")
	end
end)

local function refreshTargetDropdown()
	local names = buildPlayerNames()
	targetDropdown.SetOptions(names)
	if not getActiveTarget() and names[1] and names[1] ~= "(No other players)" then
		state.selectedTarget = plrs:FindFirstChild(names[1])
		targetDropdown.SetValue(names[1])
	end
end

pairRow(pageTarget, "Refresh Player List", function()
	refreshTargetDropdown()
	toast("Players Refreshed", tostring(#plrs:GetPlayers() - 1) .. " other players", 1.5, "ok")
end, "Select Nearest Player", function()
	local myRoot = charRoot()
	if not myRoot then return end
	local best, bestD = nil, math.huge
	for _, p in ipairs(plrs:GetPlayers()) do
		if p ~= lp and charRoot(p) then
			local d = (charRoot(p).Position - myRoot.Position).Magnitude
			if d < bestD then best, bestD = p, d end
		end
	end
	if best then
		state.selectedTarget = best
		targetDropdown.SetValue(best.Name)
		toast("Nearest Selected", best.Name .. string.format(" (%.0fm)", bestD), 1.8, "ok")
	end
end)

section(pageTarget, "Single-Target Actions")
pairRow(pageTarget, "Kill Target (Smart)", function()
	local t = getActiveTarget()
	if not t then toast("No Target", "Select a player above first", 2, "err") return end
	killTarget(t)
	toast("Kill Fired", "Attacked " .. t.Name, 1.8, "ok")
end, "TP-Punch Kill (No Gun)", function()
	local t = getActiveTarget()
	if not t then toast("No Target", "Select a player above first", 2, "err") return end
	tpPunchKill(t)
	toast("TP-Punch Kill", "Punched " .. t.Name .. " 15x", 1.8, "ok")
end)

pairRow(pageTarget, "Fling Target (Launch)", function()
	local t = getActiveTarget()
	if not t then toast("No Target", "Select a player above first", 2, "err") return end
	flingTarget(t, 1.8)
end, "Arrest Target", function()
	local t = getActiveTarget()
	if not t then toast("No Target", "Select a player above first", 2, "err") return end
	if arrestTarget(t) then
		toast("Arrested", t.Name .. " is now cuffed!", 2, "ok")
	else
		toast("Arrest Failed", "Target is a Guard or already cuffed", 2, "err")
	end
end)

pairRow(pageTarget, "Taze Target", function()
	local t = getActiveTarget()
	if not t then toast("No Target", "Select a player above first", 2, "err") return end
	if tazeTarget(t) then
		toast("Tazed", "Shocked " .. t.Name, 1.8, "ok")
	else
		toast("No Taser", "Switch to Guard team for a Taser", 2, "err")
	end
end, "Teleport To Target", function()
	local t = getActiveTarget()
	local r = t and charRoot(t)
	if r then
		teleportTo(r.CFrame * CFrame.new(0, 0, 2.5))
		toast("Teleported", "Warped behind " .. t.Name, 1.5, "ok")
	end
end)

section(pageTarget, "Target Persistent Loops & Spectate")
toggleRow(pageTarget, "loopKillTargetOn", "Loopkill Selected Target", "Automatically kills the selected target every time they respawn",
	false, function(v)
		local t = getActiveTarget()
		if t then
			state.loopKillTargets[t.Name] = v and true or nil
			toast("Loopkill", (v and "Locked onto " or "Stopped on ") .. t.Name, 2, v and "ok" or nil)
		end
	end)
toggleRow(pageTarget, "loopTazeTargetOn", "Loop-Taze Selected Target", "Continuously tazes the selected target so they stay stunned",
	false, function(v)
		local t = getActiveTarget()
		if t then
			state.loopTazeTargets[t.Name] = v and true or nil
		end
	end)
toggleRow(pageTarget, "orbitTargetOn", "Orbit / Annoy Target", "Circles rapidly around the selected target player",
	false, function() end)
toggleRow(pageTarget, "spectateTargetOn", "Spectate / View Target", "Locks your camera onto the selected target",
	false, function(v)
		local cam = currentCam()
		if not cam then return end
		if v then
			local t = getActiveTarget()
			local hum = t and charHumanoid(t)
			if hum then cam.CameraSubject = hum end
		else
			local myHum = charHumanoid()
			if myHum then cam.CameraSubject = myHum end
		end
	end)
buttonRow(pageTarget, "Clear All Loopkills & Loop-Tazes", function()
	state.loopKillTargets = {}
	state.loopTazeTargets = {}
	if state.switches.loopKillTargetOn then state.switches.loopKillTargetOn.Set(false) end
	if state.switches.loopTazeTargetOn then state.switches.loopTazeTargetOn.Set(false) end
	toast("Cleared", "All loopkill & loop-taze targets cleared", 2, "ok")
end)

-- ============================================================================
-- 4) GUNS & ITEM HANDLER PAGE
-- ============================================================================
section(pageGun, "Weapon Giver (Distance-Bypass Ready)")
dropdownRow(pageGun, "Pickup Bypass Method",
	{ "Smart Snap + Spoof", "CFrame Snap-Back", "Remote Spoof Only" },
	CONFIG.pickupMethod, function(choice) CONFIG.pickupMethod = choice end)
dropdownRow(pageGun, "Select Weapon",
	{ "Remington 870", "AK-47", "M9", "M4A1" }, CONFIG.gunChoice,
	function(choice) CONFIG.gunChoice = choice end)
pairRow(pageGun, "Give Selected Gun", function()
	if giveAnywhere(CONFIG.gunChoice) then
		toast("Weapon Granted", CONFIG.gunChoice .. " added to backpack", 2, "ok")
	end
end, "Give All Guns + Mod", function()
	giveAllLoot(true)
end)
pairRow(pageGun, "Key Card", function() giveAnywhere("Key card") end,
	"Hammer + Knife", function() giveAnywhere("Hammer"); giveAnywhere("Crude Knife") end)
pairRow(pageGun, "Riot Shield + Gear", function() giveRiotGear() end,
	"Reload Held Gun (Server)", function()
		local tool = lp.Character and lp.Character:FindFirstChildWhichIsA("Tool")
		if tool then reloadToolServer(tool); toast("Reloaded", "Server ammo refilled", 1.5, "ok") end
	end)
toggleRow(pageGun, "autoRearmOn", "Auto Re-Arm + Mod On Respawn", "Automatically pulls guns & applies One-Shot mods every respawn",
	CONFIG.autoRearm, function(v) CONFIG.autoRearm = v end)
toggleRow(pageGun, "autoReloadSrvOn", "Auto Server Reload (ReloadEvent)", "Continuously refills server-side ammo so modded guns never dry-fire",
	CONFIG.autoReloadServer, function(v) CONFIG.autoReloadServer = v end)

section(pageGun, "One-Click Gun Presets")
pairRow(pageGun, "1-Shot Laser Preset", function()
	CONFIG.gunDamage = 105
	CONFIG.gunBullets = 14
	CONFIG.gunFireRate = 0.001
	CONFIG.gunSpread = 0
	CONFIG.gunInfiniteAmmo = true
	CONFIG.gunAutoFire = true
	modAllGuns()
	toast("Laser Preset", "105 DMG · 0 Spread · Full Auto · 14x Bullets", 2.2, "ok")
end, "Wall-of-Lead Shotgun", function()
	CONFIG.gunDamage = 100
	CONFIG.gunBullets = 28
	CONFIG.gunFireRate = 0.005
	CONFIG.gunSpread = 0.025
	CONFIG.gunInfiniteAmmo = true
	CONFIG.gunAutoFire = true
	modAllGuns()
	toast("Wall of Lead", "28 Pellets per shot applied!", 2.2, "ok")
end)

section(pageGun, "Custom GunStates Editor")
sliderRow(pageGun, "Damage", 10, 250, CONFIG.gunDamage, function(v) CONFIG.gunDamage = math.floor(v + 0.5) end)
sliderRow(pageGun, "Bullets Per Shot", 1, 35, CONFIG.gunBullets, function(v) CONFIG.gunBullets = math.floor(v + 0.5) end)
sliderRow(pageGun, "Fire Delay (ms)", 0, 100, 1, function(v) CONFIG.gunFireRate = math.max(v / 1000, 0.0001) end, " ms")
sliderRow(pageGun, "Spread", 0, 100, CONFIG.gunSpread, function(v) CONFIG.gunSpread = v / 1000 end)
toggleRow(pageGun, "infAmmo", "Infinite Ammo", "CurrentAmmo pinned to math.huge",
	CONFIG.gunInfiniteAmmo, function(v) CONFIG.gunInfiniteAmmo = v end)
toggleRow(pageGun, "autoFire", "Full Automatic", "Hold mouse/tap to continuous-fire M9 & Remington",
	CONFIG.gunAutoFire, function(v) CONFIG.gunAutoFire = v end)
buttonRow(pageGun, "Apply Custom Mods To All Guns", function() modAllGuns() end, true)

-- ============================================================================
-- 5) MOVEMENT & VEHICLES PAGE
-- ============================================================================
section(pageMov, "Character Locomotion")
sliderRow(pageMov, "Walk Speed", 16, 250, CONFIG.walkSpeed,
	function(v) CONFIG.walkSpeed = math.floor(v + 0.5) end)
sliderRow(pageMov, "Jump Power", 50, 250, CONFIG.jumpPower,
	function(v) CONFIG.jumpPower = math.floor(v + 0.5) end)
toggleRow(pageMov, "noclipOn", "Noclip (Phase Through Walls)", "Walk straight through prison doors, cells, and walls",
	false, function() end)
toggleRow(pageMov, "infJump", "Infinite Jump", "Jump mid-air infinitely",
	false, function() end)
toggleRow(pageMov, "tpWalkOn", "TP-Walk (CFrame Speed Bypass)", "Moves root part via CFrame each frame",
	false, function() end)
sliderRow(pageMov, "TP-Walk Power", 1, 15, CONFIG.tpWalkPower,
	function(v) CONFIG.tpWalkPower = math.floor(v + 0.5) end)
toggleRow(pageMov, "spinOn", "SpinBot", "Rotates your character rapidly",
	false, function() end)

section(pageMov, "Flight (Key: Z)")
toggleRow(pageMov, "flyOn", "Fly (PC: WASD+E/Q · Mobile: On-Screen Pad)", "Smooth CFrame flight with zero fall drift",
	false, function(v)
		flyPad.Visible = v or (state.toggles.carFlyOn == true)
		if not v then state.touchMove = { fwd = 0, back = 0, up = 0, down = 0 } end
	end)
sliderRow(pageMov, "Fly Speed", 1, 25, CONFIG.flySpeed,
	function(v) CONFIG.flySpeed = math.floor(v + 0.5) end)
toggleRow(pageMov, "clickTpOn", "Click / Tap To Teleport", "Tap any surface in the world to warp there",
	false, function(v) CONFIG.clickTp = v end)

section(pageMov, "Vehicle Spawner & Car Mods")
pairRow(pageMov, "Spawn Sedan Here", function() spawnCarHere("Sedan") end,
	"Spawn Police Squad Here", function() spawnCarHere("Police") end)
buttonRow(pageMov, "Apply Speed & Torque Boost To Seated Car", function() modCurrentCar() end, true)
sliderRow(pageMov, "Car Speed Multiplier", 1, 8, CONFIG.carSpeedMult,
	function(v) CONFIG.carSpeedMult = v end, "x")
toggleRow(pageMov, "carFlyOn", "Car Fly (Drive In The Sky)", "Fly any vehicle while seated in the driver seat",
	false, function(v)
		flyPad.Visible = v or (state.toggles.flyOn == true)
	end)
toggleRow(pageMov, "carNoclipOn", "Car Noclip", "Drive vehicles straight through fences & prison walls",
	false, function() end)

-- ============================================================================
-- 6) VISUALS PAGE
-- ============================================================================
section(pageVis, "Player ESP")
toggleRow(pageVis, "espOn", "Enable Player ESP", "Shows Name, HP%, Distance, and Equipped Weapon",
	false, function() refreshEsp() end)
toggleRow(pageVis, "espNamesOn", "Show Names", "", true, function(v) CONFIG.espNames = v end)
toggleRow(pageVis, "espDistOn", "Show Distance & Held Weapon", "", true, function(v) CONFIG.espDistance = v end)
toggleRow(pageVis, "espHpOn", "Show Health %", "", true, function(v) CONFIG.espHealthBar = v end)
toggleRow(pageVis, "espTeamOn", "Team Color Coding", "Blue = Guard · Orange = Inmate · Red = Criminal",
	true, function(v) CONFIG.espTeamColor = v end)
toggleRow(pageVis, "espTracers", "Snapline Tracers", "Draws lines from screen bottom to every player",
	false, function(v) CONFIG.espTracers = v end)

section(pageVis, "Chams (Wall-Vision Highlights)")
toggleRow(pageVis, "chamsOn", "Team Chams (Highlights)", "Full-body glowing silhouettes visible through walls",
	false, function() refreshEsp() end)
toggleRow(pageVis, "chamsWallOn", "Always On Top (Through Walls)", "Renders highlights through solid walls",
	CONFIG.chamsThroughWalls, function(v)
		CONFIG.chamsThroughWalls = v
		for _, plr in ipairs(plrs:GetPlayers()) do applyChams(plr) end
	end)

section(pageVis, "World & Camera")
toggleRow(pageVis, "fullbrightOn", "Fullbright (No Night / Fog)", "Removes darkness, shadows, and fog",
	false, function(v) setFullbright(v) end)
toggleRow(pageVis, "fpsBoostOn", "FPS Booster", "Disables particles, smoke, and trails for higher FPS",
	false, function(v) setFpsBoost(v) end)
toggleRow(pageVis, "showAimFovShow", "Show Aimbot FOV Ring", "Displays the targeting circle when Aimbot/Silent Aim is on",
	true, function(v) CONFIG.showAimFov = v end)
sliderRow(pageVis, "Camera FOV", 50, 120, 70, function(v)
	pcall(function() currentCam().FieldOfView = math.floor(v + 0.5) end)
end)

-- ============================================================================
-- 7) TELEPORT PAGE
-- ============================================================================
section(pageTele, "Key Prison Locations")
for i = 1, #TELEPORTS, 2 do
	local a = TELEPORTS[i]
	local b = TELEPORTS[i + 1]
	if a and b then
		pairRow(pageTele, a.name, function() teleportTo(a.fn()) end,
			b.name, function() teleportTo(b.fn()) end)
	elseif a then
		buttonRow(pageTele, a.name, function() teleportTo(a.fn()) end)
	end
end

section(pageTele, "Dynamic Teleports")
pairRow(pageTele, "Nearest Player", function()
	local myRoot = charRoot()
	if not myRoot then return end
	local best, bestD = nil, math.huge
	for _, plr in ipairs(plrs:GetPlayers()) do
		if plr ~= lp and charRoot(plr) then
			local d = (charRoot(plr).Position - myRoot.Position).Magnitude
			if d < bestD then best, bestD = charRoot(plr), d end
		end
	end
	if best then teleportTo(best.CFrame * CFrame.new(0, 0, 2.5)) end
end, "Nearest Spawned Car", function()
	local cc = workspace:FindFirstChild("CarContainer")
	local seat = cc and cc:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat then
		teleportTo(seat.CFrame)
		if charHumanoid() then pcall(function() seat:Sit(charHumanoid()) end) end
	else
		toast("No Cars", "Use Spawn Sedan Here in MOVE & CAR tab", 2, "err")
	end
end)

section(pageTele, "Custom Saved Waypoints")
for slot = 1, 3 do
	pairRow(pageTele, "Save Waypoint #" .. slot, function()
		local r = charRoot()
		if r then
			CONFIG.waypoints[slot] = r.CFrame
			toast("Waypoint #" .. slot, "Saved current position!", 1.5, "ok")
		end
	end, "Teleport Waypoint #" .. slot, function()
		local cf = CONFIG.waypoints[slot]
		if cf then
			teleportTo(cf)
		else
			toast("Empty Slot", "Save Waypoint #" .. slot .. " first", 1.5, "err")
		end
	end)
end

-- ============================================================================
-- 8) WORLD & PROTECTIONS PAGE
-- ============================================================================
section(pageSrv, "Character Protections")
toggleRow(pageSrv, "antiStunOn", "Anti-Taze / Anti-Stun", "Prevents taser from freezing you or locking your Backpack UI",
	CONFIG.noStayStunned, function(v) CONFIG.noStayStunned = v end)
toggleRow(pageSrv, "antiArrestOn", "Anti-Arrest (Auto-Break Cuffs)", "Instantly respawns & returns you to your spot if a Guard cuffs you",
	CONFIG.antiArrest, function(v) CONFIG.antiArrest = v end)
toggleRow(pageSrv, "respawnDeathOn", "Respawn Where You Died", "Auto-respawns via loadchar and teleports back to your death spot",
	CONFIG.respawnAtDeath, function(v)
		CONFIG.respawnAtDeath = v
		if v then CONFIG.instantRespawn = true end
	end)
toggleRow(pageSrv, "instantRespawnOn", "Instant Respawn (No 5s Wait)", "Immediately spawns a fresh character when you die",
	CONFIG.instantRespawn, function(v) CONFIG.instantRespawn = v end)
toggleRow(pageSrv, "antiShieldOn", "Anti-Riot Shield", "Strips Riot Shields from Guards so your bullets never get blocked",
	CONFIG.antiShield, function(v) CONFIG.antiShield = v end)
toggleRow(pageSrv, "antiCrimPadOn", "Anti-Criminal Spawn Pad", "Lets Guards walk into Criminal Base without getting team-switched",
	CONFIG.antiCrimPad, function(v)
		CONFIG.antiCrimPad = v
		setAntiCrimPad(v)
	end)

section(pageSrv, "World & Map Control")
toggleRow(pageSrv, "doorsRemovedOn", "Remove All Doors & Fences (Reversible)", "Hides all prison doors, cell bars, and fences — toggle OFF to restore!",
	false, function(v) setDoorsRemoved(v) end)
buttonRow(pageSrv, "Open Prison Main Gate", function() openGate() end)
toggleRow(pageSrv, "gateLoopOn", "Loop Open Prison Gate", "Continuously opens the main prison gate on an interval",
	false, function() end)
sliderRow(pageSrv, "Gate Loop Interval", 1, 6, CONFIG.gateSpamInterval,
	function(v) CONFIG.gateSpamInterval = math.max(0.5, v) end, " s")

section(pageSrv, "Server Utilities")
pairRow(pageSrv, "Rebind Remotes", function() rebindRemotes(6) end,
	"Rejoin Current Server", function()
		toast("Rejoining", "Reconnecting to Prison Life...", 2)
		task.wait(0.3)
		pcall(function() teleportSvc:Teleport(game.PlaceId, lp) end)
	end)

-- ============================================================================
-- 9) SETUP & CONFIG PAGE
-- ============================================================================
section(pageCfg, "Hotkeys & Chat Commands")
infoRow(pageCfg, "PC HOTKEYS:\n"
	.. "RightCtrl / U = Toggle UI · G = Kill Aura · H = Arrest Aura · J = Taze Loop\n"
	.. "F = Super Punch · Z = Fly · F3 = Open Gate\n\n"
	.. "CHAT COMMANDS (Type in chat):\n"
	.. ":kill [name/all] · :loopkill [name] · :unloopkill [name] · :fling [name/all]\n"
	.. ":arrest [name/all] · :taze [name/all] · :goto [name] · :view [name] · :unview\n"
	.. ":guns · :mod · :car · :gate · :doors · :nodoors · :re · :crim · :guard · :inmate", 118)

section(pageCfg, "Configuration Persistence")
pairRow(pageCfg, "Save Config", function()
	if writefile then
		pcall(function() writefile("RiotHub_v4_Config.json", httpSvc:JSONEncode(CONFIG)) end)
		toast("Config Saved", "Saved to RiotHub_v4_Config.json", 2, "ok")
	else
		getGenv().RiotHubConfig = CONFIG
		toast("Config Cached", "Saved to executor memory", 2, "ok")
	end
end, "Load Config", function()
	local raw
	if readfile and isfile and isfile("RiotHub_v4_Config.json") then
		raw = readfile("RiotHub_v4_Config.json")
	elseif getGenv().RiotHubConfig then
		raw = httpSvc:JSONEncode(getGenv().RiotHubConfig)
	end
	if raw then
		pcall(function()
			local loaded = httpSvc:JSONDecode(raw)
			for k, v in pairs(loaded) do
				if type(v) ~= "table" then CONFIG[k] = v end
			end
		end)
		toast("Config Loaded", "Settings restored!", 2, "ok")
	else
		toast("No Saved Config", "Click Save Config first", 2, "err")
	end
end)

toggleRow(pageCfg, "safePacingOn", "Strict Server Pacing Delay", "Adds delay between ItemHandler pulls (only needed on custom anti-cheat servers)",
	CONFIG.safePacing, function(v) CONFIG.safePacing = v end)
toggleRow(pageCfg, "reduceAnimOn", "Reduce UI Animations", "Snappier transitions for low-end mobile devices",
	CONFIG.reduceAnim, function(v)
		CONFIG.reduceAnim = v
		state.uiAnim = v and 0 or 0.14
	end)

section(pageCfg, "Session Control")
pairRow(pageCfg, "Hide Hub Window", function() window.Visible = false end,
	"Unload RiotHub Completely", function()
		if getGenv().RiotHub and getGenv().RiotHub.Unload then
			getGenv().RiotHub.Unload()
		end
	end)

-- ============================================================================
-- BACKGROUND MANAGERS (AURAS, LOOPKILL, AUTO-RELOAD, STATS)
-- ============================================================================
-- 1. Combat Aura + Loopkill Loop
task.spawn(function()
	while not state.detached do
		task.wait(math.max(CONFIG.killAuraRate, 0.12))
		local myRoot = charRoot()
		if myRoot and not state.flinging then
			-- Kill Aura
			if state.toggles.auraKillOn then
				for _, plr in ipairs(plrs:GetPlayers()) do
					if plr ~= lp and selTarget(plr, "auraTargets") then
						local ch = plr.Character
						local hum = charHumanoid(plr)
						local theirRoot = charRoot(plr)
						if ch and hum and hum.Health > 0 and theirRoot then
							local d = (theirRoot.Position - myRoot.Position).Magnitude
							if d <= CONFIG.killAuraRadius then
								local ff = ch:FindFirstChildOfClass("ForceField")
								if not (ff and CONFIG.killAuraIgnoreFF) then
									killTarget(plr)
								end
							end
						end
					end
				end
			end

			-- Persistent Loopkill Targets
			for targetName, active in pairs(state.loopKillTargets) do
				if active then
					local t = plrs:FindFirstChild(targetName)
					local hum = t and charHumanoid(t)
					local ff = t and t.Character and t.Character:FindFirstChildOfClass("ForceField")
					if t and hum and hum.Health > 0 and not ff then
						killTarget(t)
					end
				end
			end

			-- Arrest Aura
			if state.toggles.auraArrestOn then
				for _, plr in ipairs(arrestables()) do
					local theirRoot = charRoot(plr)
					if theirRoot and (theirRoot.Position - myRoot.Position).Magnitude <= CONFIG.arrestAuraRadius then
						if arrestTarget(plr) then
							state.arrestCount = state.arrestCount + 1
						end
						task.wait(CONFIG.arrestAuraRate)
						break
					end
				end
			end
		end
	end
end)

-- 2. Taze Aura & Loop-Taze Loop
task.spawn(function()
	while not state.detached do
		task.wait(0.45)
		local taser = getTaser()
		if taser then
			if state.toggles.auraTazeOn then
				for _, plr in ipairs(plrs:GetPlayers()) do
					if plr ~= lp and not isGuard(plr) and charHumanoid(plr) and charHumanoid(plr).Health > 0 then
						tazeTarget(plr, taser)
						task.wait(0.08)
					end
				end
			end
			for targetName, active in pairs(state.loopTazeTargets) do
				if active then
					local t = plrs:FindFirstChild(targetName)
					if t and charHumanoid(t) and charHumanoid(t).Health > 0 then
						tazeTarget(t, taser)
					end
				end
			end
		end
	end
end)

-- 3. Auto Server Reload Loop (keeps server-side gun magazine full at all times)
task.spawn(function()
	while not state.detached do
		task.wait(0.8)
		if CONFIG.autoReloadServer and lp.Character then
			local tool = lp.Character:FindFirstChildWhichIsA("Tool")
			if tool and tool:FindFirstChild("GunStates") then
				reloadToolServer(tool)
			end
		end
	end
end)

-- 4. Gate Spam & Chams Refresh
task.spawn(function()
	while not state.detached do
		task.wait(CONFIG.gateSpamInterval)
		if state.toggles.gateLoopOn then openGate() end
	end
end)

task.spawn(function()
	while not state.detached do
		task.wait(2)
		if state.toggles.chamsOn then
			for _, plr in ipairs(plrs:GetPlayers()) do
				if plr ~= lp then applyChams(plr) end
			end
		end
	end
end)

-- 5. FPS + Status Bar Ticker
local frameCount = 0
connect(runSvc.Heartbeat, function() frameCount = frameCount + 1 end)
task.spawn(function()
	while not state.detached do
		task.wait(1)
		state.fps = frameCount
		frameCount = 0
		pcall(function()
			statusLabel.Text = "v4.0 · " .. tostring(state.fps) .. " fps · "
				.. tostring(#plrs:GetPlayers()) .. " plrs · remotes: M"
				.. (meleeEvent and "+" or "-") .. " S"
				.. (shootingEvent and "+" or "-") .. " R"
				.. (reloadEvent and "+" or "-") .. " I"
				.. (ItemHandler and "+" or "-")
			statKills.Text = tostring(state.killCounter) .. " kills/hits"
			statArrests.Text = tostring(state.arrestCount) .. " cuffs"
			statItems.Text = tostring(state.itemCount) .. " items"
		end)
	end
end)

-- ============================================================================
-- INPUTS, HOTKEYS & CHAT COMMAND ENGINE
-- ============================================================================
-- Screen Tap Gestures (Click-TP & Click-Arrest)
connect(uis.InputBegan, function(input, processed)
	if state.detached or processed then return end
	if not (input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1) then
		return
	end
	local camera = currentCam()
	if not camera then return end
	local pos = input.Position
	if state.toggles.clickTpOn then
		pcall(function()
			local ray = camera:ViewportPointToRay(pos.X, pos.Y)
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000)
			if hit and hit.Position then
				teleportTo(CFrame.new(hit.Position))
			end
		end)
	end
	if state.toggles.clickArrestOn then
		pcall(function()
			local ray = camera:ViewportPointToRay(pos.X, pos.Y)
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000)
			if hit and hit.Instance then
				local ch = hit.Instance:FindFirstAncestorOfClass("Model")
				local plr = ch and plrs:GetPlayerFromCharacter(ch)
				if plr and plr ~= lp and not isGuard(plr) then
					arrestTarget(plr)
				end
			end
		end)
	end
end)

-- Keyboard Shortcuts
connect(uis.InputBegan, function(input, processed)
	if state.detached or processed then return end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.RightControl or kc == Enum.KeyCode.U then
		window.Visible = not window.Visible
		if window.Visible then popWindow() end
	elseif kc == Enum.KeyCode.G then
		local sw = state.switches.auraKillOn
		if sw then sw.Set(not state.toggles.auraKillOn) end
	elseif kc == Enum.KeyCode.H then
		local sw = state.switches.auraArrestOn
		if sw then sw.Set(not state.toggles.auraArrestOn) end
	elseif kc == Enum.KeyCode.J then
		local sw = state.switches.auraTazeOn
		if sw then sw.Set(not state.toggles.auraTazeOn) end
	elseif kc == Enum.KeyCode.Z then
		local sw = state.switches.flyOn
		if sw then sw.Set(not state.toggles.flyOn) end
	elseif kc == Enum.KeyCode.F then
		if CONFIG.superPunch then triggerSuperPunch() end
	elseif kc == Enum.KeyCode.F3 then
		openGate()
	end
end)

-- PrizzLife / Tiger Admin Style Chat Commands (:kill, :fling, :car, :re, etc.)
connect(lp.Chatted, function(msg)
	if state.detached or not CONFIG.chatCmds then return end
	if string.sub(msg, 1, 1) ~= ":" and string.sub(msg, 1, 1) ~= ";" then return end
	local parts = string.split(string.sub(msg, 2), " ")
	local cmd = string.lower(parts[1] or "")
	local arg = parts[2] or ""

	if cmd == "kill" then
		if string.lower(arg) == "all" or arg == "" then
			killAll(CONFIG.killAuraMode)
		else
			local t = findPlayerByQuery(arg)
			if t then killTarget(t) end
		end
	elseif cmd == "loopkill" or cmd == "lk" then
		local t = findPlayerByQuery(arg)
		if t then
			state.loopKillTargets[t.Name] = true
			toast("Loopkill", "Locked onto " .. t.Name, 2, "ok")
		end
	elseif cmd == "unloopkill" or cmd == "unlk" then
		if string.lower(arg) == "all" or arg == "" then
			state.loopKillTargets = {}
		else
			local t = findPlayerByQuery(arg)
			if t then state.loopKillTargets[t.Name] = nil end
		end
		toast("Loopkill", "Stopped loopkill", 1.8, "ok")
	elseif cmd == "fling" then
		if string.lower(arg) == "all" then
			flingAll()
		else
			local t = findPlayerByQuery(arg) or getActiveTarget()
			if t then flingTarget(t, 1.8) end
		end
	elseif cmd == "arrest" then
		if string.lower(arg) == "all" or arg == "" then
			arrestAll()
		else
			local t = findPlayerByQuery(arg)
			if t then arrestTarget(t) end
		end
	elseif cmd == "taze" then
		if string.lower(arg) == "all" or arg == "" then
			tazeAll()
		else
			local t = findPlayerByQuery(arg)
			if t then tazeTarget(t) end
		end
	elseif cmd == "goto" or cmd == "to" then
		local t = findPlayerByQuery(arg)
		if t and charRoot(t) then
			teleportTo(charRoot(t).CFrame * CFrame.new(0, 0, 2.5))
		end
	elseif cmd == "view" or cmd == "spectate" then
		local t = findPlayerByQuery(arg)
		if t and charHumanoid(t) and currentCam() then
			currentCam().CameraSubject = charHumanoid(t)
		end
	elseif cmd == "unview" or cmd == "unspectate" then
		if charHumanoid() and currentCam() then
			currentCam().CameraSubject = charHumanoid()
		end
	elseif cmd == "guns" or cmd == "allguns" then
		giveAllLoot(true)
	elseif cmd == "mod" or cmd == "modguns" then
		modAllGuns()
	elseif cmd == "car" or cmd == "v" then
		spawnCarHere("Sedan")
	elseif cmd == "gate" then
		openGate()
	elseif cmd == "nodoors" or cmd == "doors" then
		setDoorsRemoved(cmd == "nodoors")
	elseif cmd == "re" or cmd == "refresh" then
		refreshCharacterInPlace()
	elseif cmd == "crim" or cmd == "criminal" then
		switchTeam("Criminal")
	elseif cmd == "guard" or cmd == "cop" then
		switchTeam("Guard")
	elseif cmd == "inmate" or cmd == "prisoner" then
		switchTeam("Inmate")
	elseif cmd == "neutral" then
		switchTeam("Neutral")
	end
end)

-- Anti-AFK
connect(lp.Idled, function()
	if not CONFIG.antiAfk then return end
	pcall(function()
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
end)

-- Death & Respawn Handler (Instant Respawn + Respawn Where You Died + Auto-Rearm)
local function hookCharacter(ch)
	if not ch then return end
	local hum = ch:WaitForChild("Humanoid", 6)
	if not hum then return end
	connect(hum.Died, function()
		if state.detached then return end
		local r = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
		if r then state.lastDeathCF = r.CFrame end
		if CONFIG.instantRespawn or CONFIG.respawnAtDeath then
			task.wait(0.35)
			local loadChar = getRemote("loadchar")
			if loadChar then
				vsafe(function() loadChar:InvokeServer(lp.Name) end)
			end
		end
	end)
end

if lp.Character then task.spawn(hookCharacter, lp.Character) end

connect(lp.CharacterAdded, function(ch)
	task.spawn(hookCharacter, ch)
	local newRoot = ch:WaitForChild("HumanoidRootPart", 6)
	task.wait(0.15)
	if CONFIG.respawnAtDeath and state.lastDeathCF and newRoot then
		pcall(function() newRoot.CFrame = state.lastDeathCF end)
	end
	if CONFIG.autoRearm then
		giveAllLoot(true)
	end
	if state.toggles.chamsOn then
		task.delay(0.5, function()
			for _, plr in ipairs(plrs:GetPlayers()) do
				if plr ~= lp then applyChams(plr) end
			end
		end)
	end
end)

connect(plrs.PlayerAdded, function(plr)
	refreshTargetDropdown()
	if not state.toggles.espOn then return end
	task.wait(1)
	if not state.detached and state.toggles.espOn and not state.espUnits[plr] then
		state.espUnits[plr] = buildEspUnit(plr)
	end
end)

connect(plrs.PlayerRemoving, function(plr)
	destroyEspUnit(plr)
	destroyTracer(plr)
	task.defer(refreshTargetDropdown)
end)

-- ============================================================================
-- BOOT & GLOBAL EXPORT
-- ============================================================================
buildFovRing()
setupAimbot()
setupTriggerBot()
setupSilentAim()
setupEspFrame()
refreshTargetDropdown()

getGenv().RiotHub = {
	Unload = function()
		state.detached = true
		pcall(function() setDoorsRemoved(false) end)
		pcall(function() setAntiCrimPad(false) end)
		pcall(function() setFullbright(false) end)
		for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
		for key, _ in pairs(state.tracers) do destroyTracer(key) end
		for _, plr in ipairs(plrs:GetPlayers()) do clearChams(plr) end
		for part, orig in pairs(state.hitboxSaved) do
			if part and part.Parent then
				pcall(function()
					part.Size = orig.Size
					part.Transparency = orig.Transparency
					part.CanCollide = orig.CanCollide
				end)
			end
		end
		pcall(function() screenGui:Destroy() end)
		pcall(function() if fovRing then fovRing:Destroy() end end)
		pcall(function() if espContainer then espContainer:Destroy() end end)
		if getgenv then getgenv().RiotHub = nil else _G.RiotHub = nil end
	end,
	log     = log,
	toast   = toast,
	config  = CONFIG,
	toggles = state.toggles,
}

log("RiotHub v4.0 armed for " .. lp.Name)
notify("RiotHub v4.0", "Loaded! Tap RH or press RightCtrl", 4)
toast("RiotHub v4.0 Ready", "Latest Prison Life Bypass + Admin Commands Active", 3.2, "ok")
