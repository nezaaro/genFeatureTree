local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

return {
	--\\ COMBAT //--
	AttackStarted = Signal.new(), -- (player: Player, weaponId: string, attackId: string)
	AttackEnded = Signal.new(), -- (player: Player, weaponId: string, attackId: string, completed: boolean) [server]
	AttackRejected = Signal.new(), -- (player: Player, reason: string) [client]
	HitConfirmed = Signal.new(), -- (attacker: Player, target: Model, damage: number, isCrit: boolean)
	CombatStateChanged = Signal.new(), -- (actorId: number, state: string, attackId: string) [client]
}
