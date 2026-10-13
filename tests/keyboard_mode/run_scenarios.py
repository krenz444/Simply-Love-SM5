"""
run_scenarios.py - drive a Keyboard Mode scenario in a portable ITGmania install and
record ENGINE-STATE evidence.

  python -I run_scenarios.py --root E:\\ITGmania-Audit\\itgmania --scenario enter --out out\\before

How it works
  1. writes Save/dev_scenarios.flag (content = scenario name) and sets the theme prefs
  2. launches Program/ITGmania.exe (windowed, sound volume 0 in the sandbox Preferences)
  3. follows Logs/log.txt; every "KBDTEST SHOT <label>" line triggers a PrintWindow capture
  4. collects every "KBDTEST ..." / "SONG_INDEX_BUILD" line into <out>/<scenario>.log
It never sends OS-level keystrokes or mouse input; scenarios call theme code directly.
"""
import argparse, ctypes, json, os, re, subprocess, sys, time
from ctypes import wintypes

from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
try:
    user32.SetProcessDPIAware()
except Exception:
    pass

user32.GetWindowDC.argtypes = [ctypes.c_void_p]; user32.GetWindowDC.restype = ctypes.c_void_p
gdi32.CreateCompatibleDC.argtypes = [ctypes.c_void_p]; gdi32.CreateCompatibleDC.restype = ctypes.c_void_p
gdi32.CreateCompatibleBitmap.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
gdi32.CreateCompatibleBitmap.restype = ctypes.c_void_p
gdi32.SelectObject.argtypes = [ctypes.c_void_p, ctypes.c_void_p]; gdi32.SelectObject.restype = ctypes.c_void_p
user32.PrintWindow.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint]; user32.PrintWindow.restype = ctypes.c_int
gdi32.GetDIBits.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint,
                            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint]
gdi32.GetDIBits.restype = ctypes.c_int
gdi32.DeleteDC.argtypes = [ctypes.c_void_p]; gdi32.DeleteObject.argtypes = [ctypes.c_void_p]
user32.ReleaseDC.argtypes = [ctypes.c_void_p, ctypes.c_void_p]


class BMIH(ctypes.Structure):
    _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
                ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG),
                ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD),
                ("biClrImportant", wintypes.DWORD)]


def capture(hwnd, path):
    user32.ShowWindow(hwnd, 9)          # SW_RESTORE in case it was minimised
    try: user32.SetForegroundWindow(hwnd)
    except Exception: pass
    time.sleep(0.15)
    rect = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    w, h = rect.right - rect.left, rect.bottom - rect.top
    if w <= 0 or h <= 0:
        return None
    hdc = user32.GetWindowDC(hwnd)
    mem = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mem, bmp)
    user32.PrintWindow(hwnd, mem, 2)  # PW_RENDERFULLCONTENT: no focus needed
    bmi = BMIH(); bmi.biSize = ctypes.sizeof(BMIH); bmi.biWidth = w; bmi.biHeight = -h
    bmi.biPlanes = 1; bmi.biBitCount = 32
    buf = (ctypes.c_char * (w * h * 4))()
    gdi32.GetDIBits(mem, bmp, 0, h, buf, ctypes.byref(bmi), 0)
    Image.frombytes("RGBA", (w, h), bytes(buf), "raw", "BGRA").convert("RGB").save(path)
    gdi32.DeleteObject(bmp); gdi32.DeleteDC(mem); user32.ReleaseDC(hwnd, hdc)
    return (w, h)


def find_window(pid):
    found = []
    def cb(hwnd, _):
        p = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            r = wintypes.RECT(); user32.GetClientRect(hwnd, ctypes.byref(r))
            if r.right - r.left > 400:
                found.append(hwnd)
        return True
    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(cb), 0)
    return found[0] if found else None


def set_pref(ini, key, value):
    lines = open(ini, encoding="utf-8").read().splitlines() if os.path.exists(ini) else ["[Simply Love]"]
    done = False
    for i, l in enumerate(lines):
        if l.split("=")[0] == key:
            lines[i] = f"{key}={value}"; done = True
    if not done:
        idx = next((i for i, l in enumerate(lines) if l.strip() == "[Simply Love]"), 0)
        lines.insert(idx + 1, f"{key}={value}")
    open(ini, "w", encoding="utf-8").write("\n".join(lines) + "\n")


