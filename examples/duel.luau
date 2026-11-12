--!strict
local CombatWorld = require("../src/CombatWorld")
local world = CombatWorld.new()
assert(world.add("fencer"))
assert(world.add("sentinel"))

local function request(id: string, payload: unknown)
	local accepted, reason = world.request(id, payload)
	print(string.format("REQUEST %-8s %s", id, reason))
	assert(accepted)
end
local function showEvents()
	local events, lost = world.drainEvents()
	for _, event in events do
		print(
			string.format(
				"%04d | %-12s | %-8s | target=%-8s | amount=%s",
				event.tick,
				event.kind,
				event.actor,
				event.target or "-",
				tostring(event.amount or "-")
			)
		)
	end
	assert(lost == 0)
end

print("Combat Systems Lab / deterministic host-driven demo / 60 ticks per second")
request("fencer", { kind = "Attack", sequence = 1, move = "Jab" })
request("sentinel", { kind = "Guard", sequence = 1 })
local first = world.snapshot("fencer")
assert(first and first.attackId)
for tick = 1, 48 do
	-- This is a scripted geometry fixture. No claim of real collision detection.
	world.step(
		if tick == 12
			then { { attacker = "fencer", target = "sentinel", attackId = first.attackId } }
			else nil
	)
	showEvents()
end
request("sentinel", { kind = "ReleaseGuard", sequence = 2 })
request("fencer", { kind = "Attack", sequence = 2, move = "Jab" })
request("sentinel", { kind = "Attack", sequence = 3, move = "Cleave" })
local second = world.snapshot("fencer")
assert(second and second.attackId)
for tick = 49, 90 do
	world.step(
		if tick == 60
			then { { attacker = "fencer", target = "sentinel", attackId = second.attackId } }
			else nil
	)
	showEvents()
end
for _, id in { "fencer", "sentinel" } do
	local state = world.snapshot(id)
	assert(state)
	print(
		string.format(
			"FINAL %-8s health=%d stamina=%d/1000 state=%s",
			id,
			state.health,
			state.stamina,
			state.state
		)
	)
end
