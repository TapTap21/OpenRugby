"""Token and cost ledger for the OpenRugby multi-agent programme.

Reads Claude Code session and subagent transcripts (JSONL) for this project,
deduplicates streamed lines per API request, and aggregates usage by session,
agent, model, effort and phase. Costs are API list-price equivalents.

Usage:
    python3 -I tools/ops/token_ledger.py [--out .omc/ledger/REPORT.md] [--json PATH]

Phase tags come from .omc/ledger/tags.json ({"<agentId or name>": "phase"}),
falling back to an agent-name prefix like "p1-rules-lead" -> "p1".
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import pathlib
from dataclasses import dataclass, field

# USD per million tokens: (input, output, cache_read). Source: claude-api skill
# model table, cached 2026-10-06. Cache writes: 1.25x input (5m), 2x input (1h).
PRICES: dict[str, tuple[float, float, float]] = {
    "claude-fable-5-1": (10.00, 50.00, 0.25),
    "claude-opus-5-5": (4.00, 20.00, 0.20),
    "claude-sonnet-5-5": (2.00, 10.00, 0.20),
    "claude-haiku-5-5": (0.10, 0.50, 0.01),  # cache read assumed at 0.1x input
}
HAIKU_LONG = (0.50, 2.50, 0.05)  # Haiku 5.5 prompts over 100K tokens
HAIKU_LONG_THRESHOLD = 100_000

DEFAULT_TRANSCRIPTS = pathlib.Path.home() / ".claude/projects/-home-wernich--t3-projects-openrugby"


@dataclass
class Usage:
    requests: int = 0
    input: int = 0
    cache_write_5m: int = 0
    cache_write_1h: int = 0
    cache_read: int = 0
    output: int = 0
    cost: float = 0.0

    def add(self, other: Usage) -> None:
        for f in (
            "requests",
            "input",
            "cache_write_5m",
            "cache_write_1h",
            "cache_read",
            "output",
            "cost",
        ):
            setattr(self, f, getattr(self, f) + getattr(other, f))

    @property
    def total_tokens(self) -> int:
        return (
            self.input + self.cache_write_5m + self.cache_write_1h + self.cache_read + self.output
        )


@dataclass
class Request:
    session: str
    agent: str
    model: str
    effort: str
    phase: str
    timestamp: str
    usage: Usage = field(default_factory=Usage)
    estimated: bool = False


def _with_estimate(u: dict, partial: bool, visible_chars: int) -> dict:
    """Streamed snapshots carry partial output counts; estimate from visible content.

    Hidden thinking is not recoverable, so estimated output is a lower bound.
    """
    if not partial:
        return u
    est = visible_chars // 4
    if est > (u.get("output_tokens") or 0):
        u = {**u, "output_tokens": est}
    return u


def price_request(model: str, u: dict) -> Usage:
    cc = u.get("cache_creation") or {}
    w5 = int(cc.get("ephemeral_5m_input_tokens", 0))
    w1 = int(cc.get("ephemeral_1h_input_tokens", 0))
    total_write = int(u.get("cache_creation_input_tokens", 0) or 0)
    if w5 + w1 < total_write:
        w5 += total_write - w5 - w1
    res = Usage(
        requests=1,
        input=int(u.get("input_tokens", 0) or 0),
        cache_write_5m=w5,
        cache_write_1h=w1,
        cache_read=int(u.get("cache_read_input_tokens", 0) or 0),
        output=int(u.get("output_tokens", 0) or 0),
    )
    rates = PRICES.get(model)
    if rates is None:
        return res
    if model == "claude-haiku-5-5":
        prompt = res.input + res.cache_write_5m + res.cache_write_1h + res.cache_read
        if prompt > HAIKU_LONG_THRESHOLD:
            rates = HAIKU_LONG
    inp, out, read = rates
    res.cost = (
        res.input * inp
        + res.cache_write_5m * inp * 1.25
        + res.cache_write_1h * inp * 2.0
        + res.cache_read * read
        + res.output * out
    ) / 1_000_000
    return res


def load_tags(path: pathlib.Path) -> dict[str, str]:
    if path.exists():
        return json.loads(path.read_text())
    return {}


def agent_label(jsonl: pathlib.Path) -> tuple[str, str]:
    """Return (agent_id, display name) for a transcript file."""
    if jsonl.parent.name != "subagents":
        return "orchestrator", "orchestrator"
    agent_id = jsonl.stem.removeprefix("agent-")
    meta = jsonl.with_suffix(".meta.json")
    name = agent_id
    if meta.exists():
        m = json.loads(meta.read_text())
        name = m.get("name") or m.get("description") or agent_id
    return agent_id, name


def collect(root: pathlib.Path, tags: dict[str, str]) -> list[Request]:
    files = [pathlib.Path(p) for p in glob.glob(str(root / "**/*.jsonl"), recursive=True)]
    out: list[Request] = []
    for f in sorted(files):
        agent_id, name = agent_label(f)
        phase = (
            tags.get(agent_id)
            or tags.get(name)
            or (
                name.split("-", 1)[0]
                if name[:1] == "p" and name[1:2].isdigit()
                else "orchestration"
                if agent_id == "orchestrator"
                else "untagged"
            )
        )
        last: dict[str, tuple[dict, dict]] = {}
        chars: dict[str, int] = collections.defaultdict(int)
        final: set[str] = set()
        for line in f.open(encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = d.get("message")
            if not isinstance(msg, dict) or not msg.get("usage"):
                continue
            key = d.get("requestId") or msg.get("id") or d.get("uuid")
            for block in msg.get("content") or []:
                if isinstance(block, dict):
                    chars[key] += len(block.get("text") or block.get("thinking") or "")
                    if block.get("type") == "tool_use":
                        chars[key] += len(json.dumps(block.get("input") or {}))
            if msg.get("stop_reason"):
                final.add(key)
                last[key] = (d, msg)
            elif key not in final:
                last[key] = (d, msg)
        for key, (d, msg) in last.items():
            model = msg.get("model") or "unknown"
            if model == "<synthetic>":
                continue
            out.append(
                Request(
                    session=(d.get("sessionId") or f.stem)[:8],
                    agent=name,
                    model=model,
                    effort=str(d.get("effort") or d.get("perTurnEffort") or "default"),
                    phase=phase,
                    timestamp=d.get("timestamp") or "",
                    usage=price_request(
                        model, _with_estimate(msg["usage"], key not in final, chars[key])
                    ),
                    estimated=key not in final,
                )
            )
    return out


def group(reqs: list[Request], *keys: str) -> dict[tuple, Usage]:
    g: dict[tuple, Usage] = collections.defaultdict(Usage)
    for r in reqs:
        g[tuple(getattr(r, k) for k in keys)].add(r.usage)
    return dict(sorted(g.items(), key=lambda kv: -kv[1].cost))


def fmt_tokens(n: int) -> str:
    return f"{n / 1e6:.2f}M" if n >= 1_000_000 else f"{n / 1e3:.1f}K"


def table(title: str, cols: list[str], groups: dict[tuple, Usage]) -> str:
    head = cols + [
        "Requests",
        "Input",
        "Cache write",
        "Cache read",
        "Output",
        "Total tokens",
        "Cost (USD)",
    ]
    lines = [f"### {title}", "", "| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    for k, u in groups.items():
        lines.append(
            "| "
            + " | ".join(
                list(k)
                + [
                    str(u.requests),
                    fmt_tokens(u.input),
                    fmt_tokens(u.cache_write_5m + u.cache_write_1h),
                    fmt_tokens(u.cache_read),
                    fmt_tokens(u.output),
                    fmt_tokens(u.total_tokens),
                    f"${u.cost:,.2f}",
                ]
            )
            + " |"
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--transcripts", type=pathlib.Path, default=DEFAULT_TRANSCRIPTS)
    ap.add_argument("--tags", type=pathlib.Path, default=pathlib.Path(".omc/ledger/tags.json"))
    ap.add_argument("--out", type=pathlib.Path, default=pathlib.Path(".omc/ledger/REPORT.md"))
    ap.add_argument("--json", type=pathlib.Path, default=pathlib.Path(".omc/ledger/requests.json"))
    ap.add_argument("--quiet", action="store_true", help="print only the totals line")
    args = ap.parse_args()

    reqs = collect(args.transcripts, load_tags(args.tags))
    total = Usage()
    for r in reqs:
        total.add(r.usage)
    unknown = sorted({r.model for r in reqs if r.model not in PRICES})
    n_est = sum(1 for r in reqs if r.estimated)

    parts = [
        "# OpenRugby token and cost ledger",
        "",
        (
            f"Costs are API list-price equivalents. Requests: {total.requests}. "
            f"Tokens: {fmt_tokens(total.total_tokens)}. **Total: ${total.cost:,.2f}**"
        ),
        "",
        (
            f"Accuracy: input and cache tokens are exact. Output is exact for "
            f"{total.requests - n_est} finished requests; for {n_est} requests the transcript only "
            "holds a mid-stream snapshot, so output is estimated from visible text and tool input "
            "(hidden thinking excluded). Treat output and total cost as a lower bound."
        ),
        "",
        table("By model and effort", ["Model", "Effort"], group(reqs, "model", "effort")),
        table("By phase", ["Phase"], group(reqs, "phase")),
        table(
            "By phase, model and effort",
            ["Phase", "Model", "Effort"],
            group(reqs, "phase", "model", "effort"),
        ),
        table("By agent", ["Agent", "Model", "Effort"], group(reqs, "agent", "model", "effort")),
        table("By session", ["Session"], group(reqs, "session")),
    ]
    if unknown:
        parts.append(f"Unpriced models (cost counted as $0): {', '.join(unknown)}\n")
    report = "\n".join(parts)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report)
    args.json.write_text(
        json.dumps(
            [
                {
                    **{
                        k: getattr(r, k)
                        for k in ("session", "agent", "model", "effort", "phase", "timestamp")
                    },
                    **r.usage.__dict__,
                }
                for r in reqs
            ],
            indent=1,
        )
    )
    if args.quiet:
        print(f"requests={total.requests} tokens={total.total_tokens} cost=${total.cost:.2f}")
    else:
        print(report)


if __name__ == "__main__":
    main()
