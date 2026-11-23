local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Source.Game.Modules.Configs)
local Network = require(ReplicatedStorage.Source.Game.Modules.Network)
local SafeUnit = require(ReplicatedStorage.Source.Game.Math.SafeUnit)
local CombatTypes = require(ReplicatedStorage.Source.Features.Combat.Modules.CombatTypes)
local WeaponRegistry = require(ReplicatedStorage.Source.Features.Combat.Modules.WeaponRegistry)
local SessionServer = require(script.Parent.Classes.SessionServer)

local MAX_ID_LENGTH = Configs.Combat.MaxIdLength
local Reasons = Configs.Combat.Reject

local sessions: { [Player]: SessionServer.SessionServer } = {}
local categories: { [string]: CombatTypes.CategoryServer } = {}
local equipValidator: ((player: Player, weaponId: string) -> boolean)? = nil

local CombatServiceServer = {}

function CombatServiceServer.RegisterCategory(name: string, definition: CombatTypes.CategoryServer)
	assert(
		type(definition) == "table"
			and type(definition.CreateState) == "function"
			and type(definition.Begin) == "function"
			and type(definition.OnMarker) == "function",
		`Category '{name}' must implement CreateState, Begin and OnMarker`
	)
	assert(not categories[name], `Category '{name}' is already registered`)

	categories[name] = definition
end

local function loadCategoryFolders()
	local modules = script.Parent:FindFirstChild("Categories")
	if not modules then
		return
	end

	for _, folder in modules:GetChildren() do
		local module = folder:FindFirstChild(`{folder.Name}Server`)
		if module and module:IsA("ModuleScript") then
			local ok, err = pcall(function()
				CombatServiceServer.RegisterCategory(folder.Name, (require :: any)(module))
			end)
			if not ok then
				warn(`CombatServiceServer: failed to load category '{folder.Name}': {err}`)
			end
		end
	end
end

function CombatServiceServer.SetEquipValidator(validator: ((player: Player, weaponId: string) -> boolean)?)
	equipValidator = validator
end

function CombatServiceServer.GetState(player: Player): string
	local session = sessions[player]
	return session and session.Machine.Current or Configs.Combat.States.Idle
end

local function onEquip(data: { weaponId: string }, player: Player?)
	if not player then
		return
	end

	local session = sessions[player]
	if not session then
		return
	end

	local weaponId = data.weaponId
	if weaponId == "" then
		return session:SetWeapon(nil, nil, nil)
	end

	session:SetWeapon(nil, nil, nil)
	if #weaponId > MAX_ID_LENGTH then
		return session:Reject(0, Reasons.BadRequest)
	end

	local entry = WeaponRegistry.Get(weaponId)
	local category = entry and categories[entry.Category]
	if not entry or not category then
		return session:Reject(0, Reasons.UnknownWeapon)
	end
	if equipValidator and not equipValidator(player, weaponId) then
		return session:Reject(0, Reasons.NotAllowed)
	end

	session:SetWeapon(weaponId, entry.Config, category)
end

local function onRequest(data: CombatTypes.AttackRequest, player: Player?)
	if not player then
		return
	end

	local session = sessions[player]
	if not session then
		return
	end

	if #data.weaponId > MAX_ID_LENGTH or #data.attackId > MAX_ID_LENGTH then
		return session:Reject(data.sequence, Reasons.BadRequest)
	end

	data.aim = if data.aim then SafeUnit(data.aim) else nil
	session:RequestAttack(data)
end

local function onMarker(data: { sequence: number, marker: string }, player: Player?)
	if not player then
		return
	end

	local session = sessions[player]
	if session and #data.marker <= MAX_ID_LENGTH then
		session:HandleMarker(data.sequence, data.marker)
	end
end

function CombatServiceServer.init()
	print(`{script.Name} initialized!`)
	WeaponRegistry.Build()
	loadCategoryFolders()

	Network.packets.CombatEquip.listen(onEquip)
	Network.packets.CombatRequest.listen(onRequest)
	Network.packets.CombatMarker.listen(onMarker)
end

function CombatServiceServer.onPlayerAdded(player: Player)
	if not sessions[player] then
		sessions[player] = SessionServer.new(player)
	end
end

function CombatServiceServer.onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		sessions[player] = nil
		session:Destroy()
	end
end

function CombatServiceServer.onCharacterAdded(character: Model, player: Player)
	local session = sessions[player]
	if session then
		session:OnCharacterAdded(character)
	end
end

export type CombatServiceServer = typeof(CombatServiceServer) & {}
return CombatServiceServer
