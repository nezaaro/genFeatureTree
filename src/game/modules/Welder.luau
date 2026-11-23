type ClassName = "Weld" | "Motor6D"

export type WeldGroupOptions = {
	className: ClassName?,
	canCollide: boolean?,
}

export type WeldModelOptions = {
	className: ClassName?,
	canCollide: boolean?,
	recursive: boolean?,
}

export type AutoWeldOptions = {
	className: ClassName?,
	canCollide: boolean?,
	ignoreNames: { string }?,
}

type Constraint = Weld | Motor6D

local Welder = {}

--// INTERNALS

local function assertIsBasePart(value: unknown, fn: string, arg: string)
	if typeof(value) ~= "Instance" or not (value :: Instance):IsA("BasePart") then
		error(string.format("Welder.%s: expected %s to be a BasePart, got %s", fn, arg, typeof(value)), 3)
	end
end

local function uniqueWeldName(base: Instance, p0: BasePart, p1: BasePart): string
	local baseName = p0.Name .. "_" .. p1.Name
	local name = baseName
	local suffix = 1
	while base:FindFirstChild(name) do
		suffix += 1
		name = baseName .. suffix
	end
	return name
end

local function buildConstraint(className: ClassName, p0: BasePart, p1: BasePart, setC0: boolean, fn: string): Constraint
	assertIsBasePart(p0, fn, "p0")
	assertIsBasePart(p1, fn, "p1")

	local constraint = Instance.new(className) :: any
	constraint.Part0 = p0
	constraint.Part1 = p1
	if setC0 then
		constraint.C0 = p0.CFrame:ToObjectSpace(p1.CFrame)
	end
	constraint.Name = uniqueWeldName(p0, p0, p1)
	constraint.Parent = p0

	p1.Anchored = false

	return constraint
end

--// PUBLIC API

function Welder.Weld(p0: BasePart, p1: BasePart): Weld
	return buildConstraint("Weld", p0, p1, true, "Weld") :: Weld
end

function Welder.M6D(p0: BasePart, p1: BasePart): Motor6D
	return buildConstraint("Motor6D", p0, p1, true, "M6D") :: Motor6D
end

function Welder.BlankWeld(p0: BasePart, p1: BasePart): Weld
	return buildConstraint("Weld", p0, p1, false, "BlankWeld") :: Weld
end

function Welder.BlankM6D(p0: BasePart, p1: BasePart): Motor6D
	return buildConstraint("Motor6D", p0, p1, false, "BlankM6D") :: Motor6D
end

function Welder.WeldGroup(base: BasePart, parts: { Instance }, options: WeldGroupOptions?): { Constraint }
	assertIsBasePart(base, "WeldGroup", "base")
	options = options or {}
	local className: ClassName = (options :: WeldGroupOptions).className or "Weld"
	local weldFn: (BasePart, BasePart) -> Constraint
	if className == "Motor6D" then
		weldFn = function(p0: BasePart, p1: BasePart): Constraint
			return Welder.M6D(p0, p1)
		end
	else
		weldFn = function(p0: BasePart, p1: BasePart): Constraint
			return Welder.Weld(p0, p1)
		end
	end

	local welds: { Constraint } = {}
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and part ~= base then
			welds[#welds + 1] = weldFn(base, part)
			if (options :: WeldGroupOptions).canCollide ~= nil then
				part.CanCollide = (options :: WeldGroupOptions).canCollide :: boolean
			end
		end
	end
	return welds
end

function Welder.WeldModel(model: Instance, base: BasePart, options: WeldModelOptions?): { Constraint }
	options = options or {}
	local opts = options :: WeldModelOptions
	local parts = opts.recursive and model:GetDescendants() or model:GetChildren()
	return Welder.WeldGroup(base, parts, opts)
end

function Welder.WeldDescendants(model: Instance, base: BasePart, options: WeldModelOptions?): { Constraint }
	options = options or {}
	local opts = options :: WeldModelOptions
	opts.recursive = true
	return Welder.WeldModel(model, base, opts)
end

function Welder.AutoWeldModel(model: Instance, base: BasePart, options: AutoWeldOptions?)
	assertIsBasePart(base, "AutoWeldModel", "base")
	options = options or {}
	local opts = options :: AutoWeldOptions
	local ignoreNames = opts.ignoreNames
	local className: ClassName = opts.className or "Weld"
	local weldFn: (BasePart, BasePart) -> Constraint
	if className == "Motor6D" then
		weldFn = function(p0: BasePart, p1: BasePart): Constraint
			return Welder.M6D(p0, p1)
		end
	else
		weldFn = function(p0: BasePart, p1: BasePart): Constraint
			return Welder.Weld(p0, p1)
		end
	end

	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= base and not (ignoreNames and table.find(ignoreNames, part.Name)) then
			weldFn(base, part)
			if opts.canCollide ~= nil then
				part.CanCollide = opts.canCollide
			end
			Welder.AutoWeldModel(part, part, opts)
		end
	end
end

return Welder
