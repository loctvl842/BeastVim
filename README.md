<div align="center">

# 🦁 BeastVim

**A Neovim config built like a product.**

Fast. Measured. Opinionated.

[![Neovim](https://img.shields.io/badge/Neovim-0.10+-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Startup](https://img.shields.io/badge/startup-20ms-success)](#performance-with-receipts)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#license)

</div>

---

## Why BeastVim?

Most Neovim configs are plugin grab-bags that get slow as they grow. BeastVim flips the model: a small, opinionated core with **built-in UI** — `statusline`, `tabline`, `explorer`, `breadcrumb`, fuzzy finder, git signs, key hint — all measured by a real benchmark suite.

- ⚡ **20 ms cold start.** Lazy-loaded, profile-tracked, regression-gated.
- 🎯 **Built-in UI, no plugin bloat.** Heavy plugins replaced by native code.
- 📊 **Latency is a tracked metric.** Real key-to-paint timings in a wezterm pane.
- 🧪 **Every component has a bench.** No "trust me, it's fast."

---

## Install

```sh
git clone https://github.com/loctvl842/BeastVim ~/.config/BeastVim
NVIM_APPNAME=BeastVim nvim
```

Optional alias:

```sh
alias bvim='NVIM_APPNAME=BeastVim nvim'
```

> Requires Neovim **0.10+**, a Nerd Font, `git`.
> Recommended: `ripgrep`, `fd`, a true-color terminal.

---

## Performance, with receipts

Measured on Apple Silicon, fresh clone, default settings.

| Bench | Target | **Measured** | Status |
|---|---|---|---|
| Cold startup (mean of 10) | < 150 ms | **20.91 ms** | ✅ 7× headroom |
| Steady startup | < 50 ms | **19.67 ms** | ✅ |
| `statusline` render | < 1 ms | **11.5 µs** (lualine: 96.8 µs) | ✅ 8× faster |
| `tabline` render | < 1 ms | **153 µs** (bufferline: 1168 µs) | ✅ 7× faster |
| `explorer` full render | < 2 ms | **464 µs** | ✅ |
| `breadcrumb` (winbar) | < 1 ms | **69 µs cold / 1.2 µs hot** | ✅ |
| Git hunk diff (5k lines) | < 10 ms | **2.61 ms** | ✅ |
| Fuzzy match (90k items) | < 80 ms | **17.7 ms** | ✅ 4× headroom |
| Key popup open | < 5 ms | **1.53 ms** | ✅ |

Reproduce any of these:

```sh
# Startup
./scripts/bench-startup.sh

# Any individual component
nvim --clean --headless -l scripts/bench-statusline.lua

# Real key-to-paint latency in a wezterm pane
LOAD_USER_CONFIG=1 ./scripts/bench-ux.sh all
```

Full methodology, knobs, and the leak-hunting workflow:
**[DEVELOPMENT.md](./DEVELOPMENT.md)**.

---

## Philosophy

1. **Measure before you optimise.** Every component has a bench.
2. **Reuse Neovim primitives.** Built-in beats plugin, almost always.
3. **Lazy by default.** If it can wait, it does.
4. **One responsibility per module.** No mega-modules.

---

## License

MIT — do anything you want, attribution appreciated.

<div align="center">

Made with too much caffeine by [loctvl842](https://github.com/loctvl842).

</div>
