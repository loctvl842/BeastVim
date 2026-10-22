---
name: review
description: New standalone lib that hosts a loopback WebSocket/MCP server for Claude Code's IDE protocol and reviews openDiff proposals as an inline Current vs Incoming diff with per-hunk accept/reject
generated: 2026-10-22
---

> PM Spec: [docs/pm-specs/review-init.md](../pm-specs/review-init.md)

# Summary
Build `lua/beast/libs/review/`, a self-contained lib in two halves: a renderer/session core that shows a proposed file content as inline hunks over a buffer and resolves to saved or rejected, and a pure-Lua WebSocket + MCP server that lets Claude Code's `openDiff` drive that core. The core is delivered first with no networking, as a public `propose()` API, so it is testable headless and reusable by the later external-change watcher (slice B).

---

# Context

## Problem
Claude Code writes files on disk with no chance for review in Neovim. Its IDE protocol (reverse-engineered, loopback WebSocket carrying MCP) lets an editor intercept edits: Claude sends `openDiff` with the full proposed content, blocks, and waits for `FILE_SAVED` or `DIFF_REJECTED`. BeastVim has no WebSocket server, no inline proposal diff, and no lock-file writer, so Claude never takes the review path.

### Solution
A new `review` lib with its own config, highlights, health, and namespace, independent of `beast.libs.git`. `review.propose()` takes a path and proposed content, paints hunks via extmarks (Current lines banded red, Incoming lines as green virtual lines), applies per-hunk decisions to the buffer, saves on completion, and calls back with `saved` or `rejected`. A `server/` subtree speaks WebSocket and JSON-RPC and maps `openDiff` onto `propose()`, replying when the callback fires.

---

# Research

## Repo Search
- Searched for: `sha1|base64|websocket|new_tcp|fs_event|new_pipe`, `checktime|autoread|FileChangedShell`, `vim.text.diff`, `packer.lazy` wiring, highlight registry, existing tests, `<leader>r` / `]r` / `[r` keymaps.
- Found: `lua/beast/libs/git/diff.lua` is a thin `vim.text.diff` wrapper (backend selection only); `git/conflict.lua` has the visual language (bands + eol labels) but is coupled to the git lib's namespace and highlights; `explorer/watch.lua` and `image/` use `vim.uv` handles with debounce via `Util.debounce`; `lua/beast/hl_reload.lua` holds `highlight_modules`; lib conventions are in `docs/development/lib-conventions.md`; test pattern is `tests/test-*.lua` run with `nvim --clean --headless -l`. No WebSocket, SHA-1, or TCP server code exists in the repo. `<leader>r*`, `]r`, `[r` are unused. `~/.claude/ide` does not exist on this machine.
- Reuse opportunity: Yes - `Util.debounce`, the `config.lua` read-only proxy pattern, `highlights.lua` + `Util.colors.build`, `hl_reload.highlight_modules` registration, `beast.libs.notify` for notices, `packer.lazy` wiring. Reference only: `git/conflict.lua` visuals. Not reused: `git/diff.lua` (the lib calls `vim.text.diff` directly to stay independent of git).

## Built-in / Existing Lib Check
- Checked: `vim.text.diff` (indices result), `vim.uv` TCP (`new_tcp`, `bind`, `getsockname`, `listen`), `vim.json`, `vim.base64` (present), `vim.fn.sha256` (present, but no SHA-1), LuaJIT `bit` (`pcall(require, "bit")` is true on this Neovim 0.12), `vim.uv.random` (CSPRNG), `vim.uv.os_getpid`, extmarks with `virt_lines` / `line_hl_group`, `nvim_buf_set_lines`.
- Found: everything needed except SHA-1, which the WebSocket handshake (`Sec-WebSocket-Accept`) requires. SHA-1 must be written in Lua on top of `bit`. Reference implementation for the protocol surface: `coder/claudecode.nvim` (`server/`, `lockfile.lua`, `tools/open_diff.lua`), cloned read-only into the scratchpad; used for method names and result shapes only, not copied.
- Decision: **Build** - no existing lib covers server, protocol, or the proposal renderer. **Use** Neovim built-ins for diff, base64, JSON, TCP, random. **Reuse** debounce, config proxy, highlight registry, notify.

