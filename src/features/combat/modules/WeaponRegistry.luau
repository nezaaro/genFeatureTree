local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = ReplicatedStorage.Source.Game.Items
local WeaponCategories = require(Items.WeaponCategories)
local CombatTypes = require(script.Parent.CombatTypes)

export type Entry = {
	Category: string,
	Config: CombatTypes.WeaponConfig,
}

local entries: { [string]: Entry } = {}
local built = false

local WeaponRegistry = {}

local function deepFreeze<T>(tbl: T): T
	if type(tbl) ~= "table" then
		return tbl
	end

	if not table.isfrozen(tbl) then
		table.freeze(tbl)
	end

	for k, v in tbl do
		if type(k) == "table" then
			deepFreeze(k)
		end
		if type(v) == "table" then
			deepFreeze(v)
		end
	end

	return tbl
end

local function isValidConfig(config: any): boolean
	return type(config) == "table"
		and type(config.Stats) == "table"
		and type(config.Stats.Cooldown) == "number"
		and type(config.Stats.Damage) == "number"
end

function WeaponRegistry.Build()
	if built then
		return
	end

	built = true

	for _, categoryName in WeaponCategories do
		if type(categoryName) ~= "string" or categoryName == "" then
			continue
		end

		local dataModule = Items:FindFirstChild(categoryName .. "Data")
		if not dataModule or not dataModule:IsA("ModuleScript") then
			warn(`WeaponRegistry: missing category data '{categoryName}'`)
			continue
		end

		local ok, dataIndex = pcall(require, dataModule)
		if not ok or type(dataIndex) ~= "table" then
			warn(`WeaponRegistry: failed to load '{categoryName}'`)
			continue
		end

		for weaponId, config in dataIndex do
			if type(weaponId) ~= "string" or not isValidConfig(config) then
				continue
			end

			if entries[weaponId] then
				warn(`WeaponRegistry: duplicate weaponId '{weaponId}'`)
				continue
			end

			deepFreeze(config)

			entries[weaponId] = {
				Category = categoryName,
				Config = config,
			}
		end
	end
end

function WeaponRegistry.Get(weaponId: string): Entry?
	return entries[weaponId]
end

return WeaponRegistry
