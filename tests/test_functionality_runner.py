import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ACCEPT = Path(__file__).resolve().parents[1] / "scripts/accept"
sys.path.insert(0, str(ACCEPT))
spec = importlib.util.spec_from_file_location("functionality", ACCEPT / "functionality.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class FunctionalityRunnerTests(unittest.TestCase):
    def test_real_output_is_forwarded_before_exit_and_retained(self):
        seen = []
        started = time.monotonic()
        class Output(io.StringIO):
            def write(self, text):
                if text:
                    seen.append((time.monotonic() - started, text))
                return super().write(text)
        output = Output()
        command = [sys.executable, "-u", "-c", "import time; print('verified first'); time.sleep(.8); print('verified last')"]
        with contextlib.redirect_stdout(output):
            result = runner.run_harness(command, env=dict(os.environ), timeout=3)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "verified first\nverified last\n")
        self.assertEqual(output.getvalue(), result.stdout)
        self.assertLess(seen[0][0], .6)
        self.assertGreater(seen[-1][0], .7)

    def test_timeout_stops_the_actual_descendant_and_does_not_wait_for_its_pipe(self):
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "child.pid"
            script = ("import subprocess,sys,time; "
                      "p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
                      f"open({str(pid_file)!r},'w').write(str(p.pid)); time.sleep(60)")
            started = time.monotonic()
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(subprocess.TimeoutExpired):
                runner.run_harness([sys.executable, "-u", "-c", script], env=dict(os.environ), timeout=.7)
            self.assertLess(time.monotonic() - started, 3)
            pid = int(pid_file.read_text())
            state = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="], text=True,
                                   stdout=subprocess.PIPE).stdout.strip()
            self.assertTrue(not state or state.startswith("Z"), state)


if __name__ == "__main__":
    unittest.main()
