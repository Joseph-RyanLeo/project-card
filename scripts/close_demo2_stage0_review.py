"""依据人工确认收口；源表不写入，变更前备份、比较，变更后读回。"""
import json,runpy
from pathlib import Path
m=runpy.run_path(str(Path(__file__).with_name('sync_rules_review_20260911.py')))
m['api'].__globals__['bridge']=runpy.run_path(m['BRIDGE'])
a,items,b=m['api'],m['items'],m['BASE']
snap=json.loads(Path('/private/tmp/project-card-closure-snapshot.json').read_text())
card='tbl6qIMmgLoYgMpX'; talent='tblbdKWKbOdZa8xV'; em='tblTf0rd7VJC95li'
terms={r['fields']['词条']:r['record_id'] for r in items(f'bitable/v1/apps/{b}/tables/tblx7PuFx6SCvjqX/records')}
updates=[]
def change(t,r,f): updates.append({'table':t,'record_id':r['record_id'],'before':{k:r['fields'].get(k) for k in f},'fields':f})
# 短文、完整说明、仍需明确的实际问题；不擅自改动数值列。
rules={
'方阵长官':('此卡组成小队时相邻的小队数值提升30%。','此卡组成小队时，相邻友方小队基础数值提升30%；单兵不视为小队。',None),
'爆弹学徒':(None,'亡语在小队死亡结算、移除并腾出位置后触发，在原小队右侧召唤1张诡雷；不在消灭前触发。',None),
'铭文学者':(None,'回响：所有友方装备本场基础数值与护甲各+1，每件最多3次；没有装备的友军跳过。',None),
'矿石鉴定师':(None,'开采直接摧毁资源。成功开采后额外2金币归本卡持有者；已摧毁的资源不能再次开采。',None),
'随军啤酒机':(None,'回响在主弹道发射后触发，为相邻友方矮人充能1秒，剩余冷却最低为0；不选择最长冷却目标。',None),
'持盾新兵':('战吼：相邻远程友军获得保护1。','战吼：使相邻、当前远程行动的友军获得保护1；不再监听相邻关系变化自动发放。',None),
'侦查员':('此卡单兵作战时，相邻单兵攻击以优先级最低的敌军为目标。','此卡与受益者均须为单兵；相邻单兵攻击优先选择受击优先级最低的合法敌军，开采目标规则优先。',None),
'军官徽章':('组成小队时行动倍率+0.15。','装备者为小队时行动倍率+0.15。通常单兵或小队仅一件装备，不设置多件同装备叠加规则。',None),
'符文铁砧':(None,'行动命中后，使目标眩晕1秒，装备者获得3护甲；本效果冷却6秒。不是受到法术伤害触发；重复眩晕沿用通则。',None),
'制式箭袋':('每场前3次远程行动倍率+0.2。','本场前3次实际远程行动倍率+0.2；基础、追加、立即行动均消耗次数并受益。',None),
'重装骑士':('战吼：获得等同于护甲的强化。','战吼结算时读取当前护甲，获得等量强化；不是随护甲实时变化的基础数值。',None),
'盾墙列兵':(None,'乡邻：每次自身获得护甲时额外获得1点；该额外护甲不再次触发本效果。老狼的额外触发各加1，不递归产生新触发。',None),
'战鼓乐师':('回响：同排友军获得强化1。','主弹道发射后结算回响，使同排友军（包含自身）获得强化1；不影响另一排。强化按通则消耗。',None),
'胆怯的步兵':('其他友军行动后：获得强化1（本效果最多累计5）。','其他友军行动后获得强化1，仅强化下一次行动，本效果最多累计5；自身行动消耗并清零。不再提供本场永久累加的基础数值。',None),
'铸甲师':(None,'每场第一次有相邻友方随从被消灭时，永久基础护甲+1。每场一次，本卡复活或重新入场不重置次数。',None),
'辎重驮夫':(None,'战吼获得1金币；该次战吼结算时若乡邻生效，额外获得2金币。不是全体生命加成。',None),
'标枪散兵':('战吼：以数值+2进行1次远程行动，随后变为近战。','战吼立即进行1次数值+2的远程行动，正常触发对应行动效果，随后锁定近战；不是2倍倍率。',None),
'并肩作战':('所有友军获得乡邻：受到的所有攻击伤害-1。','所有友军获得“乡邻：受到的所有攻击伤害-1”；仅乡邻生效者自身享有减伤，不向全体重复发放。同名减伤通常不重复叠加。',None),
'齐射令':('后排远程友军立即行动1次。','只使后排当前远程行动的友军立即行动1次，消耗强化并重置冷却；回响、元素与命中按通则结算。',None),
'灰烬战旗':('乡邻：装备者获得耀眼；同排友军数值+1。','乡邻生效且装备者存活时，装备者获得耀眼，同排友军数值+1；装备者死亡或乡邻失效时移除加成。',None),
'集结号':(None,'战吼：相邻友军本场行动冷却×0.8；不再为所有友军增加基础数值。',None),
'征兵册':(None,'携带此卡参战并获胜后，从本局已开放、可正常获取的随从池获得2张随机随从，然后消耗此卡；不含法术装备资源，遵守持有唯一及衍生排除。行动冷却-1表示减少1秒。',None),
'枪械大师':('获得时：随机远程武器进入收藏。装备远程武器时数值+1d4且必中。','获得时随机获得远程武器；装备远程武器后数值加成适用于当前行动，包括治疗、防御；必中仅对需要命中判定的行动生效。','1d4是装备时投掷固定，还是每次行动重投？本次已去掉仅攻击受益的限制。'),
'塔盾':(None,None,'“命中率降低50%”改成固定50%命中会改变与其他命中修正的叠加。建议投掷1d2、=2命中，但需确认是否正式替换原修正规则。'),
'连珠铳':(None,'远程主行动发射后排定3次40%效能追加，锁定原目标；追加不再次触发本装备追加。正常消耗强化、触发回响及元素效果；冷却×3.5。','机制已确认；是否将该触发标签改成回响？改名可能受回响增幅影响，暂保留追加表述。'),
'黑铁法杖':(None,'法术行动最终行动值×2，不仅翻倍牌型倍率。','原特效同时写冷却翻倍，建议冷却列与当前完整说明是否保留该代价需确认；倍率规则已明确，平衡评估后调。'),
'锻魂之锤':(None,None,'物品纹章已明确为将物品属性和效果转换成纹章。其随机装备池、占普通纹章槽还是装备位、是否绕过一件装备上限仍需确认。'),
'民兵指挥官':('友方人类每有一个相邻人类，获得+1/+1。','逐个计算友方人类自身的相邻人类数量，每个提供数值与生命+1；不再统计全场相邻组合或使用最多3组上限。','这是实时邻接加成，还是战吼时固定本场加成？'),
'外交官':('友方随从每有一个不同种族的相邻友军，获得+1/+1。','按每个友方随从自身的异族相邻友军数量获得数值与生命加成；取消嵌套乡邻。','是否保留原战吼触发，还是改为随相邻变化实时生效？'),
'胜利狂欢':(None,None,'已确认流程不产出玩家平局（双方空场按玩家胜利）。短文随机2张与原文所有登场随从仍不同；是否接受随机2张的平衡调整？'),
}
for r in snap[card]:
 f=r['fields'];n=f['卡牌名']
 if n not in rules: continue
 short,full,q=rules[n]; fields={'待确认事项':q,'审阅状态':'待确认' if q else '已确认'}
 if short is not None: fields['卡面短文本']=short
 if full is not None: fields['完整规则说明']=full
 if not q: fields['确认结果（人填）']=None
 # 同步被改写效果的标准词条，去掉已失效的语义标签。
 replacements={'随军啤酒机':['回响','相邻','充能Ns'],'持盾新兵':['战吼','相邻','远程','保护N'],'重装骑士':['战吼','强化N','护甲'],'胆怯的步兵':['友军行动','强化N','次数上限'],'并肩作战':['乡邻','固定减伤'],'民兵指挥官':['相邻人类','基础数值','基础生命值'],'外交官':['相邻','其他种族','基础数值','基础生命值'],'集结号':['装备','战吼','相邻','行动冷却缩短X%']}
 if n in replacements: fields['标准词条']=[terms[w] for w in replacements[n]]
 change(card,r,fields)
