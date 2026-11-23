local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local DEFAULT_PRIORITY = 50

type Record = { name: string, module: ModuleScript, service: any, priority: number }

local records: { Record } = {}
local modulesByName: { [string]: any } = {}
local registered: { [ModuleScript]: boolean } = {}

local playerConnections: { [Player]: RBXScriptConnection } = {}
local lifecycleConnections: { RBXScriptConnection } = {}
local dispatchedCharacters: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local started = false
local shuttingDown = false

local function report(moduleName: string, phase: string, err: any)
	warn(string.format("%s failed in %s:\n%s", moduleName, phase, tostring(err)))
end

local function invoke(moduleName: string, phase: string, callback: (...any) -> any, ...: any)
	local ok, err = xpcall(callback, debug.traceback, ...)
	if not ok then
		report(moduleName, phase, err)
	end
end

local function register(module: ModuleScript, defaultPriority: number)
	local name = module.Name
	if
		registered[module]
		or name:find("_", 1, true)
		or (IS_SERVER and name:find("ServiceClient$"))
		or (not IS_SERVER and name:find("ServiceServer$"))
	then
		return
	end
	registered[module] = true

	local ok, result = xpcall(require, debug.traceback, module)
	if not ok then
		report(name, "require", result)
		return
	end

	if type(result) ~= "table" then
		warn(string.format("Ignored %s: expected a table, got %s.", module:GetFullName(), typeof(result)))
		return
	end

	if modulesByName[name] ~= nil then
		warn(
			string.format(
				"Duplicate module name '%s' at %s. The first registered module remains accessible through Get().",
				name,
				module:GetFullName()
			)
		)
	else
		modulesByName[name] = result
	end

	local attribute = module:GetAttribute("Priority")
	table.insert(records, {
		name = name,
		module = module,
		service = result,
		priority = if typeof(attribute) == "number" then attribute else defaultPriority,
	})
end

local function dispatch(phase: string, ...: any)
	for _, record in records do
		local callback = record.service[phase]
		if type(callback) == "function" then
			task.spawn(invoke, record.name, phase, callback, ...)
		end
	end
end

local function bindFrame(signal: RBXScriptSignal, phase: string)
	table.insert(
		lifecycleConnections,
		signal:Connect(function(deltaTime)
			for _, record in records do
				local callback = record.service[phase]
				if type(callback) == "function" then
					invoke(record.name, phase, callback, deltaTime)
				end
			end
		end)
	)
end

local function dispatchCharacter(player: Player, character: Model)
	if shuttingDown or dispatchedCharacters[character] then
		return
	end
	dispatchedCharacters[character] = true
	dispatch("onCharacterAdded", character, player)
end

local function bindPlayer(player: Player)
	if shuttingDown or playerConnections[player] then
		return
	end

	playerConnections[player] = player.CharacterAdded:Connect(function(character)
		dispatchCharacter(player, character)
	end)

	dispatch("onPlayerAdded", player)

	if player.Character then
		dispatchCharacter(player, player.Character)
	end
end

local function unbindPlayer(player: Player)
	dispatch("onPlayerRemoving", player)

	local connection = playerConnections[player]
	if connection then
		connection:Disconnect()
		playerConnections[player] = nil
	end
end

local Loader = {}

function Loader.Get(name: string): any
	return modulesByName[name]
end

function Loader.init(input: Instance | { Instance }, priority: number?)
	assert(not started, "init() cannot be called after Start().")

	local roots: { Instance } = if typeof(input) == "table" then input else { input :: Instance }
	local defaultPriority = priority or DEFAULT_PRIORITY

	for _, root in roots do
		if root:IsA("ModuleScript") then
			register(root, defaultPriority)
		elseif root:IsA("Folder") then
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("ModuleScript") then
					register(descendant, defaultPriority)
				end
			end
		else
			warn(string.format("Ignored unsupported root: %s", root:GetFullName()))
		end
	end

	table.sort(records, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.module:GetFullName() < b.module:GetFullName()
	end)
end

function Loader.Start()
	assert(not started, "Start() has already been called.")
	started = true

	dispatch("init")

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
	table.insert(lifecycleConnections, Players.PlayerAdded:Connect(bindPlayer))
	table.insert(lifecycleConnections, Players.PlayerRemoving:Connect(unbindPlayer))

	if not IS_SERVER then
		bindFrame(RunService.PreRender, "onPreRender")
	end

	for _, record in records do
		if type(record.service.onHeartbeat) == "function" then
			bindFrame(RunService.Heartbeat, "onHeartbeat")
			break
		end
	end
end

function Loader.Destroy()
	if shuttingDown then
		return
	end
	shuttingDown = true

	for _, connection in lifecycleConnections do
		connection:Disconnect()
	end
	table.clear(lifecycleConnections)

	for _, connection in playerConnections do
		connection:Disconnect()
	end
	table.clear(playerConnections)
end

return Loader
