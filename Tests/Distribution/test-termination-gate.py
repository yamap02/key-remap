#!/usr/bin/env python3
"""Exercise AppKit termination in a disposable process, not the running app."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='rekey-termination-probe-') as temporary:
    for name in ('termination_gate_probe', 'termination_swiftui_probe', 'termination_pending_probe'):
        executable = Path(temporary) / name
        subprocess.run(['swiftc', '-parse-as-library',
                        str(root / 'Sources/ReKeyApp/TerminationGate.swift'),
                        str(root / 'Tests/Distribution' / (name + '.swift')),
                        '-o', str(executable)], check=True)
        result = subprocess.run([str(executable)], check=True, timeout=15, capture_output=True, text=True)
        if name == 'termination_pending_probe' and result.stdout.splitlines() != [
                'REQUEST 1', 'VERIFY 1', 'PASS unsafe pending update blocked termination', 'VERIFY 2']:
            raise AssertionError(f'Unexpected pending termination sequence: {result.stdout!r}')
        print(result.stdout, end='')
