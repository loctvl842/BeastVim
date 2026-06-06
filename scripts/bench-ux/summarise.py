#!/usr/bin/env python3
# scripts/bench-ux/summarise.py — turn a bench-ux event log into a summary.
#
# Reads $1 (a log file written by probe.lua) and prints a one-line summary
# per scenario invocation, plus a snapshot delta for long sessions.
#
# Usage:
#   summarise.py <log> <scenario_name> [thresh_p50_ms] [thresh_p99_ms]
#
# Exit codes:
#   0 PASS (no thresholds, or all met)
#   1 FAIL (a threshold tripped)
#   2 ERROR (no samples)

import sys, statistics, re

def pct(xs, p):
    if not xs:
        return float("nan")
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))
    return xs[k]

def parse(path):
    paints, snaps, evts = [], [], []
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            if line.startswith("paint "):
                try: paints.append(float(line.split()[1]))
                except: pass
            elif line.startswith("snap "):
                d = dict(re.findall(r"(\w+)=([\w.\-]+)", line[5:]))
                snaps.append(d)
            elif line.startswith("evt "):
                parts = line.split()
                if len(parts) >= 3:
                    evts.append((parts[1], float(parts[2])))
    return paints, snaps, evts

def fmt_paint(name, xs, t50=None, t99=None):
    if not xs:
        print(f"BENCH name={name} ERROR=no_paint_samples")
        return 2
    med = statistics.median(xs)
    p90, p99, mx = pct(xs, 90), pct(xs, 99), max(xs)
    status = "PASS"
    if t50 is not None and med > t50: status = "FAIL"
    if t99 is not None and p99 > t99: status = "FAIL"
    extra = ""
    if t50 is not None: extra += f" thresh_p50={t50}ms"
    if t99 is not None: extra += f" thresh_p99={t99}ms"
    print(f"BENCH name={name} n={len(xs)} "
          f"min={min(xs):.2f}ms p50={med:.2f}ms p90={p90:.2f}ms "
          f"p99={p99:.2f}ms max={mx:.2f}ms{extra} status={status}")
    return 0 if status == "PASS" else 1

def fmt_snap_delta(name, snaps):
    if len(snaps) < 2:
        return
    a, b = snaps[0], snaps[-1]
    def d(k, cast=int):
        try: return cast(b.get(k, 0)) - cast(a.get(k, 0))
        except: return 0
    print(f"GROWTH name={name} "
          f"d_bufs={d('bufs')} d_autocmds={d('autocmds')} "
          f"d_extmarks={d('extmarks')} d_lua_kb={d('lua_kb', float):.1f} "
          f"d_rss_kb={d('rss_kb')} d_redraw={d('redraw')} "
          f"d_lua_refcount={d('lua_refcount')} "
          f"uptime_s={float(b.get('uptime_s', 0)):.1f}")

def fmt_longsession_csv(name, snaps):
    # Print one CSV-ish row per snapshot — feed into your plotting tool of choice.
    print(f"# longsession {name}: tag,t,uptime_s,bufs,autocmds,extmarks,lua_kb,rss_kb,redraw,lua_refcount")
    for s in snaps:
        print(",".join([
            "LS",
            s.get("tag", "?"),
            s.get("t", "0"),
            s.get("uptime_s", "0"),
            s.get("bufs", "0"),
            s.get("autocmds", "0"),
            s.get("extmarks", "0"),
            s.get("lua_kb", "0"),
            s.get("rss_kb", "0"),
            s.get("redraw", "0"),
            s.get("lua_refcount", "0"),
        ]))

def main():
    if len(sys.argv) < 3:
        print("usage: summarise.py <log> <scenario> [t50] [t99] [--longsession]", file=sys.stderr)
        sys.exit(2)
    path, name = sys.argv[1], sys.argv[2]
    t50 = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] != "-" else None
    t99 = float(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] != "-" else None
    longsession = "--longsession" in sys.argv

    try:
        paints, snaps, _evts = parse(path)
    except FileNotFoundError:
        print(f"BENCH name={name} ERROR=log_missing path={path}")
        sys.exit(2)

    rc = fmt_paint(name, paints, t50, t99)
    fmt_snap_delta(name, snaps)
    if longsession:
        fmt_longsession_csv(name, snaps)
    sys.exit(rc)

if __name__ == "__main__":
    main()