# 已确认的通用指示物边界不再让英雄天赋重复提问。
for r in snap[talent]:
 if r['fields'].get('天赋名')=='三星印': change(talent,r,{'规范描述':'获得太阳、月亮、星星各一枚，按指示物统一规则处理同名限制、移动与战后保留。','待确认事项':None,'审阅状态':'已整理'})
 if r['fields'].get('天赋名')=='福金雾尼': change(talent,r,{'规范描述':r['fields']['原始描述']+'\n指示物效果按英雄附属内容中已确认版本执行；本身战后保留，福金数值和雾尼改变仅本场有效。','待确认事项':None,'审阅状态':'已整理'})
# 单纯由已确认通则覆盖的纹章清理泛化占位问题，其他保留。
clear={'四叶草Ⅰ','四叶草Ⅱ','苹果','苹果派','烤苹果','金币','金币袋','奶酪','奶酪面包','三明治','金苹果'}
for r in snap[em]:
 if r['fields']['名称'] in clear: change(em,r,{'待确认事项':None,'审阅状态':'已整理'})
Path('/private/tmp/project-card-closure-plan.json').write_text(json.dumps(updates,ensure_ascii=False,indent=2))
for t in set(u['table'] for u in updates):
 now={r['record_id']:r for r in items(f'bitable/v1/apps/{b}/tables/{t}/records')}
 for u in [u for u in updates if u['table']==t]: assert all(now[u['record_id']]['fields'].get(k)==v for k,v in u['before'].items()),'并发变更，停止覆盖'
 a(f'bitable/v1/apps/{b}/tables/{t}/records/batch_update','POST',{'records':[{'record_id':u['record_id'],'fields':u['fields']} for u in updates if u['table']==t]})
after={t:items(f'bitable/v1/apps/{b}/tables/{t}/records') for t in snap}
for u in updates:
 got=next(r['fields'] for r in after[u['table']] if r['record_id']==u['record_id'])
 for k,v in u['fields'].items():
  x=got.get(k)
  if isinstance(v,list): x=[rid for p in x for rid in (p.get('record_ids') or [])];assert sorted(x)==sorted(v)
  else: assert x==v,(u['record_id'],k)
Path('/private/tmp/project-card-closure-after.json').write_text(json.dumps(after,ensure_ascii=False,indent=2))
print(json.dumps({'updates':len(updates),'resolved_cards':sum(u['table']==card and u['fields'].get('审阅状态')=='已确认' for u in updates),'verified':True}))
