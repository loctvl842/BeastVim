window.BENCHMARK_DATA = {
  "lastUpdate": 1780718333117,
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
      }
    ]
  }
}