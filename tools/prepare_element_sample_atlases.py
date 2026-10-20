"""把用户提供的木穿刺、暗连击 GIF 整理为 Godot 可用的透明图集。

保留原画 RGB 和全部像素位置；只把黑底变透明，不提取或移动主刺。
用法：python3 tools/prepare_element_sample_atlases.py [木GIF 暗GIF]
不传路径时，使用项目中保留的源 GIF 重建。
"""

from pathlib import Path
import shutil
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/effects/hand_drawn"


def make_atlas(source: Path, name: str, crops: list[tuple], indices: list[int], columns: int) -> None:
    saved_source = OUTPUT / "source" / f"{name}.gif"
    saved_source.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() != saved_source.resolve():
        shutil.copy2(source, saved_source)
    with Image.open(saved_source) as gif:
        width, height = crops[0][2] - crops[0][0], crops[0][3] - crops[0][1]
        cells = [(crop, index) for crop in crops for index in indices]
        atlas = Image.new("RGBA", (width * columns, height * ((len(cells) + columns - 1) // columns)))
        for cell, (crop, index) in enumerate(cells):
            gif.seek(index)
            frame = gif.convert("RGBA").crop(crop)
            frame.putdata([(r, g, b, 0 if (r, g, b) == (0, 0, 0) else a) for r, g, b, a in frame.getdata()])
            atlas.paste(frame, ((cell % columns) * width, (cell // columns) * height))
        atlas.save(OUTPUT / f"{name}.png")
        print(f"{name}：{len(cells)}格，单帧{width}×{height}，原帧间隔{gif.info.get('duration', 0)}毫秒")


if __name__ == "__main__":
    sources = [Path(arg) for arg in sys.argv[1:]]
    if not sources:
        sources = [OUTPUT / "source/wood_pierce.gif", OUTPUT / "source/dark_slash.gif"]
    if len(sources) != 2:
        raise SystemExit("请提供木穿刺GIF和暗连击GIF两个路径")
    # 木：三行分别保留三个角度版本，每次只选一行。暗：每行只含一击。
    make_atlas(sources[0], "wood_pierce", [(100, 0, 260, 450), (260, 0, 420, 450), (410, 0, 570, 450)], list(range(16)), 16)
    make_atlas(sources[1], "dark_slash", [(65, 45, 289, 245)], list(range(12)), 4)
