"""飞书规则同步：先快照与审阅，再按明确计划逐项回写并读回验证。"""
import json
import runpy
import subprocess
import sys
import re
import unicodedata
from pathlib import Path

BRIDGE = '/Users/Zhuanz/Library/Application Support/ProjectCardBridge/feishu_codex_bridge.py'
BASE = 'IcuQbyEQtaPWPgsOOOrcu5shnKh'
ROOT = Path('/private/tmp/project-card-rule-sync-20260911')

def api(path, method='GET', body=None):
    b = bridge
    config = 'url = ' + json.dumps('https://open.feishu.cn/open-apis/' + path) + '\n'
    config += 'header = ' + json.dumps('Authorization: Bearer ' + b['current_user_access_token']()) + '\n'
    config += 'header = "Content-Type: application/json"\nrequest = ' + json.dumps(method) + '\n'
    if body is not None:
        config += 'data = ' + json.dumps(json.dumps(body, ensure_ascii=False), ensure_ascii=False) + '\n'
    p = subprocess.run(['/usr/bin/curl', '--silent', '--show-error', '--max-time', '60', '--config', '-'], input=config, text=True, capture_output=True, check=True)
    data = json.loads(p.stdout)
    if data.get('code', 0):
        raise RuntimeError(json.dumps(data, ensure_ascii=False))
    return data.get('data', data)

def items(path):
    rows = []
    while True:
        d = api(path + ('&' if '?' in path else '?') + 'page_size=100')
        rows.extend(d.get('items') or [])
        if not d.get('has_more'):
            return rows
        path = path.split('?')[0] + '?page_token=' + d['page_token']

def flat(v):
    if v is None: return ''
    if isinstance(v, list): return ''.join(flat(x) for x in v)
    if isinstance(v, dict): return v.get('text', '')
    return str(v)

def save(name, data):
    ROOT.mkdir(exist_ok=True)
    (ROOT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2))

def load(name):
    return json.loads((ROOT / name).read_text())

def norm(s):
    return unicodedata.normalize('NFKC', s).replace(' ', '')