### Protocol facts used (reverse-engineered, not official)
- Lock file: `~/.claude/ide/<port>.lock` (or `$CLAUDE_CONFIG_DIR/ide/`), JSON `{pid, workspaceFolders, ideName, transport="ws", authToken}`.
- Auth: WebSocket upgrade must carry header `x-claude-code-ide-authorization: <authToken>`.
- Methods to answer: `initialize`, `notifications/initialized`, `prompts/list`, `tools/list`, `tools/call`.
- `openDiff` args: `old_file_path`, `new_file_path`, `new_file_contents`, `tab_name`. Result: MCP `content[0].text` is `FILE_SAVED` or `DIFF_REJECTED`. The JSON-RPC response is deferred until the user decides.
- Also expected by the CLI: `close_tab` and `closeAllDiffTabs` (reply `TAB_CLOSED` / ok), `getOpenEditors`, `getWorkspaceFolders`, `openFile`, `getDiagnostics`. The PM spec limits scope to what makes the review work, so Phase 4 implements `openDiff`, `close_tab`, `closeAllDiffTabs`, and minimal `getOpenEditors` / `getWorkspaceFolders` / `openFile`; unknown tools return a JSON-RPC "method not found" style error.

### PM spec gaps and flags
1. The PM spec shows a "Review: ... hunk 1/2" message line. A cmdline message would be overwritten constantly, so this spec puts "1/2" in the Incoming label and uses notify only for start and finish notices.
2. Partial accept replies `FILE_SAVED` even though content differs from Claude's proposal (PM behavior rule). Verify against a real Claude Code session in Phase 5; if Claude misbehaves, the fallback is replying `DIFF_REJECTED` with no save on partial accepts, which needs a PM spec change.
3. Pending-review state is held in memory only; a Neovim crash leaves Claude's blocked call to time out on its side.

---

# Architecture Changes
- New `lua/beast/libs/review/init.lua` - `M.meta`, `M.setup(opts)`, public API `propose`, `status`, `start`, `stop`; `:Review` command.
- New `lua/beast/libs/review/config.lua` - read-only proxy; defaults: `enabled = false`, `focus = true`, `keys` (accept, reject, accept_all, reject_all, next, prev), `server = { host = "127.0.0.1" }`.
- New `lua/beast/libs/review/highlights.lua` - `BeastReview*` groups (Current, CurrentLabel, Incoming, IncomingLabel), derived from theme palette; registered in `lua/beast/hl_reload.lua`.
- New `lua/beast/libs/review/hunks.lua` - pure: diff buffer lines vs proposed lines into hunks; line splitting/EOL normalization.
- New `lua/beast/libs/review/render.lua` - extmark painting per hunk and removal.
- New `lua/beast/libs/review/session.lua` - one session per buffer: hunk states, accept/reject, completion (save, callback), queueing of a second proposal for the same buffer, cancel.
- New `lua/beast/libs/review/keymaps.lua` - buffer-local keys installed on session start, removed on end.
- New `lua/beast/libs/review/server/` - `init.lua` (lifecycle, client registry), `tcp.lua`, `handshake.lua`, `frame.lua`, `sha1.lua`, `jsonrpc.lua` (dispatch + deferred responses), `mcp.lua` (MCP method table; added during Phase 4 so every protocol-facing name lives in one file), `tools.lua` (tool table), `lockfile.lua`.
- New `tests/review_ws_client.lua` - shared fake WebSocket client used by the ws and protocol tests.
- New `lua/beast/libs/review/health.lua`.
- Modify `lua/beast/init.lua` - `packer.lazy("beast.libs.review", ...)` gated on config; `:Review` command trigger.
- Modify `lua/beast/hl_reload.lua` - add `beast.libs.review.highlights`.
- Modify `docs/CODEMAP/libraries.md` - add the lib.
- New tests: `tests/test-review-hunks.lua`, `tests/test-review-session.lua`, `tests/test-review-ws.lua`, `tests/test-review-protocol.lua`.

## Implementation Phases

## Phase 1: Hunk engine - pure functions, no UI, no network
1. **Hunk computation** (File: `lua/beast/libs/review/hunks.lua`)
   - Action: Split proposed content into lines (strip one trailing newline, record whether the proposal ends with one). Call `vim.text.diff` with `result_type = "indices"` against the buffer lines. Return a list of normalised hunks `{ row (0-based), old_count, old = string[], new = string[] }` meaning "replace buffer rows [row, row + old_count) with new" (implemented shape; replaces the raw `a_start/b_start` form). Phase 2 must pass `{}` (not `{""}`) as Current for an empty or new-file buffer. Handle the new-file case (Current = empty list, not `{""}`) and identical content (empty list).
   - Why: Everything else depends on a correct, testable hunk model. Pure code means fast headless tests.
   - Depends on: None
   - Risk: Low (pitfall: pure insertion/deletion hunks where `count_a` or `count_b` is 0 use "after line N" indexing).
