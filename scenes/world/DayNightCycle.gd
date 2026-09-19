extends Node3D

# Cycle jour/nuit de la carte : heure, course du soleil, ciel, brouillard, lumière ambiante.
# Outils natifs de Godot 4 uniquement (ProceduralSkyMaterial + WorldEnvironment + DirectionalLight3D),
# aucune dépendance externe.
#
# Ce nœud ne touche PAS aux lampadaires : il se contente de publier l'heure et l'état nuit par le
# signal `hour_changed`. C'est StreetLights.gd qui écoute et allume. Séparer les deux permet de
# mesurer l'un sans l'autre, ce qu'il a fallu faire pour choisir l'approche d'éclairage.
#
# DURÉE DU CYCLE : 48 minutes réelles pour 24 h de jeu, soit 2 min par heure de jeu. C'est la durée
# de GTA V, et elle est choisie pour être jouable : une mission de quelques minutes ne traverse pas
# trois fois la nuit, et on n'attend pas non plus une demi-heure pour voir le soleil bouger. Le jour
# utile (6 h -> 20 h) dure 28 min, la nuit noire (21 h -> 5 h) 16 min.
#
# COURSE DU SOLEIL : arc circulaire d'est en ouest, dans un plan incliné de SUN_TILT par rapport au
# zénith (donc une élévation maximale de 90° - SUN_TILT à midi), le tout pivoté de SUN_AZIMUTH pour
# que les ombres de midi ne tombent pas exactement sur un axe de la carte.
#
# LA NUIT, LE MÊME DirectionalLight3D SERT DE LUNE : il bascule à l'opposé du soleil, en bleu et très
# faible, et SES OMBRES SONT COUPÉES. Ce n'est pas qu'une économie : une carte d'ombre directionnelle
# est le plus gros poste GPU de la scène, et la lune n'a pas de quoi justifier des ombres portées.
# Mesuré sur les 6 vues de référence : c'est ce qui fait que la nuit ne coûte pas plus cher que le
# jour malgré les halos (cf. le tableau du commit).

signal hour_changed(hour: float, night: float)

const SUN_TILT := deg_to_rad(28.0)        # élévation maximale : 62° à midi
const SUN_AZIMUTH := deg_to_rad(22.0)
const REAL_MINUTES_PER_DAY := 48.0

# Heures charnières du cycle. Le « facteur nuit » vaut 0 en plein jour, 1 en pleine nuit, et
# interpole entre les deux pendant les crépuscules : c'est lui qui pilote les lampadaires.
const DAWN_START := 5.0
const DAWN_END := 7.0
const DUSK_START := 19.0
const DUSK_END := 21.0

# Palette du ciel, par heure clé. Interpolée linéairement entre deux clés.
# [heure, haut du ciel, horizon du ciel, horizon du sol, énergie du ciel]
const SKY_KEYS := [
	[0.0, Color(0.015, 0.022, 0.055), Color(0.035, 0.045, 0.085), Color(0.020, 0.022, 0.030), 0.30],
	[5.0, Color(0.035, 0.055, 0.120), Color(0.110, 0.095, 0.130), Color(0.045, 0.045, 0.055), 0.45],
	[6.5, Color(0.170, 0.260, 0.480), Color(0.850, 0.450, 0.260), Color(0.180, 0.140, 0.120), 0.90],
	[9.0, Color(0.240, 0.420, 0.760), Color(0.640, 0.720, 0.850), Color(0.300, 0.290, 0.270), 1.00],
	[13.0, Color(0.220, 0.400, 0.780), Color(0.600, 0.700, 0.860), Color(0.310, 0.300, 0.280), 1.00],
	[17.5, Color(0.240, 0.410, 0.740), Color(0.700, 0.680, 0.760), Color(0.300, 0.280, 0.260), 0.95],
	[19.5, Color(0.150, 0.190, 0.420), Color(0.880, 0.380, 0.200), Color(0.170, 0.120, 0.110), 0.80],
	[21.0, Color(0.030, 0.045, 0.100), Color(0.090, 0.075, 0.110), Color(0.040, 0.040, 0.050), 0.40],
	[24.0, Color(0.015, 0.022, 0.055), Color(0.035, 0.045, 0.085), Color(0.020, 0.022, 0.030), 0.30],
]
# [heure, couleur du soleil, énergie du soleil]
const SUN_KEYS := [
	[6.0, Color(1.00, 0.55, 0.32), 0.25],
	[7.5, Color(1.00, 0.82, 0.66), 0.85],
	[12.0, Color(1.00, 0.97, 0.92), 1.15],
	[17.0, Color(1.00, 0.90, 0.78), 1.00],
	[19.0, Color(1.00, 0.52, 0.28), 0.35],
]
const MOON_COLOR := Color(0.55, 0.66, 1.00)
const MOON_ENERGY := 0.09

