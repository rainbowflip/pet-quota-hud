import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1] / 'scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class HooksTest(unittest.TestCase):
    def test_merge_and_uninstall(self):
        old = {'description': 'existing', 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'echo custom'}]}], 'OtherEvent': []}}
        exe = Path('/Users/example/Applications/Pet Quota HUD.app/Contents/MacOS/PetQuotaHUD')
        merged = installer.merge_hooks(old, exe)
        self.assertEqual(merged, installer.merge_hooks(merged, exe))
        self.assertEqual(installer.merge_hooks(merged, exe, remove=True), old)
        self.assertEqual(len(old['hooks']['Stop']), 1)


if __name__ == '__main__':
    unittest.main()
