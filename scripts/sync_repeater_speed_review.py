"""同步用户明确修改的连珠铳审阅文案；源表与人工回复不改。"""
import json
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
module = runpy.run_path(str(ROOT / "scripts/sync_demo2_d2_1_effect_samples.py"))
RECORD_ID = "recvu8wB6wF7lq"
FIELDS = {
    "卡面短文本": "远程行动追加2次40%效能行动；冷却速度-50%。",
    "完整规则说明": "远程主行动发射后排定2次40%效能追加，锁定原目标；追加不再次触发本装备追加。正常消耗强化、触发回响及元素效果；冷却速度-50%，与其他速度增减相加，最终速度最低30%。",
    "建议行动冷却": "冷却速度-50%",
    "数值调整理由": "2026-09-15用户修改：追加次数由3次改为2次，基础与2次40%追加合计1.8次行动效能；冷却×3.5改为冷却速度-50%。其余追加结算约定保留。",
}


def sync(snapshot_path):
    snapshot = json.loads(Path(snapshot_path).read_text())
    old = next(r for r in snapshot["card_records"] if r["record_id"] == RECORD_ID)
    path = f"bitable/v1/apps/{module['BASE']}/tables/{module['CARD_TABLE']}/records/{RECORD_ID}"
    current = module["api"](path)["record"]
    if current["fields"].get("卡牌名") != "连珠铳":
        raise ValueError("记录身份不符")
    if not module["same_fields"](old["fields"], current["fields"]):
        raise ValueError("读取后发生人工编辑，停止覆盖")
    changes = {k: v for k, v in FIELDS.items() if current["fields"].get(k) != v}
    if changes:
        module["api"](path, "PUT", {"fields": changes})
    after = module["api"](path)["record"]["fields"]
    for k, v in FIELDS.items():
        if after.get(k) != v:
            raise ValueError("写入读回不一致")
    for k, v in old["fields"].items():
        if k not in FIELDS and after.get(k) != v:
            raise ValueError("非目标字段发生变化")
    print(json.dumps({"card": "连珠铳", "updated_fields": len(changes), "verified": True, "source_writes": 0}, ensure_ascii=False))


if __name__ == "__main__":
    import sys
    sync(sys.argv[1])