def build_plan():
    """只生成计划；没有任何飞书写入。"""
    source_changes = []
    sources = {sid: load(sid+'.json')['valueRange']['values'] for sid in ['kw9esj','fa884e','MBy6UZ','lnA4pD']}
    def cell(sid, address, value):
        m = re.fullmatch(r'([A-T])(\d+)', address)
        row, col = int(m[2])-1, ord(m[1])-65
        old = sources[sid][row][col]
        if flat(old) == value: return
        source_changes.append({'sid':sid,'address':address,'before':old,'after':value})
        sources[sid][row][col] = value

    io = '每天获得1枚哨位，最多储存3枚。部署时吸收容量为5+英雄等级；指示物不占位，前排、后排、法术堆各最多1枚。分别为友军分担1点即将受到的近战、远程、法术伤害。容量耗尽即摧毁；本场投入的哨位战后也摧毁，未使用库存保留。'
    cell('fa884e','C2',io)
    cell('fa884e','E9','任务：前排部署7个独立的防御行动随从并赢得一场战斗。奖励：哨位每次最多分担3点伤害，吸收容量额外+10。')
    cell('fa884e','E10','哨位储存上限变为4枚，立即获得1枚。正式开战时，每投入1枚哨位获得5金币。')
    cell('fa884e','E11','友军即将受到致命伤害时，摧毁1枚已部署哨位，免疫本次伤害并恢复5点生命。优先选择剩余容量最少的哨位，相同则前排、后排、法术堆依次优先。')
    cell('fa884e','E15','每场一次：只剩最后一个友军时，免疫伤害5秒并立即行动2次。开场仅有一个单兵或小队时也触发。')
    cell('fa884e','E19','友方前排存在卡牌时，后排不能被双方行动选为主目标，包括友方治疗和防御；元素副目标不受限制。')
    cell('fa884e','I16','携带者数值+3、生命值+6，获得耀眼，所有其他耀眼失效。')
    cell('MBy6UZ','C2','每天获得1张耐久为1的随机法术，品级随英雄等级提升。法术准备容量翻倍，通常为20张。每日产出的耐久规则不影响购买或事件获得的法术。')
    cell('MBy6UZ','E9','英雄每日产出的法术耐久改为2；不影响购买或事件获得的法术。')
    cell('MBy6UZ','K45','随从')
    cell('kw9esj','G11','每天随机变换为一个普通元素；参与牌型时，牌型倍率+0.1。')
    cell('kw9esj','I11','仅可张贴到元素符文区。贴上立即随机，此后每日首次翻牌前在木水火光暗中重抽，可连续相同。每枚参与牌型的混沌各加0.1；被遮挡仍随机但不判型、不加成，解除遮挡用当天结果。万能与混沌属于第二批局外解锁，未解锁不入池。')
    cell('kw9esj','G12','可视作任一普通元素，优先组成最高牌型，同牌型优先与左侧符文组合。')
    cell('kw9esj','I12','仅可张贴到元素符文区。仅替代木水火光暗并正常触发对应效果，不复制混沌附加效果。本局持有唯一，收藏、场上和工作包均计持有，移除后恢复获得资格。水水万能火火为三水二火；水水水万能火为四水。万能与混沌属于第二批局外解锁，未解锁不入池。')
    for row in range(6,11):
        cell('kw9esj',f'I{row}','仅可张贴到元素符文区。五种普通元素贴纸作为第一批局外解锁，未解锁不进入纹章包、商店或随机奖励池。')
    cell('kw9esj','I13','种族为造物的卡牌通常护甲较高，生命值较低。此备注不改变死亡判定规则。')
    cell('kw9esj','I20','同窗口免死优先级：英雄→卡牌自身→添加效果→其他。伊奥恩保护先于本纹章，本纹章先于暮光面纱；每步重验致命条件，已获救不继续消耗后续免死。')
    cell('kw9esj','H31','长剑+盾牌（任意等级）')
    cell('kw9esj','I45','佩戴者须实际参战且全场未死亡，战后种子未被遮挡才累计；复活不计该场。累计3场进化。')
    cell('kw9esj','I46','由种子进化：实际参战、全场未死亡且战后未遮挡累计3场。复活不计该场。')
    cell('kw9esj','O32','所有额外生命值转为护甲。护甲每次被打空，基础生命值永久-1、护甲永久+1。生命因此归零时锁定为1，并同时视为造物；此后停止本效果的永久护甲+1。')
    cell('kw9esj','P32','种族为造物的卡牌通常护甲较高，生命值较低。重新获得护甲后再次被打空仍可转换，直到生命锁1；额外生命转护甲和其他来源护甲不受停止永久+1的影响。')

    table_data = {tid:load(tid+'.json') for tid in ['tblUA6BV5udW6ggK','tblbdKWKbOdZa8xV','tblTf0rd7VJC95li','tblx7PuFx6SCvjqX']}
    terms = {flat(r['fields']['词条']):r['record_id'] for r in table_data['tblx7PuFx6SCvjqX']['rows']}
    updates, creates = [], []
    def queue(tid, rec, fields):
        if rec:
            changed = {k:v for k,v in fields.items() if rec['fields'].get(k) != v}
            if changed: updates.append({'table':tid,'record':rec['record_id'],'before':{k:rec['fields'].get(k) for k in changed},'fields':changed})
        else: creates.append({'table':tid,'fields':fields})
    def links(text, kind=''):
        keys = {'纹章' if kind=='纹章' else '伤势'} if kind else set()
        for word in ['突击','遗愿','回响','启咒','耀眼','影蔽','造物','放逐','眩晕','立即行动','指示物','伤害分担','任务','预见','每日','永久','金币','护甲','基础数值','基础生命值','伤势']:
            if word in text: keys.add(word)
        if '强化' in text: keys.add('强化N')
        if '保护1' in text or '一层保护' in text: keys.add('保护N')
        if '每' in text and '秒' in text: keys.add('周期触发')
        if '随机获得' in text: keys.add('随机获得')
        if '法术' in text: keys.add('法术')
        return [terms[k] for k in sorted(keys) if k in terms]
    # 以名称匹配纹章与伤势；不把旧圆盾擅自改名为盾牌Ⅰ。
    tid='tblTf0rd7VJC95li'
    old={norm(r['fields']['名称']):r for r in table_data[tid]['rows']}
    known={'火把','长剑','面包','光贴纸','暗贴纸','水贴纸','火贴纸','木贴纸','混沌贴纸','万能贴纸','盾牌Ⅰ','盾牌Ⅱ','烤面包','羽毛Ⅰ','羽毛Ⅱ','改造','光血','晶体化'}
    questions={
      '太阳':'生命+6已确认；所有其他耀眼失效的阵营范围及多个太阳的关系待确认。',
      '月亮':'影蔽解除与重新获得的时点、护甲+8是否为基础值待确认。',
      '星星':'遗愿指示物是否占槽、能否继续传播及无空槽处理待确认。',
      '四叶草Ⅲ':'首次致命的硬币次数范围，以及复活后是否重置待确认；免死优先级已确认。',
      '种子':'参战存活计数已确认；取下、转移后的计数继承待确认。',
      '树':'种子进化条件已确认；树本体效果沿用源表。',
      '刺盾':'配方允许任意盾牌等级；护甲取受击前还是受击后数值待确认。',
      '火焰剑':'最右符文指携带卡还是小队；转换持续范围及元素贴纸交互待确认。',
      '天选之子':'概率取优及5次计数范围待确认。',
      '厄运缠身':'劣势掷骰计数、连续1的跨战斗保留及与优势共存待确认。',
    }
    for i,row in enumerate(sources['kw9esj'],1):
        for kind,ni,di,li in [('纹章',5,6,4),('伤势',13,14,12)]:
            if i<3 or len(row)<=di or not flat(row[ni]): continue
            name=flat(row[ni]); raw=flat(row[di]); note=flat(row[8 if kind=='纹章' else 15])
            q=questions.get(name,'' if name in known else '已同步新版源表；该效果的触发／计数／持续边界待逐项审阅。')
            f={'名称':name,'类别':kind,'限定':flat(row[li]),'原始描述':raw,'规范描述':raw+('\n规则：'+note if note else ''),'备注':note or None,'待确认事项':q or None,'审阅状态':'初版待确认' if q else '已整理','来源':f'贴纸/纹章和伤势!'+(f'F{i}:I{i}' if kind=='纹章' else f'N{i}:P{i}'),'标准词条':links(raw+' '+note,kind)}
            if kind=='纹章': f.update({'稀有度':flat(row[3]),'合成途径':flat(row[7]) or None})
            queue(tid,old.get(norm(name)),f)
    if '圆盾' in old:
        queue(tid,old['圆盾'],{'待确认事项':'旧源记录“圆盾”已不在新版源表；新版新增“盾牌Ⅰ”。是否属于重命名待确认，暂保留旧记录避免误删。','审阅状态':'初版待确认'})
    # 天赋以英雄、等级与选项匹配，保留记录ID及用户布局。
    tq={
      '护':'哨位在后排／法术堆时是否也对前排提供突击护甲待确认。','破':'哨位是否受沉默／控制及其目标选择细节待确认。','锐':'哨位耗尽、免死牺牲、战后清理是否均触发遗愿，增益持续范围待确认。','咒':'获得法术进入本场队列还是收藏、耐久及出现范围待确认。',
      '至高天':'至高天穹的祝福内容待补充；周期天赋次数储存待确认。','不坏身':'翻倍与额外容量+5／+10的计算顺序待确认。','三星印':'太阳／月亮／星星的局部边界待确认。','万法皆成':'已选一级天赋是否避免重复获得待确认。','超星燃爆':'属性翻倍覆盖范围、冷却变化及疲劳风暴延后规则待确认。',
      '小费':'法术被消耗指本场触发还是战后耐久归零移出待确认。','法术傀儡':'类型已确认为随从；突击／遗愿法术的选择流程及其触发边界待确认。','奥能融合':'两张或三张的条件、产物品级与耐久待确认。','天眼':'自动预见消耗／奖励排除范围与事件已见计数待确认。','拾荒':'恢复英雄护盾已替代旧回血；随机纹章池已确认，奖励次数及预见判定待确认。',
    }
    verified={'坚固','点金','保护','孤星耀','重幕庇影','持久法术','双哨共鸣'}
    for r in table_data['tblbdKWKbOdZa8xV']['rows']:
        f=r['fields']; hero=flat(f['名称']).split('·')
        src=f['来源']; m=re.search(r'!D(\d+)',src); n=int(m[1]); sid='fa884e' if src.startswith('伊奥恩') else 'MBy6UZ' if src.startswith('莉丝忒') else 'lnA4pD'
        row=sources[sid][n-1]; name=flat(row[3]); raw=flat(row[4]); q=tq.get(name,'' if name in verified else '新版天赋名与效果已同步；该天赋具体条件、计数或持续范围待英雄专项审阅。')
        detail=raw
        if name=='点金': detail+=' 准备取放不领奖，战后不重复领取，SL回退开战收入。'
        if name=='保护': detail+=' 先进行哨位分担，仍致命才免死；优先于四叶草Ⅲ和暮光面纱，阻止致命后后续免死不消耗。'
        if name=='孤星耀': detail+=' 仍可被选中、眩晕或放逐。两次按当前行动方式执行，治疗／防御同样适用，遵守立即行动的冷却、回响和强化规则。'
        if name=='重幕庇影': detail+=' 穿刺／折射先命中后排后，其后排水扩散合法。'
        if name=='针刺': detail=detail.replace('敌方敌方','敌方')
        queue('tblbdKWKbOdZa8xV',r,{'天赋名':name,'原始描述':raw,'规范描述':detail,'标准词条':links(detail),'待确认事项':q or None,'审阅状态':'初版待确认' if q else '已整理','来源':src.split('!')[0]+f'!D{n}:E{n}'})
    for r in table_data['tblUA6BV5udW6ggK']['rows']:
        name=r['fields']['名称']; sid='fa884e' if name.startswith('伊奥恩') else 'MBy6UZ' if name.startswith('莉丝忒') else 'lnA4pD'
        raw=flat(sources[sid][1][2]); q='' if sid=='fa884e' else '每日法术品级与英雄等级的具体对应表待设计。' if sid=='MBy6UZ' else '目数奖励及自动预见与后续天赋交互待专项审阅。'
        detail=raw
        if sid=='fa884e': detail+=' 容量按部署时等级确定；天赋值随英雄等级更新。先分担伤害，仍致命再判免死。'
        queue('tblUA6BV5udW6ggK',r,{'原始描述':raw,'规范描述':detail,'标准词条':links(detail),'待确认事项':q or None,'审阅状态':'初版待确认' if q else '已整理'})
    term_rules={
      '纹章':('纹章稀有度为I、II、III、V；普通随机池I～III，基础纹章仅I，V为专属／合成／进化，普通途径不可获得。','明确配方可合成；同名可叠加，万能持有唯一。'),
      '造物':('种族之一，通常护甲高、生命低；不因造物种族自动改为按护甲判死。','改造可同时视为造物；晶体化按明确效果生命锁1。'),
      '伤害分担':('哨位先分担即将受到的对应伤害，余量仍致命才进入免死判定。','伊奥恩哨位部署时容量5+等级，每区域1枚，不占位，耗尽或战后摧毁，未用库存保留。'),
      '法术使用次数':('耐久等于通常新卡品级；本场准备法术胜负结算后统一减1，即使未触发。','准备、排序、开战不扣；复制继承复制瞬间耐久；日常一次触发不等于永久耗尽，周期法术按间隔；莉丝忒每日产出明确例外。'),
      '徽章升级':('仅按明确配方合成或指定条件进化，不按同名自动升级。','源材料来自工作包；两材料换一，卡上替换原槽；最高同名等级可替代低级，匹配取最高结果。'),
    }
    for key,(definition,boundary) in term_rules.items():
        r=next(r for r in table_data['tblx7PuFx6SCvjqX']['rows'] if flat(r['fields']['词条'])==key)
        queue('tblx7PuFx6SCvjqX',r,{'建议定义':definition,'默认边界':boundary})
    new_rules={
      '纹章合成':('非战斗准备阶段工作包材料合成，免费、不耗刮刀，前期局外解锁。','两枚材料变一枚结果，卡上占原槽不保留旧效果；紫光可合成、金光可贴空槽。首次A+B=？、确认执行后永久保存发现；不同配方独立、高级替代共享。'),
      '万能元素':('仅替代五普通元素，高牌型优先，同牌型优先左侧，正常触发替代元素效果。','收藏、场上、工作包合计持有唯一，移除后可再得；局外第二批解锁。'),
      '混沌元素':('贴上立即随机，每日首次翻牌前在五元素中重抽，可重复同元素；每枚参与牌型时牌型倍率+0.1。','可叠加；遮挡仍随机但不判型不加成，解除用当天结果；与万能第二批解锁。'),
      '特效触发优先级':('同一触发窗口：英雄→卡牌自身效果→卡牌添加效果→其他效果。','免死示例保护→四叶草Ⅲ→暮光面纱；逐步重验条件，不改变法术交替与嵌套顺序。'),
    }
    for key,(definition,boundary) in new_rules.items():
        r=next((r for r in table_data['tblx7PuFx6SCvjqX']['rows'] if flat(r['fields']['词条'])==key),None)
        queue('tblx7PuFx6SCvjqX',r,{'词条':key,'分类':'已确认规则','建议定义':definition,'默认边界':boundary,'备注':'2026-09-11用户确认；本次同步。'})
    plan={'source_changes':source_changes,'updates':updates,'creates':creates}
    save('plan.json',plan)
    print(json.dumps({'source_cells':len(source_changes),'updates':len(updates),'creates':len(creates),'new_names':[x['fields'].get('名称',x['fields'].get('词条')) for x in creates]},ensure_ascii=False))

