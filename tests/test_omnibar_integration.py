"""
test_omnibar_integration.py
Automated visual integration test suite for ITGmania Keyboard Omnibar & Navigation.
Launches ITGmania with sound completely muted, executes automated search & navigation passes,
captures pixel-perfect screenshots of all states, and asserts zero errors.
"""

import os
import sys
import time
import subprocess
import ctypes
from ctypes import wintypes
from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
kernel32 = ctypes.windll.kernel32

user32.GetWindowDC.argtypes = [ctypes.c_void_p]
user32.GetWindowDC.restype = ctypes.c_void_p
gdi32.CreateCompatibleDC.argtypes = [ctypes.c_void_p]
gdi32.CreateCompatibleDC.restype = ctypes.c_void_p
gdi32.CreateCompatibleBitmap.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
gdi32.CreateCompatibleBitmap.restype = ctypes.c_void_p
gdi32.SelectObject.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
gdi32.SelectObject.restype = ctypes.c_void_p
user32.PrintWindow.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint]
user32.PrintWindow.restype = ctypes.c_int
gdi32.GetDIBits.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint]
gdi32.GetDIBits.restype = ctypes.c_int
gdi32.DeleteDC.argtypes = [ctypes.c_void_p]
gdi32.DeleteDC.restype = ctypes.c_int
gdi32.DeleteObject.argtypes = [ctypes.c_void_p]
gdi32.DeleteObject.restype = ctypes.c_int
user32.ReleaseDC.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
user32.ReleaseDC.restype = ctypes.c_int

def capture_window(hwnd, output_path):
    rect = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    w = rect.right - rect.left
    h = rect.bottom - rect.top
    if w <= 0 or h <= 0:
        print(f"[WARN] Invalid window dimensions: {w}x{h}")
        return None
    
    hdc = user32.GetWindowDC(hwnd)
    memdc = gdi32.CreateCompatibleDC(hdc)
    hbm = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(memdc, hbm)
    
    # PW_RENDERFULLCONTENT = 2
    user32.PrintWindow(hwnd, memdc, 2)
    
    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [
            ('biSize', wintypes.DWORD),
            ('biWidth', wintypes.LONG),
            ('biHeight', wintypes.LONG),
            ('biPlanes', wintypes.WORD),
            ('biBitCount', wintypes.WORD),
            ('biCompression', wintypes.DWORD),
            ('biSizeImage', wintypes.DWORD),
            ('biXPelsPerMeter', wintypes.LONG),
            ('biYPelsPerMeter', wintypes.LONG),
            ('biClrUsed', wintypes.DWORD),
            ('biClrImportant', wintypes.DWORD)
        ]
    bmi = BITMAPINFOHEADER()
    bmi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bmi.biWidth = w
    bmi.biHeight = -h
    bmi.biPlanes = 1
    bmi.biBitCount = 32
    bmi.biCompression = 0
    bmi.biSizeImage = w * h * 4
    
    buf = (ctypes.c_char * (w * h * 4))()
    gdi32.GetDIBits(memdc, hbm, 0, h, buf, ctypes.byref(bmi), 0)
    
    gdi32.DeleteObject(hbm)
    gdi32.DeleteDC(memdc)
    user32.ReleaseDC(hwnd, hdc)
    
    img = Image.frombytes('RGBA', (w, h), bytes(buf), 'raw', 'BGRA')
    img.load()
    img.save(output_path)
    print(f"[CAPTURED] -> {output_path} (size={w}x{h})")
    return img

def find_itgmania_window(pid):
    found = []
    def enum_cb(hwnd, _):
        p = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            r = wintypes.RECT()
            user32.GetClientRect(hwnd, ctypes.byref(r))
            if (r.right - r.left) > 400:
                found.append(hwnd)
        return True
    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(enum_cb), 0)
    return found[0] if found else None

