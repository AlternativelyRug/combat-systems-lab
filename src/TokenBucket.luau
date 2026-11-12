--!strict
-- Integer token units avoid floating-point drift: each simulation tick refills one unit.
export type Bucket = { units: number, lastTick: number }
local CAPACITY = 80
local COST = 10

local function new(now: number): Bucket
	return { units = CAPACITY, lastTick = now }
end

local function consume(bucket: Bucket, now: number): boolean
	assert(now >= bucket.lastTick, "Token bucket clock moved backwards")
	bucket.units = math.min(CAPACITY, bucket.units + now - bucket.lastTick)
	bucket.lastTick = now
	if bucket.units < COST then
		return false
	end
	bucket.units -= COST
	return true
end

return table.freeze({ new = new, consume = consume })
