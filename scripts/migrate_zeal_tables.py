"""热诚迁移：只读盘点、精确计划和带并发检查的定点写入。"""
import copy
import json
import re
import runpy
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "IcuQbyEQtaPWPgsOOOrcu5shnKh"
SOURCES = ["TmBns9BTJh8m8FtJuOSc72GFnOd", "PEHqshuiDhAZIJtvaAOcbmQUn4g", "GnWksdURnhjz9ntKHC9chvd7nrh"]
_module = None


def api(path, method="GET", body=None):
    global _module
    if _module is None:
        _module = runpy.run_path(str(ROOT / "scripts/sync_rules_review_20260911.py"))
        _module["api"].__globals__["bridge"] = runpy.run_path(_module["BRIDGE"])
    allowed = path.startswith(f"bitable/v1/apps/{BASE}/") or any(
        path.startswith(f"sheets/{v}/spreadsheets/{token}/") for token in SOURCES for v in ["v2", "v3"])
    if not allowed:
        raise ValueError("访问超出本次授权资料")
    return _module["api"](path, method, body)


def items(path):
    rows = []
    token = None
    while True:
        data = api(path + "?page_size=100" + ("&page_token=" + token if token else ""))
        rows.extend(data.get("items") or [])
        if not data.get("has_more"):
            return rows
        token = data["page_token"]


def flat(value):
    if value is None:
        return ""
    if isinstance(value, list):
        return "".join(map(flat, value))
    if isinstance(value, dict):
        return value.get("text", "")
    return str(value)


def col_name(n):
    out = ""
    while n:
        n, rem = divmod(n - 1, 26)
        out = chr(65 + rem) + out
    return out


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2))


def snapshot():
    folder = Path(tempfile.mkdtemp(prefix="project-card-zeal-", dir="/private/tmp"))
    data = {"tables": [], "sheets": []}
    write_json(folder / "before.json", data)
    for t in items(f"bitable/v1/apps/{BASE}/tables"):
        tid = t["table_id"]
        data["tables"].append({**t, "fields": items(f"bitable/v1/apps/{BASE}/tables/{tid}/fields"),
                               "records": items(f"bitable/v1/apps/{BASE}/tables/{tid}/records")})
        write_json(folder / "before.json", data)
    for token in SOURCES:
        for meta in api(f"sheets/v3/spreadsheets/{token}/sheets/query")["sheets"]:
            grid = meta["grid_properties"]
            address = f'{meta["sheet_id"]}!A1:{col_name(grid["column_count"])}{grid["row_count"]}'
            values = api(f"sheets/v2/spreadsheets/{token}/values/{address}")["valueRange"]["values"]
            data["sheets"].append({"token": token, "meta": meta, "range": address, "values": values})
            write_json(folder / "before.json", data)
            print(json.dumps({"snapshot": str(folder), "sheet": meta["title"]}, ensure_ascii=False), flush=True)
    print(str(folder), flush=True)


THUNDER = "被敌方伤害行动成功命中后，本场获得热诚1，本效果最多累计5层；格挡或护甲使生命未减少也触发，未命中、目标丢失或攻击失败不触发。"
CARD_NAMES = {"散兵阵", "雷暴步兵", "连珠铳", "黑铁法杖", "“铁砧”玛格丽特", "集结号", "星月豹", "舞者的手铃", "月刃弯刀", "日月护符"}
TRAIT_NAMES = {"脑震荡", "内伤Ⅰ", "内伤Ⅱ", "撕裂Ⅰ", "撕裂Ⅱ", "撕裂Ⅲ", "冻僵", "羽毛Ⅰ", "羽毛Ⅱ"}
TEXT_FIELDS = {"卡面短文本", "原特效", "完整规则说明", "原行动冷却", "建议行动冷却", "原始描述", "规范描述"}


def zeal_text(n):
    if n != int(n):
        raise ValueError("存在非整数热诚，必须先确认")
    return f"热诚{int(n):+d}"


