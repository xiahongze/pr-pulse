#!/usr/bin/env python3
"""Collect GitHub pull requests for the current `gh` user and print one JSON snapshot."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SCHEMA = 1
DEFAULT_TIMEOUT = 40
DEFAULT_LIMIT = 50
ROLES = {"assigned": "assignee", "authored": "author", "review": "review-requested"}
FALLBACK_DIRS = (
    "/usr/bin",
    "/usr/local/bin",
    "/opt/homebrew/bin",
    "/home/linuxbrew/.linuxbrew/bin",
    "/snap/bin",
    "~/.local/bin",
    "~/bin",
    "~/.nix-profile/bin",
)

PR_FIELDS = """
fragment pr on PullRequest {
  id number title url isDraft state reviewDecision createdAt updatedAt
  additions deletions
  author { login }
  repository { nameWithOwner }
  assignees(first: 10) { nodes { login } }
  labels(first: 10) { nodes { name color } }
  comments { totalCount }
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
}
"""


def resolve_gh(configured: str | None, path_env: str | None = None, fallback_dirs=FALLBACK_DIRS) -> str | None:
    """Return the gh executable: configured path, then PATH, then common install locations."""
    def runnable(candidate: Path) -> bool:
        return candidate.is_file() and os.access(candidate, os.X_OK)

    if configured:
        candidate = Path(configured).expanduser()
        if candidate.is_dir():
            candidate = candidate / "gh"
        if runnable(candidate):
            return str(candidate)
        found = shutil.which(configured, path=path_env)
        return found
    found = shutil.which("gh", path=path_env if path_env is not None else os.environ.get("PATH", ""))
    if found:
        return found
    for directory in fallback_dirs:
        candidate = Path(directory).expanduser() / "gh"
        if runnable(candidate):
            return str(candidate)
    return None


def search_query(role: str, closed: bool, since: dt.date | None) -> str:
    query = f"is:pr {ROLES[role]}:@me archived:false sort:updated-desc"
    if closed:
        return f"{query} is:closed updated:>={since.isoformat()}"
    return f"{query} is:open"


def build_request(roles: list[str], lookback_days: int, limit: int, today: dt.date) -> tuple[str, dict[str, str]]:
    since = today - dt.timedelta(days=lookback_days) if lookback_days > 0 else None
    blocks, variables, params = [], {}, []
    for role in roles:
        # Review requests only exist on open PRs, so skip a closed search for that role.
        for closed in (False, True) if since and role != "review" else (False,):
            alias = f"{role}_{'closed' if closed else 'open'}"
            params.append(f"${alias}: String!")
            variables[alias] = search_query(role, closed, since)
            blocks.append(
                f"{alias}: search(query: ${alias}, type: ISSUE, first: {limit}) "
                "{ issueCount nodes { ...pr } }"
            )
    query = f"query({', '.join(params)}) {{ viewer {{ login }} {' '.join(blocks)} }}\n{PR_FIELDS}"
    return query, variables


def classify_failure(stderr: str) -> str:
    text = stderr.lower()
    if any(marker in text for marker in ("gh auth login", "not logged", "authentication", "http 401", "bad credentials")):
        return "gh_unauthenticated"
    if any(marker in text for marker in ("could not resolve host", "no such host", "error connecting", "dial tcp", "network", "connection", "timeout", "tls")):
        return "network"
    if "rate limit" in text:
        return "rate_limited"
    return "gh_failed"


class GhError(Exception):
    def __init__(self, code: str, detail):
        super().__init__(code)
        self.code = code
        self.detail = detail[0] if isinstance(detail, list) else str(detail)


def run_gh(gh: str, query: str, variables: dict[str, str], timeout: int) -> dict:
    command = [gh, "api", "graphql", "-f", f"query={query}"]
    for name, value in variables.items():
        command += ["-f", f"{name}={value}"]
    env = dict(os.environ, GH_PROMPT_DISABLED="1", GH_NO_UPDATE_NOTIFIER="1", NO_COLOR="1", GH_SPINNER_DISABLED="1")
    proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout, env=env)
    payload = None
    try:
        payload = json.loads(proc.stdout) if proc.stdout.strip() else None
    except json.JSONDecodeError:
        payload = None
    # gh exits non-zero on partial GraphQL errors; keep any data it still returned.
    if isinstance(payload, dict) and isinstance(payload.get("data"), dict):
        return payload
    raise GhError(classify_failure(proc.stderr), proc.stderr.strip().splitlines()[-1:] or ["gh exited with status %d" % proc.returncode])


def ci_state(node: dict) -> str:
    commits = ((node.get("commits") or {}).get("nodes") or [])
    rollup = ((commits[0].get("commit") or {}).get("statusCheckRollup") if commits else None) or {}
    return {
        "SUCCESS": "success",
        "FAILURE": "failure",
        "ERROR": "failure",
        "PENDING": "pending",
        "EXPECTED": "pending",
    }.get(rollup.get("state") or "", "none")


def pr_state(node: dict) -> str:
    state = node.get("state")
    if state == "MERGED":
        return "merged"
    if state == "CLOSED":
        return "closed"
    return "draft" if node.get("isDraft") else "open"


def normalise(node: dict) -> dict:
    return {
        "id": node.get("id") or node.get("url"),
        "url": node.get("url", ""),
        "number": node.get("number", 0),
        "title": node.get("title", ""),
        "repo": (node.get("repository") or {}).get("nameWithOwner", ""),
        "author": (node.get("author") or {}).get("login") or "ghost",
        "state": pr_state(node),
        "ci": ci_state(node),
        "review": (node.get("reviewDecision") or "none").lower(),
        "created_at": node.get("createdAt", ""),
        "updated_at": node.get("updatedAt", ""),
        "additions": node.get("additions") or 0,
        "deletions": node.get("deletions") or 0,
        "comments": (node.get("comments") or {}).get("totalCount") or 0,
        "assignees": [a["login"] for a in (node.get("assignees") or {}).get("nodes") or [] if a],
        "labels": [{"name": l["name"], "color": "#" + l.get("color", "888888")} for l in (node.get("labels") or {}).get("nodes") or [] if l],
        "roles": [],
    }


def merge_results(data: dict, roles: list[str], limit: int) -> tuple[list[dict], bool]:
    prs: dict[str, dict] = {}
    truncated = False
    for role in roles:
        for suffix in ("open", "closed"):
            result = data.get(f"{role}_{suffix}")
            if not result:
                continue
            truncated |= (result.get("issueCount") or 0) > limit
            for node in result.get("nodes") or []:
                if not node or not node.get("url"):
                    continue
                pr = prs.setdefault(node["url"], normalise(node))
                if role not in pr["roles"]:
                    pr["roles"].append(role)
    ordered = sorted(prs.values(), key=lambda pr: pr["updated_at"], reverse=True)
    return ordered, truncated


def summarise(prs: list[dict]) -> dict:
    counts = {key: 0 for key in ("open", "draft", "merged", "closed", "ci_failing", "ci_pending", "review_requested", "changes_requested", "approved")}
    for pr in prs:
        counts[pr["state"]] += 1
        if pr["state"] in ("open", "draft"):
            counts["ci_failing"] += pr["ci"] == "failure"
            counts["ci_pending"] += pr["ci"] == "pending"
            counts["review_requested"] += "review" in pr["roles"]
            counts["changes_requested"] += pr["review"] == "changes_requested"
            counts["approved"] += pr["review"] == "approved"
    return counts


def snapshot(args: argparse.Namespace, now: dt.datetime | None = None) -> dict:
    now = now or dt.datetime.now().astimezone()
    result = {
        "schema": SCHEMA,
        "generated_at": now.isoformat(timespec="seconds"),
        "generated_label": now.strftime("%H:%M"),
        "viewer": "",
        "gh_path": "",
        "error": None,
        "truncated": False,
        "prs": [],
        "counts": summarise([]),
    }
    gh = resolve_gh(args.gh)
    if not gh:
        result["error"] = {"code": "gh_not_found", "detail": args.gh or "gh is not on PATH"}
        return result
    result["gh_path"] = gh
    roles = ["assigned", "authored"] + (["review"] if args.review_requests else [])
    query, variables = build_request(roles, args.lookback_days, args.limit, now.date())
    try:
        payload = run_gh(gh, query, variables, args.timeout)
    except subprocess.TimeoutExpired:
        result["error"] = {"code": "timeout", "detail": f"gh did not respond within {args.timeout}s"}
        return result
    except GhError as exc:
        result["error"] = {"code": exc.code, "detail": exc.detail}
        return result
    except OSError as exc:
        result["error"] = {"code": "gh_failed", "detail": str(exc)}
        return result
    data = payload["data"]
    result["viewer"] = (data.get("viewer") or {}).get("login", "")
    result["prs"], result["truncated"] = merge_results(data, roles, args.limit)
    result["counts"] = summarise(result["prs"])
    if payload.get("errors"):
        result["warning"] = (payload["errors"][0] or {}).get("message", "partial results")
    return result


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gh", default="", help="gh executable or its directory (default: PATH, then common locations)")
    parser.add_argument("--lookback-days", type=int, default=7, help="include PRs merged or closed within this many days (0 disables)")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="maximum PRs per search (1-100)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument("--review-requests", action=argparse.BooleanOptionalAction, default=True, help="include PRs awaiting your review")
    parser.add_argument("--refresh-id", default="", help="ignored; makes each widget command unique")
    args = parser.parse_args(argv)
    args.limit = max(1, min(100, args.limit))
    args.lookback_days = max(0, args.lookback_days)
    return args


def main(argv: list[str] | None = None) -> int:
    json.dump(snapshot(parse_args(argv)), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
