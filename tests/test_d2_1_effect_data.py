"""真实卡包数据及纯序列化单元测试；不模拟网络服务。"""
import copy
import runpy
import unittest
from pathlib import Path

MODULE = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/sync_demo2_d2_1_effect_samples.py"))


class EffectDataTest(unittest.TestCase):
    def setUp(self):
        self.data = MODULE["read_samples"]()

    def test_pack_counts(self):
        result = MODULE["validate"](self.data)
        self.assertEqual((result["cards"], result["effects"], result["disabled_cards"]), (30, 38, 1))

    def test_serialization_roundtrip(self):
        entries = MODULE["entries"](self.data)
        ids = {x["effect"]["effect_id"]: f"record_{i}" for i, x in enumerate(entries)}
        records = [{"record_id": ids[x["effect"]["effect_id"]],
                    "fields": MODULE["effect_record_fields"](x, ids)} for x in entries]
        self.assertEqual(MODULE["export_records"](self.data, records), self.data)

    def test_invalid_data_rejected(self):
        changes = [
            lambda d: d["cards"].append(copy.deepcopy(d["cards"][0])),
            lambda d: d["cards"][0]["effects"][0].update(trigger="unknown"),
            lambda d: d["cards"][0]["effects"][0].update(end_conditions=["未知"]),
            lambda d: d["cards"][0]["effects"][0].update(review_status="confirmed", questions=["尚未确认的测试规则"]),
            lambda d: d["cards"][0]["effects"][0].update(related_effects=[{"effect_id": "missing", "relation": "after_step"}]),
        ]
        for change in changes:
            with self.subTest(change=change):
                data = copy.deepcopy(self.data)
                change(data)
                with self.assertRaises(ValueError):
                    MODULE["validate"](data)

    def test_wolf_does_not_exclude_all_modifiers(self):
        wolf = self.data["cards"][0]["effects"][0]
        self.assertEqual(wolf["modifier"]["filter"]["exclude_modifier_modes"], ["extra_execution"])
        self.assertFalse(wolf["modifier"]["recursive"])

    def test_confirmed_september_15_rules(self):
        effects = {e["effect_id"]: e for c in self.data["cards"] for e in c["effects"]}
        diplomat = effects["diplomat.effect.01"]
        self.assertNotIn("diplomat.effect.02", effects)
        self.assertEqual(diplomat["trigger"], "continuous")
        self.assertIn("target_is_non_elf", diplomat["conditions"])
        self.assertEqual(diplomat["value"], {"kind": "fixed", "amount": 1})
        for eid in ["diplomat.effect.01", "militia_commander.effect.02", "rally_horn.effect.01"]:
            self.assertEqual(effects[eid]["stacking"]["kind"], "additive")
        for eid, value in [("rally_horn.effect.01", 4), ("anvil_margaret.effect.02", -4)]:
            self.assertEqual(effects[eid]["operation"], "add_zeal")
            self.assertEqual(effects[eid]["value"]["amount"], value)
            self.assertNotIn("cooldown_order", effects[eid]["parameters"])
        for eid, seconds in [("return_to_battlefield.effect.01", 15), ("volley_order.effect.01", 8)]:
            params = effects[eid]["parameters"]
            self.assertEqual(params["at_seconds"], seconds)
            self.assertEqual(params["multiple_copy_schedule"], "same_battle_timestamp")
            self.assertEqual(params["on_no_target"], "consume_attempt")
            self.assertFalse(params["retry"])


if __name__ == "__main__":
    unittest.main()
