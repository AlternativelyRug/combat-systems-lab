--!strict
local Moves = require("./MoveCatalog")

export type Action = {
	kind: "Attack" | "Cancel" | "Guard" | "ReleaseGuard",
	sequence: number,
	move: string?,
}

local function decode(payload: unknown): Action?
	if typeof(payload) ~= "table" then
		return nil
	end
	-- Dynamic values are confined to the transport boundary; never retain the caller's table.
	local raw = payload :: { [any]: any }
	if getmetatable(raw) ~= nil then
		return nil
	end
	local count = 0
	for key in raw do
		count += 1
		if count > 3 or (key ~= "kind" and key ~= "sequence" and key ~= "move") then
			return nil
		end
	end
	local sequence = raw.sequence
	if
		typeof(sequence) ~= "number"
		or sequence ~= sequence
		or sequence < 1
		or sequence > 2147483647
		or sequence % 1 ~= 0
	then
		return nil
	end
	local kind = raw.kind
	if kind == "Attack" then
		if typeof(raw.move) ~= "string" or #raw.move > 32 or Moves[raw.move] == nil then
			return nil
		end
		return { kind = "Attack", sequence = sequence, move = raw.move }
	elseif kind == "Cancel" or kind == "Guard" or kind == "ReleaseGuard" then
		if raw.move ~= nil then
			return nil
		end
		return { kind = kind, sequence = sequence }
	end
	return nil
end

return table.freeze({ decode = decode })
