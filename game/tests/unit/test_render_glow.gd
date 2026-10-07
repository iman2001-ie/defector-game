extends GutTest
## RenderGlow: WorldEnvironment glow (intensity, bloom, HDR threshold) comes from
## tuning.json -> render.glow, not from the sandbox .tscn (Story 1.9, decision #30).

const SANDBOX_TSCN: String = "res://scenes/sandbox/sandbox.tscn"
# The pre-1.9 values hard-coded in sandbox.tscn: the data must be at least this bright.
const BASELINE_INTENSITY: float = 0.8
const BASELINE_BLOOM: float = 0.05
const BASELINE_THRESHOLD: float = 0.6


func after_each() -> void:
	Config.load_data()


func test_apply_sets_env_from_config() -> void:
	var env: Environment = Environment.new()
	RenderGlow.apply(env)
	assert_almost_eq(env.glow_intensity, Config.num("render.glow.intensity"), 0.0001, "intensity")
	assert_almost_eq(env.glow_bloom, Config.num("render.glow.bloom"), 0.0001, "bloom")
	assert_almost_eq(env.glow_hdr_threshold, Config.num("render.glow.hdr_threshold"), 0.0001, "threshold")


func test_apply_uses_changed_tuning() -> void:
	var glow: Dictionary = Config.tuning["render"]["glow"]
	glow["intensity"] = 1.3
	glow["bloom"] = 0.12
	glow["hdr_threshold"] = 0.45
	var env: Environment = Environment.new()
	RenderGlow.apply(env)
	assert_almost_eq(env.glow_intensity, 1.3, 0.0001)
	assert_almost_eq(env.glow_bloom, 0.12, 0.0001)
	assert_almost_eq(env.glow_hdr_threshold, 0.45, 0.0001)


func test_apply_null_env_is_safe() -> void:
	RenderGlow.apply(null)
	assert_push_error("RenderGlow")


func test_first_pass_values_are_at_least_baseline_brightness() -> void:
	var intensity: float = Config.num("render.glow.intensity")
	var bloom: float = Config.num("render.glow.bloom")
	var threshold: float = Config.num("render.glow.hdr_threshold")
	assert_gte(intensity, BASELINE_INTENSITY, "intensity >= baseline")
	assert_gte(bloom, BASELINE_BLOOM, "bloom >= baseline")
	assert_lte(threshold, BASELINE_THRESHOLD, "threshold <= baseline (lower is brighter)")
	var brighter: bool = intensity > BASELINE_INTENSITY or bloom > BASELINE_BLOOM \
			or threshold < BASELINE_THRESHOLD
	assert_true(brighter, "at least one value strictly brighter than the baseline")


func test_sandbox_tscn_does_not_hard_code_glow() -> void:
	var text: String = FileAccess.get_file_as_string(SANDBOX_TSCN)
	assert_false(text.is_empty(), "sandbox.tscn readable")
	for key: String in ["glow_intensity", "glow_bloom", "glow_hdr_threshold"]:
		assert_false(text.contains(key), "sandbox.tscn has no %s" % key)