def apply_plan():
    plan=load('plan.json')
    # 写入前全量核对本次涉及字段，任何并发编辑均停止。
    for sid in set(c['sid'] for c in plan['source_changes']):
        token='PEHqshuiDhAZIJtvaAOcbmQUn4g' if sid=='kw9esj' else 'GnWksdURnhjz9ntKHC9chvd7nrh'
        d=api(f'sheets/v2/spreadsheets/{token}/values/{sid}!A1:T100')['valueRange']['values']
        for c in [x for x in plan['source_changes'] if x['sid']==sid]:
            m=re.fullmatch(r'([A-T])(\d+)',c['address']); actual=d[int(m[2])-1][ord(m[1])-65]
            if actual!=c['before']: raise RuntimeError('源表出现并发修改：'+sid+'!'+c['address'])
    current={tid:{r['record_id']:r for r in items(f'bitable/v1/apps/{BASE}/tables/{tid}/records')} for tid in set(x['table'] for x in plan['updates'])}
    for u in plan['updates']:
        f=current[u['table']][u['record']]['fields']
        if any(f.get(k)!=v for k,v in u['before'].items()): raise RuntimeError('多维表出现并发修改：'+u['record'])
    journal=[]
    for f in [{'field_name':'稀有度','type':3,'property':{'options':[{'name':s,'color':i} for i,s in enumerate(['I','II','III','V'])]}},{'field_name':'合成途径','type':1},{'field_name':'备注','type':1}]:
        existing=items(f'bitable/v1/apps/{BASE}/tables/tblTf0rd7VJC95li/fields')
        if not any(x['field_name']==f['field_name'] for x in existing):
            out=api(f'bitable/v1/apps/{BASE}/tables/tblTf0rd7VJC95li/fields','POST',f);journal.append({'field':out});save('journal.json',journal)
    for token in ['PEHqshuiDhAZIJtvaAOcbmQUn4g','GnWksdURnhjz9ntKHC9chvd7nrh']:
        cells=[x for x in plan['source_changes'] if (x['sid']=='kw9esj')==(token.startswith('PEH'))]
        if cells:
            api(f'sheets/v2/spreadsheets/{token}/values_batch_update','POST',{'valueRanges':[{'range':c['sid']+'!'+c['address']+':'+c['address'],'values':[[c['after']]]} for c in cells]})
            journal.append({'source_written':len(cells),'token':token});save('journal.json',journal)
    for tid in sorted(set(x['table'] for x in plan['updates'])):
        us=[u for u in plan['updates'] if u['table']==tid]
        for start in range(0,len(us),50):
            batch=us[start:start+50]
            api(f'bitable/v1/apps/{BASE}/tables/{tid}/records/batch_update','POST',{'records':[{'record_id':u['record'],'fields':u['fields']} for u in batch]})
            journal.append({'updated':tid,'ids':[u['record'] for u in batch]});save('journal.json',journal)
    for tid in sorted(set(x['table'] for x in plan['creates'])):
        cs=[u for u in plan['creates'] if u['table']==tid]
        out=api(f'bitable/v1/apps/{BASE}/tables/{tid}/records/batch_create','POST',{'records':[{'fields':u['fields']} for u in cs]})
        journal.append({'created':tid,'records':out['records']});save('journal.json',journal)
    print('写入完成；需读回验证。')

