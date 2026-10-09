#!/usr/bin/env python3
"""Refresh the self-contained 2.6 server installer from the reviewed sources."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
names = ("kokoro_service.py", "install_kokoro.py", "download_models.py",
         "model_manifest.json", "requirements.lock.txt", "requirements-cpu.lock.txt", "LICENSE.kienzlefon-ai",
         "test_installer.py")
for name in names:
    path = root / name
    path.write_text(path.read_text().rstrip("\n") + "\n")
manifest = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in names}
(root / "source_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
body = ['# BEGIN KOKORO 2.6 GENERATED PAYLOADS', 'write_kokoro_payloads() {',
        '  local destination="$1"', '  mkdir -p "$destination"']
for index, name in enumerate((*names, "source_manifest.json")):
    marker = f"__KIENZLEFON_KOKORO_26_{index}__"
    content = (root / name).read_text()
    assert marker not in content
    body.extend([f'  cat > "$destination/{name}" <<\'{marker}\'', content.rstrip("\n"), marker])
body.extend(['}', '# END KOKORO 2.6 GENERATED PAYLOADS', ''])
installer = root.parent / "install-kienzlefon-ai_v2.6.sh"
source = installer.read_text()
start = source.find('# BEGIN KOKORO 2.6 GENERATED PAYLOADS')
if start >= 0:
    end = source.index('# END KOKORO 2.6 GENERATED PAYLOADS', start) + len('# END KOKORO 2.6 GENERATED PAYLOADS\n')
    source = source[:start] + source[end:].lstrip("\n")
source = source.replace('write_core_payload() {', '\n'.join(body) + '\nwrite_core_payload() {', 1)
installer.write_text(source)
print('Refreshed Kokoro 2.6 payloads and source manifest')
