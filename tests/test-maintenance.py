"""Exercise backup/restore using a temporary filesystem and stubbed router commands."""
import os
import re
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PHONE_PANEL_TEST_SH', 'sh')


def shell_path(path):
    value = path.resolve().as_posix()
    if os.name == 'nt':
        value = '/' + value[0].lower() + value[2:]
    return value


with tempfile.TemporaryDirectory(prefix='maintenance-test-', dir=REPO) as directory:
    base = Path(directory)
    root = base / 'router'
    bindir = base / 'bin'
    bindir.mkdir()

    def write(relative, content):
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
        target.chmod(0o700)
        return target

    source = write('etc/openclash/config/source.yaml', 'old source\n')
    write('etc/phone-dns/state', 'old state\n')
    write('etc/config/dhcp', 'old DHCP\n')
    hook = write('etc/openclash/custom/openclash_custom_overwrite.sh', 'old hook\n')
    for name in ('phone-dns', 'openclash'):
        write('etc/init.d/' + name, '#!/bin/sh\nexit 0\n')
    for name, code in {'id': 'echo 0', 'uci': "printf '%s\\n' '" + shell_path(source) + "'"}.items():
        target = bindir / name
        target.write_text('#!/bin/sh\n' + code + '\n', encoding='utf-8')
        target.chmod(0o700)

    script = (REPO / 'scripts/maintenance.sh').read_text(encoding='utf-8')
    # Redirect every absolute router path; execute the real control flow and copying.
    for prefix in ('/etc/', '/root/', '/usr/'):
        script = re.sub(r'(?<!\$B)' + re.escape(prefix), lambda _: shell_path(root) + prefix, script)
    script = script.replace('${CFG#/}', '${CFG#' + shell_path(root) + '/}')
    script = script.replace('"/$P"', '"' + shell_path(root) + '/$P"')
    runner = base / 'maintenance.sh'
    runner.write_text(script, encoding='utf-8')
    env = os.environ.copy()
    env['PATH'] = str(bindir) + os.pathsep + env['PATH']

    def run(*args, ok=True):
        result = subprocess.run([SHELL, '-x', shell_path(runner), *args], env=env, text=True, capture_output=True)
        if ok and result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        return result

    run('backup')
    snapshots = root / 'root/phone-panel-maintenance'
    snapshot = next(snapshots.iterdir())
    assert (snapshot / 'etc/openclash/config/source.yaml').read_text() == 'old source\n'
    assert (snapshot / 'etc/openclash/custom/openclash_custom_overwrite.sh').read_text() == 'old hook\n'
    write('etc/phone-dns/state', 'new state\n')
    source.write_text('new source\n')
    hook.write_text('new hook\n')
    run('restore', shell_path(snapshot), '--apply')
    assert (root / 'etc/phone-dns/state').read_text() == 'old state\n', 'restore must use selected snapshot'
    assert source.read_text() == 'old source\n'
    assert hook.read_text() == 'old hook\n'
    assert len(list(snapshots.iterdir())) == 2, 'restore must save the pre-restore state'
    outside = base / 'outside'
    outside.mkdir()
    result = run('restore', shell_path(snapshots) + '/../../outside', '--apply', ok=False)
    assert result.returncode != 0, 'path traversal must be rejected'
    nested = snapshot / 'nested'
    nested.mkdir()
    assert run('restore', shell_path(nested), '--apply', ok=False).returncode != 0

print('PASS: maintenance backup contents, selected-snapshot restore and path boundaries')
