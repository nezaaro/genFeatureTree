local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Source.Game.Modules.Configs)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Network = require(ReplicatedStorage.Source.Game.Modules.Network)
local Signals = require(ReplicatedStorage.Source.Game.Modules.Signals)
local StateMachine = require(ReplicatedStorage.Source.Game.Modules.StateMachine)
local CombatTypes = require(ReplicatedStorage.Source.Features.Combat.Modules.CombatTypes)
local HitboxServer = require(script.Parent.HitboxServer)

local States = Configs.Combat.States
local Reasons = Configs.Combat.Reject
local rng = Random.new()

export type HitOptions = {
	Damage: number,
	MaxTargets: number?,
	Duration: number?,
	Resolution: number?,
}

local SessionServer = {}
SessionServer.__index = SessionServer
export type SessionServer = typeof(setmetatable(
	{} :: {
		Player: Player,
		WeaponId: string?,
		Config: CombatTypes.WeaponConfig?,
		Category: CombatTypes.CategoryServer?,
		CategoryState: any,
		Machine: StateMachine.StateMachine,
		Sequence: number,
		LastAttackAt: number,
		Plan: CombatTypes.AttackPlan?,
		_trove: any,
		_characterTrove: any,
		_hitbox: HitboxServer.HitboxServer?,
		_hitboxModel: Instance?,
	},
	SessionServer
))

local function getLivingHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end

	return nil
end

local function findWeaponModel(character: Model, weaponId: string): Instance?
	local weapon = character:FindFirstChild(weaponId, true)
	if weapon and (weapon:IsA("Model") or weapon:IsA("BasePart")) then
		return weapon
	end

	return nil
end

local function getMaxDuration(config: CombatTypes.WeaponConfig): number
	local timing = config.Timing
	return timing and timing.MaxDuration or Configs.Combat.MaxAttackDuration
end

local function canDamage(attacker: Player, target: Model, humanoid: Humanoid): boolean
	if humanoid.Health <= 0 or target == attacker.Character or target:FindFirstChildOfClass("ForceField") then
		return false
	end

	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer and attacker.Team ~= nil and targetPlayer.Team == attacker.Team then
		return false
	end

	return true
end

function SessionServer.new(player: Player): SessionServer
	local self = setmetatable({
		Player = player,
		WeaponId = nil,
		Config = nil,
		Category = nil,
		CategoryState = nil,
		Machine = StateMachine.new({
			[States.Idle] = { Transitions = { States.Attacking } },
			[States.Attacking] = { Transitions = { States.Idle } },
		}, States.Idle),
		Sequence = 0,
		LastAttackAt = -math.huge,
		Plan = nil,
		_trove = Trove.new(),
		_characterTrove = Trove.new(),
		_hitbox = nil,
		_hitboxModel = nil,
	}, SessionServer)

	self._trove:Add(self._characterTrove)
	self._trove:Add(self.Machine)
	self._trove:Add(function()
		self:_DisposeHitbox()
	end)

	return self
end

function SessionServer.OnCharacterAdded(self: SessionServer, character: Model)
	self._characterTrove:Clean()
	self:SetWeapon(nil, nil, nil)
	self.Sequence = 0
	self.LastAttackAt = -math.huge

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self._characterTrove:Connect(humanoid.Died, function()
			self:EndAttack(false)
		end)
	end
end

function SessionServer.Destroy(self: SessionServer)
	self.Plan = nil
	self._trove:Destroy()
end

function SessionServer.SetWeapon(
	self: SessionServer,
	weaponId: string?,
	config: CombatTypes.WeaponConfig?,
	category: CombatTypes.CategoryServer?
)
	self:EndAttack(false)
	self:_DisposeHitbox()

	self.WeaponId = weaponId
	self.Config = config
	self.Category = category
	self.CategoryState = if config and category then category.CreateState(config) else nil
end

function SessionServer.RequestAttack(self: SessionServer, request: CombatTypes.AttackRequest)
	local sequence = request.sequence
	local config, category = self.Config, self.Category

	if not config or not category or request.weaponId ~= self.WeaponId then
		return self:Reject(sequence, Reasons.NotEquipped)
	end
	if sequence <= self.Sequence then
		return self:Reject(sequence, Reasons.BadSequence)
	end

	local now = os.clock()

	if self.Machine.Current == States.Attacking then
		local plan = self.Plan
		if plan and plan.StartedAt and now - plan.StartedAt <= getMaxDuration(config) then
			return self:Reject(sequence, Reasons.AttackActive)
		end
		self:EndAttack(false)
	end

	if not getLivingHumanoid(self.Player) then
		return self:Reject(sequence, Reasons.Dead)
	end
	if now - self.LastAttackAt < config.Stats.Cooldown then
		return self:Reject(sequence, Reasons.Cooldown)
	end

	local plan, reason = category.Begin(self.CategoryState, config, request, now)
	if not plan then
		return self:Reject(sequence, reason or Reasons.BadRequest)
	end

	plan.Sequence = sequence
	plan.StartedAt = now

	self.Sequence = sequence
	self.LastAttackAt = now
	self.Plan = plan

	self:_SetState(States.Attacking, plan.AttackId, sequence)
	Signals.AttackStarted:Fire(self.Player, self.WeaponId, plan.AttackId)
