class_name ImpactTier
## Impact feedback tiers (architecture: Impact Feedback Tiers). Tier rows live in
## tuning.feedback.tiers; entities store a tier and pass it to Feedback (Story 1.6).

enum { SMALL, MEDIUM, LARGE, BOSS_PART, BOSS_DEATH, PLAYER_HIT, PLAYER_DEATH }

const _BY_NAME: Dictionary[String, int] = {
	"small": SMALL,
	"medium": MEDIUM,
	"large": LARGE,
	"boss_part": BOSS_PART,
	"boss_death": BOSS_DEATH,
	"player_hit": PLAYER_HIT,
	"player_death": PLAYER_DEATH,
}


## Maps a snake_case tier name from data to the enum. Unknown names log and return SMALL.
static func from_name(tier_name: String) -> int:
	if _BY_NAME.has(tier_name):
		return _BY_NAME[tier_name]
	Log.error("data", "unknown impact tier '%s'" % tier_name)
	return SMALL
