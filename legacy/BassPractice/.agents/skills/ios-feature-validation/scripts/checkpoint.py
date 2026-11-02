#!/usr/bin/env python3
"""Read-only JSON checkpoint; never fetch, switch branches, build, or install."""
import argparse
import json
import subprocess


def run(args, cwd):
    try:
        result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=30)
        if result.returncode:
            return {"status": "unavailable", "error": result.stderr.strip()[-2000:]}
        return {"status": "ok", "output": result.stdout.rstrip("\n")}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"status": "unavailable", "error": str(error)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--github", action="store_true", help="Read open PRs via gh; no remote mutations")
    parser.add_argument("--xcresult", help="Read an existing result bundle's test summary")
    args = parser.parse_args()
    output = {"schema_version": 1}
    for key, command in {
        "commit": ["git", "rev-parse", "HEAD"],
        "branch": ["git", "branch", "--show-current"],
        "working_tree": ["git", "status", "--porcelain=v1", "--untracked-files=all"],
    }.items():
        output[key] = run(command, args.repo)
    refs = run(["git", "for-each-ref", "--format=%(refname)\t%(objectname)\t%(upstream)",
                "refs/heads", "refs/remotes"], args.repo)
    if refs["status"] == "ok":
        refs = {"status": "ok", "freshness": "local snapshot; no fetch performed", "items": [
            dict(zip(("ref", "commit", "upstream"), line.split("\t")))
            for line in refs["output"].splitlines()]}
    output["refs"] = refs
    if args.github:
        prs = run(["gh", "pr", "list", "--state", "open", "--limit", "100", "--json",
                   "number,url,title,isDraft,baseRefName,headRefName,headRefOid"], args.repo)
        if prs["status"] == "ok":
            prs = {"status": "ok", "limit": 100, "items": json.loads(prs["output"])}
        output["pull_requests"] = prs
    if args.xcresult:
        summary = run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", args.xcresult], args.repo)
        if summary["status"] == "ok":
            summary = {"status": "ok", "bundle": args.xcresult, "summary": json.loads(summary["output"])}
        output["tests"] = summary
    print(json.dumps(output, indent=2))
    return 0 if output["commit"]["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
