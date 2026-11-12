--!strict
local Moves = require("./MoveCatalog")
local Decoder = require("./ActionDecoder")
local Bucket = require("./TokenBucket")

export type State = "Idle" | "Guarding" | "Windup" | "Active" | "Recovery" | "Stunned" | "Dead"
export type Contact = { attacker: string, target: string, attackId: number }
export type Snapshot = {
	read id: string,
	read tick: number,
	read state: State,
	read health: number,
	read stamina: number,
	read attackId: number?,
	read stateEndsAt: number,
}
export type Event = {
	read tick: number,
	read kind: string,
	read actor: string,
	read target: string?,
	read amount: number?,
}
type Attack = { id: number, move: Moves.Move, hit: { [string]: boolean } }
type Actor = {
	id: string,
	state: State,
	health: number,
	stamina: number,
	endsAt: number,
	attack: Attack?,
	cooldowns: { [string]: number },
	sequence: number,
	bucket: Bucket.Bucket,
}

export type World = {
	read add: (id: string) -> boolean,
	read remove: (id: string) -> boolean,
	read request: (id: string, payload: unknown) -> (boolean, string),
	read step: (contacts: { Contact }?) -> (),
	read snapshot: (id: string) -> Snapshot?,
	read drainEvents: () -> ({ Event }, number),
}

local MAX_ACTORS = 128
local MAX_CONTACTS = 512
local MAX_EVENTS = 256
local MAX_STAMINA = 1000
local GUARD_COST = 120
local GUARD_BREAK_TICKS = 30
local CANCEL_RECOVERY_TICKS = 6

