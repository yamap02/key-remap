import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('assets', ROOT / 'scripts/check-appcast-assets.py')
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


class AppcastAssets(unittest.TestCase):
    def test_history_and_archive_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            archive = directory / 'app.zip'
            archive.write_bytes(b'new archive')
            previous = directory / 'old.xml'
            feed = directory / 'new.xml'
            ns = assets.NS
            old = ('https://github.com/o/r/releases/download/v1/app.zip', '3', 'old-signature')
            new = ('https://github.com/o/r/releases/download/v2/app.zip', '11', 'new-signature')
            def write(path, entries):
                root = ET.Element('rss')
                channel = ET.SubElement(root, 'channel')
                for version, (url, length, signature) in entries:
                    item = ET.SubElement(channel, 'item')
                    ET.SubElement(item, ns + 'version').text = version
                    ET.SubElement(item, 'enclosure', {'url': url, 'length': length, ns + 'edSignature': signature})
                ET.ElementTree(root).write(path)
            write(previous, [('1', old)])
            write(feed, [('2', new), ('1', old)])
            self.assertEqual(assets.check(feed, archive, '2', new[0], previous), 'new-signature')
            for entries in ([('2', new)], [('2', new), ('1', (old[0], old[1], 'changed'))],
                            [('2', new), ('1', old), ('1', old)],
                            [('2', ('http://bad', new[1], new[2])), ('1', old)],
                            [('2', (new[0], '12', new[2])), ('1', old)]):
                write(feed, entries)
                with self.subTest(entries=entries), self.assertRaises(ValueError):
                    assets.check(feed, archive, '2', new[0], previous)
            write(feed, [('2', new)])
            assets.check(feed, archive, '2', new[0])
            with self.assertRaises(ValueError):
                assets.check(feed, archive, '2', 'https://github.com/o/r/releases/download/v3/app.zip')


if __name__ == '__main__':
    unittest.main()
