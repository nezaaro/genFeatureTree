local BladeUtils = {}

function BladeUtils.MaxHits(combo: { MaxHits: number }): number
	return math.max(combo.MaxHits, 1)
end

function BladeUtils.AttackId(index: number): string
	return `Swing{index}`
end

function BladeUtils.NextIndex(
	comboIndex: number,
	lastSwingAt: number,
	now: number,
	combo: { MaxHits: number, ResetTime: number }
): number
	if comboIndex == 0 or now - lastSwingAt > combo.ResetTime then
		return 1
	end
	return comboIndex % BladeUtils.MaxHits(combo) + 1
end

return BladeUtils
