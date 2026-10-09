import argparse
import hashlib
import json
from pathlib import Path
from huggingface_hub import hf_hub_download

parser=argparse.ArgumentParser(); parser.add_argument('--output',required=True,type=Path)
args=parser.parse_args()
manifest=json.loads((Path(__file__).parent/'model_manifest.json').read_text())
for filename in ('config.json','model.pth','voices/thorsten.pt'):
    path=Path(hf_hub_download(repo_id=manifest['repo'],filename=filename,
             revision=manifest['revision'],local_dir=args.output))
    actual=hashlib.file_digest(path.open('rb'),'sha256').hexdigest()
    if actual!=manifest['files'][filename]['sha256']: raise RuntimeError('model_checksum_mismatch')
    path.chmod(0o644)
for path in [args.output,*[p for p in args.output.rglob('*') if p.is_dir()]]: path.chmod(0o755)
print('PINNED_MODEL_CHECKSUMS_OK')
