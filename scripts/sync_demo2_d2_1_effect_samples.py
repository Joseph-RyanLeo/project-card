"""D2-1 效果数据：离线校验、飞书计划同步、关联导出。只操作审阅库。"""
import hashlib
import json
import re
import runpy
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE_PATH = ROOT / "data/demo2/ash_ledger_effect_samples.json"
BASE = "IcuQbyEQtaPWPgsOOOrcu5shnKh"
CARD_TABLE = "tbl6qIMmgLoYgMpX"
TERM_TABLE = "tblx7PuFx6SCvjqX"
EFFECT_TABLE_NAME = "效果定义"
CARD_ID_FIELD = "稳定卡牌ID"
PLAN_PATH = Path("/private/tmp/project-card-d2-1-effect-plan.json")
VERIFIED_PATH = Path("/private/tmp/project-card-d2-1-effect-verified.json")
_bridge_api = None

TRIGGERS = {
    "continuous": "持续检查", "armor_gain_before_apply": "获得护甲量写入前",
    "rush": "突击", "last_wish": "遗愿", "pending": "待确认",
    "source_health_lost_accumulated": "自身累计失去生命", "source_armor_gained": "自身获得护甲时",
    "after_basic_heal": "基础治疗完成后", "echo": "回响", "other_ally_action_after": "其他友军行动后",
    "adjacent_ally_destroyed": "相邻友军被消灭", "other_ally_destroyed": "其他友军被消灭",
    "ally_about_to_be_destroyed": "友军即将被消灭", "battle_start_spell": "开场法术",
    "elapsed_battle_time": "战斗计时到达指定时刻",
    "equipped_unit_after_basic_action_damage": "装备者受到基础行动伤害后", "battle_won": "战斗获胜后",
}
CONDITIONS = {
    "target_is_non_elf": "目标为非精灵",
    "source_effect_active": "来源效果可用", "target_has_armor": "目标当前有护甲",
    "always": "无额外条件", "target_is_human": "目标为人类",
    "accumulated_health_loss_at_least_value": "累计失去生命达到阈值",
    "per_battle_count_below_limit": "每场次数未达上限", "neighbor_active": "乡邻生效",
    "not_same_effect_generated_gain": "不是本效果产生的额外护甲",
    "target_has_active_injury": "目标有生效伤势", "event_actor_is_other_ally": "事件对象为其他友军",
    "dead_unit_not_derived": "死亡者非衍生", "destruction_caused_by_health_reaching_zero": "因生命归零即将被消灭",
    "has_granted_effect": "已被授予本效果", "legal_dead_target": "存在合法死亡目标",
    "summon_space_available": "存在召唤空间", "equipped_unit_alive": "装备者存活",
    "damage_source_exists": "伤害来源仍存在", "equipment_equipped": "装备仍被装备",
    "source_equipment_participated": "此装备实际参战",
}
TARGETS = {
    "friendly_neighbor_effects": "友方乡邻效果", "friendly_armor_gain_events": "友方护甲获得事件",
    "all_friendly_combat_units": "所有友方战斗单位", "source_combat_unit": "效果来源战斗单位",
    "source_card_instance": "效果来源单卡实例", "source_active_rune": "自身生效符文",
    "source_dead_card": "自身死亡卡牌", "owning_player": "持有者",
    "healed_target_active_injury": "治疗目标生效伤势", "same_row_friendly_units": "同排友军",
    "self_and_adjacent_human_units": "自身与相邻人类", "granted_effect_holder": "被授予效果的单位",
    "latest_dead_nonderived_ally": "最近死亡非衍生友军", "back_row_ranged_allies": "后排远程友军",
    "equipped_unit": "装备者", "damage_source": "伤害来源", "adjacent_friendly_units": "相邻友军",
    "equipped_unit_injuries": "装备者伤势", "source_equipment": "来源装备",
}
OPERATIONS = {
    "add_zeal": "增减热诚",
    "add_cooldown_speed": "增加冷却速度",
    "modify_effect": "修改效果", "add_cooldown_seconds": "增加冷却秒数", "add_reinforcement": "获得强化",
    "forbid_stacking": "禁止堆叠", "mask_rune": "遮蔽符文", "revive": "重新入场",
    "add_action_multiplier": "增加行动倍率", "add_attribute": "增加属性", "grant_random_card": "随机获得卡牌",
    "permanently_add_base_value": "永久增加基础数值", "gain_armor": "获得护甲", "mask_injury": "遮蔽伤势",
    "permanently_add_armor": "永久增加基础护甲", "gain_gold": "获得金币", "immediate_action": "立即行动",
    "set_action_type": "设置行动方式", "add_target_priority": "修改受击优先级",
    "set_minimum_health": "设置生命下限", "grant_effect": "授予效果", "grant_keyword": "获得关键词",
    "deal_non_action_damage": "造成非行动伤害", "multiply_cooldown": "冷却乘倍率", "consume_equipment": "消耗装备",
}
DURATIONS = {"while_active": "条件成立期间", "instant": "瞬时", "until_consumed_by_action": "直到行动消耗",
             "battle": "本场", "pending": "待确认", "current_run_permanent": "本局永久", "seconds": "固定秒数"}
