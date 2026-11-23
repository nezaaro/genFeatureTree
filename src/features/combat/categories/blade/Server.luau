local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Source.Game.Modules.Configs)
local CombatTypes = require(ReplicatedStorage.Source.Features.Combat.Modules.CombatTypes)
local BladeUtils = require(ReplicatedStorage.Source.Features.Combat.Categories.Blade.BladeUtils)

local Reject = Configs.Combat.Reject

type State = { ComboIndex: number, LastSwingAt: number }

local BladesServer = {}

function BladesServer.CreateState(_config: CombatTypes.WeaponConfig): State
	return { ComboIndex = 0, LastSwingAt = -math.huge }
end

function BladesServer.Begin(
	state: State,
	config: CombatTypes.WeaponConfig,
	request: CombatTypes.AttackRequest,
	now: number
): (CombatTypes.AttackPlan?, string?)
	local combo = config.Combo
	local index = BladeUtils.NextIndex(state.ComboIndex, state.LastSwingAt, now, combo)

	if request.attackId ~= BladeUtils.AttackId(index) then
		if request.attackId ~= BladeUtils.AttackId(1) then
			return nil, Reject.ComboMismatch
		end
		index = 1
	end

	state.ComboIndex = index
	state.LastSwingAt = now

	return {
		AttackId = BladeUtils.AttackId(index),
		Finisher = index >= BladeUtils.MaxHits(combo),
	}, nil
end

function BladesServer.OnMarker(session: any, plan: CombatTypes.AttackPlan, marker: string)
	if marker ~= "Start" then
		return
	end

	local config = session.Config
	local damage = config.Stats.Damage * (if plan.Finisher then config.Combo.FinisherMultiplier or 1 else 1)

	session:StartHitbox({
		Damage = damage,
		MaxTargets = config.Stats.MaxTargets or Configs.Combat.DefaultMaxTargets,
		Duration = config.Timing and config.Timing.HitDuration or Configs.Combat.DefaultHitDuration,
	})
end

function BladesServer.OnRejected(state: State, reason: string)
	if reason == Reject.Cooldown or reason == Reject.ComboMismatch then
		state.ComboIndex = 0
	end
end

return BladesServer :: CombatTypes.CategoryServer
