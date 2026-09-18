"""本轮确认同步：源表只读，多维表定向更新，备份后清理无关联的重复记录。"""
import runpy
from pathlib import Path
import json

m = runpy.run_path(str(Path(__file__).with_name('sync_rules_review_20260911.py')))
m['api'].__globals__['bridge'] = runpy.run_path(m['BRIDGE'])
base, api, items, flat = m['BASE'], m['api'], m['items'], m['flat']
root = Path('/private/tmp/project-card-review-20260912')
root.mkdir(exist_ok=True)
def save(name, data):
    (root / name).write_text(json.dumps(data, ensure_ascii=False, indent=2))
def records(tid):
    return items(f'bitable/v1/apps/{base}/tables/{tid}/records')
tables = items(f'bitable/v1/apps/{base}/tables')
allrows = {t['table_id']: records(t['table_id']) for t in tables}
save('before.json', allrows)
em, sup, hero, term = 'tblTf0rd7VJC95li', 'tblIwlBuC5p46saI', 'tblUA6BV5udW6ggK', 'tblx7PuFx6SCvjqX'
changes, creates = [], []
def update(tid, row, fields):
    changes.append({'table':tid,'record_id':row['record_id'],'fields':fields})
def named(tid, name):
    return next(r for r in allrows[tid] if r['fields'].get('名称',r['fields'].get('词条')) == name)
rules = {
 '四叶草Ⅲ':('每枚每场仅首次致命时投掷一次，失败也耗次，复活不重置；多枚独立次数。添加效果按先添加后添加尝试，成功免死则不消耗后续效果。英雄→自身→添加→其他的优先级沿用。',None),
 '种子':('实际参战、全场未死亡、战后未遮挡才累计。进度随该枚种子保留，取下、转移、堆叠与拆队不清零；第3场有效战斗结束后原槽自动进化为树，无需操作和材料。',None),
 '树':('由种子累计3场有效战斗后在原槽自动进化，不消耗材料。',None),
 '晶体化':('0护甲时再受伤不重复触发。临时额外生命转换的护甲加成随原效果到期移除，不成为永久加成。', '主动移除护甲或属性降低导致归零，是否触发晶体化转换？本轮仅明确0护甲再受伤不重复触发。')}
for name,(detail,q) in rules.items():
    r=named(em,name); f=r['fields']
    note=(f.get('备注') or '')+'\n'+detail
    update(em,r,{'备注':note,'规范描述':f['原始描述']+'\n规则：'+note,'待确认事项':q,'审阅状态':'初版待确认' if q else '已整理'})
for name,detail in [('纹章合成','材料累计成长清除，结果按全新状态生成，例外由配方说明。'),('特效触发优先级','同属添加效果按添加时间先后尝试，不按槽位；成功免死后不消耗后续效果。')]:
    r=named(term,name); update(term,r,{'默认边界':r['fields']['默认边界']+' '+detail})
src=api('sheets/v2/spreadsheets/PEHqshuiDhAZIJtvaAOcbmQUn4g/values/a69hE4!A1:E20')['valueRange']['values']
io=api('sheets/v2/spreadsheets/GnWksdURnhjz9ntKHC9chvd7nrh/values/fa884e!C2:C2')['valueRange']['values'][0][0]
save('source.json',{'indicators':src,'io':io})
update(hero,named(hero,'伊奥恩·沃登'),{'原始描述':flat(io)})
terms={r['fields']['词条']:r['record_id'] for r in allrows[term]}
for i,row in enumerate(src,1):
    if i<3 or not row[2]: continue
    name,raw,note=flat(row[2]),flat(row[3]),flat(row[4])
    q={'月亮':'护甲+8是否为基础加成、影蔽重新获得的计时边界待确认。','星星':'遗愿传递的新星星是否继续具有传播遗愿、数值增益如何叠加待确认。','血鸦':'同名随从与本指示物分开；最低生命值平局选择规则待确认。','福金':'属性增减持续时间、负数下限及无合法目标时处理待确认。','雾尼':'纹章施加对象、符文目标范围、遮蔽持续时间及无合法目标时处理待确认。'}.get(name)
    detail='指示物而非纹章，不占纹章槽。'+note
    if name=='太阳': detail+='影响敌我双方；所有太阳携带者保留耀眼，其他单位失去耀眼。'
    fields={'名称':name,'内容类型':'指示物','原始描述':raw,'规范描述':raw+'\n规则：'+detail,'来源':f'纹章和伤势/指示物!C{i}:E{i}','标准词条':[terms[w] for w in ['指示物','耀眼','遗愿','影蔽','护甲'] if w=='指示物' or w in raw],'审阅状态':'初版待确认' if q else '已整理','待确认事项':q}
    matches=[r for r in allrows[sup] if r['fields'].get('名称')==name and r['fields'].get('内容类型')=='指示物']
    if matches: update(sup,matches[0],fields)
    else: creates.append({'fields':fields})
# 删除前扫描所有表中的关联；有引用则保留并报告，不制造悬空关系。
deletes=[]; blocked=[]
for name in ['太阳','月亮','星星','圆盾']:
    r=named(em,name); rid=r['record_id']
    refs=[]
    for tid,rows in allrows.items():
        for other in rows:
            for key,val in other['fields'].items():
                if isinstance(val,list) and any(isinstance(v,dict) and rid in (v.get('record_ids') or []) for v in val): refs.append((tid,other['record_id'],key))
    if refs: blocked.append({'name':name,'references':refs})
    else: deletes.append(rid)
save('plan.json',{'updates':changes,'creates':creates,'deletes':deletes,'blocked':blocked})
# 修改前核对受影响字段，避免覆盖读取后用户刚修改的内容。
for tid in set(c['table'] for c in changes):
    now={r['record_id']:r for r in records(tid)}
    old={r['record_id']:r for r in allrows[tid]}
    for c in [x for x in changes if x['table']==tid]:
        assert all(now[c['record_id']]['fields'].get(k)==old[c['record_id']]['fields'].get(k) for k in c['fields']), '记录已变更，停止覆盖'
    api(f'bitable/v1/apps/{base}/tables/{tid}/records/batch_update','POST',{'records':[{'record_id':c['record_id'],'fields':c['fields']} for c in changes if c['table']==tid]})
if creates:
    out=api(f'bitable/v1/apps/{base}/tables/{sup}/records/batch_create','POST',{'records':creates})
    save('created.json',out)
    for want,got in zip(creates,out['records']): changes.append({'table':sup,'record_id':got['record_id'],'fields':want['fields']})
if deletes: api(f'bitable/v1/apps/{base}/tables/{em}/records/batch_delete','POST',{'records':deletes})
after={tid:{r['record_id']:r for r in records(tid)} for tid in {c['table'] for c in changes}|{em}}
for c in changes:
    for k,v in c['fields'].items():
        got=after[c['table']][c['record_id']]['fields'].get(k)
        if isinstance(v,list): got=[x for part in (got or []) for x in (part.get('record_ids') or [])]
        assert got==v,(c['record_id'],k)
assert all(rid not in after[em] for rid in deletes)
result={'updates':len(changes)-len(creates),'creates':len(creates),'deletes':len(deletes),'blocked':blocked,'verified':True,'source_writes':0}
save('verified.json',result)
print(json.dumps(result,ensure_ascii=False))
