# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Phoenix 1.8 web app (Elixir ~> 1.17): a boids flocking simulation where every boid is its own BEAM process, rendered live in the browser on a canvas. Flocking rules (separation/alignment/cohesion) are not implemented yet — boids currently move in straight lines and bounce off the arena walls. Ecto/Postgres scaffolding from `phx.new` is still present but unused.

**Read `AGENTS.md` first.** It contains the authoritative Phoenix v1.8 / LiveView / Ecto / HEEx usage rules for this project (form handling, streams, routing aliasing, etc.) — don't duplicate that guidance, just follow it.

## Commands

```bash
mix setup              # deps.get + ecto.setup (create/migrate/seed) + assets setup/build
mix phx.server         # run the server (localhost:4000)
iex -S mix phx.server  # run the server in an IEx shell

mix test                      # run all tests (creates/migrates test DB first via the `test` alias)
mix test test/path/to_test.exs           # run a single file
mix test test/path/to_test.exs:42        # run a single test at a line
mix test --failed                        # re-run only previously failed tests

mix precommit   # compile --warnings-as-errors, deps.unlock --unused, format, credo --strict, test — run before finishing any change
mix format      # format only
mix credo --strict   # lint only (config in .credo.exs)
```

## Architecture

- **`Boids.Application`** supervises: `BoidsWeb.Telemetry`, `Boids.Repo`, `DNSCluster`, `Phoenix.PubSub`, `Boids.BoidPositions`, `Boids.DynamicSupervisor` (holds the boid processes), and `BoidsWeb.Endpoint`.
- **`Boids.Boid`** (`lib/boids/boid.ex`) — pure domain module: the `%Boid{position, velocity}` struct, `new/0` (random position/heading) and `advance_boid/1` (one step + bounce off the 1000x1000 arena). Implements `Boids.BoidBehaviour`.
- **`Boids.BoidServer`** — thin GenServer, one per boid. Ticks on a self-rescheduling `Process.send_after` timer (interval from `config :boids, :tick_interval_ms`; `:manual` in test, so tests send `:tick` themselves), calls the boid module, and writes `{{cell_x, cell_y, self()}, boid}` to ETS (cell from `Boids.BoidSpatialGrid`), deleting the old-cell row when the boid changes cell. The boid module is resolved via `Application.get_env(:boids, :boid_module)` so tests swap in `Boids.BoidMock` (Mox, defined in `test/test_helper.exs`).
- **`Boids.BoidPositions`** — GenServer whose only job is to create and own the `:boid_positions` ETS table (`:ordered_set` keyed `{cell_x, cell_y, pid}` so per-cell reads are prefix range scans, `:public`, named, read/write concurrency). Known gap: rows of dead boids are not cleaned up.
- **`Boids`** (`lib/boids.ex`) — public API: `spawn_boid/0`, `spawn_boids/1`, `list_boid_positions/0`.
- **`BoidsWeb.BoidsSimulationLive`** (routes `/` and `/boids`) — when connected, runs a ~24fps `:render_frame` timer that reads ETS and `push_event`s `"update_boid_positions"` with `[x, y]` lists. A colocated hook (`.BoidCanvas`) draws them on a `phx-update="ignore"` 1000x1000 canvas.
- **Dev tooling**: `:observer` and `:wx` are included in `extra_applications` only for `Mix.env() == :dev` (needed for `:observer.start()` inside `iex -S mix`), not in `:test`/`:prod`.
