--// VARIABLES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local LinkedList = require(script.Parent.LinkedList)
local Configs = require(ReplicatedStorage.Source.Game.Modules.Configs)

local TICKS_PER_SECOND = Configs.TicksPerSecond
local MAX_CATCHUP_TICKS = math.max(1, math.ceil(TICKS_PER_SECOND / 8))
local MAX_WARNING_TICKS = TICKS_PER_SECOND * 2

export type Task = {
	Tick: number,
	Connection: RBXScriptConnection?,
	_stopping: boolean,
	OnTick: any,
	PostTicks: any,
	StoppedConnection: any,
	StartTime: number,
}

local lastWarningTick = -1e999
local tasksExecutedThisSecond = 0
local lastSecondTaskCount = 0
local lastSecondTick = 0
local freeRunnerThread: thread? = nil

local function acquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	freeRunnerThread = acquiredRunnerThread
end

local function runEventHandlerInFreeThread(...)
	acquireRunnerThreadAndCallEventHandler(...)
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function spawnTask(fn, ...)
	freeRunnerThread = freeRunnerThread or coroutine.create(runEventHandlerInFreeThread)
	task.spawn(freeRunnerThread :: thread, fn, ...)
end

--// TASK
local tickQueue = {}
local Task = {
	init = function(self: Task)
		self.Tick = 0
		self.Connection = nil
		self._stopping = false
		self.OnTick = Signal.new()
		self.PostTicks = Signal.new()
		self.StoppedConnection = Signal.new()
	end,

	Start = function(self: Task, customStartTime: number?): boolean
		if self.Connection ~= nil then
			return false
		end

		self._stopping = false
		self.StartTime = (customStartTime or workspace:GetServerTimeNow()) - self.Tick / TICKS_PER_SECOND

		local currentTickTasks = tickQueue[self.Tick]
		if currentTickTasks ~= nil then
			tickQueue[self.Tick] = nil

			local nextTickTasks = tickQueue[self.Tick + 1]
			if nextTickTasks ~= nil then
				local taskNode = currentTickTasks:RemoveLast()
				while taskNode do
					nextTickTasks:InsertFront(taskNode)
					taskNode = currentTickTasks:RemoveLast()
				end
			else
				tickQueue[self.Tick + 1] = currentTickTasks
			end
		end

		self.Connection = RunService.Heartbeat:Connect(function()
			if self._stopping then
				return
			end

			local targetTick = math.round((workspace:GetServerTimeNow() - self.StartTime) * TICKS_PER_SECOND)
			if targetTick <= self.Tick then
				return
			end

			local tickDifference = targetTick - self.Tick
			local isOverloaded = false

			if MAX_CATCHUP_TICKS < tickDifference then
				targetTick = self.Tick + MAX_CATCHUP_TICKS

				if MAX_WARNING_TICKS < tickDifference then
					if self.Tick - lastWarningTick >= TICKS_PER_SECOND then
						lastWarningTick = self.Tick
						warn(
							string.format(
								"Task: overloaded: %d ticks behind (%.1fs), %d scheduled tasks/s. Dropping the backlog — the sim ran slow, it did not skip ticks.",
								tickDifference,
								tickDifference / TICKS_PER_SECOND,
								lastSecondTaskCount
							)
						)
					end
					isOverloaded = true
				end
			end

			while self.Tick < targetTick and not self._stopping do
				self.Tick += 1

				if self.Tick - lastSecondTick >= TICKS_PER_SECOND then
					lastSecondTaskCount = tasksExecutedThisSecond
					tasksExecutedThisSecond = 0
					lastSecondTick = self.Tick
				end

				self.OnTick:Fire(self.Tick)

				if self._stopping then
					break
				end

				local pendingTasks = tickQueue[self.Tick]
				if pendingTasks ~= nil then
					local taskNode = pendingTasks:RemoveFirst()
					while taskNode do
						if self._stopping then
							pendingTasks:InsertFront(taskNode)
							break
						end

						tasksExecutedThisSecond += 1

						if taskNode.Thread then
							task.spawn(taskNode.Thread, self.Tick)
						elseif taskNode.Parameters then
							spawnTask(taskNode.Function, unpack(taskNode.Parameters))
						else
							spawnTask(taskNode.Function)
						end

						taskNode = pendingTasks:RemoveFirst()
					end

					if pendingTasks.Next == pendingTasks then
						tickQueue[self.Tick] = nil
					end
				elseif self._stopping then
					break
				end
			end

			if not self._stopping then
				self.PostTicks:Fire(self.Tick)

				if isOverloaded and not self._stopping then
					self.StartTime = workspace:GetServerTimeNow() - self.Tick / TICKS_PER_SECOND
				end
			end
		end)

		return true
	end,

	Stop = function(self: Task): boolean
		if self.Connection == nil then
			return false
		end

		self._stopping = true
		self.Connection:Disconnect()
		self.Connection = nil
		self.StoppedConnection:Fire()

		return true
	end,

	Wait = function(self: Task, tickDelay: number): any
		local targetTick = self.Tick + math.max(tickDelay, 1)
		local taskList = tickQueue[targetTick]

		if taskList == nil then
			taskList = LinkedList.new()
			tickQueue[targetTick] = taskList
		end

		taskList:InsertBack({ Thread = coroutine.running() })

		return coroutine.yield()
	end,

	Delay = function(self: Task, tickDelay: number, callback: (...any) -> (), ...: any): any
		local targetTick = self.Tick + math.max(tickDelay, 1)
		local taskList = tickQueue[targetTick]

		if taskList == nil then
			taskList = LinkedList.new()
			tickQueue[targetTick] = taskList
		end

		if select("#", ...) == 0 then
			return taskList:InsertBack({ Function = callback })
		end

		return taskList:InsertBack({ Function = callback, Parameters = { ... } })
	end,
}

return Task