STACKING = {"additive": "数值相加", "same_name_nonstacking": "同名不叠加", "pending": "待确认",
            "not_applicable": "不适用", "refresh_duration": "刷新持续时间", "capped_additive": "有上限相加",
            "independent_by_source": "按来源独立"}
OWNERS = {"minion_card_instance": "随从卡实例", "spell_card_instance": "法术卡实例",
          "equipment_instance": "装备实例", "affected_combat_unit": "受影响战斗单位",
          "source_combat_unit": "效果来源战斗单位", "owning_player": "持有者",
          "action_provider_card": "行动数值提供单卡", "armor_provider_card": "护甲提供单卡",
          "actual_recipient_card_instance": "实际获得变化的单卡实例", "damage_source": "伤害来源"}
END_CONDITIONS = ["操作结算完成", "持续时间到期", "指定行动后", "来源死亡", "装备卸下", "乡邻失效",
                  "战斗结束", "本局结束", "来源效果失效", "条件不再满足", "装备消耗", "待确认"]
MODES = {"none": "无", "extra_execution": "额外执行", "multiply_value": "乘数值", "add_value": "加数值"}
TAGS = ["乡邻", "回响", "获得护甲", "效果修改"]
RELATIONS = {"after_step", "grant", "granted_by"}
NUMBER_FIELDS = {"效果序号"}
MULTI_FIELDS = {"条件", "结束条件", "效果标签"}
LINK_FIELDS = {"卡牌关联", "关联效果"}

def api(path, method="GET", body=None):
    # 凭据只在首次联网时由既有桥接获取，不输出，也不让离线校验联网。
    global _bridge_api
    if not path.startswith(f"bitable/v1/apps/{BASE}/"):
        raise ValueError("本工具只允许访问已授权审阅库")
    if _bridge_api is None:
        module = runpy.run_path(str(ROOT / "scripts/sync_rules_review_20260911.py"))
        module["api"].__globals__["bridge"] = runpy.run_path(module["BRIDGE"])
        _bridge_api = module["api"]
    return _bridge_api(path, method, body)

def items(path):
    result, token = [], None
    while True:
        query = path + ("&" if "?" in path else "?") + "page_size=100"
        if token:
            query += "&page_token=" + token
        data = api(query)
        result.extend(data.get("items") or [])
        if not data.get("has_more"):
            return result
        token = data["page_token"]

def read_tables():
    return items(f"bitable/v1/apps/{BASE}/tables")

def read_fields(tid):
    return items(f"bitable/v1/apps/{BASE}/tables/{tid}/fields")

def read_records(tid):
    return items(f"bitable/v1/apps/{BASE}/tables/{tid}/records")

def find_table(name):
    matches = [t for t in read_tables() if t["name"] == name]
    if len(matches) != 1:
        raise ValueError(f"预期唯一既有效果表：{name}")
    return matches[0]

def option_property(values):
    return {"options": [{"name": value, "color": i % 11} for i, value in enumerate(values)]}

