"""Install digest-verified upstream tools locally; never modifies PATH or downloads game code."""
from pathlib import Path
import hashlib
import io
import json
import platform
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PLATFORM = {"Windows": "windows", "Linux": "linux"}.get(platform.system())
if PLATFORM is None or platform.machine().lower() not in ("amd64", "x86_64"):
    raise SystemExit("Bootstrap supports Windows/Linux x86_64. See README for manual tools.")
TOOLS = {
    "windows": [
        ("luau", "https://github.com/luau-lang/luau/releases/download/0.746/luau-windows.zip", "e149fdb4fe78a52ce457fbd40741484eaab1dbf9907e7f878c6d8a9a3dac2ddd"),
        ("stylua", "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.4.0/stylua-windows-x86_64.zip", "3803853280cb524560c6ce0d4140f6d9f02e03f55e1ce50bb4f5e51e07565794"),
    ],
    "linux": [
        ("luau", "https://github.com/luau-lang/luau/releases/download/0.746/luau-ubuntu.zip", "30f11c9cde8be2dc0e3066d210705532aac3726a2db89a6c5078080b6faa6cf8"),
        ("stylua", "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.4.0/stylua-linux-x86_64.zip", "f9c84c210712061cb03ab8354a34a5d4f5fcf1f369d2ce916bea3ab9f7addac8"),
    ],
}
receipts = []
for name, url, digest in TOOLS[PLATFORM]:
    request = urllib.request.Request(url, headers={"User-Agent": "combat-systems-lab-setup"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit(f"Digest mismatch: {name}. No archive extracted.")
    destination = ROOT / ".tools" / name
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for member in archive.infolist():
            output = (destination / member.filename).resolve()
            if not output.is_relative_to(destination.resolve()):
                raise SystemExit("Unsafe archive path")
        archive.extractall(destination)
    for path in destination.iterdir():
        if path.is_file() and PLATFORM == "linux":
            path.chmod(0o755)
    receipts.append({"tool": name, "source": url, "sha256": digest})
    print(f"Verified and installed {name}")
(ROOT / ".tools" / "receipts.json").write_text(json.dumps(receipts, indent=2))