2. **Headless tests** (File: `tests/test-review-hunks.lua`)
   - Action: Cases: replace, pure insert (start, middle, end), pure delete, multi-hunk, identical, empty file to content, content with and without trailing newline, CRLF input.
   - Why: Locks the indexing semantics before UI is built on them.
   - Depends on: Step 1
   - Risk: Low

## Phase 2: Review session - the user-facing core via `propose()`
1. **Config and highlights** (Files: `config.lua`, `highlights.lua`, edit `lua/beast/hl_reload.lua`)
   - Action: Add the proxy config and highlight groups; register in the highlight registry.
   - Why: Required by lib conventions; render needs the groups.
   - Depends on: None
   - Risk: Low
2. **Renderer** (File: `render.lua`)
   - Action: Per hunk, set an anchor extmark over the Current lines (`line_hl_group` red band, eol label "Current"), and attach the Incoming lines as `virt_lines` below the range (green band, label "Incoming (Claude) i/n"). Pure inserts anchor on the preceding line. Own namespace `beast_review`. `clear(buf)` / `clear_hunk(buf, id)`.
   - Why: Display only, so no conflict markers can ever reach disk.
   - Depends on: Phase 1, step 1 of this phase
   - Risk: Medium (`virt_lines` with long wrapped lines; band width on `nowrap`).
3. **Session logic** (File: `session.lua`)
   - Action: `Session.new(buf, proposed, on_done)` computes hunks and paints. `accept(hunk)` replaces the extmark's current range with `new` via `nvim_buf_set_lines` and clears the hunk; `reject(hunk)` clears it. Hunk position comes from the extmark so earlier accepts that shift line numbers do not break later hunks. When all hunks are decided: if any accepted, write the buffer (creating parent dirs for new files) and call `on_done("saved", {accepted, rejected, included_user_edits})`; else call `on_done("rejected")`. `cancel()` clears everything with no write and calls `on_done("cancelled")`. `BufWipeout`/`BufUnload` on the buffer counts as reject-all. Per-buffer queue: a second `propose` for a buffer with an active session waits.
   - Why: This is the entire review behavior from the PM spec, independent of any protocol.
   - Depends on: Step 2
   - Risk: High (extmark ranges after user edits inside a hunk; invalid extmark at accept time must skip that hunk with a notice rather than corrupt the buffer; new-file buffer and rejection cleanup; undo grouping so one accept is one undo step).
4. **Keymaps** (File: `keymaps.lua` - superseded, see note)
   - **Changed after Phase 5 (user request):** the buffer-local keymaps and `keys` config were removed. Keys are now global bindings registered via `packer.lazy({ keys = ... })` in `lua/beast/init.lua`, so they appear in the key lib's cheatsheet. `review.accept/reject/accept_all/reject_all/next_hunk/prev_hunk` act on the current buffer's pending review and notify "no review pending in this buffer" otherwise. Remapping is done in that packer spec, not in `review/config`.
   - Action: On session start, install buffer-local maps (defaults `<leader>ra` accept hunk, `<leader>rr` reject hunk, `<leader>rA` accept all, `<leader>rR` reject all, `]r` / `[r` navigate), saving and restoring any existing buffer-local maps; remove on session end.
   - Why: Keys exist only while a review is pending (PM rule).
   - Depends on: Step 3
   - Risk: Medium
5. **Public API and command** (File: `init.lua`)
   - Action: `M.meta`, `M.setup`, `M.propose(path, contents, on_done)` which opens or finds the buffer (focus per config, jump to first hunk) and starts a session; `:Review propose <path>` reading a file as the proposal, for manual testing in Phase 2 only; start/finish notices through `beast.libs.notify`.
   - Why: Makes the core demonstrable and testable before any networking exists.
   - Depends on: Steps 1-4
   - Risk: Medium
6. **Tests** (File: `tests/test-review-session.lua`)
   - Action: Headless: accept all, reject all, mixed, order of decisions with line shifts, new file, close buffer mid-review, queued second proposal, cancel, unsaved edits included.
   - Why: Covers PM scenarios 1, 2, 3, 5, 7, 9 without a network.
   - Depends on: Step 5
   - Risk: Low

## Phase 3: WebSocket server - transport only
1. **SHA-1 and base64** (File: `server/sha1.lua`)
   - Action: SHA-1 over a string using LuaJIT `bit`, returning raw bytes; use `vim.base64.encode` for the accept key.
   - Why: No SHA-1 in Neovim; the handshake needs it.
   - Depends on: None
   - Risk: Medium (test against RFC 3174 vectors and the RFC 6455 example key).