def effect_field_definitions(tid=None):
    definitions = [
        ("效果ID", 1, None), ("卡牌关联", 18, {"table_id": CARD_TABLE, "multiple": False}),
        ("效果序号", 2, {"formatter": "0"}), ("触发", 3, option_property(TRIGGERS.values())),
        ("条件", 4, option_property(CONDITIONS.values())), ("目标", 3, option_property(TARGETS.values())),
        ("操作", 3, option_property(OPERATIONS.values())), ("数值", 1, None),
        ("持续", 3, option_property(DURATIONS.values())), ("持续参数", 1, None),
        ("叠加", 3, option_property(STACKING.values())), ("来源归属", 3, option_property(OWNERS.values())),
        ("结果归属", 3, option_property(OWNERS.values())), ("参数JSON", 1, None),
        ("完整说明快照", 1, None), ("审阅状态", 3, option_property(["已确认", "待确认"])),
        ("中文解读", 1, None), ("效果组", 1, None), ("结束条件", 4, option_property(END_CONDITIONS)),
        ("结束操作", 1, None), ("触发次数限制", 1, None),
        ("结束条件关系", 3, option_property(["任一满足", "全部满足"])), ("结束参数", 1, None),
        ("效果标签", 4, option_property(TAGS)), ("修改方式", 3, option_property(MODES.values())),
        ("修改参数", 1, None), ("待确认事项", 1, None),
    ]
    if tid:
        definitions.append(("关联效果", 18, {"table_id": tid, "multiple": True}))
    return [{"field_name": n, "type": t, **({"property": p} if p is not None else {})} for n, t, p in definitions]

def normalize_link(value):
    result = []
    for part in value or []:
        result.extend([part] if isinstance(part, str) else part.get("record_ids") or [])
    return sorted(result)

def normalized(key, value):
    if key in LINK_FIELDS:
        return normalize_link(value)
    if key in MULTI_FIELDS:
        return sorted(value or [])
    if key in NUMBER_FIELDS and value is not None:
        return int(value)
    return None if value == "" else value

def same_fields(a, b):
    return all(normalized(k, a.get(k)) == normalized(k, b.get(k)) for k in set(a) | set(b))

def validate(data):
    if data.get("schema_version") != 2:
        raise ValueError("需要schema_version=2")
    cards, effects, source_ids = {}, {}, set()
    for c in data["cards"]:
        cid = c["card_id"]
        if not re.fullmatch(r"[a-z][a-z0-9_]*", cid) or cid in cards or c["source_record_id"] in source_ids:
            raise ValueError("重复或非法卡牌身份")
        cards[cid] = c
        source_ids.add(c["source_record_id"])
        if c["availability"] == "disabled" and c["effects"]:
            raise ValueError("停用卡不能输出旧效果")
        path = c.get("resource_path")
        if path:
            text = (ROOT / path.removeprefix("res://")).read_text()
            if f'id = &"{cid}"' not in text:
                raise ValueError(f"本地资源ID不匹配：{cid}")
        for e in c["effects"]:
            eid = e["effect_id"]
            if eid in effects or not re.fullmatch(re.escape(cid) + r"\.effect\.\d{2}", eid):
                raise ValueError("重复或非法效果ID")
            effects[eid] = e
            for key, vocabulary in [("trigger", TRIGGERS), ("target", TARGETS), ("operation", OPERATIONS),
                                    ("source_owner", OWNERS), ("result_owner", OWNERS)]:
                if e[key] not in vocabulary:
                    raise ValueError(f"未知枚举：{eid}/{key}")
            if not e["conditions"] or any(v not in CONDITIONS for v in e["conditions"]):
                raise ValueError("非法条件")
            if "always" in e["conditions"] and len(e["conditions"]) > 1:
                raise ValueError("无额外条件不能与其他条件混用")
            if e["duration"]["kind"] not in DURATIONS or e["stacking"]["kind"] not in STACKING:
                raise ValueError("非法持续或叠加")
            if not e["end_conditions"] or set(e["end_conditions"]) - set(END_CONDITIONS):
                raise ValueError("非法结束条件")
            if e["end_relation"] not in ("任一满足", "全部满足") or set(e["tags"]) - set(TAGS):
                raise ValueError("非法关系或标签")
            if e["review_status"] not in ("confirmed", "pending"):
                raise ValueError("非法审阅状态")
            if e["review_status"] == "confirmed" and (e["questions"] or c["review_status"] != "confirmed"):
                raise ValueError("未决规则不能标成已确认")
            if e["duration"]["kind"] == "seconds" and e["duration"]["amount"] <= 0:
                raise ValueError("持续秒数必须为正")
            if e["modifier"] and (e["modifier"]["mode"] not in MODES or e["operation"] != "modify_effect"):
                raise ValueError("修改方式与操作不匹配")
            if e["operation"] == "modify_effect" and not e["modifier"]:
                raise ValueError("修改效果缺少筛选与修改参数")
            if e["duration"]["kind"] == "current_run_permanent" and e["result_owner"] not in ("action_provider_card", "armor_provider_card"):
                raise ValueError("永久成长必须明确实际属性提供单卡")
            if not e["reading"] or not isinstance(e["value"], dict):
                raise ValueError("缺少人工说明或数值对象")
            if not e.get("end_operation"):
                raise ValueError("缺少结束操作")
            if e["operation"] == "add_zeal" and (e["value"].get("kind") != "fixed" or type(e["value"].get("amount")) is not int):
                raise ValueError("热诚必须使用整数层数")
    edges = {eid: [] for eid in effects}
    groups = {}
    for eid, e in effects.items():
        group = groups.setdefault(e["effect_group"], [])
        group.append(e["group_order"])
        for rel in e["related_effects"]:
            if rel["effect_id"] not in effects or rel["relation"] not in RELATIONS:
                raise ValueError("效果关联悬空或关系未知")
            if rel["effect_id"] == eid:
                raise ValueError("效果不得关联自身")
            if rel["relation"] == "after_step":
                prior = effects[rel["effect_id"]]
                if prior["effect_group"] != e["effect_group"] or prior["group_order"] >= e["group_order"]:
                    raise ValueError("步骤必须指向同组较早的效果")
                edges[eid].append(rel["effect_id"])
            elif rel["relation"] == "grant":
                if e["value"].get("effect_id") != rel["effect_id"]:
                    raise ValueError("授予效果引用不一致")
    if any(len(v) != len(set(v)) for v in groups.values()):
        raise ValueError("同组步骤重复")
    return {"cards": len(cards), "effects": len(effects),
            "disabled_cards": sum(c["availability"] == "disabled" for c in cards.values()),
            "confirmed_effects": sum(e["review_status"] == "confirmed" for e in effects.values()),
            "effects_with_questions": sum(bool(e["questions"]) for e in effects.values())}

