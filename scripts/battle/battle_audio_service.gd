class_name BattleAudioService
extends Node

## 战斗音效播放器；独立随机数和多声部池都不会读写战斗随机序列。

const VOICE_COUNT: int = 3 # 每类音效允许同时播放的声部数，避免连击被单个播放器截断
const PLAYER_VOLUME_DB: float = -8.0 # 单条音效的保守播放音量，主音量仍由全局滑条控制
const BGM_VOLUME_DB: float = -12.0 # 背景音乐相对总线的音量，主音量仍由全局滑条控制
const BGM_TRACKS: Array[String] = [
	"res://assets/audio/bgm/bgm1.mp3",
	"res://assets/audio/bgm/bgm2.mp3",
	"res://assets/audio/bgm/bgm3.mp3",
]
const POOL_DEFINITIONS: Dictionary = {
	"melee_launch": ["res://assets/audio/近战a1.wav"],
	"melee_hit": ["res://assets/audio/近战b1.wav"],
	"ranged_launch": ["res://assets/audio/远程a1.wav", "res://assets/audio/远程a2.mp3"],
	"ranged_hit": ["res://assets/audio/远程b1.wav"],
	"magic_launch": ["res://assets/audio/魔法a1.wav"],
	"magic_hit": ["res://assets/audio/魔法b1.wav"],
	"armor_launch": ["res://assets/audio/护甲a1.wav", "res://assets/audio/护甲a2.wav"],
}

var _random := RandomNumberGenerator.new()
var _bgm_random := RandomNumberGenerator.new()
var _pools: Dictionary = {}
var _next_voice: Dictionary = {}
var _play_counts: Dictionary = {}
var _bgm_player: AudioStreamPlayer
var _last_bgm_index: int = -1


func _ready() -> void:
	_random.randomize()
	_bgm_random.randomize()
	for pool_id: String in POOL_DEFINITIONS:
		var voices: Array[AudioStreamPlayer] = []
		for voice_index: int in VOICE_COUNT:
			var player := AudioStreamPlayer.new()
			player.name = "%sVoice%d" % [pool_id, voice_index]
			player.bus = "Master"
			player.volume_db = PLAYER_VOLUME_DB
			add_child(player)
			voices.append(player)
		_pools[pool_id] = voices
		_next_voice[pool_id] = 0
		_play_counts[pool_id] = 0
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BackgroundMusicPlayer"
	_bgm_player.bus = "Master"
	_bgm_player.volume_db = BGM_VOLUME_DB
	add_child(_bgm_player)
	_bgm_player.finished.connect(_play_random_bgm)
	_play_random_bgm()


func play_action_launch(action_type: CardData.ActionType) -> void:
	var phase := _phase_for_action(action_type)
	if phase == "" or phase == "hit":
		return
	_play_pool("%s_launch" % phase)


func play_action_hit(action_type: CardData.ActionType) -> void:
	var phase := _phase_for_action(action_type)
	if phase == "" or phase == "launch":
		return
	_play_pool("%s_hit" % phase)


func set_master_volume_percent(percent: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	var normalized := clampf(percent, 0.0, 100.0) / 100.0
	AudioServer.set_bus_mute(bus_index, is_zero_approx(normalized))
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(normalized, 0.0001)))


func get_loaded_source_count() -> int:
	var count := 0
	for source_paths: Array in POOL_DEFINITIONS.values():
		count += source_paths.size()
	return count


func get_play_count(pool_id: String) -> int:
	return int(_play_counts.get(pool_id, 0))


func _play_pool(pool_id: String) -> void:
	var voices := _pools.get(pool_id, []) as Array
	var source_paths := POOL_DEFINITIONS.get(pool_id, []) as Array
	if voices.is_empty() or source_paths.is_empty():
		return
	var voice_index := int(_next_voice.get(pool_id, 0)) % voices.size()
	_next_voice[pool_id] = voice_index + 1
	var player := voices[voice_index] as AudioStreamPlayer
	var path := String(source_paths[_random.randi_range(0, source_paths.size() - 1)])
	var stream := load(path) as AudioStream
	if stream == null:
		return
	player.stream = stream
	player.play()
	_play_counts[pool_id] = int(_play_counts.get(pool_id, 0)) + 1


func _play_random_bgm() -> void:
	if BGM_TRACKS.is_empty() or _bgm_player == null:
		return
	var next_index := _bgm_random.randi_range(0, BGM_TRACKS.size() - 1)
	if BGM_TRACKS.size() > 1 and next_index == _last_bgm_index:
		next_index = (_last_bgm_index + _bgm_random.randi_range(1, BGM_TRACKS.size() - 1)) % BGM_TRACKS.size()
	var stream := load(BGM_TRACKS[next_index]) as AudioStream
	if stream == null:
		return
	_last_bgm_index = next_index
	_bgm_player.stream = stream
	_bgm_player.play()


func _phase_for_action(action_type: CardData.ActionType) -> String:
	match action_type:
		CardData.ActionType.MELEE:
			return "melee"
		CardData.ActionType.RANGED:
			return "ranged"
		CardData.ActionType.MAGIC:
			return "magic"
		CardData.ActionType.DEFENSE:
			return "armor"
	return ""
