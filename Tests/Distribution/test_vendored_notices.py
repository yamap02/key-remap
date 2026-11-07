import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('notices', ROOT / 'scripts/check-vendored-notices.py')
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)


class VendoredNotices(unittest.TestCase):
    def test_unknown_and_missing_notice_are_rejected(self):
        with self.assertRaises(ValueError):
            notices.inspect([str(notices.INCLUDE / 'new-dependency' / 'header.hpp')])
        with patch.dict(notices.NOTICES, {'asio': 'missing-license.txt'}):
            with self.assertRaises(ValueError):
                notices.inspect([str(notices.INCLUDE / 'asio' / 'version.hpp')])

    def test_current_compilation_dependencies_have_notices(self):
        notices.main()


if __name__ == '__main__':
    unittest.main()
