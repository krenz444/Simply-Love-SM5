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
        prompt = [kv(l) for l in L if "OPTIONS_PROMPT" in l]
        check("start: engine ran MenuStart (\"Press START for options\" is shown)", bool(prompt),
              "prompt shown" if prompt else "no options prompt: MenuStart was skipped")
        check("start: engine finalized the selection (StartFinalized)",
              any("START_FINALIZED" in l for l in L))
        in_window = [s for s in post if s["label"] == "start_t+500ms"]
        check("start: input is back with the engine during the prompt (a 2nd Start can open Player Options)",
              in_window and in_window[0]["redirP1"] == "false" and in_window[0]["redirP2"] == "false",
              ", ".join(f'{s["label"]}:{s["redirP1"]}/{s["redirP2"]}' for s in in_window))
        check("start: engine song unchanged during the prompt",
              post and all(s["synced"] == "true" for s in post))
        j = json.load(open(os.path.join(d, "start.json")))
        head = (j.get("recents_head") or [""])[0]
        want = pre[0]["highlighted"].strip('"') if pre else ""
        check("start: started song is recorded in Recent Songs", want and norm(want) in norm(head),
              f"recents[0]={head}")

    L = load(d, "omnibar_play")
    if L is not None:
        q = [kv(l) for l in L if "QUICKPLAY" in l]
        check("omnibar quick play: engine ran MenuStart (options prompt shown)",
              any("OPTIONS_PROMPT" in l for l in L),
              "prompt shown" if any("OPTIONS_PROMPT" in l for l in L) else "no options prompt")
        check("omnibar quick play: engine plays the searched song",
              q and q[0]["engine"].strip('"') == "Danger Zone",
              f'engine={q[0]["engine"]}' if q else "no line")

    L = load(d, "reload")
    if L is not None:
        r2 = [kv(l) for l in L if "RELOAD stage=2" in l]
        check("reload: after a full song reload the index does not hold freed songs",
              r2 and r2[0]["first_song_is_live"] == "true",
              f'first_song_is_live={r2[0]["first_song_is_live"]}' if r2 else "stage 2 never ran")
        builds = [l for l in L if "SONG_INDEX_BUILD" in l]
        check("reload: the index was rebuilt after the reload", len(builds) >= 2, f"{len(builds)} builds")

    L = load(d, "played_fx")
    if L is not None:
        p = [kv(l) for l in L if "PLAYEDFX" in l]
        check("played: building PLAYED inserts no score entries into the profile",
              p and p[0]["entry_before"] == "false" and p[0]["entry_after"] == "false",
              f'before={p[0]["entry_before"]} after={p[0]["entry_after"]}' if p else "no line")

    L = load(d, "ctrl_l")
    if L is not None:
        rows = [kv(l) for l in L if "CTRL_L press=" in l]
        check("ctrl+L: cycling layouts never errors without the Windows layout file",
              rows and all(r["ok"] == "true" for r in rows),
              " ".join(f'{r["press"]}:{r["layout"]}' for r in rows))
        check("ctrl+L: it keeps cycling (never stuck on one layout)",
              rows and len({r["layout"] for r in rows}) >= 3,
              " ".join(r["layout"] for r in rows))

    L = load(d, "ctrl_g")
    if L is not None:
        g = [kv(l) for l in L if "CTRL_G leaderboard_visible" in l]
        check("ctrl+G: leaderboard opens with input redirected (Start/Back can dismiss it)",
              g and g[0]["leaderboard_visible"] == "true" and g[0]["redirP1"] == "true",
              f'visible={g[0]["leaderboard_visible"]} redirP1={g[0]["redirP1"]}' if g else "no line")
        t = [kv(l) for l in L if "typing_opened_omnibar" in l]
        check("ctrl+G: typing does not open the Omnibar on top of the leaderboard",
              t and t[0]["typing_opened_omnibar"] == "false",
              f'opened={t[0]["typing_opened_omnibar"]}' if t else "no line")

    L = load(d, "jump_group")
    if L is not None:
        b = [kv(l) for l in L if "JUMP before" in l]
        a = [kv(l) for l in L if "JUMP after" in l]
        check("jump: ']' lands the engine on a song of the next pack",
              a and b and a[0]["group"] == b[0]["expect_next"],
              f'expected {b[0]["expect_next"]} got {a[0]["group"]}' if a and b else "no lines")
        check("jump: the wheel is on a song (not a section header)",
              a and a[0]["wheel_type"] == "WheelItemDataType_Song",
              f'wheel_type={a[0]["wheel_type"]}' if a else "no line")
        c = [kv(l) for l in L if "WHEELCENTER label=after_jump" in l]
        check("jump: the wheel DISPLAYS that song (centre row shows the engine's song, not the pack header)",
              c and c[0]["displayed_is_engine_song"] == "true",
              f'displayed={c[0]["displayed"]} engine={c[0]["engine"]} center_type={c[0]["center_type"]}' if c else "no line")

    for scen, label, what in (("exit_visual", "after_exit", "leaving Keyboard Mode"),
                              ("omnibar_wheel", "after_omnibar_select", "an Omnibar search in wheel mode")):
        L = load(d, scen)
        if L is not None:
            c = [kv(l) for l in L if f"WHEELCENTER label={label}" in l]
            check(f"{scen}: the wheel DISPLAYS the engine's song after {what}",
                  c and c[0]["displayed_is_engine_song"] == "true",
                  f'displayed={c[0]["displayed"]} engine={c[0]["engine"]}' if c else "no line")

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
        total = next((int(c["n"]) for c in counts if c["cat"] == "packs" and c["chip"] == "all"), None)
        az = [int(c["n"]) for c in counts if c["cat"] == "alphabet"]
        if az and total is not None:
            check("cats: A-Z buckets cover every song exactly once", sum(az) == total,
                  f"sum(buckets)={sum(az)} library={total}")
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