2. **Handshake** (File: `server/handshake.lua`)
   - Action: Parse the HTTP upgrade request (buffer until `\r\n\r\n`, cap header size), require `Upgrade: websocket` and `Sec-WebSocket-Key`, compare `x-claude-code-ide-authorization` to the token with a constant-time compare, reply `101` or `401`.
   - Why: Authentication is the only barrier on the loopback socket.
   - Depends on: Step 1
   - Risk: High (security-sensitive; reject missing and wrong tokens before any other processing).
3. **Frames** (File: `server/frame.lua`)
   - Action: Parse masked client frames (lengths 7/16/64 bit), fragmentation, ping/pong, close; encode unmasked server text frames. Cap payload size (config, default 16 MB).
   - Why: Required to carry JSON-RPC.
   - Depends on: None
   - Risk: Medium
4. **TCP server** (Files: `server/tcp.lua`, `server/init.lua`)
   - Action: Bind `127.0.0.1` on port 0, read the port via `getsockname`, accept clients, run handshake then frame loop, deliver text messages to a callback, clean up on close/error.
   - Why: Hosts the transport.
   - Depends on: Steps 2, 3
   - Risk: High (partial reads, client disconnect mid-frame, handle leaks on stop).
5. **Tests** (File: `tests/test-review-ws.lua`)
   - Action: Headless: start server, connect a raw `vim.uv` TCP client, perform the handshake with good and bad tokens, echo a frame in both directions, fragmentation, oversize payload, clean stop.
   - Why: The transport must be proven before the protocol sits on it.
   - Depends on: Step 4
   - Risk: Low

## Phase 4: MCP dispatch, lock file, openDiff
1. **JSON-RPC dispatch** (File: `server/jsonrpc.lua`)
   - Action: Decode messages, route `initialize` (protocol version, `tools` capability, server info), `notifications/initialized`, `prompts/list` (empty), `tools/list`, `tools/call`. Support deferred responses: a handler may return a pending marker and complete later by request id; drop pending ones when the client disconnects.
   - Why: `openDiff` blocks until the user decides.
   - Depends on: Phase 3
   - Risk: High (matches a reverse-engineered contract; keep method names in one table so a Claude Code change is a one-line fix).
2. **Tools** (File: `server/tools.lua`)
   - Action: `openDiff` -> `review.propose(new_file_path, new_file_contents, cb)` with a deferred reply of `FILE_SAVED` / `DIFF_REJECTED`, and cancel replies on disconnect; `close_tab` / `closeAllDiffTabs` -> cancel matching sessions, reply `TAB_CLOSED`; minimal `getOpenEditors`, `getWorkspaceFolders`, `openFile`; unknown tool -> error.
   - Why: Connects the protocol to the Phase 2 core.
   - Depends on: Step 1, Phase 2
   - Risk: Medium
