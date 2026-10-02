#!/usr/bin/env python3
"""读取伙伴发回的诊断ZIP/目录或真实采样JSON；不解压、执行或修改被分析的文件。"""
import argparse
import json
import math
import statistics
import zipfile
from pathlib import Path

METRICS = ("frame_ms", "wall_frame_ms", "collection_page_turn_ms", "battle_start_ms", "battle_result_ms", "drag_preview_ms", "release_exact_snap_ms", "battle_advance_ms", "state_sync_ms", "effect_dispatch_ms", "draw_calls")
STEPS = ("空闲（含启动/恢复）", "收藏翻页", "商店进入与卡包悬停", "离店与随从拖动", "装备拖动", "战斗开始/进行/结算")


def read_inputs(path):
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            entries = []
            for info in archive.infolist():
                if info.filename.endswith(".json"):
                    if info.file_size > 64 * 1024 * 1024:
                        raise ValueError("单个JSON超过64MiB，请先人工检查：" + info.filename)
                    entries.append((info.filename, json.loads(archive.read(info).decode("utf-8-sig"))))
            return entries
    if path.is_dir():
        return [(str(file.relative_to(path)), json.loads(file.read_text(encoding="utf-8-sig"))) for file in path.rglob("*.json")]
    return [(path.name, json.loads(path.read_text(encoding="utf-8-sig")))]


def summarize(samples, metric):
    values = sorted(float(row[metric]) for row in samples if isinstance(row.get(metric), (float, int)))
    if not values:
        return None
    return {"count": len(values), "mean": statistics.fmean(values), "p50": values[max(0, math.ceil(len(values) * .5) - 1)], "p95": values[max(0, math.ceil(len(values) * .95) - 1)], "max": values[-1]}


def analyze(entries):
    traces = sorted((name, data) for name, data in entries if isinstance(data, dict) and (isinstance(data.get("samples"), list) or isinstance(data.get("existing_trace"), list)))
    hardware = next((data for name, data in entries if name.endswith("hardware.json")), {})
    session = next((data for name, data in entries if name.endswith("session.json")), {})
    previous = []
    segments = []
    for index, (name, data) in enumerate(traces):
        all_samples = data.get("samples", data.get("existing_trace", []))
        cumulative = bool(previous) and len(all_samples) >= len(previous) and all_samples[0] == previous[0] and all_samples[len(previous) - 1] == previous[-1]
        samples = all_samples[len(previous):] if cumulative else all_samples
        segments.append({"file": name, "suggested_step": STEPS[index] if len(traces) == 6 else "需人工核对步骤", "cumulative_prefix_removed": len(previous) if cumulative else 0, "sample_count": len(samples), "engine_delta_over_33ms": sum(float(row.get("frame_ms", 0)) > 33 for row in samples), "metrics": {metric: summarize(samples, metric) for metric in METRICS}, "active_drag": summarize([row for row in samples if float(row.get("drag_preview_ms", 0)) > 0], "drag_preview_ms"), "active_battle": summarize([row for row in samples if float(row.get("battle_advance_ms", 0)) > 0], "battle_advance_ms")})
        previous = all_samples
    return {"hardware": hardware, "session": session, "segments": segments, "notes": ["步骤名称只是README顺序建议，需要用户确认；首次空闲段含启动/恢复。", "frame_ms是引擎delta；新版wall_frame_ms为主循环采样点之间的真实间隔，也包含暂停、后台等待和F10写日志。原采样器window_size是内部1280x720画布。", "battle_advance_ms包含state_sync_ms和effect_dispatch_ms，不能相加。", "每秒进程统计无法分解几十毫秒的瞬时停顿；F10日志提供逐帧脚本数据。"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, help="将分段统计保存为JSON（可选）")
    args = parser.parse_args()
    report = analyze(read_inputs(args.input))
    for segment in report["segments"]:
        print(f"{segment['suggested_step']}：{segment['sample_count']}帧，去掉前段累计{segment['cumulative_prefix_removed']}帧")
        for metric in ("frame_ms", "drag_preview_ms", "battle_advance_ms"):
            stats = segment["metrics"].get(metric)
            if stats:
                print(f"  {metric}: p95={stats['p95']:.3f}, max={stats['max']:.3f}")
    if not report["segments"]:
        print("没有F10性能数据；请结合引擎日志核对采样开关与F10操作。")
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