def convert_text(text, name=""):
    """仅替换冷却片段，不触碰同一单元格中的其他百分比或效果。"""
    def convert_percent(match):
        phrase, mode, number = match.group(0), match.group(1), float(match.group(2))
        if name == "连珠铳":
            return "热诚-10"
        if name == "黑铁法杖":
            return "热诚-12"
        if name == "雷暴步兵":
            raise ValueError("雷暴步兵必须使用已确认的完整触发规则")
        positive = mode in ("缩短", "缩减", "减少", "降低", "-")
        if "速度" in phrase:
            positive = mode in ("增加", "加快", "+")
        return zeal_text(number / 5 * (1 if positive else -1))
    text = re.sub(r"(?:基础)?(?:行动)?冷却(?:时间|速度)?(?:的)?(?:为)?(缩短|缩减|减少|降低|增加|加快|减慢|[+-])(\d+(?:\.\d+)?)[%％]", convert_percent, text)
    def multiplier(match):
        value = float(match.group(1))
        if name == "黑铁法杖":
            return "热诚-12"
        if name == "连珠铳":
            return "热诚-10"
        return zeal_text(round((1 - value) * 100, 8) / 5)
    text = re.sub(r"(?:基础)?(?:行动)?冷却×(\d+(?:\.\d+)?)", multiplier, text)
    if name == "“铁砧”玛格丽特":
        text = re.sub(r"(?:基础)?(?:行动)?冷却\+1秒", "热诚-4", text)
    if "冷却翻倍" in text:
        if name not in ("黑铁法杖", "钢化术"):
            raise ValueError("未确认的冷却翻倍转换")
        text = re.sub(r"(?:行动)?冷却翻倍", "热诚-12" if name == "黑铁法杖" else "热诚-10", text)
    return text


def replace_rich(value, transform):
    result = copy.deepcopy(value)
    if isinstance(result, str):
        return transform(result)
    if isinstance(result, list):
        for segment in result:
            if not isinstance(segment, dict) or segment.get("type") != "text":
                raise ValueError("目标富文本含非文本内容，停止自动改写")
            segment["text"] = transform(segment["text"])
        return result
    raise ValueError("不支持的文本单元格类型")


def cell_value(sheet, address):
    match = re.fullmatch(r"([A-Z]+)(\d+)", address)
    col = 0
    for ch in match[1]:
        col = col * 26 + ord(ch) - 64
    return sheet["values"][int(match[2]) - 1][col - 1]


