# Verification record

Date: 12 November 2026. Human lead: Joshua Pulliam. Build and automated verification assistance: Codex.

## Scope

- Luau 0.746 CLI execution and strict type checking.
- StyLua 2.4.0 formatting check.
- 29 behavioral tests, including 20,000 seeded simulation ticks checked against a second independent world instance.
- Scripted duel using the same combat module, with a guard block and interrupt.
- Public-file allowlist and basic secret-pattern scan.

The first suite execution failed because the combat module did not yet exist. The implementation then passed the initial 18 tests; additional boundary, lifecycle, guard-break, terminal-death and seeded tests expanded the suite. The initial static check caught read-only type mismatches and an unsupported `warn` global; those were corrected without suppressing the checker.

Five temporary mutations were also detected by the behavioral suite: repeated damage, an early phase transition, accepting a replayed sequence, omitting the stamina charge, and accepting a stale attack token. The original module was restored byte-for-byte afterward.

These are CLI tests, not Roblox Studio, multiplayer or real-network evidence. A generated replay is a bounded invariant check, not exhaustive proof. Public-file scanning is a useful guardrail, not a guarantee that every possible secret format is detectable. No performance figures are claimed.

## Reproduce

```sh
python tools/setup.py
python tools/check.py
```

CI runs the same command. Do not describe hosted CI as passed until its exact commit has actually completed successfully. Local artifact logs are ignored and excluded from publication.

Joshua's manual walkthrough and exercises remain pending; automated results do not imply personal interview readiness.
