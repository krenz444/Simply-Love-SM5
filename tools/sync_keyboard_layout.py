"""
sync_keyboard_layout.py
Directly queries the active Windows keyboard layout via Win32 API (user32.dll),
translates all DirectInput hardware scancodes to Unicode characters using ToUnicodeEx,
and writes Save/WindowsKeyboardLayout.lua for ITGmania / Simply Love.

This removes the need to hardcode keyboard layouts and guarantees 100% fidelity
with whatever keyboard layout is active in Windows (Colemak, QWERTY, Dvorak, AZERTY, etc.).
"""

import sys
import os
import ctypes
from ctypes import wintypes
import winreg

user32 = ctypes.windll.user32
user32.GetKeyboardLayout.argtypes = [ctypes.c_uint]
user32.GetKeyboardLayout.restype = ctypes.c_void_p
user32.MapVirtualKeyExW.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p]
user32.MapVirtualKeyExW.restype = ctypes.c_uint
user32.ToUnicodeEx.argtypes = [
    ctypes.c_uint,
    ctypes.c_uint,
    ctypes.POINTER(ctypes.c_ubyte),
    ctypes.c_wchar_p,
    ctypes.c_int,
    ctypes.c_uint,
    ctypes.c_void_p,
]
user32.ToUnicodeEx.restype = ctypes.c_int

# DirectInput / StepMania Scancode Table
SCANCODES = {
    "DeviceButton_q": 0x10,
    "DeviceButton_w": 0x11,
    "DeviceButton_e": 0x12,
    "DeviceButton_r": 0x13,
    "DeviceButton_t": 0x14,
    "DeviceButton_y": 0x15,
    "DeviceButton_u": 0x16,
    "DeviceButton_i": 0x17,
    "DeviceButton_o": 0x18,
    "DeviceButton_p": 0x19,
    "DeviceButton_[": 0x1A,
    "DeviceButton_]": 0x1B,
    "DeviceButton_left bracket": 0x1A,
    "DeviceButton_right bracket": 0x1B,
    "DeviceButton_a": 0x1E,
    "DeviceButton_s": 0x1F,
    "DeviceButton_d": 0x20,
    "DeviceButton_f": 0x21,
    "DeviceButton_g": 0x22,
    "DeviceButton_h": 0x23,
    "DeviceButton_j": 0x24,
    "DeviceButton_k": 0x25,
    "DeviceButton_l": 0x26,
    "DeviceButton_colon": 0x27,
    "DeviceButton_;": 0x27,
    "DeviceButton_:": 0x27,
    "DeviceButton_semicolon": 0x27,
    "DeviceButton_apostrophe": 0x28,
    "DeviceButton_'": 0x28,
    "DeviceButton_quote": 0x28,
    "DeviceButton_z": 0x2C,
    "DeviceButton_x": 0x2D,
    "DeviceButton_c": 0x2E,
    "DeviceButton_v": 0x2F,
    "DeviceButton_b": 0x30,
    "DeviceButton_n": 0x31,
    "DeviceButton_m": 0x32,
    "DeviceButton_comma": 0x33,
    "DeviceButton_,": 0x33,
    "DeviceButton_period": 0x34,
    "DeviceButton_.": 0x34,
    "DeviceButton_slash": 0x35,
    "DeviceButton_/": 0x35,
    "DeviceButton_minus": 0x0C,
    "DeviceButton_hyphen": 0x0C,
    "DeviceButton_-": 0x0C,
    "DeviceButton_equals": 0x0D,
    "DeviceButton_equal": 0x0D,
    "DeviceButton_=": 0x0D,
    "DeviceButton_`": 0x29,
    "DeviceButton_grave": 0x29,
    "DeviceButton_backslash": 0x2B,
    "DeviceButton_\\": 0x2B,
    "DeviceButton_1": 0x02,
    "DeviceButton_2": 0x03,
    "DeviceButton_3": 0x04,
    "DeviceButton_4": 0x05,
    "DeviceButton_5": 0x06,
    "DeviceButton_6": 0x07,
    "DeviceButton_7": 0x08,
    "DeviceButton_8": 0x09,
    "DeviceButton_9": 0x0A,
    "DeviceButton_0": 0x0B,
}

def get_char(scancode, hkl, shift=False):
    vk = user32.MapVirtualKeyExW(scancode, 1, hkl) # MAPVK_VSC_TO_VK
    if not vk:
        return None
    keystate = (ctypes.c_ubyte * 256)()
    if shift:
        keystate[0x10] = 0x80 # VK_SHIFT
    buf = ctypes.create_unicode_buffer(16)
    ret = user32.ToUnicodeEx(vk, scancode, keystate, buf, 16, 0, hkl)
    if ret > 0:
        return buf.value
    return None

def sync_layout(save_dir=None):
    if save_dir is None:
        base_dir = r"E:\ITGmania-Local\itgmania"
        save_dir = os.path.join(base_dir, "Save")

    os.makedirs(save_dir, exist_ok=True)
    hkl = user32.GetKeyboardLayout(0)
    
    # Get Layout Name Text from Windows Registry
    buf = ctypes.create_unicode_buffer(9)
    user32.GetKeyboardLayoutNameW(buf)
    layout_code = buf.value
    layout_name = "Windows"
    try:
        reg_path = r"SYSTEM\CurrentControlSet\Control\Keyboard Layouts\\" + layout_code
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, reg_path)
        layout_name = winreg.QueryValueEx(k, "Layout Text")[0]
    except Exception as e:
        layout_name = f"Layout_{layout_code}"

    print(f"[WINDOWS LAYOUT] Code: {layout_code} | Name: {layout_name} | HKL: {hex(hkl)}")

    lines = [
        "-- WindowsKeyboardLayout.lua",
        "-- Automatically exported from active Windows keyboard layout via Win32 API",
        "return {",
        f'    id = "windows_auto",',
        f'    name = "Windows ({layout_name})",',
        f'    layoutName = "{layout_name}",',
        f'    layoutCode = "{layout_code}",',
        "    map = {",
    ]

    for btn, sc in sorted(SCANCODES.items()):
        c = get_char(sc, hkl, False)
        if c:
            esc_btn = btn.replace("\\", "\\\\").replace('"', '\\"')
            esc = c.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'        ["{esc_btn}"] = "{esc}",')

    lines.append("    },")
    lines.append("    shift_map = {")

    for btn, sc in sorted(SCANCODES.items()):
        c = get_char(sc, hkl, True)
        if c:
            esc_btn = btn.replace("\\", "\\\\").replace('"', '\\"')
            esc = c.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'        ["{esc_btn}"] = "{esc}",')

    lines.append("    },")
    lines.append("}")

    lua_content = "\n".join(lines) + "\n"
    out_path = os.path.join(save_dir, "WindowsKeyboardLayout.lua")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(lua_content)

    print(f"[EXPORTED] -> {out_path} ({len(lua_content)} bytes)")
    return layout_name, out_path

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else None
    sync_layout(target)