def verify():
    plan=load('plan.json'); journal=load('journal.json'); failures=[]; option_additions=[]
    actual={}
    for tid in set(x['table'] for x in plan['updates']+plan['creates']):
        rows=items(f'bitable/v1/apps/{BASE}/tables/{tid}/records')
        actual[tid]={r['record_id']:r for r in rows}
        save(tid+'-after.json',rows)
    def same(got,want):
        if want is None: return got in (None,'',[])
        if isinstance(want,list):
            ids=[rid for item in (got or []) if isinstance(item,dict) for rid in (item.get('record_ids') or [])]
            return sorted(ids)==sorted(want)
        return got==want
    checks=[]
    for u in plan['updates']: checks.append((u['table'],u['record'],u['fields']))
    for j in journal:
        if 'created' in j:
            for r in j['records']: checks.append((j['created'],r['record_id'],r['fields']))
    for tid,rid,fields in checks:
        got=actual[tid][rid]['fields']
        for key,value in fields.items():
            if not same(got.get(key),value): failures.append([tid,rid,key,got.get(key),value])
    for sid in set(x['sid'] for x in plan['source_changes']):
        token='PEHqshuiDhAZIJtvaAOcbmQUn4g' if sid=='kw9esj' else 'GnWksdURnhjz9ntKHC9chvd7nrh'
        rows=api(f'sheets/v2/spreadsheets/{token}/values/{sid}!A1:T100')['valueRange']['values']
        save(sid+'-after.json',rows)
        for c in [x for x in plan['source_changes'] if x['sid']==sid]:
            m=re.fullmatch(r'([A-T])(\d+)',c['address'])
            if flat(rows[int(m[2])-1][ord(m[1])-65])!=c['after']: failures.append([sid,c['address']])
    # 所有原有字段类型和属性必须保持不变。
    for tid in set(x['table'] for x in plan['updates']):
        before=load(tid+'.json')['fields']; after=items(f'bitable/v1/apps/{BASE}/tables/{tid}/fields'); byid={f['field_id']:f for f in after}
        for f in before:
            g=byid[f['field_id']]
            if (f['type'],f['property'])!=(g['type'],g['property']):
                old_options=(f.get('property') or {}).get('options',[])
                new_options=(g.get('property') or {}).get('options',[])
                additions=[o for o in new_options if o not in old_options]
                if f['type']==g['type']==3 and all(o in new_options for o in old_options) and f['field_name']=='限定' and [o['name'] for o in additions]==['迷宫专属']:
                    option_additions.append([tid,f['field_name'],'迷宫专属'])
                else: failures.append(['field-changed',tid,f['field_name']])
    result={'verified_updates':len(plan['updates']),'verified_creates':len(plan['creates']),'source_cells':len(plan['source_changes']),'option_additions':option_additions,'failures':failures}
    save('verification.json',result); print(json.dumps(result,ensure_ascii=False))