# Étoiles : panorama généré une fois au lancement et posé en sky_cover. Généré plutôt que stocké
# parce qu'un panorama d'étoiles est du bruit, pas une œuvre : le fabriquer coûte ~15 ms au
# démarrage et évite un PNG de plus dans le dépôt.
# 2048 de large et non 512 : sky_cover étale le panorama sur 360°, donc un texel de 512 couvre 0,7°,
# soit ~8 px à l'écran — les étoiles ressortaient en flocons de neige (constaté sur la capture de
# nuit du 2026-09-19). À 2048, un texel fait 0,18°, soit 2 px : un point.
const STAR_TEX_WIDTH := 2048
const STAR_TEX_HEIGHT := 1024
const STAR_COUNT := 1600
const STAR_SEED := 20260919

# Pas de rafraîchissement du CIEL, en heures de jeu. Toucher à un ProceduralSkyMaterial force Godot
# à recalculer la radiance du ciel (c'est elle qui sert de lumière ambiante, ambient_light_source =
# ciel) : le faire à chaque image est un des rares gestes capables de plomber l'UHD 750 à eux seuls.
# 0,02 h = 1,2 minute de jeu = 2,4 s réelles : le ciel se remet à jour ~25 fois par heure de jeu,
# ce qui est invisible sur un dégradé, et le Sky est en mode incrémental pour étaler ce calcul.
# Le SOLEIL, lui, est rafraîchi à chaque image : ce n'est qu'une transformation et deux couleurs,
# et c'est ce qui rend le glissement des ombres fluide.
const SKY_STEP := 0.02

@export var hour := 8.0
@export var paused := false
@export var show_clock := true

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _clock: Label
var _clock_until := 0.0
var _sky_hour := -99.0


