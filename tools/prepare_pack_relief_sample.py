"""读取用户高度图，重新计算凹凸区域并准备独立金纹输入；不叠加预设形状。"""
import argparse
from pathlib import Path
import shutil
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/card_ui/shop/relief_sample"
LOCAL_RADIUS = 2.0  # 计算局部凸脊与凹沟时参考的原生像素范围
FEATURE_RANGE = 24.0  # 局部高度差达到此灰度差时，凹凸区域权重达到1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--height", type=Path, help="新高度图路径；省略则重用已保存的用户高度图")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    source = np.asarray(Image.open(ROOT / "assets/card_ui/shop/ash_ledger_large.png").convert("RGBA"))
    height_path = args.height if args.height else OUT / "body_height_input.png"
    height = np.asarray(Image.open(height_path).convert("RGBA"))
    if height.shape != source.shape:
        raise ValueError("高度图必须与灰烬大包同为125×188，不能缩放或裁切后代替")
    if not np.array_equal(height[:, :, 0], height[:, :, 1]) or not np.array_equal(height[:, :, 1], height[:, :, 2]):
        raise ValueError("高度图必须是灰度图，避免把彩色印刷解释为高度")
    if not np.array_equal(height[:, :, 3], source[:, :, 3]):
        raise ValueError("高度图透明轮廓必须与原卡包对齐")
    if args.height and height_path.resolve() != (OUT / "body_height_input.png").resolve():
        shutil.copyfile(height_path, OUT / "body_height_input.png")
    # 原始高度保持逐像素不变；局部均值只用于辅助标注，不能写回或改变输入高度。
    gray = height[:, :, 0].astype(float)
    local_mean = np.asarray(Image.fromarray(height[:, :, 0]).filter(ImageFilter.GaussianBlur(LOCAL_RADIUS))).astype(float)
    residual = gray - local_mean
    regions = np.zeros_like(source)
    regions[:, :, 0] = height[:, :, 0]
    regions[:, :, 1] = np.round(np.clip(residual / FEATURE_RANGE, 0, 1) * 255).astype(np.uint8)
    regions[:, :, 2] = np.round(np.clip(-residual / FEATURE_RANGE, 0, 1) * 255).astype(np.uint8)
    regions[:, :, 3] = height[:, :, 3]
    Image.fromarray(regions).save(OUT / "body_regions.png")
    gold_mask = np.zeros(source.shape[:2], dtype=bool)
    for rgb in [(192, 152, 82), (147, 114, 54), (255, 211, 134)]:
        gold_mask |= np.all(source[:, :, :3] == rgb, axis=2)
    gold = np.full_like(source, 160)
    gold[:, :, 3] = np.where(gold_mask, source[:, :, 3], 0)
    Image.fromarray(gold).save(OUT / "gold_shape_input.png")
    print(f"读取用户高度图125×188，保留原始像素；重新计算凹凸区域，金纹{gold_mask.sum()}像素")


if __name__ == "__main__":
    main()