3. **Lock file** (File: `server/lockfile.lua`)
   - Action: Generate a 32-char hex token from `vim.uv.random`, write `<port>.lock` JSON (mode 0600; directory created if missing) honoring `CLAUDE_CONFIG_DIR`, remove on stop and on `VimLeavePre`, and on start remove stale lock files whose pid is dead only when they carry `ideName = "Neovim"`.
   - Why: Discovery plus not leaving stale entries.
   - Depends on: Step 1 of Phase 3 (not needed; independent)
   - Risk: Medium (never delete another IDE's lock file).
4. **Lifecycle and status** (Files: `init.lua`, `health.lua`)
   - Action: `M.start()` / `M.stop()`, `:Review start|stop|status`; status reports running, port, connected client count, and last-message time (to surface the "protocol drift" case). `health.lua` checks Neovim version, LuaJIT `bit`, lock dir writable, and port bound.
   - Why: PM spec requires an always-answerable status.
   - Depends on: Steps 1-3
   - Risk: Low
5. **Protocol tests** (File: `tests/test-review-protocol.lua`)
   - Action: Headless: a fake client performs the handshake, `initialize`, `tools/list`, an `openDiff`, and the test resolves the review programmatically; assert `FILE_SAVED` and `DIFF_REJECTED` replies, disconnect-during-review cancels cleanly, and a cancel notification clears bands.
   - Why: Covers PM scenarios 8 and 10 and the reply contract.
   - Depends on: Steps 1-4
   - Risk: Low

## Phase 5: Wiring, real-Claude verification, docs
1. **Lazy wiring** (File: `lua/beast/init.lua`)
   - Action: `packer.lazy("beast.libs.review", ...)` with a command trigger for `:Review`; start the server at startup only when `review.enabled = true` in user config.
   - Why: Opt-in; no startup cost otherwise.
   - Depends on: Phase 4
   - Risk: Low
2. **Real session check** (no file)
   - Action: Enable the lib, start `claude` in a terminal inside a test repo, run `/ide`, ask it to edit a file; verify connection, the diff, each decision path, and what Claude says after a partial accept and after a reject.
   - Why: The protocol is reverse-engineered; this is the only true test. Record results back into this spec.
   - Depends on: Step 1
   - Risk: High (could force the partial-accept fallback in "PM spec gaps").
3. **Docs** (File: `docs/CODEMAP/libraries.md`)
   - Action: Add the `review` entry with file tree and API.
   - Why: Lib convention checklist.
   - Depends on: Step 2
   - Risk: Low

# Testing Strategy
- Headless tests: `tests/test-review-hunks.lua`, `test-review-session.lua`, `test-review-ws.lua`, `test-review-protocol.lua`, each run as `NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/<file>`; exit code 0 means PASS.
- Bench: no hot-path lib is touched. The only per-event work is extmark painting on a proposal and one TCP read callback, neither per keystroke. Run `./scripts/bench-startup.sh` once to confirm that the lib adds nothing to startup when `enabled = false` (the lib must not load at all).
- Manual (PM spec scenarios): Phase 2 uses `:Review propose <file>` for scenarios 1, 2, 3, 5, 7, 9. Phase 4 and 5 use a real `claude` session for scenarios 1-4, 6, 8, and 10 (Scenario 6, two files at once, needs Claude to propose two edits in one turn).
- Also verify: `:checkhealth beast.libs.review`, `stylua --check lua/`, and that no conflict markers ever appear in a saved file (grep the file after every manual scenario).

# Success Criteria
- [ ] After `/ide`, Claude Code lists Neovim and connects.
- [ ] A proposed change to an open file shows as Current and Incoming bands, with no markers in the buffer text.
- [ ] Each hunk can be accepted or rejected individually, and all at once.
- [ ] Accepting everything writes the proposed content and Claude continues normally.
- [ ] Rejecting everything leaves the file exactly as it was, and Claude reports the rejection.
- [ ] A partial decision saves only the accepted hunks.
- [ ] Unopened files and new files can be reviewed too.
- [ ] Two files can be reviewed independently, and a second proposal for the same file waits its turn.
- [ ] Closing the buffer, or Claude cancelling, never leaves stuck bands or a half-written file.
- [ ] Without opt-in, nothing listens and startup is unaffected (lib not loaded).
- [ ] `:Review status` always shows whether it is running and whether Claude Code is connected.
- [ ] Technical gates: connections without the correct token get `401` and no further processing; the lock file is mode 0600 and removed on exit; SHA-1 matches RFC vectors; all four headless tests PASS; `stylua --check lua/` clean; `docs/CODEMAP/libraries.md` updated.

---

# Phase 5 notes - real Claude Code session (2026-10-22)

Findings from connecting the actual `claude` CLI, recorded here because the protocol is reverse-engineered.

- **Subprotocol is mandatory.** The first real connection failed ("Failed to connect to neovim") because the handshake did not answer `Sec-WebSocket-Protocol`. Claude Code is a Node client and aborts when it offers a subprotocol and the server picks none. `server/handshake.lua` now echoes exactly one offered protocol, preferring `mcp` (RFC 6455 4.2.2). The RFC vectors and our own client could not have caught this.
- **No automatic reconnect.** Claude Code keeps the connection to the port it saw at `/ide` time. Restarting Neovim gives a new port and lock file; `/ide` must be run again. While disconnected, edits are written straight to disk with no review, which looks exactly like "the feature does nothing". `claude --ide` may auto-connect when one IDE matches (unverified).
- **Diagnostics.** `:Review status` now reports the reason for the last refused connection (`wrong auth token`, `not a WebSocket upgrade`, ...) and the time since the last message, so protocol drift is visible instead of silent.
- **Verified live:** `/ide` lists Neovim; connecting works; an `Edit` on a file open in Neovim was applied through the review and the edit tool completed.
- **Not yet verified live:** rejecting a hunk set and what Claude says afterwards; a *partial* accept (PM-spec risk: Claude is told `FILE_SAVED` although the file differs from its proposal). If Claude misbehaves after a partial accept, the fallback is to reply `DIFF_REJECTED` and not save on partial accepts, which needs a PM spec change.
- **Default:** the lib default for `enabled` is a user decision (the spec says opt-in `false`). `lua/beast/init.lua` only starts the server at VimEnter when `review.enabled` is passed in user opts; with a `true` lib default, the first `:Review <anything>` also starts it.