local function new(): World
	local tick = 0
	local nextAttackId = 0
	local actors: { [string]: Actor } = {}
	local order: { string } = {}
	local events: { Event } = {}
	local dropped = 0

	local function emit(kind: string, actor: string, target: string?, amount: number?)
		if #events == MAX_EVENTS then
			dropped += 1
			return
		end
		table.insert(
			events,
			table.freeze({
				tick = tick,
				kind = kind,
				actor = actor,
				target = target,
				amount = amount,
			})
		)
	end

	local function transition(actor: Actor, state: State, duration: number)
		actor.state = state
		actor.endsAt = tick + duration
		emit(state, actor.id, nil, nil)
	end

	local function add(id: string): boolean
		if id == "" or #id > 64 or actors[id] ~= nil or #order >= MAX_ACTORS then
			return false
		end
		actors[id] = {
			id = id,
			state = "Idle",
			health = 100,
			stamina = MAX_STAMINA,
			endsAt = tick,
			attack = nil,
			cooldowns = {},
			sequence = 0,
			bucket = Bucket.new(tick),
		}
		table.insert(order, id)
		table.sort(order)
		return true
	end

	local function remove(id: string): boolean
		if actors[id] == nil then
			return false
		end
		actors[id] = nil
		local index = table.find(order, id)
		assert(index)
		table.remove(order, index)
		return true
	end

	local function request(id: string, payload: unknown): (boolean, string)
		local actor = actors[id]
		if actor == nil then
			return false, "UnknownActor"
		end
		-- Budget even malformed requests, before parsing their contents.
		if not Bucket.consume(actor.bucket, tick) then
			return false, "RateLimited"
		end
		local action = Decoder.decode(payload)
		if action == nil then
			return false, "InvalidPayload"
		end
		if action.sequence <= actor.sequence then
			return false, "StaleSequence"
		end
		actor.sequence = action.sequence
		if actor.state == "Dead" then
			return false, "Dead"
		end
		if action.kind == "Attack" then
			if actor.state ~= "Idle" then
				return false, "InvalidState"
			end
			local moveName = action.move
			assert(moveName)
			local move = Moves[moveName]
			if tick < (actor.cooldowns[moveName] or 0) then
				return false, "Cooldown"
			end
			if actor.stamina < move.cost then
				return false, "Exhausted"
			end
			actor.stamina -= move.cost
			actor.cooldowns[moveName] = tick + move.cooldown
			nextAttackId += 1
			actor.attack = { id = nextAttackId, move = move, hit = {} }
			transition(actor, "Windup", move.windup)
		elseif action.kind == "Cancel" then
			if actor.state ~= "Windup" then
				return false, "InvalidState"
			end
			actor.attack = nil
			transition(actor, "Recovery", CANCEL_RECOVERY_TICKS)
		elseif action.kind == "Guard" then
			if actor.state ~= "Idle" then
				return false, "InvalidState"
			end
			transition(actor, "Guarding", 0)
		else
			if actor.state ~= "Guarding" then
				return false, "InvalidState"
			end
			transition(actor, "Idle", 0)
		end
		return true, "Accepted"
	end

	local function hit(contact: Contact)
		local attacker = actors[contact.attacker]
		local target = actors[contact.target]
		if attacker == nil or target == nil or attacker == target or target.state == "Dead" then
			return
		end
		local attack = attacker.attack
		if
			attacker.state ~= "Active"
			or attack == nil
			or attack.id ~= contact.attackId
			or attack.hit[target.id]
		then
			return
		end
		attack.hit[target.id] = true
		if target.state == "Guarding" then
			if target.stamina >= GUARD_COST then
				target.stamina -= GUARD_COST
				emit("Blocked", target.id, attacker.id, GUARD_COST)
				return
			end
			target.stamina = 0
			target.attack = nil
			transition(target, "Stunned", GUARD_BREAK_TICKS)
			emit("GuardBroken", target.id, attacker.id, nil)
			return
		end
		target.health = math.max(0, target.health - attack.move.damage)
		target.attack = nil
		transition(target, if target.health == 0 then "Dead" else "Stunned", attack.move.stun)
		emit("Hit", attacker.id, target.id, attack.move.damage)
	end

	local function step(contacts: { Contact }?)
		-- Contacts are supplied by trusted host geometry, not the remote command endpoint.
		-- Reject overload before changing time, so a failed host call cannot partially advance.
		assert(contacts == nil or #contacts <= MAX_CONTACTS, "Too many contacts in one tick")
		tick += 1
		for _, id in order do
			local actor = actors[id]
			if actor.state == "Idle" then
				actor.stamina = math.min(MAX_STAMINA, actor.stamina + 1)
			elseif tick >= actor.endsAt then
				local attack = actor.attack
				if actor.state == "Windup" and attack then
					transition(actor, "Active", attack.move.active)
				elseif actor.state == "Active" and attack then
					transition(actor, "Recovery", attack.move.recovery)
				elseif actor.state == "Recovery" or actor.state == "Stunned" then
					actor.attack = nil
					transition(actor, "Idle", 0)
				end
			end
		end
		if contacts then
			-- Canonical ordering removes physics-query enumeration order as a source of variance.
			-- This prototype uses sequential hits; same-tick trades are deliberately not implemented.
			local ordered = table.clone(contacts)
			table.sort(ordered, function(a: Contact, b: Contact)
				if a.attacker ~= b.attacker then
					return a.attacker < b.attacker
				end
				if a.target ~= b.target then
					return a.target < b.target
				end
				return a.attackId < b.attackId
			end)
			for _, contact in ordered do
				hit(contact)
			end
		end
	end

	local function snapshot(id: string): Snapshot?
		local actor = actors[id]
		if actor == nil then
			return nil
		end
		local attack = actor.attack
		return table.freeze({
			id = id,
			tick = tick,
			state = actor.state,
			health = actor.health,
			stamina = actor.stamina,
			attackId = if attack then attack.id else nil,
			stateEndsAt = actor.endsAt,
		})
	end

	local function drainEvents(): ({ Event }, number)
		local batch, lost = events, dropped
		events, dropped = {}, 0
		return batch, lost
	end

	return table.freeze({
		add = add,
		remove = remove,
		request = request,
		step = step,
		snapshot = snapshot,
		drainEvents = drainEvents,
	})
end

return table.freeze({ new = new })
