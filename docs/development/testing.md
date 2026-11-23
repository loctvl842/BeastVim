# Testing

> See also: [`benchmarking.md`](./benchmarking.md) for perf benches. Tests assert behaviour, benches measure speed.

BeastVim's libs are tested with Neovim's own plugin test harness
([`:help dev-test-plugin`](https://neovim.io/doc/user/dev_test/#dev-test-plugin)).

```sh
make test                                                             # everything under test/
make test TEST_FILE=test/libs/finder/bigram_spec.lua                  # one file
make test TEST_FILE=test/libs/finder/bigram_spec.lua TEST_FILTER=tombstones
rm -rf .deps                                                          # refresh the cached harness
```

The harness modules are downloaded to `.deps/` from Neovim's `master`. The `Makefile` is vendored
from `contrib/plugin_test.mk` (`NVIM_TEST_VERSION` and `NVIM_PRG` can be overridden).

## Layout

- `test/libs/<lib>/<name>_spec.lua` mirrors `lua/beast/libs/<lib>/`. Only `*_spec.lua` files are run.
- `test/helper.lua` is the shared setup (`h.clear`, `h.n`).
- Fixtures and non-spec helpers live next to the specs that use them, never as `*_spec.lua`.

## Writing a spec

```lua
local t = require("test.testutil")
local h = require("test.helper")
local n = h.n

t.describe("mylib", function()
	t.before_each(h.clear) -- fresh child Nvim, repo on runtimepath, Util/Theme/Git/View published

	t.it("does the thing", function()
		t.eq(2, n.exec_lua(function()
			return require("beast.libs.mylib").add(1, 1)
		end))
	end)
end)
```

- **Code under test runs in the child Nvim** (`n.exec_lua`); the spec file only drives it and asserts
  with `t.eq`. `exec_lua` functions cannot capture upvalues: pass values as extra arguments.
- **Return plain data.** `nil` comes back as `nil`, but a table cannot hold a `nil` field; return a flag instead.
- **Use the real globals.** `h.clear()` publishes the real `Util`, `Theme`, `Git`, `View`. Stub only what
  reaches outside the process (network, `gh`, `git push`), and do it in the child with a recorder.
- **Wait with `vim.wait` in the child**, never `sleep` in the spec.
- Test through the public surface so tests survive refactors of the internals.
- UI libs: attach a `Screen` (`require("test.functional.ui.screen")`) and use `screen:expect`.
