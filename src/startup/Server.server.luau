local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Loader = require(ReplicatedStorage.Source.Core.Runtime.Loader)

Loader.init(ServerScriptService.Features)
Loader.Start()
