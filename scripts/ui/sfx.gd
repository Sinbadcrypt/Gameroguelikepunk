## Sons synthétisés à la volée (aucun fichier audio nécessaire pour la vertical slice).
## Chaque son = une note courte avec enveloppe ; la hauteur monte à chaque Lien enchaîné.
class_name Sfx
extends AudioStreamPlayer

const MIX_RATE := 44100.0
var _playback: AudioStreamGeneratorPlayback = null


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.6
	stream = gen
	volume_db = -8.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## Note simple. wave : "square" (synthé), "sine" (doux), "noise" (impact).
func blip(freq: float, duration: float = 0.12, wave: String = "square", volume: float = 0.35) -> void:
	if _playback == null:
		return
	var frames := int(MIX_RATE * duration)
	frames = min(frames, _playback.get_frames_available())
	var phase := 0.0
	for i in frames:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 18.0) * volume
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
				s *= 0.5
			"sine":
				s = sin(phase * TAU)
			"noise":
				s = randf_range(-1.0, 1.0)
		phase += freq / MIX_RATE
		_playback.push_frame(Vector2.ONE * s * env)


## Note de carte : plus le Lien est long, plus la note monte (gamme mineure).
func card_note(chain: int) -> void:
	var scale := [0, 3, 7, 10, 12]
	var semis: int = scale[clampi(chain, 0, scale.size() - 1)]
	blip(330.0 * pow(2.0, semis / 12.0), 0.14, "square")


func hit() -> void:
	blip(90.0, 0.10, "noise", 0.3)


func shield() -> void:
	blip(660.0, 0.10, "sine", 0.3)
