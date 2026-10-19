"""Fetch only the pinned upstream audio files, verifying their SHA-256 hashes."""
from pathlib import Path
import hashlib,json,urllib.request
ROOT=Path(__file__).resolve().parents[1]
lock=json.loads((ROOT/'assets/upstream.lock.json').read_text())
for name,item in lock['assets'].items():
    dest=ROOT/item['path']
    if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest()==item['sha256']:
        continue
    url=f"https://raw.githubusercontent.com/{lock['repository']}/{lock['commit']}/{item['path']}"
    with urllib.request.urlopen(url,timeout=30) as response:
        data=response.read()
    if hashlib.sha256(data).hexdigest()!=item['sha256']:
        raise RuntimeError(f'SHA-256 mismatch: {name}')
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_bytes(data)
    print(f'Verified {name}')
