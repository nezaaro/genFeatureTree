return setmetatable({}, {
	__index = function(_: any, name: string)
		return (require :: any)(script[name])
	end,
})
