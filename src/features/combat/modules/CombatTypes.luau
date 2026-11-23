export type WeaponConfig = {
	Stats: {
		Cooldown: number,
		Damage: number,
		CritChance: number?,
		CritMultiplier: number?,
		MaxTargets: number?,
	},
	Timing: {
		MaxDuration: number?,
		HitDuration: number?,
	}?,
	[string]: any,
}

export type AttackRequest = {
	weaponId: string,
	attackId: string,
	sequence: number,
	aim: Vector3?,
}

export type AttackPlan = {
	AttackId: string,
	Sequence: number?,
	StartedAt: number?,
	[string]: any,
}

export type CategoryServer = {
	CreateState: (config: WeaponConfig) -> any,
	Begin: (state: any, config: WeaponConfig, request: AttackRequest, now: number) -> (AttackPlan?, string?),
	OnMarker: (session: any, plan: AttackPlan, marker: string) -> (),
	OnRejected: ((state: any, reason: string) -> ())?,
}

export type ClientPlan = {
	AttackId: string,
	AnimationId: number,
	Aim: Vector3?,
	[string]: any,
}

export type CategoryClient = {
	Markers: { string },
	CreateState: (config: WeaponConfig) -> any,
	Prepare: (state: any, config: WeaponConfig, now: number) -> ClientPlan?,
	Commit: (state: any, plan: ClientPlan, now: number) -> (),
	OnRejected: ((state: any, reason: string) -> ())?,
}

return {}
