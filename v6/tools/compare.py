"""把页面截图裁成舞台大小，并与 Godot 出图并排/求差。

用法：
  python v6/tools/compare.py                     # 用 .run/v6-shots 下的 page_full/ref/kit
  python v6/tools/compare.py --rect 34.2,305.5,1249.7,960
裁切矩形 = canvas.getBoundingClientRect() 的 CSS 值 × devicePixelRatio。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SHOTS = ROOT / ".run" / "v6-shots"
# 页面舞台在 2x DPR 截图里的位置（本机窗口：canvas rect × 2）
DEFAULT_RECT = (34.2, 305.5, 1249.7, 960.0)


def crop_ref(rect=DEFAULT_RECT, size=(1246, 956)):
    src = Image.open(SHOTS / "page_full.png").convert("RGB")
    x, y, w, h = rect
    box = (round(x), round(y), round(x + w), round(y + h))
    out = src.crop(box).resize(size, Image.LANCZOS)
    out.save(SHOTS / "ref_web.png")
    return out


def main() -> None:
    rect = DEFAULT_RECT
    if "--rect" in sys.argv:
        rect = tuple(float(v) for v in sys.argv[sys.argv.index("--rect") + 1].split(","))
    ref = crop_ref(rect)
    kit = SHOTS / "kit.png"
    mine = Image.open(kit).convert("RGB").resize(ref.size)

    a = np.asarray(ref, dtype=np.float32)
    b = np.asarray(mine, dtype=np.float32)
    diff = np.abs(a - b)
    # 1px 垂直对不齐是裁切取整造成的，报告里给对齐后的数字
    best = None
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            y0, y1 = max(0, dy), ref.height + min(0, dy)
            x0, x1 = max(0, dx), ref.width + min(0, dx)
            d = np.abs(a[y0:y1, x0:x1] - b[y0 - dy:y1 - dy, x0 - dx:x1 - dx]).mean()
            if best is None or d < best[0]:
                best = (d, dx, dy)
    print(f"ref={ref.size} mine={mine.size}  file={kit}")
    print(f"mean|diff|={diff.mean():.2f}/255  p95={np.percentile(diff, 95):.1f}")
    print(f"对齐后 mean|diff|={best[0]:.2f}/255 @ shift({best[1]},{best[2]})")
    print(f"ref  mean RGB={a.reshape(-1, 3).mean(axis=0).round(2)}")
    print(f"mine mean RGB={b.reshape(-1, 3).mean(axis=0).round(2)}")
    sat = a.max(axis=2) - a.min(axis=2)
    mask = sat > 25
    if mask.any():
        print(f"模型区 ref={a[mask].mean(axis=0).round(1)} mine={b[mask].mean(axis=0).round(1)} "
              f"ratio={(b[mask].mean(axis=0) / a[mask].mean(axis=0)).round(3)}")

    pair = Image.new("RGB", (ref.width * 2 + 8, ref.height), (20, 20, 20))
    pair.paste(ref, (0, 0))
    pair.paste(mine, (ref.width + 8, 0))
    pair.save(SHOTS / "compare.png")
    Image.fromarray(np.clip(diff * 3, 0, 255).astype(np.uint8)).save(SHOTS / "diff.png")
    print(f"写出 {SHOTS / 'compare.png'} 与 {SHOTS / 'diff.png'}")


if __name__ == "__main__":
    main()
