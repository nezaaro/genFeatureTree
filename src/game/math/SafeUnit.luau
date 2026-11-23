local MIN_MAGNITUDE = 1e-3

local function SafeUnit(vector: Vector3): Vector3?
	local magnitude = vector.Magnitude
	if magnitude ~= magnitude or magnitude == math.huge or magnitude < MIN_MAGNITUDE then
		return nil
	end

	return vector / magnitude
end

return SafeUnit
