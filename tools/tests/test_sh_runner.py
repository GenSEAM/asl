import unittest
from pathlib import Path
from tools.sh_runner import ShProcessRunner


class TestShProcessRunner(unittest.TestCase):
    def test_simple_exec(self):
        res = ShProcessRunner.run_cmd("echo", ["hello", "agentscript"])
        self.assertEqual(res.exit_code, 0)
        self.assertIn("hello agentscript", res.stdout)
        self.assertFalse(res.timed_out)

    def test_pipeline_exec(self):
        # echo "line1\nline2\nline3" | grep "line2"
        res = ShProcessRunner.run_pipeline([
            ["echo", "line1\nline2\nline3"],
            ["grep", "line2"]
        ])
        self.assertEqual(res.exit_code, 0)
        self.assertIn("line2", res.stdout)
        self.assertNotIn("line1", res.stdout)

    def test_not_found(self):
        res = ShProcessRunner.run_cmd("non_existent_binary_xyz_123", [])
        self.assertEqual(res.exit_code, 127)
        self.assertIn("Command not found", res.stderr)

    def test_timeout(self):
        res = ShProcessRunner.run_cmd("sleep", ["2"], timeout_sec=0.2)
        self.assertEqual(res.exit_code, -1)
        self.assertTrue(res.timed_out)


if __name__ == "__main__":
    unittest.main()
