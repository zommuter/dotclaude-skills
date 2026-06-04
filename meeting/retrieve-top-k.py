#!/usr/bin/env python3
"""retrieve-top-k.py — BGE-M3 endpoint-only retrieval for meeting skill files.

Usage: retrieve-top-k.py --file FILE --query QUERY [--k N] [--chunk-sep PATTERN]
Env:   EMBED_ENDPOINT (required), EMBED_MODEL (optional, default: bge-m3)
Exit:  0 on success (writes to stdout), 1 on any failure (caller falls back).
"""
import argparse, json, math, os, re, sys, urllib.request


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    norm = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(x * x for x in b))
    return dot / norm if norm else 0.0


def embed(texts, endpoint, model):
    body = json.dumps({"model": model, "input": texts}).encode()
    req = urllib.request.Request(endpoint, data=body,
                                  headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return [e["embedding"] for e in json.loads(r.read())["data"]]


def chunk_file(path, sep_pattern):
    with open(path) as f:
        lines = f.read().splitlines()
    blocks, cur = [], []
    for line in lines:
        if re.match(sep_pattern, line) and cur:
            blocks.append("\n".join(cur))
            cur = []
        cur.append(line)
    if cur:
        blocks.append("\n".join(cur))
    return [b for b in blocks if b.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--query", required=True)
    ap.add_argument("--k", type=int, default=10)
    ap.add_argument("--chunk-sep", default="^## ")
    args = ap.parse_args()

    endpoint = os.environ.get("EMBED_ENDPOINT")
    if not endpoint:
        sys.exit(1)
    model = os.environ.get("EMBED_MODEL", "bge-m3")

    blocks = chunk_file(args.file, args.chunk_sep)
    if not blocks:
        sys.exit(0)

    try:
        vecs = embed(blocks + [args.query], endpoint, model)
    except Exception as e:
        print(f"retrieve-top-k: embed failed: {e}", file=sys.stderr)
        sys.exit(1)

    q_vec = vecs[-1]
    ranked = sorted(zip(blocks, vecs[:-1]),
                    key=lambda bv: cosine(q_vec, bv[1]), reverse=True)
    for block, _ in ranked[:args.k]:
        print(block)
        print()


if __name__ == "__main__":
    main()
