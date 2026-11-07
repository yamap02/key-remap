#!/usr/bin/env python3
"""Exercise AppKit termination in a disposable process, not the running app."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='rekey-termination-probe-') as temporary:
    executable = Path(temporary) / 'probe'
    subprocess.run(['swiftc', '-parse-as-library',
                    str(root / 'Sources/ReKeyApp/TerminationGate.swift'),
                    str(root / 'Tests/Distribution/termination_gate_probe.swift'),
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
