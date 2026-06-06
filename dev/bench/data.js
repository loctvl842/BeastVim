window.BENCHMARK_DATA = {
  "lastUpdate": 1780750680385,
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
      }
    ]
  }
}