func _ready() -> void:
	var root := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if root == null:
		root = self
	var we := _find(root, "WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
		if _env != null and _env.sky != null:
			_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_sun = _find(root, "DirectionalLight3D") as DirectionalLight3D
	if _sky != null:
		_sky.sky_cover = _stars()
	if _env != null and _env.sky != null:
		# incrémental : la mise à jour de la radiance est étalée sur plusieurs images au lieu de
		# tomber d'un bloc sur celle où le ciel change
		_env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if show_clock:
		_build_clock()
	_apply(true)


func _process(delta: float) -> void:
	if not paused:
		hour = fposmod(hour + delta * 24.0 / (REAL_MINUTES_PER_DAY * 60.0), 24.0)
		_apply(false)
	if _clock != null:
		_clock.visible = show_clock and (paused or Time.get_ticks_msec() * 0.001 < _clock_until)
		if _clock.visible:
			_clock.text = "%02d:%02d%s" % [int(hour), int(fmod(hour, 1.0) * 60.0), "  (figé)" if paused else ""]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode != KEY_N:
		return
	if key.ctrl_pressed:
		paused = not paused
	else:
		set_hour(hour + (-1.0 if key.shift_pressed else 1.0))
	_clock_until = Time.get_ticks_msec() * 0.001 + 2.5
	print("DAY_NIGHT heure %05.2f, nuit %.2f%s" % [hour, night_factor(), ", cycle figé" if paused else ""])


# Force l'heure. Utilisé par la touche N, par --heure= dans MapShotsTest et par les tests headless.
func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply(true)


# 0 en plein jour, 1 en pleine nuit, interpolé pendant les crépuscules.
func night_factor() -> float:
	if hour <= DAWN_START or hour >= DUSK_END:
		return 1.0
	if hour >= DAWN_END and hour <= DUSK_START:
		return 0.0
	if hour < DAWN_END:
		return 1.0 - smoothstep(DAWN_START, DAWN_END, hour)
	return smoothstep(DUSK_START, DUSK_END, hour)


# Direction allant du sol VERS le soleil. Sous l'horizon la nuit : c'est ce qui décide de la bascule
# en mode lune.
func sun_direction() -> Vector3:
	var t := (hour - 6.0) / 12.0 * PI
	return Vector3(cos(t), sin(t), 0.0).rotated(Vector3.RIGHT, SUN_TILT).rotated(Vector3.UP, SUN_AZIMUTH)


func _apply(force: bool) -> void:
	_apply_sun()
	# écart circulaire à la dernière heure appliquée au ciel (le passage de 23,99 à 0,01 fait 0,02)
	var ecart := absf(fposmod(hour - _sky_hour + 12.0, 24.0) - 12.0)
	if not force and ecart < SKY_STEP:
		return
	_sky_hour = hour
	_apply_sky()
	hour_changed.emit(hour, night_factor())


func _apply_sun() -> void:
	var to_sun := sun_direction()
	if _sun != null:
		# DirectionalLight3D éclaire le long de son -Z : on l'oriente donc depuis un point vers le
		# sol. La lune est le soleil retourné, en bleu et sans ombre.
		var day := to_sun.y > 0.0
		var dir := to_sun if day else -to_sun
		if absf(dir.y) < 0.02:
			dir.y = 0.02 * signf(dir.y if dir.y != 0.0 else 1.0)
		_sun.look_at_from_position(dir * 100.0, Vector3.ZERO, Vector3.UP)
		if day:
			var sun_key := _lerp_keys(SUN_KEYS, hour)
			_sun.light_color = sun_key[0]
			# fondu de l'énergie sur les crépuscules, sinon le soleil s'éteint d'un coup à l'horizon
			_sun.light_energy = float(sun_key[1]) * clampf(to_sun.y * 4.0, 0.0, 1.0)
			_sun.shadow_enabled = _sun.light_energy > 0.12
		else:
			_sun.light_color = MOON_COLOR
			_sun.light_energy = MOON_ENERGY * night_factor()
			_sun.shadow_enabled = false


func _apply_sky() -> void:
	var n := night_factor()
	if _sky != null:
		var k := _lerp_keys(SKY_KEYS, hour)
		_sky.sky_top_color = k[0]
		_sky.sky_horizon_color = k[1]
		_sky.ground_horizon_color = k[2]
		_sky.ground_bottom_color = (k[2] as Color).darkened(0.4)
		_sky.sky_energy_multiplier = float(k[3])
		_sky.ground_energy_multiplier = float(k[3])
		_sky.sun_angle_max = lerpf(1.0, 30.0, clampf(n, 0.0, 1.0))
		_sky.sky_cover_modulate = Color(1, 1, 1, 1) * clampf((n - 0.25) / 0.75, 0.0, 1.0)
	if _env != null:
		var k := _lerp_keys(SKY_KEYS, hour)
		_env.ambient_light_energy = lerpf(1.0, 0.55, n)
		_env.fog_light_color = (k[1] as Color).lerp(Color(0.05, 0.06, 0.10), n * 0.85)
		# la brume se voit surtout au ras du sol : un peu plus dense la nuit, ce qui aide aussi les
		# halos lointains à se détacher
		_env.fog_density = lerpf(0.00045, 0.00075, n)


func _lerp_keys(keys: Array, h: float) -> Array:
	var first: Array = keys[0]
	var last: Array = keys[keys.size() - 1]
	if h <= float(first[0]):
		return first.slice(1)
	if h >= float(last[0]):
		return last.slice(1)
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if h > float(b[0]):
			continue
		var a: Array = keys[i - 1]
		var u := (h - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
		var out := []
		for c in range(1, a.size()):
			if a[c] is Color:
				out.append((a[c] as Color).lerp(b[c], u))
			else:
				out.append(lerpf(float(a[c]), float(b[c]), u))
		return out
	return last.slice(1)


# Panorama d'étoiles : des points blancs de tailles et d'éclats variés sur fond noir, concentrés
# vers le haut du ciel (la moitié basse du panorama est le sol, jamais vue).
func _stars() -> ImageTexture:
	var img := Image.create(STAR_TEX_WIDTH, STAR_TEX_HEIGHT, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for i in STAR_COUNT:
		var x := rng.randi_range(0, STAR_TEX_WIDTH - 1)
		# v proche de 0 = zénith ; on garde les étoiles dans la moitié haute, la basse est le sol
		var y := rng.randi_range(0, int(STAR_TEX_HEIGHT * 0.52))
		var b := rng.randf_range(0.30, 1.0)
		var tint := Color(b, b, b * rng.randf_range(0.90, 1.0))
		img.set_pixel(x, y, tint)
		# une sur quinze porte un seul voisin faible : de quoi lui donner un peu d'éclat sans en
		# refaire un flocon
		if rng.randf() < 0.07:
			var px := x + (1 if rng.randf() < 0.5 else -1)
			if px >= 0 and px < STAR_TEX_WIDTH:
				img.set_pixel(px, y, tint * 0.45)
	return ImageTexture.create_from_image(img)


func _build_clock() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HorlogeCycle"
	add_child(layer)
	_clock = Label.new()
	_clock.name = "Heure"
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.offset_left = -170.0
	_clock.offset_top = 8.0
	_clock.offset_right = -10.0
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.add_theme_color_override(&"font_color", Color(1, 0.95, 0.8))
	_clock.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_clock.add_theme_constant_override(&"outline_size", 4)
	_clock.visible = false
	layer.add_child(_clock)


func _find(n: Node, type_name: String) -> Node:
	if n.get_class() == type_name:
		return n
	for c in n.get_children():
		var r := _find(c, type_name)
		if r != null:
			return r
	return null
