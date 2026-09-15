#!/usr/bin/env python3
"""Install the independent app and merge only its optional hook handlers."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess

EVENTS = ('SessionStart', 'UserPromptSubmit', 'Stop', 'Interrupt')
MARKER = 'PetQuotaHUD --hook'  # command suffix remains stable even if paths contain spaces


def ours(handler):
    return 'Pet Quota HUD.app/Contents/MacOS/PetQuotaHUD' in handler.get('command', '') and ' --hook ' in handler.get('command', '')


def merge_hooks(root, executable, remove=False):
    root = json.loads(json.dumps(root))
    hooks = root.setdefault('hooks', {})
    if not isinstance(hooks, dict):
        raise ValueError('hooks must be an object; refusing to overwrite')
    for event in EVENTS:
        entries = []
        for entry in hooks.get(event, []):
            entry = dict(entry)
            original = entry.get('hooks', [])
            remaining = [h for h in original if not ours(h)]
            if remaining or not original:
                entry['hooks'] = remaining
                entries.append(entry)
        if not remove:
            entries.append({'hooks': [{'type': 'command', 'command': shlex.quote(str(executable)) + ' --hook ' + event, 'async': True, 'timeout': 3}]})
        if entries:
            hooks[event] = entries
        else:
            hooks.pop(event, None)
    return root


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--uninstall', action='store_true')
    parser.add_argument('--without-hooks', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    app = Path.home() / 'Applications/Pet Quota HUD.app'
    executable = app / 'Contents/MacOS/PetQuotaHUD'
    codex_home = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
    path = codex_home / 'hooks.json'
    old = json.loads(path.read_text()) if path.exists() else {}
    updated = merge_hooks(old, executable, remove=args.uninstall)
    if args.dry_run:
        print(json.dumps({'app': str(app), 'hooksFile': str(path), 'events': list(EVENTS), 'preservesExistingHandlers': True, 'uninstall': args.uninstall}, indent=2))
        return
    if args.uninstall:
        # Stop this exact executable, never another Codex or pet process.
        subprocess.run(['/usr/bin/pkill', '-f', '^' + str(executable) + '$'], check=False)
        if app.exists():
            shutil.rmtree(app)
    else:
        source = project / 'dist/Pet Quota HUD.app'
        if not source.exists():
            raise SystemExit('Run bash scripts/build.sh first')
        app.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, app, dirs_exist_ok=True)
    if not args.without_hooks and updated != old:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            shutil.copy2(path, path.with_name('hooks.json.pet-quota-backup-' + stamp))
        temp = path.with_name('hooks.json.pet-quota.tmp')
        temp.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + '\n')
        temp.chmod(0o600)
        temp.replace(path)
    if not args.uninstall:
        subprocess.run(['/usr/bin/open', str(app)], check=True)
        print('Installed and launched. Review/trust the added hooks in Codex; polling works before trust.')
    else:
        print('App and its hooks removed. Cached numeric quota and hook backups retained.')


if __name__ == '__main__':
    main()
