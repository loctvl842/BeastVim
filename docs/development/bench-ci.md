# Startup Benchmark CI — gh-pages dashboard

> See also: [`benchmarking.md`](./benchmarking.md) for the bench contract and inventory, [`writing-benches.md`](./writing-benches.md) for adding new benches.

BeastVim publishes startup-time history to a public chart so we can spot regressions commit-by-commit, day-by-day.

- **Dashboard:** <https://loctvl842.github.io/BeastVim/dev/bench/>
- **Workflow:** [`.github/workflows/bench.yml`](../../.github/workflows/bench.yml)
- **Adapter:** [`scripts/bench-to-benchmark-json.sh`](../../scripts/bench-to-benchmark-json.sh)
- **Bench source:** [`scripts/bench-startup.sh`](../../scripts/bench-startup.sh) (hyperfine JSON export)

---

## What gets published

Each workflow run produces four datapoints — all in milliseconds, smaller is better:

| Metric | Source field | Meaning |
|---|---|---|
| `BeastVim startup (warm) mean`   | `results[0].mean`   | Average wall-clock startup across runs |
| `BeastVim startup (warm) stddev` | `results[0].stddev` | Run-to-run consistency |
| `BeastVim startup (warm) min`    | `results[0].min`    | Best observed run |
| `BeastVim startup (warm) max`    | `results[0].max`    | Worst observed run |

These are extracted from the hyperfine JSON emitted by `bench-startup.sh` and reshaped into the `customSmallerIsBetter` format expected by [`benchmark-action/github-action-benchmark`](https://github.com/benchmark-action/github-action-benchmark).

---

## When it runs

| Trigger | Behavior |
|---|---|
| Push to `main`              | Run bench → **append** datapoint to `gh-pages/dev/bench/data.js` → redeploy Pages |
| Pull request targeting `main` | Run bench → **compare** vs prior best → comment on PR if any metric is > 115 % of best |
| `workflow_dispatch`         | Manual run from the Actions tab |

`fail-on-alert` is **off**, so a regression posts a comment but doesn't block merging. Flip it on in `bench.yml` if you want hard gates.

---

## Reading the dashboard

The published page is a Chart.js dashboard with one chart per metric. Hover any point to see:

- Commit SHA + message
- Exact value (ms)
- Date/time of the run

The y-axis is the metric value; the x-axis is chronological commit order. A datapoint highlighted red means it tripped the 115 % regression threshold.

---

## Caveats — CI numbers ≠ your laptop

The workflow runs on **GitHub-hosted `ubuntu-latest`** runners. Absolute values will differ from your local Mac because:

- Different CPU (Intel Xeon vs Apple Silicon)
- Different OS (Linux vs Darwin)
- Different I/O subsystem
- No dyld/exec overhead the way macOS has it

**What matters is the trend, not the absolute number.** If the chart line slopes up, something you merged got slower — go check the commit.

For wall-clock truth on your dev machine, keep running `./scripts/bench-startup.sh 20 warm` locally.

---

## How the workflow is wired

1. **Install Neovim stable** from the official Linux tarball (pinned to the `stable` release for reproducibility).
2. **Install `hyperfine` + `jq`** via apt.
3. **Stage the repo** into `~/.config/BeastVim/` so `NVIM_APPNAME=BeastVim` resolves.
4. **Prime** the config with `nvim --headless +qa`. BeastVim is fully self-configured: `lua/beast/libs/packer` calls `vim.pack.add()` during `setup()`, so the first headless start clones any missing plugins synchronously. A second headless start warms caches before measurement.
5. **Run** `./scripts/bench-startup.sh 20 warm BeastVim`.
6. **Adapt** the latest `~/.cache/beast-bench/startup-BeastVim-warm-*.json` via `bench-to-benchmark-json.sh` into `bench-result.json`.
7. **Publish** with `benchmark-action/github-action-benchmark@v1` — pushes to `gh-pages` on `main`, comments-only on PRs.

---

## One-time setup (already done — for posterity)

These steps were required exactly once when wiring this up. Document here so future-you (or a fork) knows the dance:

1. Commit `.github/workflows/bench.yml` and `scripts/bench-to-benchmark-json.sh`.
2. **Seed the `gh-pages` branch** as an orphan — the action will not create it on first run:
   ```sh
   git switch --orphan gh-pages
   echo "# BeastVim benchmarks" > index.md
   git add index.md
   git commit --no-verify -m "chore(gh-pages): initialize benchmark dashboard branch"
   git push --no-verify -u origin gh-pages
   git switch main
   ```
   `--no-verify` bypasses the codemap-freshness pre-commit/pre-push hooks, which don't apply to the docs-only `gh-pages` branch.
3. **Enable GitHub Pages** pointing at `gh-pages` / root:
   ```sh
   gh api -X POST repos/loctvl842/BeastVim/pages \
     -f 'source[branch]=gh-pages' -f 'source[path]=/'
   ```
   Or via UI: Repo → Settings → Pages → Source: *Deploy from branch* → `gh-pages` / `/ (root)`.
4. Wait ~60 s for the first Pages build, then visit the dashboard URL.

After that, everything is automatic.

---

## Tuning knobs

Open [`.github/workflows/bench.yml`](../../.github/workflows/bench.yml) and edit:

| Knob | Default | What to change it to |
|---|---|---|
| Runs per measurement       | `20`         | More (slower, smoother) or fewer (faster, noisier) |
| Bench mode                 | `warm`       | `cold` if you care about dyld/exec — but cold needs `sudo purge` which CI can't do, so this is local-only |
| `alert-threshold`          | `115%`       | Tighter (`110%`) or looser (`125%`) regression sensitivity |
| `fail-on-alert`            | `false`      | `true` to block PRs on regressions |
| `alert-comment-cc-users`   | `@loctvl842` | Add reviewers who should be pinged on regression |

---

## Extending — track a second config as a baseline

To plot a different Neovim config on the same chart for comparison (e.g. a previous BeastVim release tag, or an upstream distro like LazyVim/AstroNvim/NvChad):

1. Stage the other config under a second `NVIM_APPNAME` in a parallel workflow step.
2. Run `./scripts/bench-startup.sh 20 warm <APPNAME>`.
3. Adapt with a different label: `bench-to-benchmark-json.sh <json> "<APPNAME> startup (warm)"`.
4. Concatenate the two JSON arrays into one `bench-result.json` (`jq -s 'add'`).

The dashboard will render each `NVIM_APPNAME` as a separate line under the same chart.
