"""集中同步已确认规则；源表只读，既有字段及人工确认内容不改。"""
import runpy, json
from pathlib import Path
m=runpy.run_path(str(Path(__file__).with_name('sync_rules_review_20260911.py')))
m['api'].__globals__['bridge']=runpy.run_path(m['BRIDGE'])
api,items,base,flat=m['api'],m['items'],m['BASE'],m['flat']
root=Path('/private/tmp/project-card-confirmed-roundup');root.mkdir(exist_ok=True)
def save(n,d): (root/n).write_text(json.dumps(d,ensure_ascii=False,indent=2))
def rows(t): return items(f'bitable/v1/apps/{base}/tables/{t}/records')
sup,term,em='tblIwlBuC5p46saI','tblx7PuFx6SCvjqX','tblTf0rd7VJC95li'
before={t:rows(t) for t in [sup,term,em]};save('before.json',before)
doc=Path(__file__).resolve().parents[1].joinpath('GAMEPLAY_DESIGN.md').read_text()
def section(title): return doc.split('### '+title+'\n',1)[1].split('\n### ',1)[0].strip()
ind=section('指示物的持续、目标与转移')
notes={
 '太阳':'影响敌我双方，所有太阳携带者保留耀眼，其他单位失去耀眼。仅附着随从；战后保留。',
 '月亮':'基础护甲+8，移除时失去加成，战后保留。发射弹道开始固定3秒计时，期间行动不刷新，到期重新获得影蔽。',
 '星星':'完整星星仅向无同名星星的友军转移，可继续传播；接收者自带数值+1，另得本场+1，合计+2。战后按快照回到原持有者和位置；传播到召唤物亦然。',
 '注视':'按当前生命绝对值最低、目标优先级更低、纯随机依次选另一个友军。注视战后消失。',
 '福金':'置于半场区域，可与雾尼共存。数值增减可累计，仅本场有效，下限0。首次战斗计时4秒触发；无合法目标跳过后仍等待完整周期。指示物本身战后保留。',
 '雾尼':'置于半场区域，可与福金共存。先选友军再随机效果；失败先尝试另一效果，两者均失败才换目标，全部不可执行才跳过。纹章直接贴空槽。临时纹章和刮开状态战后还原，符文内容不重抽；临时纹章赋予卡牌的永久成长保留，自身进度不保留。敌方只选择未遮蔽纹章或符文，本场有效。首次5秒，跳过仍等待完整周期；指示物本身保留。',
 '哨位':'部署时容量5+英雄等级；同一区域最多一枚。已部署哨位战后销毁，库存保留，不适用其他指示物的战后保留规则。'}
src=api('sheets/v2/spreadsheets/PEHqshuiDhAZIJtvaAOcbmQUn4g/values/a69hE4!A1:E20')['valueRange']['values']
sources={flat(r[2]):flat(r[3]) for r in src[2:] if r[2]}
updates=[]
for r in before[sup]:
 f=r['fields'];n=f.get('名称')
 if f.get('内容类型')=='指示物' and n in notes:
  updates.append((sup,r,{'原始描述':sources[n],'规范描述':sources[n]+'\n规则：'+notes[n],'待确认事项':None,'审阅状态':'已整理'}))
mapping={'指示物':ind,'永久':section('战前快照与永久变化结算'),'装备':'堆叠只有一件则保留为小队装备，多件全部退回收藏；拆队统一退回收藏。直接修正小队属性，无需装备单卡提供对应属性。准备阶段免费卸下，战斗中不可手动卸下。准备属性变化重算并补满生命护甲。','纹章':'附加到战斗卡牌时随机选未遮挡合法空槽，无槽失败；工作包奖励另算。临时纹章占槽，被动立即生效，不补战吼；自动合成暂不设计。','伤势':'只考虑未遮挡槽，先填空槽再升级；满且均不可升级则不生效不替换。伤势改变生存条件导致死亡正常进入死亡流程，无伤害来源死亡不触发施加者荣耀。','基础生命值':'成长同时增加当前生命；空白生命只加上限。上限降低只降上限，不扣当前生命，因此当前生命可暂时高于新上限；不算伤害受击、不消耗保护。晶体化把两种新增生命都转护甲，治疗仍恢复生命。','护甲':'永久基础护甲成长立即增加当前护甲，晶体化同样处理。','万能元素':'持有时排除，移除后恢复获得资格；不限制整局获得次数。无法发放唯一奖励时用预设替代奖励或不生成事件。'}
marker='\n本轮已确认补充：\n'
for r in before[term]:
 n=r['fields']['词条']
 if n in mapping:
  old=r['fields'].get('默认边界') or ''
  updates.append((term,r,{'默认边界':old.split(marker)[0]+marker+mapping[n]}))
cr=api('sheets/v2/spreadsheets/PEHqshuiDhAZIJtvaAOcbmQUn4g/values/kw9esj!N32:P32')['valueRange']['values'][0]
for r in before[em]:
 n=r['fields']['名称'];f=r['fields']
 if n=='晶体化':
  detail='由小队生命和护甲生效卡承担，不分别触发。主动移除、属性降低归零也触发；0护甲不重复触发。新增生命与空白生命均转护甲，治疗不转换。护甲成长立即增加当前护甲；上限下降只降上限，不扣当前生命。临时生命转换加成到期移除。'
  updates.append((em,r,{'原始描述':flat(cr[1]),'备注':flat(cr[2])+'\n'+detail,'规范描述':flat(cr[1])+'\n规则：'+detail}))
save('plan.json',[{'table':t,'record_id':r['record_id'],'fields':f} for t,r,f in updates])
for t in [sup,term,em]:
 current={r['record_id']:r for r in rows(t)}
 batch=[]
 for tid,r,f in updates:
  if tid!=t: continue
  assert all(current[r['record_id']]['fields'].get(k)==r['fields'].get(k) for k in f),'并发变更，停止覆盖'
  batch.append({'record_id':r['record_id'],'fields':f})
 if batch: api(f'bitable/v1/apps/{base}/tables/{t}/records/batch_update','POST',{'records':batch})
after={t:{r['record_id']:r for r in rows(t)} for t in [sup,term,em]}
for t,r,f in updates: assert all(after[t][r['record_id']]['fields'].get(k)==v for k,v in f.items())
save('verified.json',{'updates':len(updates),'source_writes':0,'verified':True})
print('读回验证通过：更新'+str(len(updates))+'条，源表写入0处。')