def read_supplement():
    tid='tblIwlBuC5p46saI'
    d={'fields':items(f'bitable/v1/apps/{BASE}/tables/{tid}/fields'),'rows':items(f'bitable/v1/apps/{BASE}/tables/{tid}/records')}
    save(tid+'.json',d)
    print('FIELDS',[(f['field_name'],f['type']) for f in d['fields']])
    for r in d['rows']:
        if r['fields'].get('名称') in ['太阳','法术傀儡','哨位','月亮','星星']: print(json.dumps(r,ensure_ascii=False))

def finish_supplement():
    tid='tblIwlBuC5p46saI'
    before=load(tid+'.json')['rows']
    current={r['record_id']:r for r in items(f'bitable/v1/apps/{BASE}/tables/{tid}/records')}
    changes=[]
    for r in before:
        name=r['fields'].get('名称')
        if name=='太阳':
            text='携带者基础数值+3、生命值+6，获得耀眼，所有其他耀眼失效。'
            fields={'原始描述':flat(load('fa884e-after.json')[15][8]),'规范描述':text,'待确认事项':'所有其他耀眼失效的作用范围、多个太阳共存时的规则仍待确认；与纹章表同名内容的分类关系待确认。'}
        elif name=='法术傀儡':
            fields={'规范描述':r['fields']['原始描述'],'审阅状态':'初版待确认','待确认事项':'已补全为造物随从。突击与遗愿法术的选择池、选择时机，以及是否消耗所选法术耐久仍待确认。'}
        else: continue
        for key in fields:
            if current[r['record_id']]['fields'].get(key)!=r['fields'].get(key): raise RuntimeError('附属记录已发生变更，停止覆盖')
        changes.append({'record_id':r['record_id'],'fields':fields})
    save('supplement-plan.json',changes)
    api(f'bitable/v1/apps/{BASE}/tables/{tid}/records/batch_update','POST',{'records':changes})
    after={r['record_id']:r for r in items(f'bitable/v1/apps/{BASE}/tables/{tid}/records')}
    assert all(after[c['record_id']]['fields'].get(k)==v for c in changes for k,v in c['fields'].items())
    save('supplement-verified.json',changes)
    print('附属内容2条已更新并验证')

