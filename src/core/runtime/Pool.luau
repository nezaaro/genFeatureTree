--!native

local RunService = game:GetService("RunService")

export type Config<T> = {
	maxSize: number?,
	prewarm: number?,
	storage: Instance?,
	onAcquire: ((T) -> ())?,
	onRelease: ((T) -> ())?,
	destroy: ((T) -> ())?,
	safe: boolean?,
	deferPark: boolean?,
}

export type Stats = { idle: number, active: number, total: number }

export type Pool<T> = {
	acquire: (self: Pool<T>, parent: Instance?) -> T?,
	acquireFor: (self: Pool<T>, lifetime: number, parent: Instance?) -> T?,
	acquireMany: (self: Pool<T>, count: number, parent: Instance?, out: { T }?) -> ({ T }, number),
	release: (self: Pool<T>, obj: T) -> boolean,
	releaseMany: (self: Pool<T>, objs: { T }, count: number?) -> number,
	releaseAll: (self: Pool<T>) -> (),
	destroy: (self: Pool<T>) -> (),
	stats: (self: Pool<T>, out: Stats?) -> Stats,
	[any]: any,
}

local EMPTY_CONFIG = table.freeze({})
local MAX_PREALLOC = 1024

local Pool = {}

function Pool.new<T>(source: Instance | () -> T, config: Config<T>?): Pool<T>
	local cfg: Config<T> = config or EMPTY_CONFIG

	local max: number = cfg.maxSize or math.huge
	local prewarm: number = cfg.prewarm or 0
	if prewarm > max then
		prewarm = max
	end
	local storage = cfg.storage
	local onAcquire = cfg.onAcquire
	local onRelease = cfg.onRelease
	local destroyFn = cfg.destroy
	local deferPark = cfg.deferPark == true

	local template: Instance? = nil
	local create: any = nil
	local isInst = false
	local kindKnown = false
	if typeof(source) == "Instance" then
		template = source
		isInst = true
		kindKnown = true
	else
		create = source
	end

	local parkNow = isInst and storage ~= nil and not deferPark

	local cap = if max < MAX_PREALLOC then max else MAX_PREALLOC
	if prewarm > cap then
		cap = prewarm
	end

	local idle: { any } = table.create(cap)
	local roster: { any } = table.create(cap)
	local idleN = 0
	local parkedN = 0
	local rosterN = 0
	local total = 0
	local destroyed = false

	local activeSet: { [any]: boolean }? = if cfg.safe then {} else nil

	local gen = 0
	local timed: { [any]: number }? = nil
	local timedN = 0
	local heap: { any }? = nil
	local hn = 0
	local timerConn: RBXScriptConnection? = nil
	local flushConn: RBXScriptConnection? = nil
	local scratch: any = false

	--// cold paths

	local function make(): any
		if total >= max then
			return nil
		end
		total += 1
		local obj: any = nil
		if template then
			obj = template:Clone()
		else
			obj = create()
		end
		if obj == nil then
			total -= 1
			return nil
		end
		if not kindKnown then
			kindKnown = true
			isInst = typeof(obj) == "Instance"
			parkNow = isInst and storage ~= nil and not deferPark
		end
		rosterN += 1
		roster[rosterN] = obj
		return obj
	end

	local function flush()
		local n = idleN
		for i = parkedN + 1, n do
			idle[i].Parent = storage
		end
		parkedN = n
	end

	--// hot paths

	local function release(_: any, obj: any): boolean
		if destroyed then
			return false
		end
		if activeSet then
			if not activeSet[obj] then
				return false
			end
			activeSet[obj] = nil
		end
		if timedN > 0 then
			local t: any = timed
			if t[obj] then
				t[obj] = nil
				timedN -= 1
			end
		end
		if onRelease then
			onRelease(obj)
			if destroyed then
				return true
			end
		end
		if parkNow then
			obj.Parent = storage
		end
		local n = idleN + 1
		idleN = n
		idle[n] = obj
		return true
	end

	local function onTick()
		local h: any = heap
		local now = os.clock()
		while hn > 0 and h[1] <= now do
			local n = hn - 1
			hn = n
			local o, g = h[2], h[3]

			local lb = n * 3 + 1
			local le, lo, lg = h[lb], h[lb + 1], h[lb + 2]
			h[lb] = nil
			h[lb + 1] = nil
			h[lb + 2] = nil

			if n > 0 then
				local i = 0
				while true do
					local c = i * 2 + 1
					if c >= n then
						break
					end
					local cb = c * 3 + 1
					local ce = h[cb]
					local r = c + 1
					if r < n then
						local re = h[r * 3 + 1]
						if re < ce then
							c = r
							cb = r * 3 + 1
							ce = re
						end
					end
					if ce >= le then
						break
					end
					local ib = i * 3 + 1
					h[ib] = ce
					h[ib + 1] = h[cb + 1]
					h[ib + 2] = h[cb + 2]
					i = c
				end
				local b = i * 3 + 1
				h[b] = le
				h[b + 1] = lo
				h[b + 2] = lg
			end

			local t: any = timed
			if t[o] == g then
				release(nil, o)
			end
		end
		if hn == 0 then
			local c = timerConn
			if c then
				timerConn = nil
				c:Disconnect()
			end
		end
	end

	local function schedule(obj: any, g: number, life: number)
		local h: any = heap
		if not h then
			h = table.create(48)
			heap = h
		end
		local exp = os.clock() + life
		local i = hn
		hn = i + 1
		while i > 0 do
			local p = (i - 1) // 2
			local pb = p * 3 + 1
			local pe = h[pb]
			if pe <= exp then
				break
			end
			local ib = i * 3 + 1
			h[ib] = pe
			h[ib + 1] = h[pb + 1]
			h[ib + 2] = h[pb + 2]
			i = p
		end
		local b = i * 3 + 1
		h[b] = exp
		h[b + 1] = obj
		h[b + 2] = g
		if not timerConn then
			timerConn = RunService.Heartbeat:Connect(onTick)
		end
	end

	local function acquireFull(_: any, parent: Instance?, life: number?): any
		if destroyed then
			return nil
		end

		local obj
		local pending = false
		local n = idleN
		if n > 0 then
			obj = idle[n]
			idleN = n - 1
			if deferPark then
				if n > parkedN then
					pending = true
				else
					parkedN = n - 1
				end
			end
		else
			obj = make()
			if obj == nil then
				return nil
			end
		end

		if activeSet then
			activeSet[obj] = true
		end

		local g = 0
		if life then
			g = gen + 1
			gen = g
			local t = timed or {}
			timed = t
			t[obj] = g
			timedN += 1
		end

		if onAcquire then
			onAcquire(obj)
		end

		if isInst then
			if pending then
				if parent then
					if obj.Parent ~= parent then
						obj.Parent = parent
					end
				else
					obj.Parent = storage
				end
			elseif parent then
				obj.Parent = parent
			end
		end

		if life then
			local t: any = timed
			if t[obj] == g then
				schedule(obj, g, life)
			end
		end
		return obj
	end

	local function acquireFor(_: any, lifetime: number, parent: Instance?): any
		return acquireFull(nil, parent, lifetime)
	end

	local function acquireLean(_: any, parent: Instance?): any
		local obj
		local n = idleN
		if n > 0 then
			obj = idle[n]
			idleN = n - 1
		else
			obj = make()
			if obj == nil then
				return nil
			end
		end
		if onAcquire then
			onAcquire(obj)
		end
		if parent then
			obj.Parent = parent
		end
		return obj
	end

	local function acquireMany(_: any, count: number, parent: Instance?, out: { any }?): ({ any }, number)
		local res: { any } = out or table.create(count)
		if destroyed or count <= 0 then
			return res, 0
		end

		local got = 0
		local n = idleN
		local take = if count < n then count else n
		if take > 0 then
			local first = n - take + 1
			table.move(idle, first, n, 1, res)
			idleN = n - take
			local oldParked = parkedN
			if deferPark and oldParked > idleN then
				parkedN = idleN
			end
			if activeSet or onAcquire or isInst then
				for i = 1, take do
					local obj = res[i]
					if activeSet then
						activeSet[obj] = true
					end
					if onAcquire then
						onAcquire(obj)
					end
					if isInst then
						if deferPark and first + i - 1 > oldParked then
							if parent then
								if obj.Parent ~= parent then
									obj.Parent = parent
								end
							else
								obj.Parent = storage
							end
						elseif parent then
							obj.Parent = parent
						end
					end
				end
			end
			got = take
		end

		for _j = take + 1, count do
			local obj = make()
			if obj == nil then
				break
			end
			got += 1
			res[got] = obj
			if activeSet then
				activeSet[obj] = true
			end
			if onAcquire then
				onAcquire(obj)
			end
			if parent and isInst then
				obj.Parent = parent
			end
		end
		return res, got
	end

	local function releaseMany(_: any, objs: { any }, count: number?): number
		local k = count or #objs
		if destroyed or k <= 0 then
			return 0
		end
		if activeSet or timedN > 0 or onRelease then
			local done = 0
			for i = 1, k do
				if release(nil, objs[i]) then
					done += 1
				end
			end
			return done
		end
		local n = idleN
		table.move(objs, 1, k, n + 1, idle)
		idleN = n + k
		if parkNow then
			for i = 1, k do
				objs[i].Parent = storage
			end
		end
		return k
	end

	local function releaseAll(_: any)
		if destroyed or rosterN == idleN then
			return
		end
		local set = scratch or {}
		scratch = false
		for i = 1, idleN do
			set[idle[i]] = true
		end
		local n = rosterN
		for i = 1, n do
			local obj = roster[i]
			if not set[obj] then
				release(nil, obj)
			end
		end
		table.clear(set)
		scratch = set
	end

	local function destroy(_: any)
		if destroyed then
			return
		end
		destroyed = true
		max = -1

		local c = timerConn
		if c then
			timerConn = nil
			c:Disconnect()
		end
		c = flushConn
		if c then
			flushConn = nil
			c:Disconnect()
		end
		if heap then
			table.clear(heap)
		end
		hn = 0
		if timed then
			table.clear(timed)
		end
		timedN = 0
		if activeSet then
			table.clear(activeSet)
		end

		for i = rosterN, 1, -1 do
			local obj = roster[i]
			if isInst then
				obj:Destroy()
			elseif destroyFn then
				destroyFn(obj)
			end
		end
		table.clear(roster)
		table.clear(idle)
		rosterN = 0
		idleN = 0
		parkedN = 0
		total = 0

		if scratch then
			table.clear(scratch)
		end
		scratch = false
		template = nil
		create = nil
		storage = nil
		onAcquire = nil
		onRelease = nil
		destroyFn = nil
	end

	local function stats(_: any, out: Stats?): Stats
		if out then
			out.idle = idleN
			out.active = rosterN - idleN
			out.total = rosterN
			return out
		end
		return { idle = idleN, active = rosterN - idleN, total = rosterN }
	end

	--// construction

	for _i = 1, prewarm do
		local obj = make()
		if obj == nil then
			break
		end
		if isInst and storage then
			obj.Parent = storage
		end
		idleN += 1
		idle[idleN] = obj
	end
	parkedN = idleN

	if deferPark then
		flushConn = RunService.Heartbeat:Connect(flush)
	end

	return {
		acquire = if deferPark or activeSet then acquireFull else acquireLean,
		acquireFor = acquireFor,
		acquireMany = acquireMany,
		release = release,
		releaseMany = releaseMany,
		releaseAll = releaseAll,
		destroy = destroy,
		stats = stats,
	} :: any
end

return Pool
