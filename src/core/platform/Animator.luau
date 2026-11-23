local activeTracks: { [Model]: { [number]: AnimationTrack } } = {}

local Animator = {}

local function getorCreateAnimator(character: Model): Animator?
	local controller = character:FindFirstChildWhichIsA("Humanoid")
		or character:FindFirstChildWhichIsA("AnimationController")

	if not controller then
		return nil
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = controller
		animator = newAnimator
	end

	return animator
end

function Animator.Play(
	character: Model,
	id: number,
	fadeTime: number?,
	weight: number?,
	speed: number?
): AnimationTrack?
	local tracks = activeTracks[character]
	if not tracks then
		tracks = {}
		activeTracks[character] = tracks
	end

	local track = tracks[id]
	if not track then
		local animator = getorCreateAnimator(character)
		if not animator then
			return nil
		end

		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{id}`

		track = animator:LoadAnimation(animation)
		animation:Destroy()

		tracks[id] = track
	end

	track:Play(fadeTime or 0.1, weight or 1, speed or 1)

	return track
end

function Animator.Stop(character: Model, id: number, fadeTime: number?)
	local track = activeTracks[character] and activeTracks[character][id]
	if track then
		track:Stop(fadeTime or 0.1)
	end
end

function Animator.StopAll(character: Model, fadeTime: number?)
	local tracks = activeTracks[character]
	if not tracks then
		return
	end

	for _, track in tracks do
		track:Stop(fadeTime or 0.1)
	end

	activeTracks[character] = nil
end

function Animator.Clear(character: Model)
	activeTracks[character] = nil
end

return Animator