def read_samples():
    data = json.loads(SAMPLE_PATH.read_text())
    validate(data)
    return data

def json_text(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

def limit_text(limit):
    scope, count = limit["scope"], limit.get("count")
    return {"continuous": "持续检查，不按次数发放", "pending": "待确认", "event": "每次合法事件执行一次",
            "battle": f"每场最多{count}次；重新入场不重置", "group_battle": f"同效果组每场共用{count}次",
            "settlement": "同一次战后结算只应用一次"}[scope]

def effect_record_fields(entry, effect_record_ids=None):
    c, e = entry["card"], entry["effect"]
    modifier = e["modifier"]
    fields = {
        "效果ID": e["effect_id"], "卡牌关联": [c["source_record_id"]], "效果序号": entry["index"],
        "触发": TRIGGERS[e["trigger"]], "条件": [CONDITIONS[v] for v in e["conditions"]],
        "目标": TARGETS[e["target"]], "操作": OPERATIONS[e["operation"]], "数值": json_text(e["value"]),
        "持续": DURATIONS[e["duration"]["kind"]], "持续参数": json_text(e["duration"]),
        "叠加": STACKING[e["stacking"]["kind"]], "来源归属": OWNERS[e["source_owner"]],
        "结果归属": OWNERS[e["result_owner"]],
        "参数JSON": json_text({k: e[k] for k in ["parameters", "group_order", "trigger_limit", "related_effects", "stacking"]}),
        "完整说明快照": c["source_fields"]["完整规则说明"],
        "审阅状态": "已确认" if e["review_status"] == "confirmed" else "待确认",
        "中文解读": e["reading"], "效果组": e["effect_group"], "结束条件": e["end_conditions"],
        "结束条件关系": e["end_relation"], "结束参数": e["end_parameters"], "结束操作": e["end_operation"],
        "触发次数限制": limit_text(e["trigger_limit"]), "效果标签": e["tags"] or None,
        "修改方式": MODES[modifier["mode"] if modifier else "none"], "修改参数": json_text(modifier),
        "待确认事项": "\n".join(e["questions"]) or None,
    }
    if effect_record_ids is not None:
        fields["关联效果"] = [effect_record_ids[r["effect_id"]] for r in e["related_effects"]] or None
    return fields

def entries(data):
    return [{"card": c, "index": i, "effect": e} for c in data["cards"] for i, e in enumerate(c["effects"], 1)]

def snapshot():
    tid = find_table(EFFECT_TABLE_NAME)["table_id"]
    return {"effect_table_id": tid, "card_fields": read_fields(CARD_TABLE), "card_records": read_records(CARD_TABLE),
            "effect_fields": read_fields(tid), "effect_records": read_records(tid)}

def ensure_field(tid, definition):
    existing = {f["field_name"]: f for f in read_fields(tid)}
    old = existing.get(definition["field_name"])
    if not old:
        return api(f"bitable/v1/apps/{BASE}/tables/{tid}/fields", "POST", definition)
    if old["type"] != definition["type"]:
        raise ValueError(f"字段类型变化需要单独迁移：{old['field_name']}")
    if old["type"] in (3, 4):
        options = (old.get("property") or {}).get("options", [])
        names = {o["name"] for o in options}
        additions = [o for o in definition["property"]["options"] if o["name"] not in names]
        if additions:
            body = {"field_name": old["field_name"], "type": old["type"], "property": {**old["property"], "options": options + additions}}
            return api(f"bitable/v1/apps/{BASE}/tables/{tid}/fields/{old['field_id']}", "PUT", body)
    return old

def build_plan():
    data = read_samples()
    before = snapshot()
    rows = {r["record_id"]: r["fields"] for r in before["card_records"]}
    for c in data["cards"]:
        actual = rows[c["source_record_id"]]
        # 改名不改变ID，但新文案需要先重新审阅，不能拿旧效果配新说明。
        for k, v in c["source_fields"].items():
            if k != CARD_ID_FIELD and actual.get(k) != v:
                raise ValueError(f"卡牌源字段在拆分后变化：{c['display_name']}/{k}")
        if actual.get(CARD_ID_FIELD) not in (None, c["card_id"]):
            raise ValueError("稳定卡牌ID冲突")
    ids = {}
    for r in before["card_records"]:
        cid = r["fields"].get(CARD_ID_FIELD)
        if cid:
            if cid in ids:
                raise ValueError("线上重复卡牌ID")
            ids[cid] = r["record_id"]
    for c in data["cards"]:
        if c["card_id"] in ids and ids[c["card_id"]] != c["source_record_id"]:
            raise ValueError("拟分配ID已被其他卡使用")
    folder = Path(tempfile.mkdtemp(prefix="project-card-d2-1-", dir="/private/tmp"))
    (folder / "before.json").write_text(json.dumps(before, ensure_ascii=False, indent=2))
    plan = {"data": data, "before": before, "sha256": hashlib.sha256(SAMPLE_PATH.read_bytes()).hexdigest(), "audit_dir": str(folder)}
    PLAN_PATH.write_text(json.dumps(plan, ensure_ascii=False, indent=2))
    (folder / "plan.json").write_text(PLAN_PATH.read_text())
    print(json.dumps({**validate(data), "audit_dir": str(folder), "source_writes": 0}, ensure_ascii=False))

def assert_unchanged(before, after):
    b = {r["record_id"]: r["fields"] for r in before}
    a = {r["record_id"]: r["fields"] for r in after}
    if set(a) != set(b) or any(not same_fields(b[r], a[r]) for r in b):
        raise ValueError("计划后发生并发编辑，停止覆盖")

def record_map(records):
    result = {}
    for r in records:
        eid = r["fields"].get("效果ID")
        if not eid:
            continue
        if eid in result:
            raise ValueError("线上重复效果ID")
        result[eid] = r
    return result

def apply_plan():
    plan = json.loads(PLAN_PATH.read_text())
    if hashlib.sha256(SAMPLE_PATH.read_bytes()).hexdigest() != plan["sha256"]:
        raise ValueError("本地数据改变，请重新生成计划")
    data, before = plan["data"], plan["before"]
    validate(data)
    retired = set(data.get("retired_effect_ids", []))
    if retired & {e["effect_id"] for c in data["cards"] for e in c["effects"]}:
        raise ValueError("退役效果仍在活动数据中")
    tid = before["effect_table_id"]
    assert_unchanged(before["card_records"], read_records(CARD_TABLE))
    assert_unchanged(before["effect_records"], read_records(tid))
    if before["effect_fields"] != read_fields(tid) or before["card_fields"] != read_fields(CARD_TABLE):
        raise ValueError("计划后字段结构被修改")
    # 添加枚举选项时保留既有选项ID、顺序和颜色。全程不调用视图写入接口。
    for f in effect_field_definitions(tid):
        ensure_field(tid, f)
    old_cards = {r["record_id"]: r["fields"] for r in before["card_records"]}
    card_batch = [{"record_id": c["source_record_id"], "fields": {CARD_ID_FIELD: c["card_id"]}}
                  for c in data["cards"] if old_cards[c["source_record_id"]].get(CARD_ID_FIELD) != c["card_id"]]
    old_effects = record_map(before["effect_records"])
    creates, updates = [], []
    for entry in entries(data):
        fields = effect_record_fields(entry)
        old = old_effects.get(fields["效果ID"])
        if not old:
            creates.append({"fields": fields})
        else:
            changed = {k: v for k, v in fields.items() if normalized(k, old["fields"].get(k)) != normalized(k, v)}
            if changed:
                updates.append({"record_id": old["record_id"], "fields": changed})
    # 创建字段后再次检查值，新增空列不视为改动。
    assert_unchanged(before["card_records"], read_records(CARD_TABLE))
    assert_unchanged(before["effect_records"], read_records(tid))
    for table, batch, route in [(CARD_TABLE, card_batch, "batch_update"), (tid, creates, "batch_create"), (tid, updates, "batch_update")]:
        if batch:
            api(f"bitable/v1/apps/{BASE}/tables/{table}/records/{route}", "POST", {"records": batch})
    # 创建完全部效果，再建立关联，以保证引用不悬空。
    current = record_map(read_records(tid))
    ids = {k: v["record_id"] for k, v in current.items()}
    links = []
    for entry in entries(data):
        fields = effect_record_fields(entry, ids)
        r = current[fields["效果ID"]]
        if normalized("关联效果", r["fields"].get("关联效果")) != normalized("关联效果", fields["关联效果"]):
            links.append({"record_id": r["record_id"], "fields": {"关联效果": fields["关联效果"]}})
    if links:
        api(f"bitable/v1/apps/{BASE}/tables/{tid}/records/batch_update", "POST", {"records": links})
    # 只删除数据中显式退役的ID；人工回复与完整记录已保存在本次计划备份。
    retired_records = [r["record_id"] for eid, r in current.items() if eid in retired]
    if retired_records:
        api(f"bitable/v1/apps/{BASE}/tables/{tid}/records/batch_delete", "POST", {"records": retired_records})
    result = verify(before=before)
    result.update(created_effects=len(creates), updated_effects=len(updates), linked_effects=len(links), assigned_card_ids=len(card_batch))
    (Path(plan["audit_dir"]) / "verified.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    VERIFIED_PATH.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps(result, ensure_ascii=False))

def verify(before=None):
    data = read_samples()
    tid = find_table(EFFECT_TABLE_NAME)["table_id"]
    field_list = read_fields(tid)
    fields = {f["field_name"]: f for f in field_list}
    for definition in effect_field_definitions(tid):
        f = fields[definition["field_name"]]
        if f["type"] != definition["type"]:
            raise ValueError("字段类型错误")
        if f["type"] in (3, 4):
            if {o["name"] for o in definition["property"]["options"]} - {o["name"] for o in f["property"]["options"]}:
                raise ValueError("缺少枚举选项")
        if f["type"] == 18 and (f["property"]["table_id"], f["property"]["multiple"]) != (definition["property"]["table_id"], definition["property"]["multiple"]):
            raise ValueError("关联字段指向错误")
    card_records = read_records(CARD_TABLE)
    cards = {r["record_id"]: r["fields"] for r in card_records}
    effect_records = read_records(tid)
    rows = record_map(effect_records)
    if set(data.get("retired_effect_ids", [])) & set(rows):
        raise ValueError("退役效果仍留在线上活动表")
    ids = {eid: r["record_id"] for eid, r in rows.items()}
    for c in data["cards"]:
        if cards[c["source_record_id"]].get(CARD_ID_FIELD) != c["card_id"]:
            raise ValueError("卡牌ID读回不一致")
    for entry in entries(data):
        expected = effect_record_fields(entry, ids)
        actual = rows[expected["效果ID"]]["fields"]
        for k, v in expected.items():
            if normalized(k, actual.get(k)) != normalized(k, v):
                raise ValueError(f"读回不一致：{expected['效果ID']}/{k}")
    if before:
        owned_columns = {f["field_name"] for f in effect_field_definitions(tid)}
        for old in before["effect_records"]:
            eid = old["fields"].get("效果ID")
            if eid in rows:
                for key, value in old["fields"].items():
                    if key not in owned_columns and rows[eid]["fields"].get(key) != value:
                        raise ValueError("人工回复等非同步列发生变化")
        after_by_id = {f["field_id"]: f for f in field_list}
        for old in before["effect_fields"]:
            new = after_by_id[old["field_id"]]
            if (old["field_name"], old["type"]) != (new["field_name"], new["type"]):
                raise ValueError("既有字段类型或名称改变")
            if old["type"] in (3, 4):
                if new["property"]["options"][:len(old["property"]["options"])] != old["property"]["options"]:
                    raise ValueError("既有选项ID、顺序或颜色改变")
            elif new.get("property") != old.get("property"):
                raise ValueError("既有字段属性改变")
        if read_fields(CARD_TABLE) != before["card_fields"]:
            raise ValueError("卡牌字段结构改变")
        for old in before["card_records"]:
            for k, v in old["fields"].items():
                if k != CARD_ID_FIELD and cards[old["record_id"]].get(k) != v:
                    raise ValueError("卡牌既有内容被改变")
    export = export_records(data, effect_records)
    if export != data:
        raise ValueError("关联导出往返不一致")
    return {**validate(data), "verified": True, "roundtrip": True, "source_writes": 0,
            "effect_table_id": tid, "runtime_implemented": False}

def export_records(data, records):
    # 从可选字段和参数反向构造效果，而不是拿本地JSON冒充线上导出。
    result = json.loads(json.dumps(data))
    rows = record_map(records)
    id_by_record = {r["record_id"]: eid for eid, r in rows.items()}
    reverse = lambda dic, v: {label: key for key, label in dic.items()}[v]
    for c in result["cards"]:
        restored = []
        for source in c["effects"]:
            f = rows[source["effect_id"]]["fields"]
            meta = json.loads(f["参数JSON"])
            e = dict(source)
            for key, col, vocabulary in [("trigger", "触发", TRIGGERS), ("target", "目标", TARGETS),
                                         ("operation", "操作", OPERATIONS), ("source_owner", "来源归属", OWNERS),
                                         ("result_owner", "结果归属", OWNERS)]:
                e[key] = reverse(vocabulary, f[col])
            e.update(meta)
            e["conditions"] = [reverse(CONDITIONS, v) for v in f["条件"]]
            e["value"] = json.loads(f["数值"])
            e["duration"] = json.loads(f["持续参数"])
            e["effect_group"] = f["效果组"]
            e["end_conditions"] = f["结束条件"]
            e["end_relation"] = f["结束条件关系"]
            e["end_parameters"] = f["结束参数"]
            e["end_operation"] = f["结束操作"]
            e["reading"] = f["中文解读"]
            e["tags"] = f.get("效果标签") or []
            e["modifier"] = json.loads(f["修改参数"])
            e["questions"] = (f.get("待确认事项") or "").splitlines()
            e["review_status"] = "confirmed" if f["审阅状态"] == "已确认" else "pending"
            link_ids = sorted(id_by_record[r] for r in normalize_link(f.get("关联效果")))
            if link_ids != sorted(r["effect_id"] for r in e["related_effects"]):
                raise ValueError("真实关联与关系参数不一致")
            # 多选字段顺序没有语义；恢复为本地明确展示顺序再比较。
            for key in ["conditions", "end_conditions", "tags"]:
                if sorted(e[key]) != sorted(source[key]):
                    raise ValueError("导出多选值变化")
                e[key] = source[key]
            restored.append(e)
        c["effects"] = restored
    validate(result)
    return result

if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "validate"
    if command == "validate":
        print(json.dumps(validate(read_samples()), ensure_ascii=False))
    elif command == "snapshot":
        directory = Path(tempfile.mkdtemp(prefix="project-card-d2-1-read-", dir="/private/tmp"))
        (directory / "snapshot.json").write_text(json.dumps(snapshot(), ensure_ascii=False, indent=2))
        print(directory)
    elif command == "plan":
        build_plan()
    elif command == "apply":
        apply_plan()
    elif command == "verify":
        print(json.dumps(verify(), ensure_ascii=False))
    elif command == "export":
        data = read_samples()
        tid = find_table(EFFECT_TABLE_NAME)["table_id"]
        exported = export_records(data, read_records(tid))
        output = Path("/private/tmp/project-card-d2-1-online-export.json")
        output.write_text(json.dumps(exported, ensure_ascii=False, indent=2))
        print(output)
    else:
        raise SystemExit("用法：validate | snapshot | plan | apply | verify | export")
