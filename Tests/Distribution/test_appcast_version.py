import importlib.util
import pathlib
import tempfile
import unittest

path = pathlib.Path(__file__).resolve().parents[2] / 'scripts/check-appcast-version.py'
spec = importlib.util.spec_from_file_location('appcast_version', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AppcastVersions(unittest.TestCase):
    def check(self, contents, candidate):
        with tempfile.TemporaryDirectory() as directory:
            feed = pathlib.Path(directory) / 'appcast.xml'
            feed.write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' + contents + '</channel></rss>')
            return module.check(feed, candidate)

    def test_checks_every_item_and_legacy_enclosure(self):
        items = '<item><sparkle:version>3</sparkle:version></item><item><enclosure sparkle:version="17"/></item>'
        self.assertEqual(self.check(items, '18'), 17)
        for candidate in ('17', '16', '0', '1.2', '01'):
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                self.check(items, candidate)

    def test_refuses_empty_or_invalid_history(self):
        for items in ('', '<item/>', '<item><sparkle:version>2.1</sparkle:version></item>'):
            with self.subTest(items=items), self.assertRaises(ValueError):
                self.check(items, '20')


if __name__ == '__main__':
    unittest.main()
