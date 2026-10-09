#!/usr/bin/env python3
"""Computes the ship-ready verdict from evidence, so the agent cannot overclaim.

Usage:  python3 verdict.py <gate.json> [report.json] [--write]
        gate.json    output of `quality_gate.sh --json` run after the last edit
        report.json  the findings report (.quality/report.json), optional
        --write      store the computed verdict and conditions back into report.json
Exit:   0 READY · 1 READY_WITH_CONDITIONS · 2 NOT_READY · 3 usage or input error
Needs:  python3 (standard library only)

Rules (from references/report-format.md):
  NOT_READY             any open P0 finding, any failed gate, or no gate checks ran
  READY_WITH_CONDITIONS any open P1 finding, any skipped gate, or findings not supplied
  READY                 otherwise
"""
import json
import sys

OPEN_STATUSES = {"open", "needs_verification", "capped_not_converged"}


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"cannot read {path}: {e}", file=sys.stderr)
        sys.exit(3)


def decide(gate, report):
    blockers, conditions = [], []
    checks = gate.get("checks", [])
    ran = [c for c in checks if c.get("status") in ("PASS", "FAIL")]
    if not ran:
        blockers.append("no quality-gate checks ran")
    for c in checks:
        name = c.get("check", "?")
        if c.get("status") == "FAIL":
            blockers.append(f"gate failed: {name}")
        elif c.get("status") == "SKIPPED":
            conditions.append(f"gate skipped: {name} ({c.get('detail', '')})")

    if report is None:
        conditions.append("no findings report supplied; open P0/P1 status unknown")
    else:
        for f in report.get("findings", []):
            if str(f.get("status", "")).lower() not in OPEN_STATUSES:
                continue
            label = f"{f.get('id', '?')} {f.get('severity', '?')}: {f.get('title', '')}".strip()
            if f.get("severity") == "P0":
                blockers.append(f"open {label}")
            elif f.get("severity") == "P1":
                conditions.append(f"open {label}")

    if blockers:
        return "NOT_READY", blockers + conditions
    if conditions:
        return "READY_WITH_CONDITIONS", conditions
    return "READY", []


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__.strip().split("\n\n")[1])
        return 3
    gate = load(args[0])
    report_path = args[1] if len(args) > 1 else None
    report = load(report_path) if report_path else None

    verdict, reasons = decide(gate, report)
    print(f"VERDICT: {verdict}")
    for r in reasons:
        print(f"  - {r}")

    if "--write" in argv and report_path:
        report["verdict"] = verdict
        report["verdict_reasons"] = reasons
        report["verdict_source"] = "scripts/verdict.py"
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2)
            f.write("\n")
        print(f"written to {report_path}")
    return {"READY": 0, "READY_WITH_CONDITIONS": 1, "NOT_READY": 2}[verdict]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