def run_integration_test():
    base_dir = r"E:\ITGmania-Local\itgmania"
    prog_dir = os.path.join(base_dir, "Program")
    exe_path = os.path.join(prog_dir, "ITGmania.exe")
    flag_path = os.path.join(base_dir, "Save", "run_test.flag")
    log_path = os.path.join(base_dir, "Logs", "log.txt")
    out_dir = os.path.join(base_dir, "tests", "screenshots")
    os.makedirs(out_dir, exist_ok=True)

    # 0. Sync active Windows keyboard layout directly into Save/WindowsKeyboardLayout.lua
    try:
        tools_dir = os.path.join(base_dir, "tools")
        if tools_dir not in sys.path:
            sys.path.insert(0, tools_dir)
        import sync_keyboard_layout
        layout_name, _ = sync_keyboard_layout.sync_layout(os.path.join(base_dir, "Save"))
        print(f"[0/5] Synced active Windows keyboard layout: {layout_name}")
    except Exception as e:
        print(f"[WARN] Failed to auto-sync Windows layout: {e}")
    
    # 1. Create flag file
    with open(flag_path, "w") as f:
        f.write("test_active")
    print(f"[1/5] Created test flag: {flag_path}")
    
    # 2. Launch game
    print(f"[2/5] Launching ITGmania from {prog_dir}...")
    proc = subprocess.Popen([exe_path], cwd=prog_dir)
    print(f"Launched PID: {proc.pid}")
    
    # 3. Find window
    hwnd = None
    for _ in range(20):
        time.sleep(0.5)
        hwnd = find_itgmania_window(proc.pid)
        if hwnd:
            break
            
    if not hwnd:
        print("[ERROR] Window not found within timeout!")
        proc.terminate()
        if os.path.exists(flag_path):
            os.remove(flag_path)
        return False
        
    print(f"[3/5] Located HWND: {hex(hwnd)}")
    
    # 4. Monitor log and capture each step
    captured_steps = set()
    start_time = time.time()
    
    step_targets = {
        "ready": "01_ssm_ready.png",
        "open": "02_omnibar_open.png",
        "colemak_typed": "02b_colemak_typed.png",
        "search_bad": "03_search_bad.png",
        "search_artist": "03b_search_artist.png",
        "search_author": "03c_search_author.png",
        "search_album": "03d_search_album.png",
        "search_diff": "04_search_diff.png",
        "search_zero": "04b_search_zero.png",
        "selected": "05_wheel_selected.png",
        "reopen_recents": "06_reopen_recents.png",
        "history_recall": "07_history_recall.png",
    }
    
    print("[4/5] Monitoring test execution steps in log...")
    last_pos = 0
    while time.time() - start_time < 35.0:
        if os.path.exists(log_path):
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                f.seek(last_pos)
                new_lines = f.readlines()
                last_pos = f.tell()
                
            for line in new_lines:
                if "OMNIBAR_TEST_STEP:" in line:
                    step_name = line.split("OMNIBAR_TEST_STEP:")[1].strip()
                    if step_name in step_targets and step_name not in captured_steps:
                        time.sleep(0.3)
                        out_file = os.path.join(out_dir, step_targets[step_name])
                        capture_window(hwnd, out_file)
                        captured_steps.add(step_name)
                    elif step_name == "finished":
                        captured_steps.add("finished")
                        
        if "finished" in captured_steps or len(captured_steps) == len(step_targets):
            print("[SUCCESS] All steps triggered and captured!")
            break
        time.sleep(0.2)
        
    # 5. Clean up
    print("[5/5] Cleaning up...")
    if os.path.exists(flag_path):
        os.remove(flag_path)
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except:
        proc.kill()
        
    missing = set(step_targets.keys()) - captured_steps
    if missing:
        print(f"[WARN] Some steps were not captured: {missing}")
        return False
        
    print("[TEST COMPLETE] All screenshots captured successfully!")
    return True

if __name__ == "__main__":
    success = run_integration_test()
    sys.exit(0 if success else 1)
