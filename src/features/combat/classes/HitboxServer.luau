local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove = require(ReplicatedStorage.Packages.Trove)
local ShapecastHitbox = require(ReplicatedStorage.Packages.ShapecastHitbox)

local HitboxServer = {}
HitboxServer.__index = HitboxServer
export type HitboxServer = typeof(setmetatable(
	{} :: {
		_instance: Instance,
		_stop: (() -> ())?,
		_destroyed: boolean,
	},
	HitboxServer
))

export type Context = {
	Character: Model,
	WeaponModel: Instance,
	Damage: number,
	MaxTargets: number,
	OnConfirmedHit: (Model, RaycastResult) -> (),
}

export type StartOptions = {
	Duration: number?,
	Resolution: number?,
}

local DEFAULT_RESOLUTION = 60

function HitboxServer.new(instance: Instance): HitboxServer
	assert(instance:IsA("Model") or instance:IsA("BasePart"), "HitboxServer requires a Model or BasePart")

	return setmetatable({
		_instance = instance :: Instance,
		_stop = nil,
		_destroyed = false,
	}, HitboxServer)
end

function HitboxServer.Start(self: HitboxServer, context: Context, options: StartOptions?): boolean
	assert(not self._destroyed, "HitboxServer is destroyed")

	if self._stop then
		return false
	end

	local character = context.Character
	local weapon = context.WeaponModel
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	assert(weapon == self._instance, "WeaponModel does not match instance")
	assert(weapon:IsDescendantOf(character), "WeaponModel must be inside Character")
	assert(context.Damage >= 0, "Damage cannot be negative")
	assert(context.MaxTargets >= 1, "MaxTargets must be at least 1")
	assert(humanoid and humanoid.Health > 0, "Character has no living Humanoid")

	local duration = options and options.Duration
	local resolution = (options and options.Resolution) or DEFAULT_RESOLUTION
	local maxTargets = context.MaxTargets

	assert(duration == nil or duration > 0, "Duration must be positive")
	assert(resolution > 0, "Resolution must be positive")

	local trove = Trove.new()
	local hitbox = ShapecastHitbox.new(
		weapon,
		(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			params.IgnoreWater = true
			return params
		end)()
	)

	local hitTargets: { [Model]: boolean } = {}
	local hitCount = 0
	local cleaned = false

	local function cleanup()
		if cleaned then
			return
		end

		cleaned = true
		self._stop = nil
		trove:Destroy()
	end

	self._stop = cleanup

	trove:Add(cleanup)
	trove:Add(hitbox)
	hitbox:SetResolution(resolution)
	hitbox:OnHit(function(result: RaycastResult)
		if cleaned or hitCount >= maxTargets then
			return
		end

		if not character.Parent or humanoid.Health <= 0 then
			return cleanup()
		end

		if not weapon:IsDescendantOf(character) then
			return cleanup()
		end

		local target = result.Instance:FindFirstAncestorOfClass("Model")
		if not target or hitTargets[target] then
			return
		end

		local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
		if not targetHumanoid or targetHumanoid.Health <= 0 then
			return
		end

		hitTargets[target] = true
		hitCount += 1

		local ok = pcall(context.OnConfirmedHit, target, result)
		if not ok then
			warn("HitboxServer: OnConfirmedHit failed")
		end

		if hitCount >= maxTargets then
			cleanup()
		end
	end)

	trove:Connect(character.Destroying, cleanup)
	trove:Connect(weapon.Destroying, cleanup)
	hitbox:HitStart(duration)
	return true
end

function HitboxServer.Stop(self: HitboxServer)
	if self._stop then
		self._stop()
	end
end

function HitboxServer.IsActive(self: HitboxServer): boolean
	return self._stop ~= nil
end

function HitboxServer.Destroy(self: HitboxServer)
	if self._destroyed then
		return
	end

	self:Stop()
	self._destroyed = true
end

return HitboxServer