def make_plan(folder, include_extra=False):
    folder = Path(folder)
    before = json.loads((folder / "before.json").read_text())
    tables = {t["name"]: t for t in before["tables"]}
    updates, cells = [], []
    terms = tables["标准词条"]
    zeal = next((r for r in terms["records"] if r["fields"].get("词条") == "热诚"), None)
    obsolete_ids = {r["record_id"] for r in terms["records"] if r["fields"].get("词条") in ["行动冷却缩短X%", "冷却惩罚", "冷却倍率"]}

    def update(table, row, fields, add_link=False):
        changed = {k: v for k, v in fields.items() if row["fields"].get(k) != v}
        if add_link:
            ids = [rid for link in row["fields"].get("标准词条", []) for rid in (link.get("record_ids") or [])]
            if row["fields"].get("卡牌名") == "雷暴步兵":
                ids = [rid for rid in ids if rid != "recvuuOcFA2OP7"] + ["recvujvxMxqc2Q"]
            changed["标准词条"] = [rid for rid in ids if rid not in obsolete_ids and (not zeal or rid != zeal["record_id"])] + ["$ZEAL"]
        if changed:
            updates.append({"table": table["table_id"], "record_id": row["record_id"], "name": row["fields"].get("卡牌名", row["fields"].get("名称", row["fields"].get("词条"))), "fields": changed})

    for table_name in ["卡牌审阅", "纹章与伤势", "英雄附属内容"]:
        table = tables[table_name]
        for row in table["records"]:
            f = row["fields"]
            name = f.get("卡牌名", f.get("名称"))
            if name not in CARD_NAMES | TRAIT_NAMES | {"法术傀儡·突击选项2"}:
                continue
            fields = {}
            for k in TEXT_FIELDS:
                text = f.get(k)
                if not isinstance(text, str):
                    continue
                if name == "雷暴步兵" and k in ["原特效", "完整规则说明", "卡面短文本"]:
                    fields[k] = THUNDER
                else:
                    fields[k] = convert_text(text, name)
                if k in ["原行动冷却", "建议行动冷却"]:
                    if name in ["舞者的手铃", "月刃弯刀"] and text in ["-5%", "-0.05"]:
                        fields[k] = "热诚+1"
                    elif name == "黑铁法杖" and text in ["×2", "2"]:
                        fields[k] = "热诚-12"
            if name in ["舞者的手铃", "月刃弯刀", "黑铁法杖"]:
                for k in ["卡面短文本", "完整规则说明"]:
                    if k in fields and "热诚" not in fields[k]:
                        fields[k] += " 装备者" + ("热诚-12。" if name == "黑铁法杖" else "热诚+1。")
            if name == "雷暴步兵":
                fields["卡面短文本"] = "被敌方伤害行动命中后，本场获得热诚1（本效果最多5层）。"
                fields["数值调整理由"] = f["数值调整理由"].replace("无上限缩短会趋近0", "无上限加速会过快").replace("设置20%上限", "设置本效果最多5层热诚的上限")
            elif name == "黑铁法杖":
                fields["待确认事项"] = f["待确认事项"].replace("原特效同时写冷却翻倍，建议冷却列与当前完整说明是否保留该代价需确认", "冷却代价已确认为热诚-12")
                fields["数值调整理由"] = f["数值调整理由"].replace("将冷却翻倍移入结构化字段，效果文本只保留行动倍率", "冷却代价改为热诚-12，行动倍率效果保持原约定")
            elif name == "连珠铳":
                fields["数值调整理由"] = f["数值调整理由"].replace("冷却×3.5改为冷却速度-50%", "冷却惩罚改为热诚-10")
            elif name == "集结号":
                fields["数值调整理由"] = "热诚与其他速度来源按层数相加，本场热诚+4允许多个来源叠加；最终速度最低30%，普通行动间隔最低0.5秒。"
            update(table, row, fields, True)

    # 原词条记录保留身份与关联兼容性，定义明确转向新词条；不复制多个热诚定义。
    for row in terms["records"]:
        if row["record_id"] in obsolete_ids:
            update(terms, row, {"建议定义": "旧冷却修正分类，相关效果已迁移为热诚；每层热诚改变5%冷却速度。", "默认边界": "新效果使用热诚，原有来源的持续与同名叠加约束保留。", "备注": "热诚迁移保留的旧分类；不再作为独立速度修正重复结算。"})
    for row in tables["组合风险"]["records"]:
        if row["fields"].get("组合名称") == "无下限减冷却":
            update(tables["组合风险"], row, {"组合名称": "热诚与充能组合", "可能问题": "热诚改变冷却推进速度，充能直接减少剩余冷却；同时存在时需避免同帧递归行动。", "建议防线": "热诚每层5%，最终速度最低30%；实际普通行动间隔0.5～99秒；充能保持独立规则，同一逻辑层每个行动者最多开始一次基础行动。"})

    known = {
        ("灰烬证册", "F14"): "“铁砧”玛格丽特", ("灰烬证册", "J105"): "集结号",
        ("铁壁铭刻", "J14"): "散兵阵", ("铁壁铭刻", "J40"): "雷暴步兵",
        ("铁壁铭刻", "B92"): "连珠铳", ("铁壁铭刻", "F92"): "黑铁法杖",
        ("银月之章", "F66"): "星月豹", ("银月之章", "J105"): "日月护符",
        ("莉丝忒·碎星", "J59"): "法术傀儡·突击选项2",
    }
    for address in ["O6", "O13", "O14", "O16", "O17", "O18", "O21", "G36", "G37"]:
        known[("纹章和伤势", address)] = "纹章伤势"
    if include_extra:
        known.update({("镀金委托（改）", "B40"): "契约之魔·奈克斯", ("镀金委托", "B40"): "契约之魔·奈克斯", ("千帆悬赏", "F66"): "嗜血魔", ("虫蚀图志", "R105"): "虫母腺体", ("锻金配方", "J79"): "钢化术"})
    numeric = {("银月之章", "D102"): (-0.05, "热诚+1"), ("银月之章", "H102"): (-0.05, "热诚+1"), ("铁壁铭刻", "H89"): (2, "热诚-12")}
    for s in before["sheets"]:
        title = s["meta"]["title"]
        for (sheet_name, address), name in known.items():
            if title != sheet_name:
                continue
            old = cell_value(s, address)
            new = replace_rich(old, lambda text: THUNDER if name == "雷暴步兵" else convert_text(text, name))
            if old != new:
                cells.append({"token": s["token"], "sid": s["meta"]["sheet_id"], "sheet": title, "address": address, "before": old, "after": new})
        for (sheet_name, address), (expected, new) in numeric.items():
            if title == sheet_name:
                old = cell_value(s, address)
                if old != expected:
                    raise ValueError("源数值不符，不能套用旧映射")
                cells.append({"token": s["token"], "sid": s["meta"]["sheet_id"], "sheet": title, "address": address, "before": old, "after": new})
    definition = {"词条": "热诚", "分类": "冷却修改", "建议定义": "热诚为可正可负的层数。每层热诚使冷却速度增加5%；每层负热诚使冷却速度减少5%。正负相加后计算速度。", "默认边界": "最终速度=max(30%,100%+热诚层数×5%)；普通行动间隔0.5～99秒。速度变化保留已有进度；来源持续时间与同名叠加规则按各效果保留。", "备注": "10秒及以上冷却数字舍去小数，10.2显示10；仅显示取整，不改变实际计时。"}
    plan = {"updates": updates, "source_cells": cells, "term_table": terms["table_id"], "term_record": zeal["record_id"] if zeal else None, "term_fields": definition, "include_extra": include_extra}
    write_json(folder / "plan.json", plan)
    print(json.dumps({"updated_records": len(updates), "source_cells": len(cells), "term_create": not bool(zeal)}, ensure_ascii=False))


