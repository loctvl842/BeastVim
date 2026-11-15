# Chains

A picker can lead to another one with a key: Files, Buffers and Help to a grep in the matching files; Pull
Requests to their changed files or their commits; a commit or the changed files to a grep in your local copies;
Issues to a grep in their text. `<BS>` on an empty prompt (or `<C-o>`) goes back, exactly as you left the picker.

The set of chains is built in (`chains.lua`); you only choose among them. Edge ids are `"from|to"`.

```lua
-- in the finder part of the Beast setup
finder = {
  chains = {
    back = { "<BS>", "<C-o>" },                  -- keys that go back ("<BS>" only on an empty prompt)
    edges = {
      ["gh_pr|gh_commits"]  = { key = "<C-t>" }, -- another key (default shown)
      ["gh_pr|gh_pr_files"] = false,             -- switch an edge off: no key, not in the hint line
      ["files|live_grep"]   = { key = "<M-g>" },
    },
  },
}
```

| Edge id | Default key |
|---|---|
| `files\|live_grep`, `buffers\|live_grep`, `help_tags\|live_grep` | `<C-g>` |
| `gh_pr\|gh_pr_files` | `<C-g>` |
| `gh_pr\|gh_commits` | `<C-t>` |
| `gh_pr_files\|live_grep`, `gh_commits\|live_grep` | `<C-g>` |
| `gh_issue\|gh_issue_grep` | `<C-g>` |

`finder.setup` raises, naming the problem, for an unknown edge id, a value that is not `false` or `{ key = "..." }`,
a key that a picker key already uses (`<C-j>`, `<CR>`, ...), two edges of one picker with the same key, or a key
that is also a back key. `:lua =require("beast.libs.finder").chains()` lists the edges that are on, with their keys.