end

function SessionServer.HandleMarker(self: SessionServer, sequence: number, marker: string)
	local plan, config = self.Plan, self.Config
	if not plan or not config or plan.Sequence ~= sequence then
		return
	end

	if marker == Configs.Combat.EndMarker then
		return self:EndAttack(true)
	end

	if plan.StartedAt and os.clock() - plan.StartedAt > getMaxDuration(config) then
		return self:EndAttack(false)
	end

	local category = self.Category
	if category then
		category.OnMarker(self, plan, marker)
	end
end

function SessionServer.EndAttack(self: SessionServer, completed: boolean)
	local plan = self.Plan
	if not plan then
		return
	end

	self.Plan = nil
	self:_StopHitbox()
	self:_SetState(States.Idle, plan.AttackId, plan.Sequence or 0)
	Signals.AttackEnded:Fire(self.Player, self.WeaponId, plan.AttackId, completed)
end

function SessionServer.StartHitbox(self: SessionServer, options: HitOptions): boolean
	local config, weaponId = self.Config, self.WeaponId
	local character = self.Player.Character
	if not self.Plan or not config or not weaponId or not character or not getLivingHumanoid(self.Player) then
		return false
	end

	local weapon = findWeaponModel(character, weaponId)
	if not weapon then
		return false
	end

	local hitbox = self._hitbox
	if hitbox and hitbox:IsActive() then
		return false
	end

	if not hitbox or weapon ~= self._hitboxModel then
		self:_DisposeHitbox()
		hitbox = HitboxServer.new(weapon)
		self._hitbox = hitbox
		self._hitboxModel = weapon
	end
	if not hitbox then
		return false
	end

	local damage = options.Damage
	local ok, started = pcall(hitbox.Start, hitbox, {
		Character = character,
		WeaponModel = weapon,
		Damage = damage,
		MaxTargets = options.MaxTargets or Configs.Combat.DefaultMaxTargets,
		OnConfirmedHit = function(target: Model)
			self:_ConfirmHit(target, damage)
		end,
	}, {
		Duration = options.Duration,
		Resolution = options.Resolution,
	})

	if not ok then
		warn(`SessionServer: hitbox failed to start ({started})`)
		return false
	end

	return started
end

function SessionServer.Reject(self: SessionServer, sequence: number, reason: string)
	local category = self.Category
	if sequence ~= 0 and category and category.OnRejected then
		category.OnRejected(self.CategoryState, reason)
	end

	Network.packets.CombatReject.sendTo({ sequence = sequence, reason = reason }, self.Player)
end

function SessionServer._SetState(self: SessionServer, state: string, attackId: string, sequence: number)
	if not self.Machine:Set(state) then
		return
	end

	Network.packets.CombatState.sendToAll({
		actorId = self.Player.UserId,
		state = state,
		attackId = attackId,
		sequence = sequence,
	})
end

function SessionServer._ConfirmHit(self: SessionServer, target: Model, baseDamage: number)
	local config = self.Config
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not config or not humanoid or not canDamage(self.Player, target, humanoid) then
		return
	end

	local stats = config.Stats
	local critChance = stats.CritChance or 0
	local isCrit = critChance > 0 and rng:NextNumber() < critChance
	local damage = if isCrit then baseDamage * (stats.CritMultiplier or 1) else baseDamage

	humanoid:TakeDamage(damage)

	Network.packets.CombatHit.sendToAll({
		attackerId = self.Player.UserId,
		target = target,
		damage = damage,
		isCrit = isCrit,
	})
	Signals.HitConfirmed:Fire(self.Player, target, damage, isCrit)
end

function SessionServer._StopHitbox(self: SessionServer)
	local hitbox = self._hitbox
	if hitbox then
		hitbox:Stop()
	end
end

function SessionServer._DisposeHitbox(self: SessionServer)
	local hitbox = self._hitbox
	if hitbox then
		self._hitbox = nil
		self._hitboxModel = nil
		hitbox:Destroy()
	end
end

return SessionServer
