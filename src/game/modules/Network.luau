local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BN = require(ReplicatedStorage.Packages.ByteNetMax)

return BN.defineNamespace("Network", function()
	return {
		packets = {
			--\\ COMBAT //--
			-- client -> server
			CombatEquip = BN.definePacket({
				value = BN.struct({
					weaponId = BN.string,
				}),
			}),
			CombatRequest = BN.definePacket({
				value = BN.struct({
					weaponId = BN.string,
					attackId = BN.string,
					sequence = BN.uint32,
					aim = BN.optional(BN.vec3),
				}),
			}),
			CombatMarker = BN.definePacket({
				value = BN.struct({
					sequence = BN.uint32,
					marker = BN.string,
				}),
			}),

			-- server -> client
			CombatState = BN.definePacket({
				value = BN.struct({
					actorId = BN.float64,
					state = BN.string,
					attackId = BN.string,
					sequence = BN.uint32,
				}),
			}),
			CombatHit = BN.definePacket({
				value = BN.struct({
					attackerId = BN.float64,
					target = BN.inst,
					damage = BN.float32,
					isCrit = BN.bool,
				}),
			}),
			CombatReject = BN.definePacket({
				value = BN.struct({
					sequence = BN.uint32,
					reason = BN.string,
				}),
			}),
		},
	}
end)
