"""给 demo/验收用：把一个 part 复制到 parts_over 并整体放大（默认 1.5 倍）。

验证「改个别模型」这条路：parts_over/<name>.tscn 优先于生成的 parts/<name>.tscn，
改了它不用动 GLB、不用重跑拆件器，观看器/编辑器立刻生效。
"""
import re
import sys
from pathlib import Path

PART = sys.argv[1] if len(sys.argv) > 1 else "dome-tent"
SCALE = float(sys.argv[2]) if len(sys.argv) > 2 else 1.5

root = Path(__file__).resolve().parents[2]
src = root / "v6" / "assets" / "parts" / f"{PART}.tscn"
dst = root / "v6" / "assets" / "parts_over" / f"{PART}.tscn"
dst.parent.mkdir(parents=True, exist_ok=True)

lines = src.read_text(encoding="utf-8").split("\n")
header = None
for i, ln in enumerate(lines):
    if ln.startswith(f'[node name="{PART}"'):
        header = i
        break
if header is None:
    raise SystemExit(f"找不到根节点 {PART}")

# 根节点后面紧跟的那行如果是 transform 就替换，否则插入
if header + 1 < len(lines) and lines[header + 1].startswith("transform = Transform3D("):
    lines[header + 1] = ("transform = Transform3D(%g, 0, 0, 0, %g, 0, 0, 0, %g, 0, 0, 0)"
                         % (SCALE, SCALE, SCALE))
else:
    lines.insert(header + 1,
                 "transform = Transform3D(%g, 0, 0, 0, %g, 0, 0, 0, %g, 0, 0, 0)"
                 % (SCALE, SCALE, SCALE))

dst.write_text("\n".join(lines), encoding="utf-8")
print(f"WROTE {dst.relative_to(root)}  scale={SCALE}")
