import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("install_owned", ROOT / "bin/lib/install_owned.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallOwnedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.target = self.root / "installed"

    def tearDown(self):
        self.tmp.cleanup()

    def skill(self, pack, name, text="original"):
        path = self.root / pack / "skills" / name
        path.mkdir(parents=True)
        (path / "SKILL.md").write_text(f"---\nname: {name}\ndescription: Test skill\n---\n{text}")
        (path / "reference.md").write_text("supporting resource")
        return path

    def test_identity_resources_and_repeat_install_remove_stale_files(self):
        path = self.skill("test-pack", "build")
        installer.install(self.target, [("owner/test-pack", path)])
        self.assertEqual("supporting resource", (self.target / "build/reference.md").read_text())
        (path / "reference.md").unlink()
        installer.install(self.target, [("owner/test-pack", path)])
        self.assertFalse((self.target / "build/reference.md").exists())
        manifest = json.loads((self.target / installer.MANIFEST).read_text())
        self.assertEqual({"path": "build", "source": "owner/test-pack"}, manifest["skills"]["test-pack:build"])

    def test_collisions_refuse_before_any_skill_changes(self):
        first, second = self.skill("one", "build"), self.skill("two", "build", "replacement")
        with self.assertRaisesRegex(ValueError, "collision"):
            installer.install(self.target, [("owner/one", first), ("owner/two", second)])
        self.assertFalse(self.target.exists())
        installer.install(self.target, [("owner/one", first)])
        with self.assertRaisesRegex(ValueError, "collision"):
            installer.install(self.target, [("owner/two", second)])
        self.assertIn("original", (self.target / "build/SKILL.md").read_text())

    def test_unmanaged_and_symlink_destinations_are_never_overwritten(self):
        source = self.skill("pack", "build")
        self.target.mkdir()
        (self.target / "build").symlink_to(source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "collision"):
            installer.install(self.target, [("owner/pack", source)])
        self.assertTrue((self.target / "build").is_symlink())

    def test_real_shell_installer_emits_identity_manifest_in_temporary_home(self):
        skill = self.skill("test-pack", "build")
        repo = skill.parents[1]
        for args in (["init", "-q", str(repo)], ["-C", str(repo), "add", "skills"],
                     ["-C", str(repo), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture"]):
            subprocess.run(["git", *args], check=True, capture_output=True)
        home = self.root / "home"
        (home / ".dotskills").mkdir(parents=True)
        (home / ".dotskills/config.toml").write_text(f'[repos]\nowned = ["owner/test-pack|{repo}|skills"]\n')
        env = {**os.environ, "HOME": str(home), "PATH": f"{Path(sys.executable).parent}:{os.environ['PATH']}"}
        result = subprocess.run(["bash", str(ROOT / "install.sh")], env=env, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        manifest = json.loads((home / ".agents/skills" / installer.MANIFEST).read_text())
        self.assertIn("test-pack:build", manifest["skills"])


if __name__ == "__main__":
    unittest.main()
