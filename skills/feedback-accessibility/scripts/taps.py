#!/usr/bin/env python3
"""Replays Feedback's tap selection over a JSON export and reports where taps fall through.

Usage: taps.py <feedback.json> [--step 8]

A tap "falls through" when it selects the screen, a layer, or a component that is the root of
its screen or layer, such as the screen view's own `.feedback(self)`. The report lists the
fall-through share, the bands of the capture where most of a row falls through, and the
elements that sit directly under a root, which are the usual candidates for a missing tag.
"""
import json
import sys


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    step = float(args[args.index("--step") + 1]) if "--step" in args else 8.0
    nodes = json.load(open(args[0]))["nodes"]

    depth = {}
    for node in nodes:
        parent = node.get("parent")
        depth[node["id"]] = 0 if parent is None else depth[parent] + 1

    def rect(node):
        f = node["frame"]
        return f["x"], f["y"], f["x"] + f["width"], f["y"] + f["height"]

    def contains(node, x, y):
        x0, y0, x1, y1 = rect(node)
        return x0 <= x <= x1 and y0 <= y <= y1

    def area(node):
        return node["frame"]["width"] * node["frame"]["height"]

    # Mirrors Capture.hitTest: only the topmost layer covering the point competes, then the
    # smallest node wins, and the deeper one on a tie.
    def hit(x, y):
        layer = max((n["layer"] for n in nodes if n["kind"] == "layer" and contains(n, x, y)), default=0)
        candidates = [n for n in nodes if n["layer"] == layer and n["kind"] != "screen" and contains(n, x, y)]
        if not candidates:
            return nodes[0]
        return min(candidates, key=lambda n: (area(n), -depth[n["id"]]))

    by_id = {n["id"]: n for n in nodes}
    roots = {0} | {n["id"] for n in nodes if n["kind"] == "layer"}
    roots |= {n["id"] for n in nodes if n["kind"] == "component" and n.get("parent") in roots}

    def title(node):
        label = node.get("label")
        name = f'{node["name"]} "{label[:50]}"' if label else node["name"]
        return f'#{node["id"]} {name}' + (f' ({node["source"]})' if node.get("source") else "")

    width, height = rect(nodes[0])[2], rect(nodes[0])[3]
    rows = []
    total = through = 0
    y = step / 2
    while y < height:
        row = []
        x = step / 2
        while x < width:
            row.append(hit(x, y)["id"] in roots)
            x += step
        rows.append((y, sum(row) / len(row)))
        total += len(row)
        through += sum(row)
        y += step

    print(f"Fall-through: {through / total:.0%} of {total} grid points ({step:g} pt grid over {width:g}x{height:g} pt)")
    print("Bands where most of a row falls through (often margins and gaps, sometimes a missing tag):")
    band = None
    for y, share in rows + [(height + step, 0)]:
        if share > 0.5:
            band = band or y
        elif band is not None:
            print(f"  y {band - step / 2:.0f}-{y - step / 2:.0f}")
            band = None
    print("Elements directly under a root (each should be fine on its own, or belong to a tagged region):")
    for node in nodes:
        if node["kind"] == "element" and node.get("parent") in roots and node["parent"] != 0:
            print(f"  {title(node)}  under {title(by_id[node['parent']])}")


main()
