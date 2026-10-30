#!/usr/bin/env python3
"""Conservative publication gate; not a substitute for manual review."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[1]
patterns = [
    r'/Users/[^\s/]+', r'/var/folders/',
    r'gh[pousr]_[A-Za-z0-9]{20,}', r'github_pat_[A-Za-z0-9_]{20,}',
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    r'(?im)^\s*(?:password|secret|private-key)\s*:\s*[\w+/=]{6,}\s*$',
]
forbidden = {'.png', '.jpg', '.jpeg', '.pcap', '.pcapng', '.zip', '.gz'}
runtime = {'mapping.yaml', 'devices.yaml', 'listeners.yaml', 'import-status.yaml', 'config.json', 'hosts.yml'}
errors = []
files = [p for p in root.rglob('*') if p.is_file() and '.git' not in p.parts]
for p in files:
    rel = str(p.relative_to(root))
    if p.suffix.lower() in forbidden or p.name in runtime:
        errors.append(rel + ': forbidden runtime/binary artifact')
        continue
    text = p.read_text(encoding='utf-8')
    if p.name == 'privacy_check.py':
        continue
    for pattern in patterns:
        if re.search(pattern, text):
            errors.append(rel + ': potential sensitive content')
            break
    for mac in re.findall(r'(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b', text):
        if mac.lower() != '00:00:00:00:00:00' and not mac.lower().startswith('02:'):
            errors.append(rel + ': non-synthetic MAC')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print(f'PASS: {len(files)} publication files checked (also review manually).')
