#!/bin/bash
# Launch only a disposable copy; never replace or terminate the installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import os
import plistlib
import shutil
import socket
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

source = Path('.build/DSH Desktop Community.app').resolve()
if not source.is_dir():
    raise SystemExit('Build the app with ./build.sh first.')
identifier = 'io.github.dramtea.dsh-desktop-community.smoke-' + uuid.uuid4().hex
with tempfile.TemporaryDirectory(prefix='dsh-app-smoke-') as temporary:
    root = Path(temporary)
    app = root / source.name
    shutil.copytree(source, app, symlinks=True)
    info = app / 'Contents/Info.plist'
    with info.open('rb') as handle:
        metadata = plistlib.load(handle)
    metadata['CFBundleIdentifier'] = identifier
    with info.open('wb') as handle:
        plistlib.dump(metadata, handle)
    subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    # Hold an unused port without listening, so this launch cannot adopt another service.
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
        # NSArgumentDomain stores command-line overrides as strings. Import
        # typed values so the service's Bool/Int settings cannot fall back to
        # auto-start or the user's normal port during this isolated check.
        preferences = root / 'preferences.plist'
        with preferences.open('wb') as handle:
            plistlib.dump({'autoStart': False, 'stopOnQuit': False, 'cleanupStaleOnStart': False,
                'dshPath': str(root / 'no-runtime-for-smoke-test'), 'host': '127.0.0.1', 'port': port,
                'localModelStartExecutable': '', 'localModelStopExecutable': '',
                'localModelHealthURL': '', 'stopLocalModelOnQuit': False}, handle)
        subprocess.run(['/usr/bin/defaults', 'import', identifier, str(preferences)], check=True)
        arguments = [str(app / 'Contents/MacOS/DSHLauncher')]
        environment = dict(os.environ, DSH_HOME=str(root / 'dsh'))
        log_path = root / 'launch.log'
        process = None
        try:
            with log_path.open('wb') as log:
                process = subprocess.Popen(arguments, stdout=log, stderr=log, env=environment)
                time.sleep(5)
                if process.poll() is not None:
                    raise RuntimeError(f'App exited during startup ({process.returncode}):\n{log_path.read_text()}')
                print('App startup smoke passed: isolated bundle and data, process alive after 5 seconds.')
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            # Delete only the unique, disposable preference domain created above.
            subprocess.run(['/usr/bin/defaults', 'delete', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
