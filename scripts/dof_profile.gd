extends Resource
## Per-camera values. Distances are positive eye-space metres.
@export var profile_id := "standard"
@export_range(0.0, 0.35) var amount := 0.10
@export_range(1.0, 25.0) var near_clear := 6.0
@export_range(1.0, 30.0) var far_clear := 10.0
@export_range(0.1, 30.0) var near_transition := 5.0
@export_range(0.1, 100.0) var far_transition := 18.0
@export_range(0.1, 20.0) var focus_speed := 4.0

func valid() -> bool:
    return amount >= 0.0 and amount <= 0.35 and near_clear > 0.0 and far_clear > 0.0 and near_transition > 0.0 and far_transition > 0.0 and focus_speed > 0.0
