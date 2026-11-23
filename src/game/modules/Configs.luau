return {
	version = "0.0.1",
	TicksPerSecond = 60,

	Combat = {
		MaxAttackDuration = 2,
		DefaultHitDuration = 1,
		DefaultMaxTargets = 3,
		MaxIdLength = 64,

		EndMarker = "End",

		States = {
			Idle = "Idle",
			Attacking = "Attacking",
		},

		Reject = {
			UnknownWeapon = "UnknownWeapon",
			NotAllowed = "NotAllowed",
			NotEquipped = "NotEquipped",
			BadSequence = "BadSequence",
			AttackActive = "AttackActive",
			Cooldown = "Cooldown",
			ComboMismatch = "ComboMismatch",
			Dead = "Dead",
			BadRequest = "BadRequest",
		},
	},
}
