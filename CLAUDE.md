# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Phoenix 1.8 web app (Elixir ~> 1.17): a boids flocking simulation where every boid is its own BEAM process, rendered live in the browser on a canvas. Separation, cohesion and alignment can each be toggled at runtime. A telemetry dashboard and a "Break things" panel (kill boids, crash boids, CPU hogs, kill the positions table owner) demonstrate OTP supervision and fair scheduling. There is no database.

**Read `AGENTS.md` first.** It contains the authoritative Phoenix v1.8 / LiveView / HEEx usage rules for this project (form handling, streams, routing aliasing, etc.) — don't duplicate that guidance, just follow it.

## Commands

```bash
mix setup              # deps.get + assets setup/build
mix phx.server         # run the server (localhost:4000)
iex -S mix phx.server  # run the server in an IEx shell

mix test                      # run all tests
mix test test/path/to_test.exs           # run a single file
mix test test/path/to_test.exs:42        # run a single test at a line
mix test --failed                        # re-run only previously failed tests

mix precommit   # compile --warnings-as-errors, deps.unlock --unused, format, credo --strict, test — run before finishing any change
mix format      # format only
mix credo --strict   # lint only (config in .credo.exs)
```

Don't run tests or performance measurements while a dev server is running: 5,000 boids saturate the CPU, skew measurements, and contend for the build lock.

## Architecture

Code is split into `lib/boids/domain/` (pure functions, no processes) and `lib/boids/processes/` (GenServers and supervisors).

**Supervision tree** (`Boids.Application`, `:one_for_one`), in start order:
- `BoidsWeb.Telemetry`, `DNSCluster`, `Phoenix.PubSub`
- `Boids.BoidPositionsSupervisor` (`:rest_for_one`) over `Boids.BoidPositions` (owns the `:boid_positions` ETS table) and `Boids.BoidJanitor` (monitors every boid, deletes rows left by killed boids, counts crashes in a `:persistent_term` counter). If the table owner dies, the janitor restarts with it and re-adopts the running boids.
- `Boids.BoidFlockingRuleToggles` — owns a `:protected` ETS table with the on/off state of each rule; changes go through a `GenServer.call` and are broadcast on PubSub. It never allows cohesion or alignment without separation (separation is the only rule that bounds density; without it neighbor counts and memory grow until the app freezes).
- `Boids.DynamicSupervisor` — one `Boids.BoidServer` per boid, `max_restarts: 10_000` so the failure demos don't exhaust the restart limit.
- `Boids.CpuHogSupervisor` — busy-looping `Boids.CpuHog` tasks for the fair-scheduling demo.
- `Boids.SimulationMetrics` — samples once a second (tick rate, process counts, scheduler utilization, memory, reductions split boids/hogs/other, restarts) and broadcasts a snapshot plus a 60-sample history.
- `BoidsWeb.Endpoint`

**Domain modules:** `Boids.Boid` (struct `position`, `velocity`, `spawned_at_ms`; `new/0`, `advance_boid/3`), `Boids.BoidFlockingRules` (the three steering vectors, weighted and summed), `Boids.BoidFlockingConfig` (radii, weights, speeds), `Boids.BoidSpatialGrid` (position → cell math), `Boids.World` (1000×1000 arena).

**`Boids.BoidServer`** — ticks on a self-rescheduling `Process.send_after` (`config :boids, :tick_interval_ms`; `:manual` in test, so tests send `:tick` themselves). Each tick it reads the toggles, looks up neighbors (skipped when every rule is off), advances the boid, writes `{{cell_x, cell_y, self()}, boid}` to ETS, and deletes the old-cell row when it changes cell. It traps exits and deletes its own row in `terminate/2`. The boid module comes from `Application.get_env(:boids, :boid_module)` so tests can swap in `Boids.BoidMock` (Mox, defined in `test/test_helper.exs`).

**`Boids.BoidPositions`** — the table is an `:ordered_set` keyed `{cell_x, cell_y, pid}`, so a cell is a prefix range scan. `boids_within_radius/3` filters by squared distance inside a match spec, so only real neighbors are copied out of ETS.

**`Boids`** (`lib/boids.ex`) — public API: spawning/removing/capping boids (max 5,000), the failure scenarios (`kill_boids/1`, `crash_boids/1`, `kill_boid_positions_owner/0`, CPU hogs), toggles and metrics.

**`BoidsWeb.BoidsSimulationLive`** (routes `/` and `/boids`) — controls, the canvas and the dashboard (`BoidsWeb.SimulationDashboardComponents`). A ~24 fps `:render_frame` timer reads ETS and `push_event`s `[x, y, newness]` per boid; a colocated hook draws them on a `phx-update="ignore"` canvas, with recently respawned boids flashing red.

**Dev tooling**: `:observer` and `:wx` are in `extra_applications` only for `Mix.env() == :dev` (for `:observer.start()` inside `iex -S mix`).
