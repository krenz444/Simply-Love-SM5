"""
deploy_cabinet.py - safe, verifiable deploy of this theme's fork-owned files to the DDR cabinet.

  python -I tools/deploy_cabinet.py --host <ip>            # dry run: compare hashes, change nothing
  python -I tools/deploy_cabinet.py --host <ip> --apply    # back up remote files, then copy

Replaces the ad-hoc scripts that lived in another session's scratch folder. Differences:
  * dry run by default; --apply is required to change anything
  * compares SHA-256 of every fork-owned file (nothing is silently skipped or partially copied)
  * backs the remote file up to <theme>/../ThemeBackups/<timestamp>/ before overwriting
  * never uploads dev-only files (DevScenarios.lua, tests/, tools/)
Connection details are arguments / environment (DDR_HOST, DDR_USER, DDR_KEY, DDR_HOSTKEYALIAS);
nothing is hard-coded and no secrets are stored.
"""
import argparse
import hashlib
import os
import pathlib
import subprocess
import sys
import time

EXCLUDE_PREFIXES = ("tests/", "tools/", ".git")
EXCLUDE_NAMES = ("DevScenarios.lua",)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout, r.stderr


def fork_files(theme, base):
    rc, out, err = run(["git", "-C", str(theme), "diff", "--name-only", "--diff-filter=AM",
                        f"{base}..HEAD"])
    if rc != 0:
        sys.exit("git diff failed: " + err)
    files = [f for f in out.splitlines()
             if f and not f.startswith(EXCLUDE_PREFIXES) and os.path.basename(f) not in EXCLUDE_NAMES]
    return sorted(files)


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest().upper()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", default=str(pathlib.Path(__file__).resolve().parent.parent))
    ap.add_argument("--base", default="dd06138b", help="upstream commit the fork diverged from")
    ap.add_argument("--host", default=os.environ.get("DDR_HOST"))
    ap.add_argument("--user", default=os.environ.get("DDR_USER", "ddr"))
    ap.add_argument("--key", default=os.environ.get("DDR_KEY"))
    ap.add_argument("--host-key-alias", default=os.environ.get("DDR_HOSTKEYALIAS"))
    ap.add_argument("--remote-theme", default="C:/Games/ITGmania/Themes/Simply Love")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    if not a.host:
        sys.exit("--host (or DDR_HOST) is required")

    ssh_opts = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no"]
    if a.key:
        ssh_opts += ["-i", a.key]
    if a.host_key_alias:
        ssh_opts += ["-o", f"HostKeyAlias={a.host_key_alias}"]
    target = f"{a.user}@{a.host}"

    def ssh(cmd):
        return run(["ssh", *ssh_opts, target, cmd])

    def scp(src, dst):
        return run(["scp", *ssh_opts, src, f"{target}:{dst}"])

    theme = pathlib.Path(a.theme)
    files = fork_files(theme, a.base)
    print(f"{len(files)} fork-owned files vs {a.base}; remote theme: {a.remote_theme}")

    ps = "; ".join(
        f"if (Test-Path -LiteralPath '{a.remote_theme}/{f}') {{ '{f}|' + "
        f"(Get-FileHash -LiteralPath '{a.remote_theme}/{f}' -Algorithm SHA256).Hash }} "
        f"else {{ '{f}|MISSING' }}" for f in files)
    rc, out, err = ssh(f'powershell -NoProfile -Command "{ps}"')
    if rc != 0:
        sys.exit("remote hash failed: " + err)
    remote = dict(l.split("|", 1) for l in out.splitlines() if "|" in l)

    todo = []
    for f in files:
        local, rem = sha(theme / f), remote.get(f, "MISSING")
        state = "SAME" if local == rem else ("NEW " if rem == "MISSING" else "DIFF")
        print(f"  {state}  {f}")
        if state != "SAME":
            todo.append(f)
    if not todo:
        print("cabinet already matches; nothing to do")
        return
    if not a.apply:
        print(f"\ndry run: {len(todo)} file(s) would change. Re-run with --apply.")
        return

    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = f"{a.remote_theme}/../ThemeBackups/{stamp}"
    for f in todo:
        d = str(pathlib.PurePosixPath(f).parent)
        ssh("powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path "
            f"'{a.remote_theme}/{d}','{backup}/{d}' | Out-Null; "
            f"if (Test-Path -LiteralPath '{a.remote_theme}/{f}') "
            f"{{ Copy-Item -LiteralPath '{a.remote_theme}/{f}' -Destination '{backup}/{f}' -Force }}\"")
        rc, _, err = scp(str(theme / f), f"{a.remote_theme}/{f}")
        print(f"  {'OK  ' if rc == 0 else 'FAIL'} {f} {err.strip() if rc else ''}")
    print(f"backups: {backup}")


if __name__ == "__main__":
    main()
