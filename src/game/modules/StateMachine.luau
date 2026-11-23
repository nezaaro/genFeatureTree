local StateMachine = {}
StateMachine.__index = StateMachine
export type StateMachine = typeof(setmetatable(
	{} :: {
		Current: string?,
		_states: { [string]: State },
		_listeners: { (to: string, from: string?) -> () },
	},
	StateMachine
))

export type State = {
	Enter: ((from: string?, ...any) -> ())?,
	Update: ((dt: number) -> ())?,
	Exit: ((to: string) -> ())?,
	Transitions: { string }?,
}

function StateMachine.new(states: { [string]: State }, initial: string?, ...: any): StateMachine
	local self = setmetatable({
		Current = nil,
		_states = states,
		_listeners = {},
	}, StateMachine)
	if initial then
		self:Set(initial, ...)
	end
	return self
end

-- Returns true if the transition happened.
function StateMachine.Set(self: StateMachine, name: string, ...: any): boolean
	local nextState = self._states[name]
	assert(nextState, `Unknown state: {name}`)

	local fromName = self.Current
	local from = fromName and self._states[fromName]
	if from then
		if from.Transitions and not table.find(from.Transitions, name) then
			return false
		end
		if from.Exit then
			from.Exit(name)
		end
	end

	self.Current = name
	if nextState.Enter then
		nextState.Enter(fromName, ...)
	end
	for _, fn in self._listeners do
		task.spawn(fn, name, fromName)
	end
	return true
end

function StateMachine.Update(self: StateMachine, dt: number)
	local state = self.Current and self._states[self.Current]
	if state and state.Update then
		state.Update(dt)
	end
end

-- Returns a disconnect function.
function StateMachine.OnChanged(self: StateMachine, fn: (to: string, from: string?) -> ()): () -> ()
	table.insert(self._listeners, fn)
	return function()
		local i = table.find(self._listeners, fn)
		if i then
			table.remove(self._listeners, i)
		end
	end
end

function StateMachine.Destroy(self: StateMachine)
	local state = self.Current and self._states[self.Current]
	if state and state.Exit then
		state.Exit("")
	end
	self.Current = nil
	table.clear(self._listeners)
end

return StateMachine
