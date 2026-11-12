--!strict
local World = require("../src/CombatWorld")

local passed = 0
local failed = 0
local function check(name: string, run: () -> ())
	local ok, reason = pcall(run)
	if ok then
		passed += 1
		print("PASS " .. name)
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(reason))
	end
end
local function equal(actual: any, expected: any)
	assert(
		actual == expected,
		string.format("expected %s, got %s", tostring(expected), tostring(actual))
	)
end
local function fixture()
	local world = World.new()
	assert(world.add("alpha"))
	assert(world.add("beta"))
	return world
end
local function advance(world: World.World, ticks: number)
	for _ = 1, ticks do
		world.step()
	end
end
local function view(world: World.World, id: string): World.Snapshot
	local result = world.snapshot(id)
	assert(result)
	return result
end
local function attack(world: World.World, id: string, sequence: number, move: string?): number
	local accepted, reason =
		world.request(id, { kind = "Attack", sequence = sequence, move = move or "Jab" })
	assert(accepted, reason)
	local token = view(world, id).attackId
	assert(token)
	return token
end

check("windup, active and recovery boundaries are exact", function()
	local w = fixture()
	attack(w, "alpha", 1)
	equal(view(w, "alpha").state, "Windup")
	advance(w, 11)
	equal(view(w, "alpha").state, "Windup")
	w.step()
	equal(view(w, "alpha").state, "Active")
	advance(w, 4)
	equal(view(w, "alpha").state, "Recovery")
	advance(w, 18)
	equal(view(w, "alpha").state, "Idle")
end)
check("one target receives damage once per attack", function()
	local w = fixture()
	local token = attack(w, "alpha", 1)
	advance(w, 11)
	local contact = { attacker = "alpha", target = "beta", attackId = token }
	w.step({ contact, contact })
	equal(view(w, "beta").health, 91)
	w.step({ contact })
	equal(view(w, "beta").health, 91)
end)
check("stale attack token cannot register a hit", function()
	local w = fixture()
	local token = attack(w, "alpha", 1)
	advance(w, 48)
	attack(w, "alpha", 2)
	advance(w, 11)
	w.step({ { attacker = "alpha", target = "beta", attackId = token } })
	equal(view(w, "beta").health, 100)
end)
check("contacts during windup or after active expiry miss", function()
	local w = fixture()
	local token = attack(w, "alpha", 1)
	local contact = { attacker = "alpha", target = "beta", attackId = token }
	w.step({ contact })
	equal(view(w, "beta").health, 100)
	advance(w, 14)
	w.step({ contact })
	equal(view(w, "alpha").state, "Recovery")
	equal(view(w, "beta").health, 100)
end)
check("interrupt invalidates the victim's attack", function()
	local w = fixture()
	local token = attack(w, "alpha", 1)
	attack(w, "beta", 1, "Cleave")
	advance(w, 11)
	w.step({ { attacker = "alpha", target = "beta", attackId = token } })
	equal(view(w, "beta").state, "Stunned")
	equal(view(w, "beta").attackId, nil)
	advance(w, 9)
	equal(view(w, "beta").state, "Idle")
end)
check("cancel spends its cost and preserves cooldown", function()
	local w = fixture()
	attack(w, "alpha", 1)
	assert(w.request("alpha", { kind = "Cancel", sequence = 2 }))
	equal(view(w, "alpha").stamina, 820)
	advance(w, 6)
	local ok, reason = w.request("alpha", { kind = "Attack", sequence = 3, move = "Jab" })
	equal(ok, false)
	equal(reason, "Cooldown")
end)
check("active attacks cannot be cancelled", function()
	local w = fixture()
	attack(w, "alpha", 1)
	advance(w, 12)
	local ok, reason = w.request("alpha", { kind = "Cancel", sequence = 2 })
	equal(ok, false)
	equal(reason, "InvalidState")
end)
check("guard absorbs damage and spends stamina", function()
	local w = fixture()
	assert(w.request("beta", { kind = "Guard", sequence = 1 }))
	local token = attack(w, "alpha", 1)
	advance(w, 11)
	w.step({ { attacker = "alpha", target = "beta", attackId = token } })
	equal(view(w, "beta").health, 100)
	equal(view(w, "beta").stamina, 880)
	equal(view(w, "beta").state, "Guarding")
end)
check("sequence replay cannot spend stamina twice", function()
	local w = fixture()
	attack(w, "alpha", 1)
	local ok, reason = w.request("alpha", { kind = "Attack", sequence = 1, move = "Jab" })
	equal(ok, false)
	equal(reason, "StaleSequence")
	equal(view(w, "alpha").stamina, 820)
end)
check("rejected gameplay command still consumes its sequence", function()
	local w = fixture()
	attack(w, "alpha", 1)
	w.request("alpha", { kind = "Attack", sequence = 2, move = "Jab" })
	advance(w, 48)
	local ok, reason = w.request("alpha", { kind = "Attack", sequence = 2, move = "Jab" })
	equal(ok, false)
	equal(reason, "StaleSequence")
end)
check("host identity cannot be overridden by payload", function()
	local w = fixture()
	local ok, reason =
		w.request("alpha", { kind = "Attack", sequence = 1, move = "Jab", actor = "beta" })
	equal(ok, false)
	equal(reason, "InvalidPayload")
	equal(view(w, "beta").state, "Idle")
end)
check("malformed payloads fail without exceptions", function()
	local w = fixture()
	local bad: { any } = {
		false,
		42,
		"Attack",
		{},
		{ kind = "Attack", sequence = 0, move = "Jab" },
		{ kind = "Attack", sequence = 0 / 0, move = "Jab" },
		{ kind = "Attack", sequence = math.huge, move = "Jab" },
		{ kind = "Attack", sequence = 1.5, move = "Jab" },
		{ kind = "Attack", sequence = 1, move = "Unknown" },
		{ kind = "Guard", sequence = 1, move = "Jab" },
		{ kind = "Attack", sequence = 1, move = {} },
	}
	for _, payload in bad do
		local ok = w.request("alpha", payload)
		equal(ok, false)
	end
	equal(view(w, "alpha").stamina, 1000)
end)
check("rate limit refills using simulation ticks", function()
	local w = fixture()
	for i = 1, 8 do
		w.request("alpha", { kind = "Cancel", sequence = i })
	end
	local ok, reason = w.request("alpha", { kind = "Guard", sequence = 9 })
	equal(ok, false)
	equal(reason, "RateLimited")
	advance(w, 10)
	assert(w.request("alpha", { kind = "Guard", sequence = 10 }))
end)
check("snapshots cannot mutate authoritative state", function()
	local w = fixture()
	local state = view(w, "alpha")
	local mutable: any = state
	local ok = pcall(function()
		mutable.health = 0
	end)
	equal(ok, false)
	equal(view(w, "alpha").health, 100)
end)
check("actor removal revokes access and incoming contacts", function()
	local w = fixture()
	local token = attack(w, "alpha", 1)
	assert(w.remove("beta"))
	advance(w, 11)
	w.step({ { attacker = "alpha", target = "beta", attackId = token } })
	equal(w.snapshot("beta"), nil)
	local ok, reason = w.request("beta", { kind = "Guard", sequence = 1 })
	equal(ok, false)
	equal(reason, "UnknownActor")
end)
check("duplicate registration never resets an actor", function()
	local w = fixture()
	attack(w, "alpha", 1)
	equal(w.add("alpha"), false)
	equal(view(w, "alpha").stamina, 820)
end)
check("idle regeneration clamps to maximum", function()
	local w = fixture()
	attack(w, "alpha", 1)
	advance(w, 2000)
	equal(view(w, "alpha").stamina, 1000)
end)
check("trace storage is bounded and reports dropped events", function()
	local w = fixture()
	for i = 1, 300 do
		assert(
			w.request(
				"alpha",
				{ kind = if i % 2 == 1 then "Guard" else "ReleaseGuard", sequence = i }
			)
		)
		advance(w, 10)
	end
	local events, dropped = w.drainEvents()
	equal(#events, 256)
	assert(dropped > 0)
	local again, lost = w.drainEvents()
	equal(#again, 0)
	equal(lost, 0)
end)
check("guard breaks on the ninth unpaid block and recovers", function()
	local w = fixture()
	assert(w.request("beta", { kind = "Guard", sequence = 1 }))
	for sequence = 1, 9 do
		local token = attack(w, "alpha", sequence)
		advance(w, 11)
		w.step({ { attacker = "alpha", target = "beta", attackId = token } })
		if sequence < 9 then
			advance(w, 200)
		end
	end
	equal(view(w, "beta").state, "Stunned")
	equal(view(w, "beta").stamina, 0)
	equal(view(w, "beta").health, 100)
	advance(w, 29)
	equal(view(w, "beta").state, "Stunned")
	w.step()
	equal(view(w, "beta").state, "Idle")
end)
check("exhaustion rejects an affordable-state attack without charging", function()
	local w = fixture()
	for sequence = 1, 3 do
		attack(w, "alpha", sequence, "Cleave")
		advance(w, 90)
	end
	local before = view(w, "alpha").stamina
	local ok, reason = w.request("alpha", { kind = "Attack", sequence = 4, move = "Cleave" })
	equal(ok, false)
	equal(reason, "Exhausted")
	equal(view(w, "alpha").stamina, before)
end)
check("death is terminal and health never becomes negative", function()
	local w = fixture()
	for sequence = 1, 5 do
		local token = attack(w, "alpha", sequence, "Cleave")
		advance(w, 23)
		w.step({ { attacker = "alpha", target = "beta", attackId = token } })
		advance(w, 400)
	end
	equal(view(w, "beta").health, 0)
	equal(view(w, "beta").state, "Dead")
	local ok, reason = w.request("beta", { kind = "Guard", sequence = 1 })
	equal(ok, false)
	equal(reason, "Dead")
end)
check("same-tick contacts resolve in stable actor order", function()
	local function run(reverse: boolean): (number, number)
		local w = fixture()
		local a = attack(w, "alpha", 1)
		local b = attack(w, "beta", 1)
		advance(w, 11)
		local first = { attacker = "alpha", target = "beta", attackId = a }
		local second = { attacker = "beta", target = "alpha", attackId = b }
		w.step(if reverse then { second, first } else { first, second })
		return view(w, "alpha").health, view(w, "beta").health
	end
	local a, b = run(false)
	local c, d = run(true)
	equal(a, c)
	equal(b, d)
	equal(a, 100)
	equal(b, 91)
end)
check("registration order cannot change transition event order", function()
	local w = World.new()
	assert(w.add("beta"))
	assert(w.add("alpha"))
	attack(w, "beta", 1)
	attack(w, "alpha", 1)
	w.drainEvents()
	advance(w, 12)
	local events = w.drainEvents()
	equal(events[1].actor, "alpha")
	equal(events[2].actor, "beta")
end)
check("event records are immutable", function()
	local w = fixture()
	attack(w, "alpha", 1)
	local events = w.drainEvents()
	local mutable: any = events[1]
	equal(
		pcall(function()
			mutable.kind = "Forged"
		end),
		false
	)
end)
check("malformed spam consumes the same request budget", function()
	local w = fixture()
	for _ = 1, 8 do
		w.request("alpha", false)
	end
	local ok, reason = w.request("alpha", { kind = "Guard", sequence = 1 })
	equal(ok, false)
	equal(reason, "RateLimited")
end)
check("actor count is bounded and removal frees capacity", function()
	local w = World.new()
	for i = 1, 128 do
		assert(w.add(tostring(i)))
	end
	equal(w.add("overflow"), false)
	assert(w.remove("1"))
	assert(w.add("replacement"))
end)
check("overloaded host contact batch fails before advancing time", function()
	local w = fixture()
	local contacts: { World.Contact } = {}
	for _ = 1, 513 do
		table.insert(contacts, { attacker = "alpha", target = "beta", attackId = 1 })
	end
	equal(
		pcall(function()
			w.step(contacts)
		end),
		false
	)
	equal(view(w, "alpha").tick, 0)
end)
check("removing and readding attacker cannot reuse its attack token", function()
	local w = fixture()
	local old = attack(w, "alpha", 1)
	assert(w.remove("alpha"))
	assert(w.add("alpha"))
	local current = attack(w, "alpha", 1)
	assert(current > old)
	advance(w, 11)
	w.step({ { attacker = "alpha", target = "beta", attackId = old } })
	equal(view(w, "beta").health, 100)
end)
check("20,000 seeded ticks preserve resource and replay invariants", function()
	local left, right = fixture(), fixture()
	local seed = 73
	local function nextNumber(): number
		seed = (seed * 48271) % 2147483647
		return seed
	end
	local function stateKey(w: World.World, id: string): string
		local s = view(w, id)
		assert(s.health >= 0 and s.health <= 100)
		assert(s.stamina >= 0 and s.stamina <= 1000 and s.stamina % 1 == 0)
		return string.format(
			"%d:%s:%d:%d:%s:%d",
			s.tick,
			s.state,
			s.health,
			s.stamina,
			tostring(s.attackId),
			s.stateEndsAt
		)
	end
	for sequence = 1, 20000 do
		local id = if nextNumber() % 2 == 0 then "alpha" else "beta"
		local choice = nextNumber() % 5
		local payload = {
			kind = if choice < 2
				then "Attack"
				elseif choice == 2 then "Cancel"
				elseif choice == 3 then "Guard"
				else "ReleaseGuard",
			sequence = sequence,
			move = if choice < 2 then (if choice == 0 then "Jab" else "Cleave") else nil,
		}
		local okA, reasonA = left.request(id, payload)
		local okB, reasonB = right.request(id, payload)
		equal(okA, okB)
		equal(reasonA, reasonB)
		local contacts: { World.Contact } = {}
		for _, attacker in { "alpha", "beta" } do
			local token = view(left, attacker).attackId
			if token and nextNumber() % 3 == 0 then
				table.insert(contacts, {
					attacker = attacker,
					target = if attacker == "alpha" then "beta" else "alpha",
					attackId = token,
				})
			end
		end
		left.step(contacts)
		right.step(contacts)
		for _, actor in { "alpha", "beta" } do
			equal(stateKey(left, actor), stateKey(right, actor))
		end
		if sequence % 100 == 0 then
			local a, lostA = left.drainEvents()
			local b, lostB = right.drainEvents()
			equal(#a, #b)
			equal(lostA, lostB)
			for i, event in a do
				equal(event.tick, b[i].tick)
				equal(event.kind, b[i].kind)
				equal(event.actor, b[i].actor)
				equal(event.target, b[i].target)
				equal(event.amount, b[i].amount)
			end
			-- Restart dead fixtures to keep the generated run exercising active combat.
			if view(left, "alpha").state == "Dead" or view(left, "beta").state == "Dead" then
				left, right = fixture(), fixture()
			end
		end
	end
end)
print(string.format("RESULT %d passed; %d failed", passed, failed))
assert(failed == 0, "Test suite failed")
