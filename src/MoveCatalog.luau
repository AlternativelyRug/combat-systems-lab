--!strict
-- Synthetic demonstration values. These are not extracted from a shipped game.
export type Move = {
	windup: number,
	active: number,
	recovery: number,
	cooldown: number,
	cost: number,
	damage: number,
	stun: number,
}

local moves: { [string]: Move } = {
	Jab = {
		windup = 12,
		active = 4,
		recovery = 18,
		cooldown = 48,
		cost = 180,
		damage = 9,
		stun = 9,
	},
	Cleave = {
		windup = 24,
		active = 6,
		recovery = 30,
		cooldown = 90,
		cost = 350,
		damage = 24,
		stun = 20,
	},
}
for _, move in moves do
	table.freeze(move)
end
return table.freeze(moves)
