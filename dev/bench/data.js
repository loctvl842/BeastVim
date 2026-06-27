window.BENCHMARK_DATA = {
  "lastUpdate": 1782568861209,
  "repoUrl": "https://github.com/loctvl842/BeastVim",
  "entries": {
    "BeastVim Startup": [
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "f048614e9dd8f1c4ed9282868a49f98c63d7378c",
          "message": "ci(bench): publish startup benchmark history to gh-pages\n\nAdds a GitHub Actions workflow that runs scripts/bench-startup.sh on\nevery push to main and on every PR, then uses\nbenchmark-action/github-action-benchmark to:\n\n  * push the hyperfine results into the gh-pages branch under\n    dev/bench/ as a chart dashboard, and\n  * comment on PRs whenever a metric regresses past 115% of the\n    previous best.\n\nscripts/bench-to-benchmark-json.sh is a small jq adapter that turns\nthe hyperfine JSON emitted by bench-startup.sh into the\ncustomSmallerIsBetter format the action expects (mean / stddev /\nmin / max, all in ms).",
          "timestamp": "2026-06-06T10:28:23+07:00",
          "tree_id": "d7d9decd315be2bea6346162b8e672bfe2068069",
          "url": "https://github.com/loctvl842/BeastVim/commit/f048614e9dd8f1c4ed9282868a49f98c63d7378c"
        },
        "date": 1780718332355,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 51.9662523,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 4.498717602576038,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 48.907938,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 70.00314200000001,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "7e3fdefc294988fb641c181edb4390d39a49e42d",
          "message": "fix(init,key): document built-in keys + cover [/]/<leader> as triggers\n\n- <leader>p (packer UI) had no opts at all — surfaced in hint as the\n  bare key with no description or group. Add desc='Open packer UI'\n  group='Packer'.\n- [B/]B (tabline move buffer) nested their options under a third\n  positional element. Beast.KeymapSpec uses flat options; the packer\n  keys trigger silently dropped mode/desc/group so they showed as\n  'Lazy load X'. Flatten to match the type hint.\n- Default hint triggers only covered <leader>/<localleader>, but\n  beast/init.lua ships [B, ]B, [c, ]c. Add [ and ] to defaults so\n  the hint opens for every prefix Beast itself registers.",
          "timestamp": "2026-06-06T11:16:44+07:00",
          "tree_id": "4a839c48ced164d3a261e2afa44b81dd008713ab",
          "url": "https://github.com/loctvl842/BeastVim/commit/7e3fdefc294988fb641c181edb4390d39a49e42d"
        },
        "date": 1780719446744,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 55.71177810000001,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 22.067717104228958,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 39.715155,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 116.130673,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "b3b2914228e64281136cd01654f44edf4dd3de02",
          "message": "feat(key/hint): sort by group + opt-in group headers in UI\n\nSort visible children by group label first so rows that share a\ngroup cluster together (Buffer, Git, Packer, ...). Rows with no\ngroup sink to the bottom. Within a group, alphabetical by key.\n\nAdd config.hint.show_group_headers (default false). When enabled,\nrender '── Group ──' separator rows between sections highlighted\nas BeastKeyHintHeader. Ungrouped tail gets a bare '──' separator.\n\nLeverages the explicit group field on every managed keymap — one\nof our advantages over which-key.nvim, where groupings are\ninferred from desc prefixes alone.\n\nbench unchanged: index_p50=237us, open_p50=228us.",
          "timestamp": "2026-06-06T11:32:28+07:00",
          "tree_id": "cb3364e3ea96c2dd778f4d6c6f8a8f4e49f36b99",
          "url": "https://github.com/loctvl842/BeastVim/commit/b3b2914228e64281136cd01654f44edf4dd3de02"
        },
        "date": 1780720427743,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 50.46322485000001,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 1.0945597483501028,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 49.117514,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 53.00844800000001,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "fa86d9d4a2c611bf217b8c9173490d15984b532a",
          "message": "docs(bench): document gh-pages dashboard, drop bogus :Lazy step\n\n* .github/workflows/bench.yml — remove '+Lazy! sync' from the prime\n  step. BeastVim is self-configured (lua/beast/libs/packer on top of\n  vim.pack.add); there is no :Lazy command. First headless start\n  clones missing plugins; second start warms caches.\n* docs/development/bench-ci.md — new reference covering what gets\n  published, when the workflow runs, the one-time setup we already\n  did (orphan gh-pages + 'gh api pages'), tuning knobs, and how to\n  add a baseline config to the same chart.\n* docs/development/benchmarking.md — cross-link to bench-ci.md.\n* README.md — add bench-dashboard badge and a sentence pointing at\n  the per-commit history page.",
          "timestamp": "2026-06-06T11:35:38+07:00",
          "tree_id": "9f9b3457f65ced9dfea3fe66e342cda14c4ca0e9",
          "url": "https://github.com/loctvl842/BeastVim/commit/fa86d9d4a2c611bf217b8c9173490d15984b532a"
        },
        "date": 1780720587230,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 63.205429450000004,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 40.051825744132834,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 51.387772000000005,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 232.46572600000002,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "7c87f0821261ff4c253f84e91b078831bd28bf26",
          "message": "fix(git): anchor preview float to source window\n\nTreat preview.width = 'full' as the width of the source window (not the\nwhole editor) and offset the float left by the window's gutter so its\nborder sits flush with the window edge, overriding statuscolumn /\nsigncolumn / numberwidth.",
          "timestamp": "2026-06-06T13:34:47+07:00",
          "tree_id": "b6487004a89b1615b5fecb36aa9d5ec68e3f020f",
          "url": "https://github.com/loctvl842/BeastVim/commit/7c87f0821261ff4c253f84e91b078831bd28bf26"
        },
        "date": 1780727722455,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 52.752183349999996,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 1.861581970701385,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 50.420759000000004,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 57.921957000000006,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "9dea5ee2d8e3bf65523d10e913d9168714971d4a",
          "message": "refactor(key/hint): smooth held-trigger autorepeat + split M.start\n\nFixes the perceived low-fps cursor movement when holding <leader> (or any\nsingle-segment trigger) and simplifies the now-grown M.start function.\n\nBehavior fixes\n--------------\n* On autorepeat detection, feed `trigger .. trigger` instead of a single\n  trigger. The loop consumes two presses (the keymap fire + the one\n  getcharstr eats) so feeding only one halved the visible cursor rate.\n* Replace the fixed 100 ms autorepeat-resume timer with a `vim.on_key`\n  watcher + 50 ms quiet timer. The trigger keymap now stays deleted for\n  the entire hold (zero Lua per OS autorepeat), and re-registers only\n  after input goes quiet — i.e. the user actually released the key.\n\nRefactor (behavior-preserving)\n------------------------------\n* Extract `termcodes`, `feed`, `getchar_to_str` helpers (each previously\n  inlined 5-7 times).\n* Split M.start (130 lines) into named phases, each <30 lines:\n  - try_autorepeat_fast_path\n  - bump_recursion_guard\n  - drain_typeahead_prefix\n  - new_state (also shared by _internal.render_once)\n* M.start is now 56 lines of straight-line orchestration with early\n  returns; reads as a TOC of the lifecycle phases.\n\nVerified: luac syntax check + headless module load.",
          "timestamp": "2026-06-06T19:57:15+07:00",
          "tree_id": "fc437d47dc96c964266be064acb7036aca5ef9a9",
          "url": "https://github.com/loctvl842/BeastVim/commit/9dea5ee2d8e3bf65523d10e913d9168714971d4a"
        },
        "date": 1780750679891,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 50.130241099999985,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 1.245483763235243,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 48.802875,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 53.323930000000004,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "67ba650ff7af7b06e813cb3ef12e8344a250874c",
          "message": "fix(git): re-apply gutter offset when re-anchoring preview on scroll\n\nWinScrolled handler was hardcoding col = 0, undoing the textoff offset\napplied at open time, so the float jumped rightward past the source\nwindow's statuscolumn/sign/number on the first scroll. Recompute textoff\non each scroll so the float stays flush with the window edge even when\nthe gutter grows mid-preview (e.g. line numbers crossing 99 → 100).",
          "timestamp": "2026-06-07T00:10:08+07:00",
          "tree_id": "2df18e39076aa3a17807f8a8d168d9c6982f19ea",
          "url": "https://github.com/loctvl842/BeastVim/commit/67ba650ff7af7b06e813cb3ef12e8344a250874c"
        },
        "date": 1780765848321,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 25.042563150000003,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 0.4393113950062587,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 24.337404,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 25.716779000000002,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "b4066615c67d10a7e6d8c63267d7e41339809f34",
          "message": "feat(bench-ux): add keymaps scenario driving every lua/beast/init.lua binding\n\nNew scenario exercises notification, tabline, window, git hunk\nnav/preview/stage/unstage/reset/repeat, finder pickers, packer UI,\nexplorer toggle, and buffer-delete keymaps end-to-end. Forces\nLOAD_USER_CONFIG=1 + FIXTURE_GIT=1 so git keymaps have real hunks to\noperate on. Brackets each press with :BenchMark km_<name> and prints\nboth aggregate p50/p99 and a per-keymap breakdown via summarise.py\n--per-keymap so cold lazy loads stand out from cheap motions.\n\nsummarise.py gains parse_paint_with_ts + fmt_per_keymap to attribute\neach paint sample to the most recent evt marker while preserving the\nlegacy paint-only parser for existing callers.",
          "timestamp": "2026-06-07T00:15:23+07:00",
          "tree_id": "31a04861c14126dc5ff32d2ffdb79e1639682590",
          "url": "https://github.com/loctvl842/BeastVim/commit/b4066615c67d10a7e6d8c63267d7e41339809f34"
        },
        "date": 1780766160319,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 24.889196700000007,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 0.8606964113811739,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 24.140849000000003,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 28.371435,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "c551732009b748dd35a69469a545e3bc6dcbeb4f",
          "message": "Merge branch 'main' of https://github.com/loctvl842/BeastVim",
          "timestamp": "2026-06-08T12:10:08+07:00",
          "tree_id": "127f6e00e94e136628c5325d4236fc2ee581c86c",
          "url": "https://github.com/loctvl842/BeastVim/commit/c551732009b748dd35a69469a545e3bc6dcbeb4f"
        },
        "date": 1780895448831,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 36.400002399999984,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 1.5620942033137306,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 35.009281,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 39.607155000000006,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "abb5874cacd5432cd3038e7362283161fae9b004",
          "message": "fix(tabline): invalidate cache on BufFilePost (rename of opened file)\n\nRenaming an opened file from the explorer calls nvim_buf_set_name,\nwhich fires BufFilePre / BufFilePost / BufNew — none of which the\ntabline was listening to. Result: state.dirty stayed false, render()\nreturned the cached string with the old basename, and the cell looked\n\"frozen\" or visually mismatched against the new buffer state.\n\nAdd BufFilePost to the layout-change autocmd list so the cache is\ninvalidated and the next render rebuilds with vim.api.nvim_buf_get_name's\nnew value.\n\nVerified: before rename tabline shows old basename, after\nnvim_buf_set_name + 50ms wait the next render() returns the new\nbasename and the cache string differs.",
          "timestamp": "2026-06-08T19:14:11+07:00",
          "tree_id": "70e671a4fb05c19de613b3cb7ee0560020aa01c3",
          "url": "https://github.com/loctvl842/BeastVim/commit/abb5874cacd5432cd3038e7362283161fae9b004"
        },
        "date": 1780920904434,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 32.4176199,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 1.5521251975335688,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 30.684275,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 35.995048000000004,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "5d563d96b9b2674e0180edf15a18d4ca8e94579e",
          "message": "feat(git/preview): recompute float width on source window resize\n\nFloat width was computed once when the preview opened and never updated.\nOpening a new split (which halves the source window) left the float\noverflowing its parent.\n\nAdd a WinResized autocmd that:\n  - guards on float + source_win validity\n  - filters via vim.v.event.windows so unrelated splits are ignored\n  - reapplies window config with a freshly computed width and textoff\n\nWidth is recomputed via a closure captured at open-time so the resize\nhandler reuses the same compute_width + body + gutter inputs.",
          "timestamp": "2026-06-09T17:04:44+07:00",
          "tree_id": "d750c6c5b2a1de25c1b195f76725cfeb602f4656",
          "url": "https://github.com/loctvl842/BeastVim/commit/5d563d96b9b2674e0180edf15a18d4ca8e94579e"
        },
        "date": 1780999539007,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 34.38565559999999,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 2.3010909349642104,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 32.729393,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 41.547977,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "3f2feb01da1d69cff4c35c61d63df72fb0ea2832",
          "message": "dev: easier developing nvim config",
          "timestamp": "2026-06-09T17:54:37+07:00",
          "tree_id": "56879a2eea5d9972a235cba90cb1f66705b798ba",
          "url": "https://github.com/loctvl842/BeastVim/commit/3f2feb01da1d69cff4c35c61d63df72fb0ea2832"
        },
        "date": 1781002524000,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 36.60585595,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 2.56141246949726,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 34.142991,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 43.503213,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "0734312430949b21a54a68d8ff6dead4f4ae1948",
          "message": "refactor: lazy load all libs",
          "timestamp": "2026-06-10T18:06:05+07:00",
          "tree_id": "0d50153364c828a9df3d805dc8aef0f32379612e",
          "url": "https://github.com/loctvl842/BeastVim/commit/0734312430949b21a54a68d8ff6dead4f4ae1948"
        },
        "date": 1781089602906,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 24.056152,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 12.308320488415758,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 19.395823,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 70.97093800000002,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "c4e3f7e969d77cee64954403ee5a4666a96b0178",
          "message": "fix(blink): early load for CmdlineEnter",
          "timestamp": "2026-06-10T19:35:18+07:00",
          "tree_id": "e34fdd83f87d3144cb39c5c4c9908254b3054823",
          "url": "https://github.com/loctvl842/BeastVim/commit/c4e3f7e969d77cee64954403ee5a4666a96b0178"
        },
        "date": 1781094957579,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 24.78069925,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 0.6044218182005255,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 24.017533,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 26.333374000000003,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "1be112475c903327070ba5f029ce69b8025a3124",
          "message": "docs(codemap): refresh lsp section after attach/keys/diagnostics inline",
          "timestamp": "2026-06-15T22:41:39+07:00",
          "tree_id": "94cb3f3b2a15e92cc2357d8770eb4cf93cef7513",
          "url": "https://github.com/loctvl842/BeastVim/commit/1be112475c903327070ba5f029ce69b8025a3124"
        },
        "date": 1781538150012,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 26.58694535,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 0.38847900044407635,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 25.833066000000002,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 27.458816,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "ebbc265020a9c849195202a99b96f74eeac497e8",
          "message": "chore(treesitter): better enable context by default",
          "timestamp": "2026-06-16T16:38:26+07:00",
          "tree_id": "d358e9ffc27b39ea62d5e7616af35022bd436054",
          "url": "https://github.com/loctvl842/BeastVim/commit/ebbc265020a9c849195202a99b96f74eeac497e8"
        },
        "date": 1781602841790,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 22.018713750000003,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 0.7743413985928453,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 21.322126,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 24.055537,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "b3b997679f96243e00e6f739d3ec1ff193915e4f",
          "message": "style: better highlighting",
          "timestamp": "2026-06-16T16:47:21+07:00",
          "tree_id": "317f3b4ad8cfa1dc4340616736395da6308f7dc9",
          "url": "https://github.com/loctvl842/BeastVim/commit/b3b997679f96243e00e6f739d3ec1ff193915e4f"
        },
        "date": 1781603283646,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 26.326136700000003,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 0.33828099249169796,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 25.863591000000003,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 27.325497000000002,
            "unit": "ms"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "committer": {
            "email": "loclepnvx@gmail.com",
            "name": "loctvl842",
            "username": "loctvl842"
          },
          "distinct": true,
          "id": "b18a75701ec51aa366240d0158b754addff588ea",
          "message": "feat(finder): highlight the matched text in grep/LSP list rows\n\nGrep and LSP match lines showed the line content unhighlighted, so it\nwasn't obvious what matched. Split the matched substring into its own\nBeastFinderListMatch segment in the live_grep formatter (rendered by the\nexisting list highlight path). The range comes from match_text for grep\nand from end_pos for LSP, with a plain-text fallback search when the\nreported column doesn't line up (e.g. ugrep visual vs byte columns).",
          "timestamp": "2026-06-27T20:14:49+07:00",
          "tree_id": "b844f8f4ebd2fb986f33ffd6e05dc5d3386b8b22",
          "url": "https://github.com/loctvl842/BeastVim/commit/b18a75701ec51aa366240d0158b754addff588ea"
        },
        "date": 1782568860811,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "BeastVim startup (warm) mean",
            "value": 36.76286475,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) stddev",
            "value": 32.84309416294307,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) min",
            "value": 22.712052,
            "unit": "ms"
          },
          {
            "name": "BeastVim startup (warm) max",
            "value": 135.811913,
            "unit": "ms"
          }
        ]
      }
    ]
  }
}