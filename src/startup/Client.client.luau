local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loader = require(ReplicatedStorage.Source.Core.Runtime.Loader)

Loader.init(ReplicatedStorage.Source.Features)
Loader.Start()
