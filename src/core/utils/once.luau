local function once<T...>(callback: (T...) -> ()): (T...) -> ()
	local called = false

	return function(...: T...)
		if called then
			return
		end

		called = true
		callback(...)
	end
end

return once
