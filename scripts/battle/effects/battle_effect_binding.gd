class_name BattleEffectBinding
extends RefCounted

## 把一条通用定义绑定到本场的具体来源实例。

var binding_id: int = 0
var definition: BattleEffectDefinition
var source: BattleEffectOwnerRef
var enabled: bool = true
