local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Animator = require(ReplicatedStorage.Source.Core.Platform.Animator)
local Configs = require(ReplicatedStorage.Source.Game.Modules.Configs)
local Network = require(ReplicatedStorage.Source.Game.Modules.Network)
local Signals = require(ReplicatedStorage.Source.Game.Modules.Signals)
local CombatTypes = require(script.Parent.Modules.CombatTypes)
local WeaponRegistry = require(script.Parent.Modules.WeaponRegistry)

local localPlayer = Players.LocalPlayer

type Equipped = {
	WeaponId: string,
	Config: CombatTypes.WeaponConfig,
	Category: CombatTypes.CategoryClient,
	State: any,
}

type ActiveAttack = {
	Track: AnimationTrack,
	Sequence: number,
	Trove: any,
}

local categories: { [string]: CombatTypes.CategoryClient } = {}
local equipped: Equipped? = nil
local lastAttackAt = -math.huge
local sequence = 0
local activeAttack: ActiveAttack? = nil
local actorStates: { [number]: string } = {}

local CombatServiceClient = {}

local function getCategory(name: string): CombatTypes.CategoryClient?
	local cached = categories[name]
	if cached then
		return cached
	end

	local folder = script.Parent.Categories:FindFirstChild(name)
	local module = folder and folder:FindFirstChild(`{name}Client`)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end

	local ok, definition = pcall(require, module)
	if not ok or type(definition) ~= "table" then
		warn(`CombatServiceClient: failed to load category '{name}'`)
		return nil
	end

	categories[name] = definition
	return definition
end

local function stopAttack()
	local attack = activeAttack
	if attack then
		activeAttack = nil
		attack.Track:Stop(0.1)
	end
end

function CombatServiceClient.Equip(weaponId: string)
	local entry = if weaponId == "" then nil else WeaponRegistry.Get(weaponId)
	local category = entry and getCategory(entry.Category)
	if weaponId ~= "" and not (entry and category) then
		warn(`CombatServiceClient: unknown weapon '{weaponId}'`)
		return
	end

	stopAttack()
	if entry and category then
		equipped = {
			WeaponId = weaponId :: string,
			Config = entry.Config,
			Category = category,
			State = category.CreateState(entry.Config),
		}
	else
		equipped = nil
	end

	Network.packets.CombatEquip.send({ weaponId = weaponId })
end

function CombatServiceClient.Attack(): boolean
	local weapon = equipped
	if not weapon or activeAttack then
		return false
	end

	local now = os.clock()
	if now - lastAttackAt < weapon.Config.Stats.Cooldown then
		return false
	end

	local character = localPlayer.Character
	local plan = weapon.Category.Prepare(weapon.State, weapon.Config, now)
	if not character or not plan then
		return false
	end

	local track = Animator.Play(character, plan.AnimationId, 0.05)
	if not track then
		return false
	end

	weapon.Category.Commit(weapon.State, plan, now)
	lastAttackAt = now
	sequence += 1

	local attackSequence = sequence
	local attackTrove = Trove.new()
	local attack: ActiveAttack = { Track = track, Sequence = attackSequence, Trove = attackTrove }
	activeAttack = attack

	local endSent = false
	local function sendEnd()
		if not endSent then
			endSent = true
			Network.packets.CombatMarker.send({ sequence = attackSequence, marker = Configs.Combat.EndMarker })
		end
	end

	for _, marker in weapon.Category.Markers do
		attackTrove:Connect(track:GetMarkerReachedSignal(marker), function()
			Network.packets.CombatMarker.send({ sequence = attackSequence, marker = marker })
		end)
	end
	attackTrove:Connect(track:GetMarkerReachedSignal(Configs.Combat.EndMarker), sendEnd)

	track.Stopped:Once(function()
		sendEnd()
		attackTrove:Destroy()
		if activeAttack == attack then
			activeAttack = nil
		end
	end)

	Network.packets.CombatRequest.send({
		weaponId = weapon.WeaponId,
		attackId = plan.AttackId,
		sequence = attackSequence,
		aim = plan.Aim,
	})
	Signals.AttackStarted:Fire(localPlayer, weapon.WeaponId, plan.AttackId)

	return true
end

function CombatServiceClient.GetState(player: Player): string
	return actorStates[player.UserId] or Configs.Combat.States.Idle
end

function CombatServiceClient.GetEquippedWeapon(): string?
	local weapon = equipped
	return weapon and weapon.WeaponId
end

function CombatServiceClient.init()
	print(`{script.Name} initialized!`)
	WeaponRegistry.Build()

	Network.packets.CombatState.listen(function(data)
		actorStates[data.actorId] = data.state
		Signals.CombatStateChanged:Fire(data.actorId, data.state, data.attackId)
	end)

	Network.packets.CombatHit.listen(function(data)
		local attacker = Players:GetPlayerByUserId(data.attackerId)
		if attacker and data.target:IsA("Model") then
			Signals.HitConfirmed:Fire(attacker, data.target, data.damage, data.isCrit)
		end
	end)

	Network.packets.CombatReject.listen(function(data)
		Signals.AttackRejected:Fire(localPlayer, data.reason)

		if data.sequence == 0 then
			stopAttack()
			equipped = nil
		elseif data.sequence == sequence then
			local weapon = equipped
			if weapon and weapon.Category.OnRejected then
				weapon.Category.OnRejected(weapon.State, data.reason)
			end
			stopAttack()
		end
	end)
end

function CombatServiceClient.onPlayerRemoving(player: Player)
	actorStates[player.UserId] = nil
end

function CombatServiceClient.onCharacterAdded(character: Model, player: Player)
	if player ~= localPlayer then
		return
	end

	stopAttack()
	equipped = nil
	lastAttackAt = -math.huge
	sequence = 0

	character.Destroying:Once(function()
		Animator.Clear(character)
	end)
end

export type CombatServiceClient = typeof(CombatServiceClient) & {}
return CombatServiceClient
