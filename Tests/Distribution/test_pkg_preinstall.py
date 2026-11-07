import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PreinstallTests(unittest.TestCase):
    def run_script(self, *, services=(), alive=False, failure=''):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launchctl = root / 'launchctl'
            launchctl.write_text('''#!/bin/sh
if [ "$1" = print ] && [ "$2" = system ]; then [ "$FAILURE" != inspect ]; exit; fi
name=${2#system/}
if [ "$1" = print ]; then [ -f "$STATE/$name" ]; exit; fi
if [ "$1" = bootout ]; then
    [ "$FAILURE" != bootout ] || exit 1
    if [ "$FAILURE" != remains ]; then /bin/rm "$STATE/$name"; fi
    exit 0
fi
exit 2
''')
            pgrep = root / 'pgrep'
            pgrep.write_text('#!/bin/sh\n[ "$FAILURE" = pgrep ] && exit 2\n[ "$ALIVE" = yes ]\n')
            sleep = root / 'sleep'
            sleep.write_text('#!/bin/sh\nexit 0\n')
            for path in (launchctl, pgrep, sleep):
                path.chmod(0o700)
            for name in services:
                (root / name).touch()
            script = (ROOT / 'Resources/pkg-preinstall').read_text()
            script = script.replace('/bin/launchctl', str(launchctl))
            script = script.replace('/usr/bin/pgrep', str(pgrep))
            script = script.replace('/bin/sleep', str(sleep))
            env = dict(os.environ, STATE=str(root), FAILURE=failure, ALIVE='yes' if alive else 'no')
            return subprocess.run(['/bin/sh'], input=script, text=True, env=env, capture_output=True)

    def test_absent_and_cleanly_stopped_services(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.run_script(services=['jp.example.rekey.core', 'jp.example.rekey.vhid']).returncode, 0)

    def test_refuses_failed_inspection_stop_or_live_process(self):
        for kwargs in ({'failure': 'inspect'},
                       {'services': ['jp.example.rekey.core'], 'failure': 'bootout'},
                       {'services': ['jp.example.rekey.core'], 'failure': 'remains'},
                       {'alive': True}, {'failure': 'pgrep'}):
            with self.subTest(kwargs=kwargs):
                self.assertNotEqual(self.run_script(**kwargs).returncode, 0)


if __name__ == '__main__':
    unittest.main()
