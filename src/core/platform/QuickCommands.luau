local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local QuickCommands = {}

function QuickCommands.TweenObject(
	instance: Instance,
	duration: number,
	easingStyle: string,
	easingDirection: string,
	properties: { [string]: any }
): Tween
	local tweenInfo =
		TweenInfo.new(duration, (Enum.EasingStyle :: any)[easingStyle], (Enum.EasingDirection :: any)[easingDirection])
	return TweenService:Create(instance, tweenInfo, properties)
end

function QuickCommands.Tween(
	instance: Instance,
	duration: number,
	easingStyle: string,
	easingDirection: string,
	properties: { [string]: any }
)
	local tween = QuickCommands.TweenObject(instance, duration, easingStyle, easingDirection, properties)
	tween:Play()
	tween.Completed:Wait()
	tween:Destroy()
end

function QuickCommands.GetPlayerIcon(userId: number): (string, boolean)
	if not userId or userId <= 0 then
		return "", false
	end

	local success, content, isReady = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)

	if success then
		return content, isReady
	end

	return "", false
end

function QuickCommands.GetProductPrice(assetId: number, isGamePass: boolean?): number?
	if not assetId then
		return nil
	end

	local infoType = if isGamePass then Enum.InfoType.GamePass else Enum.InfoType.Product
	local success, productInfo = pcall(function()
		return MarketplaceService:GetProductInfoAsync(assetId, infoType)
	end)

	if success and productInfo and productInfo.PriceInRobux then
		return productInfo.PriceInRobux
	end

	return nil
end

function QuickCommands.FormatTime_MS(totalSeconds: number): string
	local minutes = math.floor(totalSeconds / 60)
	local seconds = math.floor(totalSeconds % 60)
	return string.format("%d:%02d", minutes, seconds)
end

function QuickCommands.FormatTime_HMS(totalSeconds: number): string
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = math.floor(totalSeconds % 60)
	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

return QuickCommands
