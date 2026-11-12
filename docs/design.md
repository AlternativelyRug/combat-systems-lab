# Design contract

## Ownership and time

`CombatWorld.new()` owns its actor map through closures. Callers receive a frozen method table and fresh frozen snapshots; they cannot change health by editing a snapshot. Removing an actor removes its state, request budget and cooldowns. Attack identifiers remain unique within the world across removal/re-registration.

The host calls `step` exactly once per simulation tick, intended at 60 Hz. The module does not read wall-clock time or schedule work. Commands between ticks execute in their call order. On each step:

1. Reject a contact batch larger than 512 before mutating time.
2. Advance the tick counter.
3. Visit actors in sorted ID order. Regenerate one stamina unit if already idle; otherwise process an expired phase.
4. Sort trusted contacts by attacker, target and attack ID; resolve them sequentially.

A jab requested at tick 0 is in windup through tick 11, active at ticks 12–15, recovery at 16–33 and idle at 34. Contacts at the active start count; contacts at the active end do not. There is no elapsed-time shortcut: the host must process every tick and its geometry. A catch-up budget and overload policy belong to the eventual host adapter.

## Request boundary

The authenticated host binds `id`. Payloads contain only `kind`, `sequence`, and an attack's `move`. No client-supplied identity, damage, timestamp, stamina or hit result is accepted.

Budget every request before decoding, including malformed requests. Each actor has an eight-request burst capacity and regains one request per ten ticks. These are demonstration limits, not a recommended production tuning profile. Unknown identities allocate nothing.

After decoding, sequence numbers must increase. A decoded gameplay rejection consumes its sequence; retrying a cooldown failure with the same sequence cannot later become an attack. Rate-limited or malformed requests do not update the sequence because they do not reach that stage. Sequence state resets only when the trusted host removes and recreates an actor; a real transport needs session binding as well.

## Combat rules

Attacks require idle state, an expired move cooldown and sufficient stamina. Acceptance spends stamina and starts the cooldown atomically. There is no cancellation refund. Windup can be cancelled into six recovery ticks; active and recovery cannot be cancelled.

Contacts must match the attacker's current unique attack ID and active phase. Self hits, unknown actors, dead targets and repeated hits against the same target ID are ignored. A damaging hit clears the target's attack and applies stun or terminal death. Guard spends 120 stamina units per contact; insufficient stamina breaks guard into 30 ticks of stun without health damage on that breaking hit.

Stamina is an integer from 0–1000. Idle regeneration adds one unit per tick and clamps at the maximum. Guard and attacking states do not regenerate. Health clamps to zero. These rules are intentionally small enough to inspect completely.

## Determinism and lifecycle tradeoffs

Sorted iteration makes traces independent of registration order and contact enumeration order. It does not guarantee cross-machine lockstep physics, fairness of sequential hit ordering or network determinism. Identical initial state and identical ordered commands/contact sets produce identical logical results in the tested CLI runtime.

The active hit set retains target IDs until the attack ends. If a target is removed and re-added under the same ID during that attack, it cannot be hit again by that attack. This conservative respawn policy is deliberate.

The world accepts at most 128 actors, 512 contacts per tick, and retains at most 256 undrained events. Once the event queue fills, newer diagnostic events are counted as dropped; combat still runs. Diagnostics are not an authoritative replication channel. The host should drain them regularly. Snapshot creation and contact sorting allocate; this is not marketed as allocation-free code.

## Security and integration work still required

Real geometry, distance/line-of-sight checks, equipment ownership, authenticated session identity, disconnect lifecycle and remote serialization belong in a reviewed Roblox adapter. This sample has none of those services. Do not expose host contacts to a client or claim this module alone prevents cheating. Input release/retry behavior and real latency must be tested when a transport is added.

Future improvements should start with a failing observable test and an explicit rule. Keep balance data separate from mechanisms; avoid building generic extension points before a second real use case exists.
