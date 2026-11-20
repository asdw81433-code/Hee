class_name PIDController2D
extends RefCounted
## Vector2 PID controller (used by the balance controller to push the body's
## centre of mass back over the feet).

var kp: float
var ki: float
var kd: float
var integral_limit: float
var _integral := Vector2.ZERO


func _init(p_kp: float = 30.0, p_ki: float = 2.0, p_kd: float = 8.0, p_integral_limit: float = 0.3) -> void:
	kp = p_kp
	ki = p_ki
	kd = p_kd
	integral_limit = p_integral_limit


## error = current offset (we want 0), rate = d(error)/dt
func update(error: Vector2, rate: Vector2, delta: float) -> Vector2:
	_integral = (_integral + error * delta).limit_length(integral_limit)
	return error * kp + _integral * ki + rate * kd


func reset() -> void:
	_integral = Vector2.ZERO
