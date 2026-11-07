import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PreinstallTests(unittest.TestCase):
    def run_script(self, *, services=(), alive='', failure=''):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launchctl = root / 'launchctl'
            launchctl.write_text('''#!/bin/sh
if [ "$1" = print ] && [ "$2" = system ]; then [ "$FAILURE" != inspect ]; exit; fi
name=${2#system/}
if [ "$1" = print ]; then [ -f "$STATE/$name" ]; exit; fi
if [ "$1" = bootout ]; then
    printf '%s\n' "$name" >> "$STATE/bootouts"
    [ "$FAILURE" != bootout ] || exit 1
    if [ "$FAILURE" != remains ]; then /bin/rm "$STATE/$name"; fi
    exit 0
fi
exit 2
''')
            pgrep = root / 'pgrep'
            pgrep.write_text('#!/bin/sh\n[ "$FAILURE" = pgrep ] && exit 2\n[ "$ALIVE" = "$2" ]\n')
            sleep = root / 'sleep'
            sleep.write_text('#!/bin/sh\nexit 0\n')
            for path in (launchctl, pgrep, sleep):
                path.chmod(0o700)
            for name in services:
                (root / name).touch()
            script = (ROOT / 'Resources/pkg-preinstall').read_text()
            script = script.replace('@REKEY_CORE_LABEL@', 'org.example.product.core')
            script = script.replace('/bin/launchctl', str(launchctl))
            script = script.replace('/usr/bin/pgrep', str(pgrep))
            script = script.replace('/bin/sleep', str(sleep))
            env = dict(os.environ, STATE=str(root), FAILURE=failure, ALIVE=alive)
            result = subprocess.run(['/bin/sh'], input=script, text=True, env=env, capture_output=True)
            log = root / 'bootouts'
            result.bootouts = log.read_text().splitlines() if log.exists() else []
            return result

    def test_absent_and_cleanly_stopped_services(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.run_script(services=['org.example.product.core', 'jp.example.rekey.core', 'jp.example.rekey.vhid']).returncode, 0)

    def test_refuses_failed_inspection_stop_or_live_process(self):
        for kwargs in ({'failure': 'inspect'},
                       {'services': ['jp.example.rekey.core'], 'failure': 'bootout'},
                       {'services': ['org.example.product.core'], 'failure': 'bootout'},
                       {'services': ['jp.example.rekey.core'], 'failure': 'remains'},
                       {'alive': 'ReKey'}, {'alive': 'ReKeyAgent'},
                       {'alive': 'rekey-core'}, {'alive': 'rekey-vhid'}, {'failure': 'pgrep'}):
            with self.subTest(kwargs=kwargs):
                self.assertNotEqual(self.run_script(**kwargs).returncode, 0)

    def test_running_ui_or_agent_does_not_stop_the_core(self):
        for name in ('ReKey', 'ReKeyAgent'):
            with self.subTest(name=name):
                result = self.run_script(services=['org.example.product.core'], alive=name)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.bootouts, [])


if __name__ == '__main__':
    unittest.main()
