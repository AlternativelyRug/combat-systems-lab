"""One local/CI entry point. All tools must succeed; no baseline failures are waived."""
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXE = ".exe" if os.name == "nt" else ""
def tool(name: str, folder: str) -> str:
    path = ROOT / ".tools" / folder / (name + EXE)
    if not path.is_file():
        raise SystemExit("Run python tools/setup.py first")
    return str(path)

def run(args: list[str]) -> None:
    print("CHECK", Path(args[0]).name, " ".join(args[1:]), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)

run([tool("stylua", "stylua"), "--check", "src", "tests", "examples"])
run([tool("luau-analyze", "luau"), "src", "tests", "examples"])
run([tool("luau", "luau"), "tests/run.luau"])
run([tool("luau", "luau"), "examples/duel.luau"])

# An allowlist makes accidentally staging an archive or private attachment conspicuous.
approved = set((ROOT / "tools/public-files.txt").read_text().splitlines())
listed = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).decode().split("\0")
files = {name for name in listed if name}
if files != approved:
    raise SystemExit(f"Public file list mismatch. Extra={sorted(files-approved)} Missing={sorted(approved-files)}")
patterns = [r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", r"\bgh[pousr]_[A-Za-z0-9]{20,}\b", r"\bgithub_pat_[A-Za-z0-9_]{20,}\b", r"\bAKIA[A-Z0-9]{16}\b", r"[A-Z]:\\Users\\", r"\.ROBLOSECURITY"]
for name in sorted(files):
    path = ROOT / name
    if path.is_symlink() or path.stat().st_size > 500_000:
        raise SystemExit(f"Unexpected public artifact: {name}")
    text = path.read_text(encoding="utf-8")
    # The scanner's regex declarations are not credentials.
    if name == "tools/check.py":
        continue
    if any(re.search(pattern, text) for pattern in patterns):
        raise SystemExit(f"Possible private data in {name}; inspect locally before publishing")
print(f"PASS public-file allowlist and basic secret scan: {len(files)} text files")
print("PASS all checks")
