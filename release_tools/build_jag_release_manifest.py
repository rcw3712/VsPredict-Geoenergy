from pathlib import Path
import csv
import hashlib

repo = Path(__file__).resolve().parents[1]
manifest = repo / "JAG_RELEASE_MANIFEST_SHA256.csv"

excluded_parts = {".git"}
excluded_names = {manifest.name}
rows = []

for path in sorted(repo.rglob("*"), key=lambda p: str(p.relative_to(repo)).lower()):
    if not path.is_file():
        continue
    rel = path.relative_to(repo)
    if any(part in excluded_parts for part in rel.parts) or path.name in excluded_names:
        continue
    if rel.parts and rel.parts[0] == "data" and path.suffix.lower() in {".xlsx", ".xls", ".las", ".csv"}:
        raise RuntimeError(f"Potential proprietary input found in public data directory: {rel}")
    rows.append(
        [
            str(rel).replace("\\", "/"),
            path.stat().st_size,
            hashlib.sha256(path.read_bytes()).hexdigest(),
        ]
    )

with manifest.open("w", newline="", encoding="utf-8-sig") as handle:
    writer = csv.writer(handle)
    writer.writerow(["RELATIVE_PATH", "BYTES", "SHA256"])
    writer.writerows(rows)

print(f"Wrote {len(rows)} hashes to {manifest}")
