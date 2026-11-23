local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatTypes = require(ReplicatedStorage.Source.Features.Combat.Modules.CombatTypes)
local BladeUtils = require(script.Parent.BladeUtils)

type State = { ComboIndex: number, LastSwingAt: number }

local BladesClient = {}

BladesClient.Markers = table.freeze({ "Start" })

function BladesClient.CreateState(_config: CombatTypes.WeaponConfig): State
	return { ComboIndex = 0, LastSwingAt = -math.huge }
end

function BladesClient.Prepare(state: State, config: CombatTypes.WeaponConfig, now: number): CombatTypes.ClientPlan?
	local index = BladeUtils.NextIndex(state.ComboIndex, state.LastSwingAt, now, config.Combo)
	local animationId = config.Assets.Animations.Swings[index]
	if not animationId then
		return nil
	end

	return {
		AttackId = BladeUtils.AttackId(index),
		AnimationId = animationId,
		ComboIndex = index,
	}
end

function BladesClient.Commit(state: State, plan: CombatTypes.ClientPlan, now: number)
	state.ComboIndex = plan.ComboIndex
	state.LastSwingAt = now
end

function BladesClient.OnRejected(state: State, _reason: string)
	state.ComboIndex = 0
end

return BladesClient :: CombatTypes.CategoryClient
