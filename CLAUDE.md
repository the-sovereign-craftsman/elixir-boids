# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Phoenix 1.8 web app (Elixir ~> 1.17). The eventual goal is a boids flocking simulation (`Boids.Boid` GenServers driven by a shared tick), but the codebase today is mostly Phoenix scaffolding plus two unrelated learning features (a `Url` shortener-style CRUD context and a `User` schema) that the user is using to learn Elixir/Phoenix fundamentals.

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

mix precommit   # compile --warnings-as-errors, deps.unlock --unused, format, test — run before finishing any change
mix format      # format only
```

There is no separate lint task beyond `mix format` and `compile --warnings-as-errors`, both covered by `mix precommit`.

## Architecture

- **`Boids.Application`** supervises: `BoidsWeb.Telemetry`, `Boids.Repo`, `DNSCluster`, `Phoenix.PubSub`, a `Boids.DynamicSupervisor` (intended for spawning `Boid` GenServers, not yet wired up), and `BoidsWeb.Endpoint`.
- **`Boids.Boid`** (`lib/boids/boid.ex`) is a `GenServer` meant to represent one boid in the flock, ticking every 17ms (`@tick_interval_ms`) inside a fixed 1000x1000 world arena. Currently the tick loop is a stub (reschedules itself but doesn't update position/velocity or apply flocking rules yet) — this is the active area of in-progress work.
- **Contexts** (`lib/boids/`) follow standard Phoenix context conventions: a context module (e.g. `Boids.Urls`) wraps `Ecto.Repo` calls and changesets for its schema module (e.g. `Boids.Urls.Url`). `Boids.User` is a bare schema with no context module yet.
- **Web layer** (`lib/boids_web/`) is a standard Phoenix router/controller/LiveView split:
  - `router.ex`: `:browser` pipeline for HTML/LiveView routes, `:api` pipeline (JSON only) for `/api/urls` (full REST except `:new`/`:edit`, since there's no HTML form for it).
  - `BoidsWeb.ThermostatLive` is the one existing LiveView, useful as a local reference for LiveView conventions in this codebase.
  - `BoidsWeb.Plugs.Locale` sets locale from request in the `:browser` pipeline.
- **Dev tooling**: `:observer` and `:wx` are included in `extra_applications` only for `Mix.env() == :dev` (needed for `:observer.start()` inside `iex -S mix`), not in `:test`/`:prod`.