def snapshot():
    tables = items(f'bitable/v1/apps/{BASE}/tables')
    save('tables.json', tables)
    print('TABLES', json.dumps(tables, ensure_ascii=False), flush=True)
    for t in tables:
        if t['name'] not in ['纹章与伤势', '纹章和伤势', '英雄', '英雄天赋', '英雄附属', '英雄附属卡牌', '标准词条']:
            continue
        tid = t['table_id']
        fields = items(f'bitable/v1/apps/{BASE}/tables/{tid}/fields')
        rows = items(f'bitable/v1/apps/{BASE}/tables/{tid}/records')
        save(tid + '.json', {'fields': fields, 'rows': rows})
        print('TABLE', t['name'], tid, 'FIELDS', json.dumps(fields, ensure_ascii=False), flush=True)
        print('ROWS', json.dumps(rows, ensure_ascii=False), flush=True)
    for title, token, sid in [('纹章', 'PEHqshuiDhAZIJtvaAOcbmQUn4g', 'kw9esj'), ('伊奥恩', 'GnWksdURnhjz9ntKHC9chvd7nrh', 'fa884e'), ('莉丝忒', 'GnWksdURnhjz9ntKHC9chvd7nrh', 'MBy6UZ'), ('血鸦', 'GnWksdURnhjz9ntKHC9chvd7nrh', 'lnA4pD')]:
        d = api(f'sheets/v2/spreadsheets/{token}/values/{sid}!A1:T100')
        save(sid + '.json', d)
        print('SHEET', title, flush=True)
        for i, row in enumerate(d['valueRange']['values'], 1):
            cells = {chr(65+j): flat(v) for j, v in enumerate(row) if flat(v)}
            if cells: print(i, json.dumps(cells, ensure_ascii=False), flush=True)

if __name__ == '__main__':
    bridge = runpy.run_path(BRIDGE)
    if sys.argv[1] == 'snapshot': snapshot()
    elif sys.argv[1] == 'plan': build_plan()
    elif sys.argv[1] == 'apply': apply_plan()
    elif sys.argv[1] == 'verify': verify()
    elif sys.argv[1] == 'supplement': read_supplement()
    elif sys.argv[1] == 'finish': finish_supplement()
