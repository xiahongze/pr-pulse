import datetime as dt
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import pr_pulse  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"
FAKE_GH = str(FIXTURES / "fake_gh")
NOW = dt.datetime(2026, 10, 2, 12, 0, tzinfo=dt.timezone.utc)


def collect(*argv, mode="ok", fixture="search.json", **env):
    environ = {"FAKE_GH_MODE": mode, "FAKE_GH_FIXTURE": str(FIXTURES / fixture), **env}
    with mock.patch.dict(os.environ, environ):
        return pr_pulse.snapshot(pr_pulse.parse_args(["--gh", FAKE_GH, *argv]), now=NOW)


class ResolveGhTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def make_gh(self, directory):
        directory = self.root / directory
        directory.mkdir(parents=True, exist_ok=True)
        gh = directory / "gh"
        gh.write_text("#!/bin/sh\n")
        gh.chmod(0o755)
        return str(gh)

    def test_configured_file_wins_over_path(self):
        configured = self.make_gh("custom")
        self.make_gh("onpath")
        self.assertEqual(pr_pulse.resolve_gh(configured, path_env=str(self.root / "onpath")), configured)

    def test_configured_directory_is_accepted(self):
        configured = self.make_gh("custom")
        self.assertEqual(pr_pulse.resolve_gh(str(self.root / "custom"), path_env=""), configured)

    def test_invalid_configured_path_does_not_fall_back(self):
        self.make_gh("onpath")
        self.assertIsNone(pr_pulse.resolve_gh(str(self.root / "missing/gh"), path_env=str(self.root / "onpath")))

    def test_path_then_fallback_dirs(self):
        on_path = self.make_gh("onpath")
        fallback = self.make_gh("fallback")
        self.assertEqual(pr_pulse.resolve_gh("", path_env=str(self.root / "onpath"), fallback_dirs=[str(self.root / "fallback")]), on_path)
        self.assertEqual(pr_pulse.resolve_gh("", path_env="", fallback_dirs=[str(self.root / "fallback")]), fallback)
        self.assertIsNone(pr_pulse.resolve_gh("", path_env="", fallback_dirs=[str(self.root / "none")]))

    def test_non_executable_is_ignored(self):
        gh = Path(self.make_gh("noexec"))
        gh.chmod(0o644)
        self.assertIsNone(pr_pulse.resolve_gh("", path_env="", fallback_dirs=[str(gh.parent)]))


class RequestTests(unittest.TestCase):
    def test_queries_cover_roles_and_lookback(self):
        query, variables = pr_pulse.build_request(["assigned", "authored", "review"], 7, 50, NOW.date())
        self.assertEqual(sorted(variables), ["assigned_closed", "assigned_open", "authored_closed", "authored_open", "review_open"])
        self.assertIn("assignee:@me", variables["assigned_open"])
        self.assertIn("is:open", variables["authored_open"])
        self.assertIn("updated:>=2026-09-25", variables["authored_closed"])
        self.assertIn("review-requested:@me", variables["review_open"])
        self.assertIn("first: 50", query)
        self.assertIn("fragment pr on PullRequest", query)

    def test_zero_lookback_skips_closed_searches(self):
        _, variables = pr_pulse.build_request(["assigned", "authored"], 0, 10, NOW.date())
        self.assertEqual(sorted(variables), ["assigned_open", "authored_open"])

    def test_variables_are_passed_as_strings(self):
        with tempfile.NamedTemporaryFile(suffix=".json") as args_file:
            collect("--no-review-requests", FAKE_GH_ARGS=args_file.name)
            argv = json.loads(Path(args_file.name).read_text())
        self.assertEqual(argv[:2], ["api", "graphql"])
        self.assertNotIn("-F", argv)
        self.assertNotIn("review_open=", " ".join(argv))


class SnapshotTests(unittest.TestCase):
    def test_merges_roles_and_derives_states(self):
        result = collect()
        self.assertIsNone(result["error"])
        self.assertEqual(result["viewer"], "octocat")
        prs = {pr["number"]: pr for pr in result["prs"]}
        self.assertEqual(len(prs), 5)
        self.assertEqual(prs[11]["roles"], ["assigned", "review"])
        self.assertEqual(prs[7]["roles"], ["assigned", "authored"])
        self.assertEqual([prs[n]["state"] for n in (11, 8, 5, 4)], ["open", "draft", "merged", "closed"])
        self.assertEqual([prs[n]["ci"] for n in (11, 7, 8, 5, 4)], ["failure", "none", "pending", "success", "none"])
        self.assertEqual(prs[11]["review"], "changes_requested")
        self.assertEqual(prs[7]["review"], "none")
        self.assertEqual(prs[4]["author"], "ghost")
        self.assertEqual(prs[11]["labels"], [{"name": "bug", "color": "#d73a4a"}])

    def test_sorted_by_update_and_counts(self):
        result = collect()
        self.assertEqual([pr["number"] for pr in result["prs"]], [7, 11, 8, 5, 4])
        self.assertTrue(result["truncated"])
        counts = result["counts"]
        self.assertEqual((counts["open"], counts["draft"], counts["merged"], counts["closed"]), (2, 1, 1, 1))
        self.assertEqual((counts["ci_failing"], counts["ci_pending"], counts["review_requested"], counts["changes_requested"]), (1, 1, 1, 1))

    def test_partial_graphql_errors_keep_data(self):
        result = collect(mode="partial")
        self.assertIsNone(result["error"])
        self.assertEqual(len(result["prs"]), 5)

    def test_gh_not_found(self):
        result = pr_pulse.snapshot(pr_pulse.parse_args(["--gh", "/definitely/missing/gh"]), now=NOW)
        self.assertEqual(result["error"]["code"], "gh_not_found")
        self.assertEqual(result["prs"], [])

    def test_unauthenticated(self):
        self.assertEqual(collect(mode="unauthenticated")["error"]["code"], "gh_unauthenticated")

    def test_network_failure(self):
        self.assertEqual(collect(mode="network")["error"]["code"], "network")

    def test_timeout(self):
        self.assertEqual(collect("--timeout", "1", mode="slow")["error"]["code"], "timeout")

    def test_main_prints_single_json_line(self):
        environ = {"FAKE_GH_MODE": "ok", "FAKE_GH_FIXTURE": str(FIXTURES / "search.json")}
        with mock.patch.dict(os.environ, environ), mock.patch("sys.stdout") as stdout:
            self.assertEqual(pr_pulse.main(["--gh", FAKE_GH]), 0)
        printed = "".join(call.args[0] for call in stdout.write.call_args_list)
        self.assertEqual(json.loads(printed)["schema"], pr_pulse.SCHEMA)


if __name__ == "__main__":
    unittest.main()
