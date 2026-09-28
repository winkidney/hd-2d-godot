extends Resource
## Multipliers for each layer's own natural horizontal parallax.
const IDS = ["ridge_near", "ridge_mid", "ridge_far", "clouds_near", "clouds_far"]
@export_enum("natural", "artistic") var mode := "natural"
@export_range(0.0, 2.0) var global_strength := 1.0
@export_range(0.0, 1.0) var transition_time := 0.2
@export var layer_gains: Dictionary = {
    "ridge_near": 1.0, "ridge_mid": 1.0, "ridge_far": 1.0,
    "clouds_near": 1.0, "clouds_far": 1.0}

func requested(id: String) -> float:
    return global_strength * float(layer_gains[id])

func effective(id: String) -> float:
    return 1.0 if mode == "natural" else clampf(requested(id), 0.0, 2.0)

func valid() -> bool:
    if mode not in ["natural", "artistic"]: return false
    if not is_finite(global_strength) or global_strength < 0 or global_strength > 2: return false
    if not is_finite(transition_time) or transition_time < 0 or transition_time > 1: return false
    if layer_gains.size() != IDS.size(): return false
    for id in IDS:
        if not layer_gains.has(id): return false
        var value = layer_gains[id]
        if typeof(value) not in [TYPE_FLOAT, TYPE_INT]: return false
        if not is_finite(float(value)) or value < 0 or value > 2: return false
    return true
