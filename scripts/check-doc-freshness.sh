#!/bin/bash
# check-doc-freshness.sh
# Scan ~/products/niteride/engineering/**/*.md for backtick-quoted filesystem paths,
# classify each, check existence where possible, report stale.
#
# Exit 0 = no STALE. Exit 1 = at least one STALE. Exit 2 = usage/runtime error.
#
# v1 scope:
# - Paths under known roots only (~/code/, ~/products/, ~/obsidian-wiki/, /Users/jessepifer/)
# - INFRA paths (/etc/, /opt/, /var/, /srv/, /usr/local/) flagged for manual SSH verify
# - Nginx location-block strings, API route paths, container mounts: SKIPPED (not filesystem)
# - Line-range suffixes (:123 or :123-456) stripped before existence check
# - Template placeholders (<repo>, <channel>, etc.) ignored

set -e

ENG_DIR="${1:-$HOME/products/niteride/engineering}"

if [ ! -d "$ENG_DIR" ]; then
  echo "ERROR: engineering dir not found: $ENG_DIR" >&2
  exit 2
fi

python3 << PYTHON_SCRIPT
import os
import re
import sys
from pathlib import Path

ENG_DIR = Path("$ENG_DIR").expanduser()
HOME = str(Path.home())

# Filesystem-path roots we can check locally
LOCAL_ROOTS = (HOME + '/code/', HOME + '/products/', HOME + '/obsidian-wiki/',
               HOME + '/incidents/', HOME + '/.claude/', '/Users/jessepifer/')
# Paths that require SSH to verify
INFRA_ROOTS = ('/etc/', '/opt/', '/var/', '/srv/', '/usr/local/', '/usr/bin/', '/home/')

# Strip trailing :line or :line-range suffix (keep the path portion)
LINE_SUFFIX_RE = re.compile(r':(\d+(-\d+)?)\$')
# Backtick-wrapped candidate
PATH_RE = re.compile(r'\`+([^\`\s]+)\`+')

rows = []
stale_count = 0
infra_count = 0
ok_count = 0
skipped = {'url': 0, 'placeholder': 0, 'not-absolute': 0, 'route-or-mount': 0, 'regex': 0}

REGEX_LIKE = re.compile(r'[\\\^\\\$\\\*\\\+\\\?\\\|\\\(\\\)\\\[\\\]\\\{\\\}]')

def classify(raw):
    # Step 1: cheap filters
    if '://' in raw:
        skipped['url'] += 1
        return None
    if '<' in raw or '>' in raw:
        skipped['placeholder'] += 1
        return None
    if REGEX_LIKE.search(raw):
        skipped['regex'] += 1
        return None
    if '/' not in raw:
        return None  # not a path-like token

    # Must start with / or ~/
    if not (raw.startswith('/') or raw.startswith('~/')):
        skipped['not-absolute'] += 1
        return None

    # Strip line suffix for existence check
    m = LINE_SUFFIX_RE.search(raw)
    path_only = raw[:m.start()] if m else raw

    # Expand ~
    abspath = os.path.expanduser(path_only)

    # Is it under a local-checkable root?
    for root in LOCAL_ROOTS:
        if abspath.startswith(root):
            exists = os.path.exists(abspath)
            return ('OK' if exists else 'STALE', raw, abspath)

    # Is it infra (remote-only)?
    for root in INFRA_ROOTS:
        if abspath.startswith(root):
            return ('INFRA', raw, abspath)

    # Starts with / but not under a known root — likely an nginx location, API route, or mount
    skipped['route-or-mount'] += 1
    return None

def scan(md_path):
    global stale_count, infra_count, ok_count
    try:
        with open(md_path, 'r', encoding='utf-8') as f:
            for lineno, line in enumerate(f, 1):
                for m in PATH_RE.finditer(line):
                    result = classify(m.group(1))
                    if result is None:
                        continue
                    kind, raw, abspath = result
                    relmd = str(md_path.relative_to(ENG_DIR))
                    rows.append((kind, relmd, lineno, raw, abspath))
                    if kind == 'STALE': stale_count += 1
                    elif kind == 'INFRA': infra_count += 1
                    elif kind == 'OK': ok_count += 1
    except (UnicodeDecodeError, PermissionError):
        pass

for md in ENG_DIR.rglob('*.md'):
    scan(md)

order = {'STALE': 0, 'INFRA': 1, 'OK': 2}
rows.sort(key=lambda r: (order.get(r[0], 99), r[1], r[2]))

for kind, relmd, lineno, raw, abspath in rows:
    marker = {'STALE': 'STALE', 'INFRA': 'INFRA (manual)', 'OK': 'OK'}[kind]
    print(f"{marker:<15} {relmd}:{lineno}   {raw}")

total = len(rows) + sum(skipped.values())
print('---')
print(f"Summary: {total} candidates scanned, {stale_count} stale, {infra_count} infra (manual), {ok_count} ok")
print(f"Skipped: {skipped['url']} urls, {skipped['placeholder']} placeholders, {skipped['regex']} regex-like, {skipped['route-or-mount']} routes/mounts, {skipped['not-absolute']} relative")

sys.exit(1 if stale_count > 0 else 0)
PYTHON_SCRIPT
