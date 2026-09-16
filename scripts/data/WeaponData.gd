class_name WeaponData
extends Resource

# Données d'une arme à feu. Un exemplaire de départ (valeurs par défaut ci-dessous)
# suffit pour l'instant ; on pourra créer des .tres par arme plus tard.

@export var magazine_size: int = 12
@export var current_ammo: int = 12
@export var reserve_ammo: int = 48
@export var damage: int = 25
@export var fire_rate: float = 0.40   # délai minimum entre deux tirs (secondes) ; 0.18 -> 0.24 -> 0.40
@export var reload_time: float = 1.5  # durée du rechargement (tir désactivé pendant ce temps)
@export var shot_range: float = 100.0 # portée du raycast

func can_reload() -> bool:
	return reserve_ammo > 0 and current_ammo < magazine_size

# Transfère de la réserve vers le chargeur (jusqu'à magazine_size).
func do_reload() -> void:
	var needed: int = magazine_size - current_ammo
	var moved: int = mini(needed, reserve_ammo)
	current_ammo += moved
	reserve_ammo -= moved
