import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

SOURCE = Path(os.environ.get("PROJECT_SRC", Path(__file__).resolve().parents[1]))
BASH = shutil.which("bash")


class Operations(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        self.saved = self.state / "server/Pal/Saved"
        self.saved.mkdir(parents=True)
        (self.saved / "world").write_text("fictional-save")
        self.config = self.root / "config"
        self.config.mkdir()
        self.backups = self.root / "backups"
        (self.config / "palworld.json").write_text(json.dumps({
            "stateDirectory": str(self.state), "unit": "anq-game-palworld.service",
            "fetchUnit": "anq-game-fetch-palworld.service", "backupDirectory": str(self.backups),
            "backupPaths": ["server/Pal/Saved"],
        }))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.control = self.root / "control.json"
        self.control.write_text(json.dumps({"running": True, "fail_fetch": False, "stop_result": "success", "calls": []}))
        self.executable("id", "#!/bin/sh\necho 0\n")
        self.executable("systemctl", "#!" + shutil.which("python3") + "\n" + '''import json,os,sys
from pathlib import Path
p=Path(os.environ['CONTROL']);s=json.loads(p.read_text());a=sys.argv[1:];s['calls'].append(a)
code=0
if a[0]=='is-active':code=0 if s['running'] else 3
elif a[0]=='show':print(s['stop_result'])
elif a[0]=='stop':s['running']=False
elif a[0]=='start':
 if 'fetch' in a[-1]:code=1 if s['fail_fetch'] else 0
 else:s['running']=True
p.write_text(json.dumps(s));sys.exit(code)
''')
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"], CONTROL=str(self.control), ANQ_CONFIG_ROOT=str(self.config), ANQ_RESTORE_HELPER=str(SOURCE / "scripts/restore-check.py"))

    def tearDown(self):
        self.temp.cleanup()

    def executable(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def run_ops(self, *args):
        return subprocess.run([BASH, str(SOURCE / "scripts/ops.sh"), *args], env=self.env, capture_output=True, text=True)

    def control_state(self, **changes):
        state = json.loads(self.control.read_text())
        state.update(changes)
        self.control.write_text(json.dumps(state))
        return state

    def archive(self):
        return next(self.backups.glob("*.tar.gz"))

    def test_backup_quiesces_and_restores_previous_running_state(self):
        result = self.run_ops("backup", "palworld")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.control_state()
        self.assertTrue(state["running"])
        self.assertTrue(any(call[0] == "stop" for call in state["calls"]))
        self.assertEqual(self.archive().stat().st_mode & 0o777, 0o600)
        with tarfile.open(self.archive()) as archive:
            self.assertEqual(archive.extractfile("server/Pal/Saved/world").read(), b"fictional-save")

    def test_update_takes_backup_and_preserves_a_stopped_service(self):
        self.control_state(running=False)
        result = self.run_ops("update", "palworld")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.control_state()["running"])
        self.assertTrue(self.archive().exists())

    def test_failed_update_stays_stopped_and_preserves_snapshot(self):
        self.control_state(fail_fetch=True)
        result = self.run_ops("update", "palworld")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.control_state()["running"])
        self.assertTrue(self.archive().exists())
        self.assertIn("remains stopped", result.stderr)

    def test_backup_failure_does_not_fetch_and_restarts_unchanged_service(self):
        self.executable("tar", "#!/bin/sh\nexit 1\n")
        result = self.run_ops("update", "palworld")
        self.assertNotEqual(result.returncode, 0)
        state = self.control_state()
        self.assertTrue(state["running"])
        self.assertFalse(any("fetch" in call[-1] for call in state["calls"]))
        self.assertEqual(list(self.backups.glob("*.tar.gz")), [])

    def test_unclean_stop_aborts_without_fetch_or_restart(self):
        self.control_state(stop_result="timeout")
        self.assertNotEqual(self.run_ops("update", "palworld").returncode, 0)
        state = self.control_state()
        self.assertFalse(state["running"])
        self.assertFalse(any(call[0] == "start" for call in state["calls"]))

    def test_restore_check_extracts_into_new_directory_only(self):
        self.assertEqual(self.run_ops("backup", "palworld").returncode, 0)
        target = self.root / "restored"
        result = self.run_ops("restore-check", "palworld", str(self.archive()), str(target))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / "server/Pal/Saved/world").read_text(), "fictional-save")
        self.assertNotEqual(self.run_ops("restore-check", "palworld", str(self.archive()), str(target)).returncode, 0)
        self.assertNotEqual(self.run_ops("restore-check", "palworld", str(self.archive()), str(self.state / "new")).returncode, 0)

    def test_corrupted_archives_and_link_traversal_fail_before_extraction(self):
        self.assertEqual(self.run_ops("backup", "palworld").returncode, 0)
        archive = self.archive()
        archive.write_bytes(b"corrupted")
        self.assertNotEqual(self.run_ops("restore-check", "palworld", str(archive), str(self.root / "bad")).returncode, 0)
        self.assertFalse((self.root / "bad").exists())
        for name, link in [("../escape", False), ("link", True)]:
            with tarfile.open(archive, "w:gz") as output:
                info = tarfile.TarInfo(name)
                if link:
                    info.type = tarfile.SYMTYPE
                    info.linkname = "/etc/passwd"
                    output.addfile(info)
                else:
                    info.size = 1
                    output.addfile(info, io.BytesIO(b"x"))
            Path(str(archive) + ".sha256").write_text(hashlib.sha256(archive.read_bytes()).hexdigest())
            self.assertNotEqual(self.run_ops("restore-check", "palworld", str(archive), str(self.root / "bad")).returncode, 0)
            self.assertFalse((self.root / "bad").exists())

    def test_invalid_commands_and_names_cannot_be_shell_code(self):
        self.assertNotEqual(self.run_ops("update", "palworld;touch pwned").returncode, 0)
        self.assertNotEqual(self.run_ops("update", "palworld", "extra").returncode, 0)
        self.assertEqual(self.control_state()["calls"], [])

    def test_snapshot_with_links_cannot_authorize_an_update(self):
        (self.saved / "link").symlink_to("/etc/passwd")
        result = self.run_ops("update", "palworld")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not safely restorable", result.stderr)
        state = self.control_state()
        self.assertTrue(state["running"])
        self.assertFalse(any("fetch" in call[-1] for call in state["calls"]))
        self.assertEqual(list(self.backups.glob("*.tar.gz")), [])

    def test_same_game_operations_use_an_exclusive_lock(self):
        self.backups.mkdir()
        (self.backups / ".locks").mkdir()
        with (self.backups / ".locks/palworld.lock").open("w") as lock:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertNotEqual(self.run_ops("backup", "palworld").returncode, 0)
        self.assertEqual(self.control_state()["calls"], [])


if __name__ == "__main__":
    unittest.main()
