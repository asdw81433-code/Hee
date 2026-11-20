class_name BalanceController
extends RefCounted
## Inverted-pendulum balance model.
##
## The body's centre of mass (COM) drifts horizontally from the support point (feet).
## Gravity makes the drift grow (unstable), a PID "ankle/hip strategy" pushes it back
## with limited strength. When the drift is too big for posture alone the body takes
## corrective steps (stepping strategy). When even that fails, it falls.
##
## Everything is in world XZ (Vector2: x = world X, y = world Z), metres and m/s.

enum Result { STABLE, RECOVERING, STEP, FALL }

const GRAVITY := 9.81

var offset := Vector2.ZERO        ## COM displacement from support
var velocity := Vector2.ZERO      ## COM velocity relative to support
var pid := PIDController2D.new(34.0, 3.0, 9.0)

# Body properties (set from the owning character)
var pendulum_height: float = 1.0
var strength: float = 0.5          ## 0..1
var balance_skill: float = 0.5     ## 0..1
var reaction_time: float = 0.15    ## seconds before corrective control kicks in
var fatigue: float = 0.0           ## 0..1
var injury: float = 0.0            ## 0..1
var friction: float = 1.0          ## ground friction factor 0..1
var stun: float = 0.0              ## 0..1 (head hits), decays

var steps_left: int = 3
var step_cooldown: float = 0.0
var time_since_disturbance: float = 10.0
var last_control := Vector2.ZERO


func capacity() -> float:
	var c := 13.0 * (0.6 + 0.6 * strength) * (0.7 + 0.5 * balance_skill)
	c *= (1.0 - 0.45 * fatigue) * (1.0 - 0.5 * injury) * (1.0 - 0.6 * stun)
	c *= clampf(friction / 0.6, 0.25, 1.0)
	return c


func step_threshold() -> float:
	return 0.09 + 0.04 * balance_skill


func fall_threshold() -> float:
	return (0.28 + 0.12 * balance_skill) * (1.0 - 0.3 * stun) * (1.0 - 0.25 * fatigue)


func max_capture_distance() -> float:
	return (0.85 + 0.35 * balance_skill) * (1.0 - 0.3 * fatigue) * (1.0 - 0.3 * stun)


## 0 = rock solid, 1 = about to fall
func instability() -> float:
	return clampf(offset.length() / fall_threshold(), 0.0, 1.0)


func add_velocity(dv: Vector2) -> void:
	velocity += dv
	time_since_disturbance = 0.0


func add_offset(d: Vector2) -> void:
	offset += d
	time_since_disturbance = 0.0


func reset() -> void:
	offset = Vector2.ZERO
	velocity = Vector2.ZERO
	pid.reset()
	steps_left = 3
	stun = 0.0


## Integrates one step. `external_accel` covers slopes, slips, wind...
## Returns {result, step_dir, step_len}
func step(delta: float, external_accel: Vector2 = Vector2.ZERO) -> Dictionary:
	time_since_disturbance += delta
	step_cooldown = maxf(0.0, step_cooldown - delta)
	stun = maxf(0.0, stun - delta * 0.35)
	if time_since_disturbance > 1.2:
		steps_left = 3
	# Muscles resist passively at once (~45%); the active reflex ramps in after the reaction time.
	var ramp := 0.45 + 0.55 * clampf((time_since_disturbance - reaction_time) / 0.12, 0.0, 1.0)
	var control := pid.update(offset, velocity, delta) * ramp
	control = control.limit_length(capacity())
	last_control = control
	var accel := offset * (GRAVITY / pendulum_height) - control + external_accel
	velocity += accel * delta
	velocity *= 1.0 - minf(delta * 0.8, 0.5)
	offset += velocity * delta
	var dist := offset.length()
	var out := {"result": Result.STABLE, "step_dir": Vector2.ZERO, "step_len": 0.0}
	if dist > fall_threshold():
		out.result = Result.FALL
		return out
	# Capture point: where the feet would have to go to stop the body. If that is
	# further than anyone can step, the fall is unavoidable.
	var capture := offset + velocity / sqrt(GRAVITY / pendulum_height)
	if capture.length() > max_capture_distance():
		out.result = Result.FALL
		return out
	var moving_out := velocity.dot(offset) > 0.0
	if dist > step_threshold() and moving_out and step_cooldown <= 0.0 and steps_left > 0 and friction > 0.2:
		var dir := offset.normalized()
		var length := clampf(dist * 1.7 + velocity.length() * 0.18, 0.18, 0.65)
		steps_left -= 1
		step_cooldown = 0.26
		# Placing the foot under the COM removes most of the drift.
		offset -= dir * minf(length * 0.8, dist * 0.9)
		velocity *= 0.45
		out.result = Result.STEP
		out.step_dir = dir
		out.step_len = length
		return out
	if dist > 0.02 or velocity.length() > 0.05:
		out.result = Result.RECOVERING
	return out
