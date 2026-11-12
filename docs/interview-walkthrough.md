# Interview walkthrough and practice

## A truthful opening

"I directed a small Luau combat-systems portfolio project. It separates trusted simulation state from input requests and uses deterministic ticks so timing can be tested without a running game. I used AI assistance for the initial implementation and tests, and I'm working through the code and extending it myself."

Update the last sentence only after completing and recording your own work. Avoid claiming production deployment, solo implementation or measured multiplayer performance from this sample.

## Walk through one attack

1. Open `examples/duel.luau`. Explain why the host chooses `fencer`, while the payload specifies only intent and sequence.
2. Follow `CombatWorld.request`. Explain why malformed traffic still consumes the request budget.
3. Open `ActionDecoder`. Show the bounded key loop, integer sequence validation, move lookup and creation of a fresh typed command.
4. Return to `request`. State, cooldown and stamina checks happen before any attack cost is applied.
5. Follow `step`. At the active-start tick, the attack becomes hittable before that tick's contacts are resolved.
6. Follow `hit`. The unique token rejects old contacts; the hit set prevents repeated damage; interruption clears the victim's attack.
7. Read a snapshot and drain events. Explain the difference between authoritative state and lossy diagnostic output.

## Questions you should be able to answer

**Why integer ticks?** They make phase boundaries exact and reproducible. They do not solve latency or physics determinism, and the host still needs a fixed-step driver.

**Why a state machine rather than several booleans?** One state excludes contradictory combinations such as attacking and guarding. The transition code is a readable place to inspect allowed behavior.

**Why validate a typed payload?** Network data is untrusted at runtime. Static types help developers; they do not make remote callers honest.

**Why unique attack IDs?** A delayed contact from an old attack must not damage someone during a later active window. Sequence numbers solve a different problem: replayed commands.

**Why no refund on cancel?** It is an explicit demonstration rule that keeps costs predictable. A refund could be added, but requires tests for repeat cancels and resource caps.

**What happens on simultaneous hits?** Contacts are sorted and resolved sequentially; an earlier hit can interrupt a later one. This is deterministic but potentially unfair. A simultaneous outcome-collection phase would be a separate design decision.

**How does the code scale?** The actor update is O(A), contact sorting O(C log C), and each resolved contact uses map lookups. Storage is bounded by actor/contact/trace limits. There is no published performance benchmark yet.

**What would break if the client supplied contacts?** The client could invent targets and geometry. The current host-only API is a trust contract, not a transport security layer.

## Hands-on exercises for Joshua

Complete these yourself before describing them as your implementation. Keep each in a separate small commit with its test.

1. Add an uppercut-like synthetic move with new placeholder values. First write a test for its active boundary. Explain why the engine code should not need a new branch.
2. Add an explicit `isAlive` query without exposing mutable actor state. Test missing and dead actors.
3. Change guard breaking so the breaking hit deals a small fixed amount of damage. Write the failure first and explain whether the old behavior remains desirable.
4. Build a deterministic same-tick trade resolver on a separate branch. Compare the outcome to the documented sequential policy.
5. Design, on paper first, the Roblox host adapter: authenticated player-to-actor binding, fixed-step driving, geometry queries and disconnect cleanup.

For each exercise, record: prediction, failing test, change, passing result, and one tradeoff. Bring the diff to an interview; it is stronger evidence than memorizing a script.

## Two-minute demonstration

Run the full check command, then the duel. Show the blocked hit at tick 12 and interrupt at tick 60. Open the duplicate-hit and stale-token tests. Finish by naming one deliberate limitation and the next test you would write. Keep the conversation grounded in observable behavior.
