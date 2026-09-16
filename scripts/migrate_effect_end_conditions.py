"""原位迁移结束条件列，备份旧值并验证未修改其他内容。"""
import json
import runpy
from pathlib import Path

m = runpy.run_path(str(Path(__file__).with_name('sync_demo2_d2_1_effect_samples.py')))
tid = 'tblee6ATGioYRrDu'
prefix = f"bitable/v1/apps/{m['BASE']}/tables/{tid}"
fields, records = m['read_fields'](tid), m['read_records'](tid)
backup = Path('/private/tmp/project-card-end-conditions-before.json')
assert not backup.exists(), '已有迁移备份，请先核对上次状态'
backup.write_text(json.dumps({'fields': fields, 'records': records}, ensure_ascii=False, indent=2))
by_name = {f['field_name']: f for f in fields}
assert by_name['结束条件']['type'] == 1
mapping = {'行动消耗强化或战后清理': ['指定行动后', '战斗结束'], '本局结束': ['本局结束'], '施加后经过5秒': ['持续时间到期'], '操作结算完成': ['操作结算完成']}
effects = {e['effect_id']: e for c in m['read_samples']()['cards'] for e in c['effects']}
batch = []
for r in records:
    e = effects[r['fields']['效果ID']]
    assert mapping[r['fields']['结束条件']] == e['end_conditions']
    batch.append({'record_id': r['record_id'], 'fields': {'结束条件': e['end_conditions'], '结束条件关系': e['end_relation'], '结束参数': e['end_parameters']}})
assert m['read_records'](tid) == records, '出现并发修改'
definitions = {f['field_name']: f for f in m['effect_field_definitions']()}
m['api'](prefix + '/fields/' + by_name['结束条件']['field_id'], 'PUT', definitions['结束条件'])
for name in ['结束条件关系', '结束参数']:
    m['ensure_field'](tid, definitions[name])
m['api'](prefix + '/records/batch_update', 'POST', {'records': batch})
after_fields = {f['field_id']: f for f in m['read_fields'](tid)}
for f in fields:
    g = after_fields[f['field_id']]
    if f['field_name'] == '结束条件':
        assert g['type'] == 4
        assert [o['name'] for o in g['property']['options']] == m['END_CONDITIONS']
    else:
        assert (f['field_name'], f['type'], f.get('property')) == (g['field_name'], g['type'], g.get('property'))
after = {r['record_id']: r['fields'] for r in m['read_records'](tid)}
for r, change in zip(records, batch):
    got = after[r['record_id']]
    for k, v in change['fields'].items():
        assert got.get(k) == v, (r['record_id'], k)
    for k, v in r['fields'].items():
        if k != '结束条件':
            assert got.get(k) == v, (r['record_id'], k)
print('迁移验证通过：6条记录；原字段ID保留；其他原字段及内容保留。')
