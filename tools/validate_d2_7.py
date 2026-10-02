#!/usr/bin/env python3
"""D2-7首批普通商店专项验收；串行运行，不自动重试失败项。"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot可执行文件路径")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    steam_godot = Path.home() / "Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"
    executable = args.godot or (str(steam_godot) if steam_godot.is_file() else shutil.which("godot"))
    if not executable:
        parser.error("未找到Godot，请用 --godot 指定已有可执行文件；不自动安装引擎。")
    log_dir = Path("/private/tmp") if sys.platform == "darwin" else Path(tempfile.gettempdir())
    cases = [
        ("卡池、空档重分配、保底与商店事务/存档", "d2_7_ordinary_shop_test", True, []),
        ("暗单八类合法提示、统一报价与保存校验", "d2_7_shop_hint_test", True, []),
        ("隐藏符文断点与基础收益", "d2_7_hidden_runes_test", True, []),
        ("品级遮罩素材、像素阈值与存档迁移", "d2_7_rune_cover_save_test", True, []),
        ("真实贴纸库存容量", "d2_7_sticker_inventory_test", True, []),
        ("刮刀库存与贴纸/伤势移除规则", "d2_7_inspection_interaction_test", False, []),
        ("点击携带与检视刮刀回归", "d2_7_inspection_click_carry_regression_test", False, []),
        ("2K真实刀头输入、分槽付款与退出结算", "d2_7_rune_scrape_2k_test", False, []),
        ("固定金币像素、贴纸包叠放与包装检视倾斜光栅", "d2_7_pack_surface_test", False, []),
        ("轮播保留、商品补位、检视往返及开包交易一致性", "d2_7_shop_animation_test", False, []),
        ("首排紧凑商品、固定价格、刮刀凹槽与飞回", "d2_7_shop_compact_test", False, ["2k"]),
        ("2K商店金币图片、三包遮挡、卡包检视与回弹", "d2_7_shop_polish_test", False, ["2k"]),
        ("2K原生贴纸拖拽与刮刀点击回归", "d2_7_native_sticker_drag_test", False, []),
        ("商店入口与真实鼠标输入（720p）", "d2_7_shop_input_test", False, ["capture"]),
        ("商店入口与真实鼠标输入（2K）", "d2_7_shop_input_test", False, ["2k", "capture"]),
        ("商店层级、暗单轮播与真实防泄漏渲染（720p）", "d2_7_shop_presentation_test", False, []),
        ("商店层级、暗单轮播与真实防泄漏渲染（2K）", "d2_7_shop_presentation_test", False, ["2k"]),
        ("商品静止、卡包堆叠与轮播不透明（720p）", "d2_7_shop_stack_motion_test", False, []),
        ("商品静止、卡包堆叠与轮播不透明（2K）", "d2_7_shop_stack_motion_test", False, ["2k"]),
    ]
    results = []
    for index, (label, script, headless, user_args) in enumerate(cases, 1):
        log = log_dir / f"project-card-d2-7-{index}.log"
        output_log = log.with_suffix(".stdout.log")
        command = [executable, "--path", str(project), "--log-file", str(log)]
        if headless:
            command.append("--headless")
        command.extend(["--script", f"res://tests/{script}.gd"])
        if user_args:
            command.extend(["--", *user_args])
        print(f"[{index}/{len(cases)}] {label}", flush=True)
        with output_log.open("w", encoding="utf-8") as output:
            result = subprocess.run(command, cwd=project, stdout=output, stderr=subprocess.STDOUT)
        results.append((label, result.returncode, output_log, log))
    print("\nD2-7专项结果（每项只运行一次）：")
    for label, exit_code, output_log, engine_log in results:
        print(f"{'通过' if exit_code == 0 else '失败'}：{label}；输出 {output_log}；Godot日志 {engine_log}")
    return int(any(exit_code != 0 for _, exit_code, _, _ in results))


if __name__ == "__main__":
    raise SystemExit(main())
