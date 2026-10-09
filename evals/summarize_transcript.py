"""Turns a Claude Code stream-json transcript into a readable Markdown trace for grading.

Usage: python3 summarize_transcript.py transcript.txt > transcript.md
Shows every tool call (with Bash commands and their exit/output tail), assistant text,
and the final result with cost and turn count.
"""
import json
import sys

MAX_OUTPUT = 1500


def text_of(content):
    if isinstance(content, str):
        return content
    return "\n".join(c.get("text", "") for c in content if isinstance(c, dict))


def main(path):
    for raw in open(path, encoding="utf-8", errors="replace"):
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue
        kind = event.get("type")
        if kind == "assistant":
            for block in event["message"].get("content", []):
                if block.get("type") == "text" and block["text"].strip():
                    print(f"\n**assistant:** {block['text'].strip()}\n")
                elif block.get("type") == "tool_use":
                    args = block.get("input", {})
                    shown = args.get("command") or args.get("file_path") or args.get("skill") or json.dumps(args)[:300]
                    print(f"- `{block['name']}` → `{shown}`")
        elif kind == "user":
            for block in event["message"].get("content", []):
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    out = text_of(block.get("content", ""))
                    if out.strip():
                        tail = out[-MAX_OUTPUT:]
                        flag = " (error)" if block.get("is_error") else ""
                        print(f"  <details><summary>output{flag}</summary>\n\n```\n{tail}\n```\n</details>")
        elif kind == "result":
            print(f"\n---\n**result** turns={event.get('num_turns')} cost=${event.get('total_cost_usd', 0):.2f} "
                  f"duration={event.get('duration_ms', 0) / 1000:.0f}s\n\n{event.get('result', '')}")


if __name__ == "__main__":
    main(sys.argv[1])
