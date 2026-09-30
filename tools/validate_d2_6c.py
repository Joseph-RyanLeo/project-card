#!/usr/bin/env python3
"""D2-6C阶段验收：一个入口、串行执行、失败不自动重跑。

用法：python3 tools/validate_d2_6c.py [--godot Godot可执行文件]
只运行本阶段相关专项，不等同于项目全量套件。
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
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
        ("资源布局与生成", "d2_6c_resource_layout_test", True, []),
        ("资源战斗与收获", "d2_6c_resource_battle_test", True, []),
        ("主场景结算与下一关", "d2_6c_resource_settlement_test", True, []),
        ("存档与中断恢复", "d2_5_run_save_test", True, []),
        ("卡牌资料与装备入口", "d2_6c_resource_card_intake_test", True, []),
        ("720p真实鼠标与悬停", "d2_6c_resource_input_test", False, ["capture"]),
        ("2K真实鼠标与悬停", "d2_6c_resource_input_test", False, ["2k", "capture"]),
    ]
    results = []
    for index, (label, script, headless, user_args) in enumerate(cases, 1):
        log = log_dir / f"project-card-d2-6c-acceptance-{index}.log"
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
        results.append((label, result.returncode, output_log))
    print("\n阶段验收汇总（每项只运行一次）：")
    for label, exit_code, log in results:
        print(f"{'通过' if exit_code == 0 else '失败'}：{label}；日志 {log}")
    print("退出告警仍需查日志；退出码为0不代表历史问题已修复。")
    return int(any(exit_code != 0 for _, exit_code, _ in results))


if __name__ == "__main__":
    raise SystemExit(main())
