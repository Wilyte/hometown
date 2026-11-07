"""读 calib_*.png 中心像素，反推 Godot 的归一化系数与颜色空间处理。

约定：PNG 里的值是 sRGB 编码，线性值 = srgb_to_linear(pixel)。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PI = 3.141592653589793
GRAY_LIN = 0.2140  # sRGB 0.5 → 线性


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def sample(path: Path) -> float:
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    h, w, _ = img.shape
    patch = img[h // 2 - 4:h // 2 + 4, w // 2 - 4:w // 2 + 4]
    return float(np.median([srgb_to_linear(float(v)) for v in patch.reshape(-1)]))


def main(shots_dir: str) -> None:
    d = Path(shots_dir)
    v = {}
    for p in sorted(d.glob("calib_*.png")):
        v[p.name.split("_")[1]] = sample(p)

    def show(tag, val, note):
        print(f"{tag:22} linear={val:.4f}  {note}")

    if "A" in v:
        show("A bg gray 0.5", v["A"], "→ 0.214 说明 background_color 被 sRGB→线性")
    if "B" in v:
        k = v["B"] / 0.25
        show("B sun white E=.25", v["B"], f"k_dir={k:.4f}（three.js 为 1/PI={1/PI:.4f}）")
    if "C" in v:
        kc = v["C"] / (0.25 * (0.5 if False else 1.0))  # 仅用于对比
        show("C sun gray E=.25", v["C"], f"若 light_color 走 sRGB 则 ≈{0.25*GRAY_LIN:.4f}，否则 ≈0.1250")
    if "D" in v:
        show("D amb gray E=1", v["D"], f"若 sRGB 则 ≈{GRAY_LIN:.4f}，否则 ≈0.5000")
    if "E" in v:
        show("E albedo gray E=1", v["E"], f"若 albedo 走 sRGB 则 ≈{GRAY_LIN:.4f}，否则 ≈0.5000")
    if "F" in v:
        show("F sky white E=1", v["F"], "天光系数（1.0 表示 sky 颜色直接当辐照度）")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "shots")
