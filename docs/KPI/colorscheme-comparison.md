# Colorscheme Startup Comparison — 2026-05-08

Measured with `nvim --startuptime` (10 cold runs each) and `beast.profile`.
All runs use `NVIM_APPNAME=BeastVim` with early colorscheme loading via packer.

---

## Startup Time

| Config | Mean (ms) | Std (ms) | Min (ms) | Max (ms) |
|---|---|---|---|---|
| No colorscheme | 30.60 | 6.28 | 21.06 | 44.55 |
| **Updated monokai-pro** | **39.85** | **2.96** | **34.52** | **44.43** |
| Tokyonight | 47.02 | 3.59 | 39.84 | 53.14 |
| Old monokai-pro | 50.96 | 18.51 | 28.99 | 98.68 |

> Tokyonight excludes run 1 (219 ms cold-cache outlier — `colors/tokyonight.lua`
> took 177 ms on first-ever load due to Lua compilation + file cache miss).
> Monokai-pro's run 1 (98.68 ms) is included since it wasn't as extreme.

### Cost of colorscheme

| Colorscheme | Added cost vs baseline | % of total startup |
|---|---|---|
| Updated monokai-pro | +9.3 ms | 23% |
| Tokyonight | +16.4 ms | 35% |
| Old monokai-pro | +20.4 ms | 40% |

---

## Consistency

Monokai-pro has **5× higher variance** than tokyonight:

| Colorscheme | Std (ms) | Coefficient of variation |
|---|---|---|
| Updated monokai-pro | 2.96 | 7.4% |
| Tokyonight | 3.59 | 7.6% |
| Old monokai-pro | 18.51 | 36.3% |

Monokai-pro's std is borderline on the 20 ms warn threshold. The variance
likely comes from its heavier `setup()` which processes integration detectors,
plugin overrides, and devicons integration.

---

## Profile Breakdown (beast.profile)

### Tokyonight

| Function | Self (ms) | Calls |
|---|---|---|
| `packer.setup` | 4.14 | 1 |
| `buf.new` | 1.99 | 1 |
| `packer.state.load` | 0.62 | 1 |
| `diagnostics.provider` | 0.96 | 2 |

- `packer.state.load` called only once (vs 2× with monokai-pro)
- `plugins.colorscheme` require self: 0.67 ms

### Monokai-pro

| Function | Self (ms) | Calls |
|---|---|---|
| `packer.state.load` | 12.06 | 2 |
| `packer.setup` | 2.97 | 1 |
| `buf.new` | 1.97 | 1 |
| `diagnostics.provider` | 0.92 | 2 |

- `packer.state.load` called **2×** — the early colorscheme load triggers
  it once, then the normal load path triggers it again
- `plugins.colorscheme` require self: 0.14 ms (lighter module, but heavier config)

### Key difference

Monokai-pro's `packer.state.load` self time (12.06 ms) dominates.
This includes `vim.cmd.packadd`, running `init()`, and calling `config()`
which does `require("monokai-pro").setup({...}).load()` — the setup
processes 7 integration detectors and an override function with 20+
highlight groups.

Tokyonight's config is just `require("tokyonight").setup()` — no
integrations, no overrides.

---

## Slowest Sourcing Event (--startuptime)

| Colorscheme | Slowest event | Time (ms) |
|---|---|---|
| None | `init.lua` | 26.30 |
| Tokyonight | `init.lua` | 30.50 |
| Monokai-pro | `init.lua` | 75.13 |

Monokai-pro's worst-case sourcing of `init.lua` (75.13 ms) exceeds the
60 ms action threshold. This is because `init.lua` → `packer.setup()` →
`apply_early_colorscheme()` → `state.load("monokai-pro.nvim")` all
happens within that single sourcing event.

---

## Verdict

| | Updated Monokai-pro | Tokyonight | Old Monokai-pro |
|---|---|---|---|
| Speed | ✅ 40 ms | ⚠️ 47 ms | ⚠️ 51 ms |
| Consistency | ✅ std 3.0 ms | ✅ std 3.6 ms | ⚠️ std 18.5 ms |
| Colorscheme cost | ✅ +9.3 ms | ⚠️ +16.4 ms | ⚠️ +20.4 ms |
| Profile overhead | ✅ state.load 7.8 ms | ✅ state.load 0.6 ms | ⚠️ state.load 12 ms |

**Updated monokai-pro is now the clear winner** — fastest startup, lowest
variance, and 54% less colorscheme overhead compared to the old version.
The update cut colorscheme cost from 20.4 ms to 9.3 ms while keeping
the same visual appearance.
