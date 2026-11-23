return {
	DisplayName = "Example Sword",

	Stats = {
		Damage = 20,
		Cooldown = 0.45,
		CritChance = 0.1,
		CritMultiplier = 1.5,
		MaxTargets = 3,
	},

	Combo = {
		MaxHits = 4,
		ResetTime = 1.2,
		FinisherMultiplier = 1.5,
	},

	Assets = {
		Animations = {
			Idle = 0,
			Equip = 0,
			Swings = { 0, 0, 0, 0 },
		},
		Sounds = {
			Equip = 0,
			Swing = 0,
		},
	},
}