def normalized(key, value):
    if key == "标准词条":
        if not value:
            return []
        return sorted([v for v in value if isinstance(v, str)] + [rid for v in value if isinstance(v, dict) for rid in v.get("record_ids") or []])
    return value


def apply_plan(folder):
    folder = Path(folder)
    before = json.loads((folder / "before.json").read_text())
    plan = json.loads((folder / "plan.json").read_text())
    table_ids = {u["table"] for u in plan["updates"]} | {plan["term_table"]}
    old_tables = {t["table_id"]: t for t in before["tables"]}
    source_keys = {(c["token"], c["sid"]) for c in plan["source_cells"]}
    old_sheets = {(s["token"], s["meta"]["sheet_id"]): s for s in before["sheets"]}
    # 所有目标先检查，再开始写入；不以先写后检查处理并发编辑。
    for tid in table_ids:
        rows = items(f"bitable/v1/apps/{BASE}/tables/{tid}/records")
        fields = items(f"bitable/v1/apps/{BASE}/tables/{tid}/fields")
        if rows != old_tables[tid]["records"] or fields != old_tables[tid]["fields"]:
            raise ValueError("审阅库发生并发编辑，停止覆盖：" + tid)
    for key in source_keys:
        s = old_sheets[key]
        values = api(f'sheets/v2/spreadsheets/{s["token"]}/values/{s["range"]}')["valueRange"]["values"]
        if values != s["values"]:
            raise ValueError("源表发生并发编辑，停止覆盖：" + s["meta"]["title"])
    journal = []
    term_id = plan["term_record"]
    if term_id:
        api(f'bitable/v1/apps/{BASE}/tables/{plan["term_table"]}/records/{term_id}', "PUT", {"fields": plan["term_fields"]})
    else:
        term_id = api(f'bitable/v1/apps/{BASE}/tables/{plan["term_table"]}/records', "POST", {"fields": plan["term_fields"]})["record"]["record_id"]
    journal.append({"term_id": term_id})
    write_json(folder / "journal.json", journal)
    for token in sorted({c["token"] for c in plan["source_cells"]}):
        cells = [c for c in plan["source_cells"] if c["token"] == token]
        api(f"sheets/v2/spreadsheets/{token}/values_batch_update", "POST", {"valueRanges": [{"range": f'{c["sid"]}!{c["address"]}:{c["address"]}', "values": [[c["after"]]]} for c in cells]})
        journal.append({"source_token": token, "cells": len(cells)})
        write_json(folder / "journal.json", journal)
    updates = copy.deepcopy(plan["updates"])
    for u in updates:
        if "标准词条" in u["fields"]:
            u["fields"]["标准词条"] = [term_id if rid == "$ZEAL" else rid for rid in u["fields"]["标准词条"]]
    for tid in sorted({u["table"] for u in updates}):
        records = [{"record_id": u["record_id"], "fields": u["fields"]} for u in updates if u["table"] == tid]
        api(f"bitable/v1/apps/{BASE}/tables/{tid}/records/batch_update", "POST", {"records": records})
        journal.append({"table": tid, "records": len(records)})
        write_json(folder / "journal.json", journal)
    after_tables, after_sheets = {}, {}
    for tid in table_ids:
        rows = items(f"bitable/v1/apps/{BASE}/tables/{tid}/records")
        after_tables[tid] = rows
        by_id = {r["record_id"]: r["fields"] for r in rows}
        for old in old_tables[tid]["records"]:
            expected = copy.deepcopy(old["fields"])
            for u in updates:
                if u["table"] == tid and u["record_id"] == old["record_id"]:
                    expected.update(u["fields"])
            if old["record_id"] == term_id:
                expected.update(plan["term_fields"])
            actual = by_id[old["record_id"]]
            for key in set(expected) | set(actual):
                if normalized(key, expected.get(key)) != normalized(key, actual.get(key)):
                    raise ValueError(f"审阅字段读回不一致：{tid}/{old['record_id']}/{key}")
        if tid == plan["term_table"]:
            if any(by_id[term_id].get(k) != v for k, v in plan["term_fields"].items()):
                raise ValueError("热诚定义读回不一致")
        if items(f"bitable/v1/apps/{BASE}/tables/{tid}/fields") != old_tables[tid]["fields"]:
            raise ValueError("字段属性发生变化")
    for key in source_keys:
        s = old_sheets[key]
        after = api(f'sheets/v2/spreadsheets/{s["token"]}/values/{s["range"]}')["valueRange"]["values"]
        expected = copy.deepcopy(s["values"])
        for c in plan["source_cells"]:
            if (c["token"], c["sid"]) == key:
                match = re.fullmatch(r"([A-Z]+)(\d+)", c["address"])
                col = 0
                for ch in match[1]:
                    col = col * 26 + ord(ch) - 64
                expected[int(match[2]) - 1][col - 1] = c["after"]
        if after != expected:
            write_json(folder / (s["meta"]["sheet_id"] + "-unexpected.json"), after)
            raise ValueError("源表内容或富文本样式读回不一致：" + s["meta"]["title"])
        after_sheets[s["meta"]["sheet_id"]] = after
    # 行列、冻结、合并等结构不写入，读回确认保持原样。
    for token in {key[0] for key in source_keys}:
        metas = {m["sheet_id"]: m for m in api(f"sheets/v3/spreadsheets/{token}/sheets/query")["sheets"]}
        for key in source_keys:
            if key[0] == token and metas[key[1]] != old_sheets[key]["meta"]:
                raise ValueError("源表结构发生变化")
    write_json(folder / "after-tables.json", after_tables)
    write_json(folder / "after-sheets.json", after_sheets)
    result = {"verified": True, "source_cells": len(plan["source_cells"]), "updated_records": len(updates), "term_id": term_id, "other_fields_unchanged": True, "rich_text_preserved": True}
    write_json(folder / "verified.json", result)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    if sys.argv[1] == "snapshot":
        snapshot()
    elif sys.argv[1] == "plan":
        make_plan(sys.argv[2], "--include-extra" in sys.argv)
    elif sys.argv[1] == "apply":
        apply_plan(sys.argv[2])