def run(root, scenario, out, timeout, stage_reset=True):
    prog = os.path.join(root, "Program")
    exe = os.path.join(prog, "ITGmania.exe")
    save = os.path.join(root, "Save")
    log = os.path.join(root, "Logs", "log.txt")
    flag = os.path.join(save, "dev_scenarios.flag")
    os.makedirs(out, exist_ok=True)

    set_pref(os.path.join(save, "ThemePrefs.ini"), "CategoryNavigation", "false")
    set_pref(os.path.join(save, "ThemePrefs.ini"), "KeyboardFeatures", "true")
    open(flag, "w").write(scenario)

    if os.path.exists(log):
        try: os.remove(log)
        except OSError: pass
    proc = subprocess.Popen([exe], cwd=prog)
    hwnd = None
    t0 = time.time()
    lines_out, shots, pos = [], {}, 0
    status = "timeout"
    try:
        while time.time() - t0 < timeout:
            hwnd = hwnd or find_window(proc.pid)
            if os.path.exists(log):
                with open(log, "r", encoding="utf-8", errors="replace") as f:
                    f.seek(pos); chunk = f.read(); pos = f.tell()
                for line in chunk.splitlines():
                    if "KBDTEST " in line or "SONG_INDEX_BUILD" in line or re.search(r"Lua error|Error running|attempt to", line):
                        txt = line.split("]", 1)[-1] if "KBDTEST" not in line else line[line.index("KBDTEST"):]
                        lines_out.append(txt.strip())
                        m = re.search(r"KBDTEST SHOT (\S+)", line)
                        if m:
                            time.sleep(0.25)
                            hwnd = find_window(proc.pid) or hwnd
                            p = os.path.join(out, f"{scenario}__{m.group(1)}.png")
                            size = capture(hwnd, p) if hwnd else None
                            shots[m.group(1)] = p
                            lines_out.append(f"(captured {os.path.basename(p)} {size})")
                        if re.search(r"KBDTEST DONE", line):
                            status = "done"
                        if re.search(r"KBDTEST EVENT start_pressed", line) and hwnd:
                            # after the transition begins, grab where we ended up
                            time.sleep(2.2)
                            p = os.path.join(out, f"{scenario}__next_screen.png")
                            capture(find_window(proc.pid) or hwnd, p); shots["next_screen"] = p
                            lines_out.append("(captured next_screen)")
                            status = "done"
            if status == "done":
                time.sleep(0.5); break
            if proc.poll() is not None:
                status = "exited"; break
            time.sleep(0.15)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try: proc.wait(timeout=5)
            except Exception: proc.kill()
        if os.path.exists(flag): os.remove(flag)
    with open(os.path.join(out, f"{scenario}.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines_out) + "\n")
    # count module instance loads straight from the engine log
    loads = 0
    if os.path.exists(log):
        txt = open(log, encoding="utf-8", errors="replace").read()
        loads = len(re.findall(r"Loading .*SongSearchEngine\.lua", txt))
    recents = os.path.join(save, "KeyboardRecentSongs.txt")
    rec = open(recents, encoding="utf-8", errors="replace").read().splitlines()[:3] if os.path.exists(recents) else []
    res = {"recents_head": rec, "scenario": scenario, "status": status, "lines": lines_out, "shots": shots,
           "song_index_module_loads": loads}
    json.dump(res, open(os.path.join(out, f"{scenario}.json"), "w"), indent=1)
    return res


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True); ap.add_argument("--scenario", required=True)
    ap.add_argument("--out", required=True); ap.add_argument("--timeout", type=float, default=90)
    a = ap.parse_args()
    r = run(a.root, a.scenario, a.out, a.timeout)
    print(f"[{r['status']}] {a.scenario}: {len(r['lines'])} lines, shots={list(r['shots'])}, SongSearchEngine loads={r['song_index_module_loads']}")
    for l in r["lines"]:
        print("  ", l)
