import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('archive', ROOT / 'scripts/verify-update-archive.py')
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class UpdateArchive(unittest.TestCase):
    def test_ditto_archive_matches_contents_modes_and_links(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = root / 'ReKey.app'
            binary = app / 'Contents/MacOS/ReKey'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'first release')
            binary.chmod(0o755)
            link = app / 'Contents/link'
            link.symlink_to('MacOS/ReKey')
            zipped = root / 'release.zip'
            subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(zipped)], check=True)
            archive.verify(app, zipped)
            binary.write_bytes(b'other release')
            with self.assertRaises(ValueError):
                archive.verify(app, zipped)
            binary.write_bytes(b'first release')
            binary.chmod(0o644)
            with self.assertRaises(ValueError):
                archive.verify(app, zipped)
            binary.chmod(0o755)
            link.unlink()
            link.symlink_to('elsewhere')
            with self.assertRaises(ValueError):
                archive.verify(app, zipped)
            link.unlink()
            link.symlink_to('MacOS/ReKey')
            (app / 'extra').write_text('extra')
            with self.assertRaises(ValueError):
                archive.verify(app, zipped)

    def test_unsafe_metadata_paths_are_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = root / 'ReKey.app'
            app.mkdir()
            (app / 'file').write_text('content')
            zipped = root / 'release.zip'
            subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(app), str(zipped)], check=True)
            with zipfile.ZipFile(zipped, 'a') as output:
                output.writestr('__MACOSX/../outside', 'bad')
            with self.assertRaises(ValueError):
                archive.verify(app, zipped)


if __name__ == '__main__':
    unittest.main()
