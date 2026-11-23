local function RoundNumber(value: number, decimals: number): number
	decimals = decimals or 0
	return math.round(value * 10 ^ decimals) / 10 ^ decimals
end

return RoundNumber
