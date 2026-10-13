"""
assert_scenarios.py - assert on ENGINE-STATE evidence produced by run_scenarios.py.

  python -I assert_scenarios.py <evidence_dir>

Every check reads state the engine reports (GAMESTATE current song, input-redirect flags,
player join state, index build count), never the return value of a Lua handler (the engine
ignores those for the top screen). Exit code 0 = all checks passed.
"""
import json
import os
import re
import sys


def load(d, name):
    p = os.path.join(d, name + ".log")
    if not os.path.exists(p):
        return None
    return [l.strip() for l in open(p, encoding="utf-8", errors="replace") if l.strip()]


def kv(line):
    return dict(re.findall(r'(\w+)=("[^"]*"|\S*)', line))


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def main(d):
    results = []

    def check(name, ok, detail=""):
        results.append((name, bool(ok), detail))

    L = load(d, "enter")
    if L is not None:
        s = [kv(l) for l in L if "SNAP label=keyboard_entered" in l]
        check("enter: engine song == highlighted row after Tab", s and s[0]["synced"] == "true",
              f'highlighted={s[0]["highlighted"]} engine={s[0]["engine"]}' if s else "no snap")

    L = load(d, "omnibar")
    if L is not None:
        s = [kv(l) for l in L if "SNAP label=after_omnibar_return" in l]
        check("omnibar: engine song == highlighted row after search-return",
              s and s[0]["synced"] == "true",
              f'highlighted={s[0]["highlighted"]} engine={s[0]["engine"]}' if s else "no snap")

    L = load(d, "start")
    if L is not None:
        snaps = [kv(l) for l in L if "SNAP label=" in l]
        pre = [s for s in snaps if s["label"] == "before_start"]
        post = [s for s in snaps if s["label"].startswith("start_")]
        check("start: engine song == highlighted row at Start", pre and pre[0]["synced"] == "true",
              f'highlighted={pre[0]["highlighted"]} engine={pre[0]["engine"]}' if pre else "")
        check("start: input stays redirected for the whole fade-out",
              post and all(s["redirP1"] == "true" and s["redirP2"] == "true" for s in post),
              ", ".join(f'{s["label"]}:{s["redirP1"]}/{s["redirP2"]}' for s in post))
        check("start: engine song unchanged during fade-out",
              post and all(s["synced"] == "true" for s in post))
        j = json.load(open(os.path.join(d, "start.json")))
        head = (j.get("recents_head") or [""])[0]
        want = pre[0]["highlighted"].strip('"') if pre else ""
        check("start: started song is recorded in Recent Songs", want and norm(want) in norm(head),
              f"recents[0]={head}")

    L = load(d, "arbit")
    if L is not None:
        rows = [kv(l) for l in L if "ARBIT case=" in l]
        cases = {}
        for r in rows:
            cases.setdefault(r["case"], {})[r["order"]] = (r["omnibar_open"], r["catnav_active"])
        for case, per_order in cases.items():
            check(f"arbit: {case}: same outcome in both handler orders",
                  len(set(per_order.values())) == 1, str(per_order))
        check("arbit: Omnibar and Keyboard Mode are never active together",
              rows and not any(r["omnibar_open"] == "true" and r["catnav_active"] == "true" for r in rows))

    L = load(d, "cats")
    if L is not None:
        counts = [kv(l) for l in L if "KBDTEST COUNT" in l]
        cat_ids = {c["cat"] for c in counts}
        check("cats: no placeholder categories (groovestats/search)",
              not (cat_ids & {"groovestats", "search"}), ",".join(sorted(cat_ids)))
        bpm = {c["chip"]: int(c["n"]) for c in counts if c["cat"] == "bpm"}
        if bpm:
            tiers = sum(v for k, v in bpm.items() if k != "all")
            check("cats: BPM tiers partition the library", tiers == bpm["all"],
                  f"sum(tiers)={tiers} all={bpm['all']}")
        probes = [kv(l) for l in L if "BPMPROBE" in l]
        check("cats: every probe BPM (129.5/130/155/180/210) is in exactly one tier",
              probes and all(len([t for t in p["tiers"].split(",") if t]) == 1 for p in probes),
              "; ".join(f'{p["bpm"]}->{p["tiers"] or "none"}' for p in probes))
        fav = [kv(l) for l in L if "FAVPROBE" in l]
        check("cats: Favorites == the player's favorites (no title/substring false positives)",
              fav and fav[0]["n"] == fav[0]["truth"],
              f'n={fav[0]["n"]} truth={fav[0]["truth"]}' if fav else "")

    L = load(d, "perf")
    if L is not None:
        p = [kv(l) for l in L if "PERF " in l]
        v = float(p[0]["per_move_ms"]) if p else 1e9
        check("perf: cursor move costs < 2 ms (188-song staging)", v < 2.0, f"{v:.2f} ms/move")

    L = load(d, "index")
    if L is not None:
        builds = [l for l in L if "SONG_INDEX_BUILD" in l]
        inst = set()
        for l in builds:
            m = re.search(r"instance=(\S+ \S+)", l)
            if m:
                inst.add(m.group(1))
        check("index: library indexed once across two screen entries", len(builds) == 1,
              f"{len(builds)} builds")
        check("index: a single shared SongSearchEngine instance", len(inst) == 1,
              f"{len(inst)} instances")

    L = load(d, "guard")
    if L is not None:
        g = {kv(l)["case"]: kv(l) for l in L if "GUARD case=" in l}
        a = g.get("both_joined_master_P2:after")
        check("guard: both joined, master P2 -> master kept",
              a and a["p2"] == "true" and a["humans"] == "1",
              f'p1={a["p1"]} p2={a["p2"]} master={a["master"]}' if a else "")
        b = g.get("only_P2:after")
        check("guard: only P2 joined -> P2 stays joined",
              b and b["humans"] == "1" and b["p2"] == "true",
              f'humans={b["humans"]} master={b["master"]}' if b else "")

    width = max((len(n) for n, _, _ in results), default=0)
    ok_all = True
    for name, ok, detail in results:
        ok_all &= ok
        print(f'{"PASS" if ok else "FAIL"}  {name.ljust(width)}  {detail}')
    print(f'\n{sum(1 for _, o, _ in results if o)}/{len(results)} checks passed')
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
