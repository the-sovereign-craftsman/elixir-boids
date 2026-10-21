# Elixir Boids

[![CI](https://github.com/the-sovereign-craftsman/elixir-boids/actions/workflows/ci.yml/badge.svg)](https://github.com/the-sovereign-craftsman/elixir-boids/actions/workflows/ci.yml)

A flocking simulation where **every boid is its own Erlang process**. 5,000 independent processes, each ticking 30 times a second, rendered live in the browser with Phoenix LiveView.

It's a hands-on example of Elixir concurrency and the features the BEAM gives you for free: **lightweight processes**, **preemptive scheduling**, **supervision trees** and **"let it crash"** fault tolerance. Kill thousands of boids and their supervisor brings them back. Corrupt their state and they crash and heal. Start processes that spin forever and the scheduler keeps the flock moving anyway. A live dashboard shows what the VM is doing the whole time.

<!-- TODO(gif): hero shot. 5,000 boids, all rules on, dashboard visible. -->

## Run it

The quickest way is Docker. No Elixir or Erlang needed:

```bash
docker run --rm -p 4000:4000 ghcr.io/the-sovereign-craftsman/elixir-boids
```

Then open **http://localhost:4000**. Press `Ctrl+C` in the terminal to stop it.

> Don't have Docker? Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows, Mac or Linux), start it once, then run the command above.

### From source

With Elixir 1.20 and Erlang/OTP 28 installed:

```bash
mix setup
mix phx.server
```

Then open **http://localhost:4000**. There's no database or other service to set up.

## What to try

1. **Set the flock size** to 5,000 and turn on all three flocking rules.
2. **Toggle the rules** one at a time to see what each contributes:
   - **Separation** steers away from boids that are too close.
   - **Alignment** matches the heading of nearby boids.
   - **Cohesion** steers toward the center of nearby boids.
3. **Break things** with the controls under the canvas, and watch the dashboard.

## Break things

Each scenario demonstrates one part of OTP. Boids that were just restarted flash red, so you can see the recovery happen.

| Scenario | What happens | What it shows |
|---|---|---|
| **Kill boids** | Random boid processes are killed outright (`Process.exit(pid, :kill)`). | The `DynamicSupervisor` starts a replacement for each one immediately. The process count holds at 5,000 while "Restarts" climbs. |
| **Crash boids** | Boids' state is corrupted, so their own code raises on the next tick. | "Let it crash". No defensive code, no try/rescue. The failure stays inside one process, and the supervisor restarts it with fresh state. |
| **CPU hogs** | Processes that loop forever, never waiting or yielding. Start one, or one per core. | Preemptive scheduling. The BEAM switches processes after a fixed budget of work, so a hog can't starve the boids. The stacked CPU bar fills, and the flock keeps moving. |
| **Kill the positions table owner** | Kills the process that owns the ETS table holding every boid's position. | ETS tables die with their owner. A `rest_for_one` supervisor restarts the table and its cleanup process together, and the boids repopulate it on their next tick. |

<!-- TODO(gif): one clip per scenario. -->

## Why only 5,000 boids?

The BEAM is known for running millions of processes, and it can. An idle process costs about 2.6 KB, and a million of them start in just over a second. What limits this demo is the **work each process does**, not the number of processes.

Every boid is busy all the time. Thirty times a second, each one wakes up, copies its neighbors out of ETS and computes a new velocity. At 5,000 boids that's 150,000 wakeups a second, enough to keep most of the cores on a multi-core machine busy. Adding boids makes it worse faster than you'd expect. As the arena gets denser, each boid has more neighbors to process. Double the flock and the work roughly quadruples. Any runtime doing this much computation per entity hits the same wall.

The million-process systems the BEAM is famous for are made of processes that mostly wait: connections, sessions, timers. This demo shows the other side, a few thousand processes that are all working at once, and that's where the BEAM's concurrency model shows its strengths:

- **Preemptive scheduling.** No boid, and no runaway process, can hold a CPU core. Every process gets its turn, so the flock keeps moving even with a busy-looping process on every core.
- **Isolation.** Each boid has its own heap and its own garbage collection. A boid that crashes takes nothing else with it, and garbage collection never pauses the whole flock.
- **Supervision.** Thousands of processes can fail at once and are replaced within milliseconds, without any error-handling code in the boids themselves.

The cap is set at 5,000 so the simulation stays smooth on an ordinary laptop, with headroom left for the scenarios above to visibly stress it.

## How it works

### One process per boid

Each boid is a `GenServer` (`Boids.BoidServer`). About 30 times a second it:

1. finds its neighbors,
2. computes its new velocity from the enabled flocking rules (pure functions in `Boids.BoidFlockingRules`),
3. writes its new position to a shared ETS table.

No boid ever messages another. They coordinate only through that table, the same way real birds only watch each other.

### Finding neighbors with a spatial grid in ETS

Checking every boid against every other would be 25 million distance checks per tick at 5,000 boids. Instead, the 1000×1000 arena is divided into cells the size of a boid's perception radius, and the table is an `:ordered_set` keyed by `{cell_x, cell_y, pid}`. Rows in the same cell sit next to each other, so a boid reads the 9 cells around it as a handful of short range scans. The distance check runs inside ETS itself (a match spec), so only real neighbors are copied into the boid's process.

### Supervision tree

```
Boids.Supervisor (one_for_one)
├── Phoenix.PubSub
├── Boids.BoidPositionsSupervisor (rest_for_one)
│   ├── Boids.BoidPositions          owns the positions ETS table
│   └── Boids.BoidJanitor            monitors boids, cleans up after killed ones, counts crashes
├── Boids.BoidFlockingRuleToggles    which rules are on (ETS + PubSub)
├── Boids.DynamicSupervisor          one Boids.BoidServer per boid
├── Boids.CpuHogSupervisor           the CPU hogs, kept apart from the boids
├── Boids.SimulationMetrics          samples the VM once a second for the dashboard
└── BoidsWeb.Endpoint                the LiveView page
```

### The page

`BoidsWeb.BoidsSimulationLive` reads the positions table 24 times a second and pushes them to the browser, where a small JavaScript hook draws them on a canvas. The dashboard subscribes to `Boids.SimulationMetrics` and shows process counts, tick rate, restarts, scheduler utilization per core, where the CPU work goes (boids, hogs, everything else) and memory.

## Design notes

Why the system is built the way it is, measured at 5,000 boids.

- **Every boid is a process, and processes share nothing.** Each `BoidServer` has its own heap and is garbage-collected on its own, so a boid crashing or being killed affects nothing but itself. That isolation is what makes "let it crash" safe here: there's no shared state for a failure to corrupt.
- **Reads from ETS copy data, so the app copies as little as possible.** Reading a row copies it into the reading process's heap. With every flocking rule off, boids skip the neighbor lookup entirely, because copying neighbors nobody uses was most of the cost (about 1.2 GB of memory and 45% CPU, against 230 MB and 7% without it).
- **Neighbors are filtered inside ETS.** The distance check runs inside the table as a match spec, so only real neighbors are copied out, not every row in the 9 surrounding cells. That more than halves memory with every rule on (1.8 GB to 0.8 GB).
- **Cohesion and alignment require separation.** Separation is the only rule that pushes boids apart. Cohesion pulls them together, and alignment lets groups merge and never split. Without separation, density climbs without limit, and so does the work of copying neighbors. With alignment alone, the busiest grid cell went from 27 boids to over 500 and memory reached 3 GB in 20 seconds. The rule toggles enforce this, turning separation on or the other rules off as needed.
- **The positions table and its janitor restart together.** An ETS table is deleted when its owner dies, and the janitor that cleans up after killed boids can't work without the table. A `rest_for_one` supervisor over the pair restarts the janitor whenever the table owner restarts. The boid supervisor is deliberately outside that group. Restarting it would start an empty flock.

## Development

```bash
mix test          # run the tests
mix precommit     # compile with warnings as errors, format, credo --strict, test
```

CI runs the same checks on every push, then builds the Docker image for Intel and ARM, smoke-tests it, and publishes it to the GitHub Container Registry.

## License

[MIT](LICENSE)
