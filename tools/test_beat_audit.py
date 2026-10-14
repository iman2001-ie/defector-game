"""Tests for tools/beat_audit.py (Story 8.4). Stdlib unittest only; no real launch.

Run from the repo root:  uv run python -m unittest tools/test_beat_audit.py

The synthetic logs below use the exact message formats the GDScript writes
(Log.format "[LEVEL][category] message"); FormatContractTest checks those
format strings are still in the game's sources.
"""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import beat_audit as tool  # noqa: E402

GAME = tool.REPO / "game"
SHIPPED_FLAGS = {
    "surrender_prompts": True,
    "isolde_interruptions": True,
    "tarek_fall": True,
    "hunter_wasp": False,
    "council_epilogue": True,
}

# A full release run from a fresh save, built from the GDScript message formats:
# boot.gd, save_manager.gd, level.gd, wave_director.gd, story.gd, comms_channel.gd, end_screen.gd.
FULL_RUN = [
    "Godot Engine v4.7.2.stable.official - https://godotengine.org",
    "[INFO][boot] Build: release",
    "[INFO][boot] Config loaded (20 tuning sections, 5 flags)",
    "[INFO][save] No save at user://save.cfg; using defaults (level 1)",
    "[INFO][scene] Title ready 1650 ms after launch",
    "[INFO][scene] Story 'opening_main' before level 1",
    "[INFO][beat] Story 'opening_main'",
    "[INFO][scene] Level 1 'Cargo Ambush' started (res://data/levels/level_1.json)",
    "[INFO][beat] Level 1 wave 1: wave_start trigger fired (2 actions)",
    "[INFO][beat] Level 1 wave 2: comms 'l1_w3_tarek_warning'",
    "[INFO][beat] Level 1 wave 3: comms 'l1_w3_isolde_interrupt'",
    "[INFO][beat] Level 1 wave 5: comms 'l1_w5_surrender'",
    "[INFO][beat] Choice 'refuse' picked in 'l1_w5_surrender'",
    "[INFO][beat] Level 1 outro 'l1_tarek_closing'",
    "[INFO][save] Saved to user://save.cfg (level 2 unlocked)",
    "[INFO][scene] Level 2 'The Blockade' started (res://data/levels/level_2.json)",
    "[INFO][beat] Level 2 intro 'l2_briefing'",
    "[INFO][beat] Level 2 wave 2: comms 'l2_w3_isolde_interrupt'",
    "[INFO][beat] Level 2 wave 5: story event 'tarek_fall'",
    "[INFO][scene] Tarek's fall: shielding Vale",
    "[INFO][beat] Level 2 outro 'l2_ryn_report'",
    "[INFO][save] Saved to user://save.cfg (level 3 unlocked)",
    "[INFO][scene] Level 3 'Siege of the Throne World' started (res://data/levels/level_3.json)",
    "[INFO][beat] Level 3 intro 'l3_briefing'",
    "[INFO][beat] Level 3 wave 2: comms 'l3_w3_isolde_taunt'",
    "[INFO][beat] Choice 'destroy' picked in 'l3_final_choice'",
    "[INFO][beat] Level 3 outro 'l3_isolde_final'",
    "[INFO][save] Saved to user://save.cfg (level 3 unlocked)",
    "[INFO][scene] Story 'ending_council' before the end screen",
    "[INFO][beat] Story 'ending_council'",
    "[INFO][scene] Going to the end screen",
    "[INFO][scene] End screen ready",
    "[INFO][beat] End screen: campaign finished 812 s after launch (final choice 'destroy')",
]


def run_text(lines: list[str]) -> str:
    return "\r\n".join(lines) + "\r\n"


def without(lines: list[str], fragment: str) -> list[str]:
    return [line for line in lines if fragment not in line]


def replaced(lines: list[str], old: str, new: str) -> list[str]:
    return [new if line == old else line for line in lines]


def statuses(report: tool.Report) -> dict[str, str]:
    return dict(report.beats)


def label_of(fragment: str) -> str:
    matches = [beat.label for beat in tool.MANIFEST if fragment in beat.label]
    assert len(matches) == 1, f"one manifest label contains {fragment!r}: {matches}"
    return matches[0]


class FullRunTest(unittest.TestCase):
    def test_a_full_release_run_passes(self) -> None:
        report = tool.audit(run_text(FULL_RUN), SHIPPED_FLAGS)
        self.assertEqual(report.reasons, [])
        self.assertTrue(report.passed)
        self.assertEqual(report.build, "release")
        self.assertTrue(report.fresh)
        self.assertEqual([status for _label, status in report.beats], [tool.OK] * len(tool.MANIFEST))
        self.assertEqual(report.attempts, {1: 1, 2: 1, 3: 1})
        self.assertEqual(report.end_s, 812)
        self.assertEqual(report.choices, [("refuse", "l1_w5_surrender"), ("destroy", "l3_final_choice")])
        self.assertEqual(report.errors, [])
        text = tool.format_report("godot.log", report)
        self.assertIn("== godot.log ==", text)
        self.assertIn("attempts L1=1 L2=1 L3=1", text)
        self.assertIn("time to end screen 812 s", text)
        self.assertIn("'refuse' in l1_w5_surrender, 'destroy' in l3_final_choice", text)
        self.assertTrue(text.endswith("result=PASS"))

    def test_kill_share_lines_are_listed_and_never_fail(self) -> None:
        self.assertIn("kill share: none", tool.format_report("x", tool.audit(run_text(FULL_RUN), SHIPPED_FLAGS)))
        lines = list(FULL_RUN)
        lines.insert(lines.index("[INFO][beat] Level 1 outro 'l1_tarek_closing'") + 1,
                     "[INFO][combat] Kills: 72 total, ally 9 (13%); target 10-15%")
        lines.insert(lines.index("[INFO][beat] Level 2 outro 'l2_ryn_report'") + 1,
                     "[INFO][combat] Kills: 35 total, ally 1 (3%); target 10-15%")
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertTrue(report.passed, "a share outside the target is information only")
        self.assertEqual(report.kill_shares, ["Kills: 72 total, ally 9 (13%); target 10-15%",
                                              "Kills: 35 total, ally 1 (3%); target 10-15%"])
        text = tool.format_report("x", report)
        self.assertIn("kill share: Kills: 72 total, ally 9 (13%); target 10-15%\n"
                      "kill share: Kills: 35 total, ally 1 (3%); target 10-15%", text, "in log order")
        self.assertNotIn("kill share: none", text)

    def test_the_manifest_has_the_ac_beats_in_order(self) -> None:
        self.assertEqual(len(tool.MANIFEST), 11)
        self.assertIn("opening_main", tool.MANIFEST[0].label)
        self.assertIs(tool.END_BEAT, tool.MANIFEST[-1])
        self.assertEqual([beat.flag for beat in tool.MANIFEST], [
            None, "isolde_interruptions", "surrender_prompts", "isolde_interruptions", "tarek_fall", None,
            "isolde_interruptions", None, None, "council_epilogue", None,
        ])

    def test_the_wave_number_is_matched_loosely(self) -> None:
        lines = replaced(FULL_RUN, "[INFO][beat] Level 1 wave 3: comms 'l1_w3_isolde_interrupt'",
                         "[INFO][beat] Level 1 wave 4: comms 'l1_w3_isolde_interrupt'")
        self.assertTrue(tool.audit(run_text(lines), SHIPPED_FLAGS).passed)

    def test_another_levels_line_does_not_count(self) -> None:
        lines = replaced(FULL_RUN, "[INFO][beat] Level 2 wave 2: comms 'l2_w3_isolde_interrupt'",
                         "[INFO][beat] Level 3 wave 2: comms 'l2_w3_isolde_interrupt'")
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertEqual(statuses(report)[label_of("l2_w3_isolde_interrupt")], tool.MISSING)


class FailureTest(unittest.TestCase):
    def test_a_missing_beat_fails(self) -> None:
        report = tool.audit(run_text(without(FULL_RUN, "story event 'tarek_fall'")), SHIPPED_FLAGS)
        self.assertEqual(statuses(report)[label_of("tarek_fall")], tool.MISSING)
        self.assertFalse(report.passed)
        self.assertIn("1 beat missing", report.reasons)
        self.assertIn("MISSING", tool.format_report("x", report))

    def test_a_beat_before_an_earlier_one_is_out_of_order(self) -> None:
        lines = without(FULL_RUN, "comms 'l1_w5_surrender'")
        lines.insert(lines.index("[INFO][beat] Story 'opening_main'"), "[INFO][beat] Level 1 wave 5: comms 'l1_w5_surrender'")
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertEqual(statuses(report)[label_of("Opening")], tool.OK)
        self.assertEqual(statuses(report)[label_of("l1_w3_isolde_interrupt")], tool.OK)
        self.assertEqual(statuses(report)[label_of("l1_w5_surrender")], tool.OUT_OF_ORDER,
                         "its first occurrence comes before the opening and Isolde's interruption")
        self.assertFalse(report.passed)
        self.assertIn("1 beat out of order", report.reasons)

    def test_repeats_on_a_retry_only_count_their_first_occurrence(self) -> None:
        lines = list(FULL_RUN)
        at = lines.index("[INFO][beat] Level 2 outro 'l2_ryn_report'")
        lines[at + 1:at + 1] = [
            "[INFO][scene] Level 3 'Siege of the Throne World' started (res://data/levels/level_3.json)",
            "[INFO][beat] Level 3 wave 2: comms 'l3_w3_isolde_taunt'",
            "[INFO][combat] Kills: 40 total, ally 5 (12%); target 10-15%",
            "[INFO][scene] Level 3 'Siege of the Throne World' started (res://data/levels/level_3.json) (retry)",
        ]
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertTrue(report.passed, report.reasons)
        self.assertEqual(report.attempts, {1: 1, 2: 1, 3: 3})

    def test_a_save_that_already_existed_is_not_fresh(self) -> None:
        lines = replaced(FULL_RUN, "[INFO][save] No save at user://save.cfg; using defaults (level 1)",
                         "[INFO][save] Save loaded from user://save.cfg (level 3 unlocked)")
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertFalse(report.fresh)
        self.assertIn("not a fresh save", report.reasons)
        self.assertIn("fresh save: NO", tool.format_report("x", report))

    def test_a_bad_save_warning_first_is_not_fresh(self) -> None:
        lines = replaced(FULL_RUN, "[INFO][save] No save at user://save.cfg; using defaults (level 1)",
                         "[WARN][save] Save user://save.cfg has no valid save_version; using defaults")
        self.assertIn("not a fresh save", tool.audit(run_text(lines), SHIPPED_FLAGS).reasons)

    def test_no_save_line_fails(self) -> None:
        report = tool.audit(run_text(without(FULL_RUN, "[INFO][save]")), SHIPPED_FLAGS)
        self.assertFalse(report.fresh)
        self.assertIn("no save line (fresh save not proven)", report.reasons)
        self.assertIn("fresh save: NO (no save line)", tool.format_report("x", report))

    def test_a_debug_build_fails(self) -> None:
        lines = replaced(FULL_RUN, "[INFO][boot] Build: release", "[INFO][boot] Build: debug")
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertEqual(report.reasons, ["not a release build"])
        self.assertIn("result=FAIL: not a release build", tool.format_report("x", report))

    def test_no_build_line_fails(self) -> None:
        report = tool.audit(run_text(without(FULL_RUN, "Build: ")), SHIPPED_FLAGS)
        self.assertIsNone(report.build)
        self.assertEqual(report.reasons, ["not a release build"])

    def test_allow_debug_turns_the_build_into_a_note(self) -> None:
        lines = replaced(FULL_RUN, "[INFO][boot] Build: release", "[INFO][boot] Build: debug")
        report = tool.audit(run_text(lines), SHIPPED_FLAGS, allow_debug=True)
        self.assertTrue(report.passed)
        self.assertEqual(report.notes, ["not a release build (allowed by --allow-debug)"])
        text = tool.format_report("x", report)
        self.assertIn("note: not a release build", text)
        self.assertTrue(text.endswith("result=PASS"))

    def test_error_lines_fail_and_are_listed(self) -> None:
        lines = list(FULL_RUN)
        lines[8:8] = [
            "[ERROR][wave] level_1.json waves[2]: spawn entry unknown",
            "ERROR: [ERROR][wave] level_1.json waves[2]: spawn entry unknown",
            "   at: push_error (core/variant/variant_utility.cpp:1024)",
            "SCRIPT ERROR: Invalid access to property or key 'x' on a base object of type 'Nil'.",
            "ERROR: Condition \"!is_inside_tree()\" is true.",
        ]
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertEqual(report.errors, [
            "[ERROR][wave] level_1.json waves[2]: spawn entry unknown",
            "SCRIPT ERROR: Invalid access to property or key 'x' on a base object of type 'Nil'.",
            "ERROR: Condition \"!is_inside_tree()\" is true.",
        ], "push_error's echo of a [ERROR] line is not listed twice")
        self.assertIn("3 errors in the log", report.reasons)
        self.assertIn("errors: 3 (first 3 listed)", tool.format_report("x", report))

    def test_a_shader_error_fails(self) -> None:
        lines = FULL_RUN + ["SHADER ERROR: Expected expression, found: ')'."]
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertEqual(report.errors, ["SHADER ERROR: Expected expression, found: ')'."])
        self.assertFalse(report.passed)

    def test_a_crash_fails(self) -> None:
        lines = FULL_RUN + ["================================================================",
                            "CrashHandlerException: Program crashed with signal 11"]
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertEqual(report.errors, ["CrashHandlerException: Program crashed with signal 11"])
        self.assertFalse(report.passed)

    def test_only_the_first_ten_errors_are_listed(self) -> None:
        lines = FULL_RUN + [f"[ERROR][data] problem {n}" for n in range(12)]
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        text = tool.format_report("x", report)
        self.assertIn("errors: 12 (first 10 listed)", text)
        self.assertIn("  [ERROR][data] problem 9", text)
        self.assertNotIn("problem 10", text)

    def test_warnings_are_only_counted(self) -> None:
        lines = FULL_RUN + [
            "[WARN][audio] no music stream for 'x'; music stays silent",
            "WARNING: [WARN][audio] no music stream for 'x'; music stays silent",
            "WARNING: ObjectDB instances leaked at exit",
        ]
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertTrue(report.passed, report.reasons)
        self.assertEqual(report.warnings, 2, "push_warning's echo is not counted twice")
        self.assertIn("warnings: 2", tool.format_report("x", report))

    def test_a_skipped_tarek_fall_scene_fails(self) -> None:
        lines = list(FULL_RUN)
        lines.insert(lines.index("[INFO][beat] Level 2 wave 5: story event 'tarek_fall'") + 1,
                     "[INFO][scene] Tarek's fall: no patrolling Tarek; scene skipped")
        report = tool.audit(run_text(lines), SHIPPED_FLAGS)
        self.assertEqual(report.errors, ["[INFO][scene] Tarek's fall: no patrolling Tarek; scene skipped"])
        self.assertFalse(report.passed)

    def test_a_run_that_never_reaches_the_end_fails(self) -> None:
        cut = FULL_RUN[:FULL_RUN.index("[INFO][beat] Level 3 outro 'l3_isolde_final'")]
        report = tool.audit(run_text(cut), SHIPPED_FLAGS)
        self.assertEqual(statuses(report)[tool.END_BEAT.label], tool.MISSING)
        self.assertIn("never reached the end screen", report.reasons)
        self.assertIsNone(report.end_s)
        self.assertIn("time to end screen n/a", tool.format_report("x", report))

    def test_an_empty_log_fails_with_every_beat_missing(self) -> None:
        report = tool.audit("", SHIPPED_FLAGS)
        self.assertEqual([status for _label, status in report.beats], [tool.MISSING] * len(tool.MANIFEST))
        self.assertIn("result=FAIL", tool.format_report("x", report))


class FlagTest(unittest.TestCase):
    def test_a_flag_off_skips_its_beat(self) -> None:
        flags = dict(SHIPPED_FLAGS, tarek_fall=False)
        report = tool.audit(run_text(without(FULL_RUN, "story event 'tarek_fall'")), flags)
        self.assertEqual(statuses(report)[label_of("tarek_fall")], tool.SKIPPED)
        self.assertTrue(report.passed, report.reasons)
        self.assertIn("skipped (flag off)", tool.format_report("x", report))

    def test_one_flag_skips_every_beat_it_gates(self) -> None:
        flags = dict(SHIPPED_FLAGS, isolde_interruptions=False)
        report = tool.audit(run_text(without(FULL_RUN, "_w3_isolde_")), flags)
        skipped = [label for label, status in report.beats if status == tool.SKIPPED]
        self.assertEqual(len(skipped), 3)
        self.assertTrue(report.passed, report.reasons)

    def test_flags_come_from_the_shipped_data(self) -> None:
        with open(GAME / "data" / "flags.json", encoding="utf-8") as handle:
            self.assertEqual(tool.load_flags(), json.load(handle))


class CommandTest(unittest.TestCase):
    def _logs_dir(self, tmp: str) -> Path:
        folder = Path(tmp) / "DEFECTOR" / "logs"
        folder.mkdir(parents=True)
        return folder

    def _write(self, path: Path, lines: list[str], mtime: float) -> None:
        path.write_text(run_text(lines), encoding="utf-8")
        os.utime(path, (mtime, mtime))

    def _main(self, argv: list[str], env: dict) -> tuple[int, str]:
        out = io.StringIO()
        code = tool.main(argv, env, out, SHIPPED_FLAGS)
        return code, out.getvalue()

    def test_paths_are_audited_and_all_pass_exits_0(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "run.log"
            self._write(log, FULL_RUN, 1000.0)
            code, text = self._main([str(log)], {})
            self.assertEqual(code, 0)
            self.assertIn("result=PASS", text)
            self.assertIn("1 log audited, 1 PASS, 0 FAIL", text)

    def test_any_fail_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            good = Path(tmp) / "good.log"
            bad = Path(tmp) / "bad.log"
            self._write(good, FULL_RUN, 1000.0)
            self._write(bad, without(FULL_RUN, "Story 'opening_main'"), 1000.0)
            code, text = self._main([str(good), str(bad)], {})
            self.assertEqual(code, 1)
            self.assertIn("2 logs audited, 1 PASS, 1 FAIL", text)

    def test_allow_debug_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "debug.log"
            self._write(log, replaced(FULL_RUN, "[INFO][boot] Build: release", "[INFO][boot] Build: debug"), 1000.0)
            self.assertEqual(self._main([str(log)], {})[0], 1)
            self.assertEqual(self._main(["--allow-debug", str(log)], {})[0], 0)

    def test_latest_picks_the_newest_logs_by_mtime(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = self._logs_dir(tmp)
            self._write(folder / "godot.log", FULL_RUN, 5000.0)
            self._write(folder / "godot2026-10-13T10.00.00.log", without(FULL_RUN, "Build: "), 4000.0)
            self._write(folder / "godot2026-10-13T09.00.00.log", FULL_RUN, 3000.0)
            self._write(folder / "godot2026-10-13T08.00.00.log", FULL_RUN, 2000.0)
            self._write(folder / "other.log", FULL_RUN, 9000.0)
            code, text = self._main(["--latest", "2"], {"APPDATA": tmp})
            self.assertEqual(code, 1, "the second-newest run fails")
            self.assertIn("2 logs audited, 1 PASS, 1 FAIL", text)
            self.assertNotIn("other.log", text, "only godot*.log")
            self.assertNotIn("T09.00.00", text, "only the 2 newest")
            self.assertLess(text.index("godot2026-10-13T10.00.00.log"), text.index("godot.log =="), "oldest first")
            self.assertEqual(tool.latest_logs(folder, 3), [
                folder / "godot2026-10-13T09.00.00.log", folder / "godot2026-10-13T10.00.00.log", folder / "godot.log"])

    def test_no_paths_defaults_to_the_newest_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = self._logs_dir(tmp)
            self._write(folder / "godot.log", FULL_RUN, 5000.0)
            self._write(folder / "godot2026-10-13T10.00.00.log", without(FULL_RUN, "Build: "), 4000.0)
            code, text = self._main([], {"APPDATA": tmp})
            self.assertEqual(code, 0)
            self.assertIn("1 log audited, 1 PASS", text)

    def test_fewer_logs_than_asked_counts_each_missing_one_as_a_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = self._logs_dir(tmp)
            self._write(folder / "godot.log", FULL_RUN, 5000.0)
            code, text = self._main(["--latest", "3"], {"APPDATA": tmp})
            self.assertEqual(code, 1, "1 clean run is not 3")
            self.assertIn("only 1 log", text)
            self.assertIn("result=PASS", text, "the log found is still audited")
            self.assertIn("1 log audited, 1 PASS, 2 FAIL (2 missing logs counted as FAIL)", text)

    def test_no_logs_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            code, text = self._main(["--latest", "3"], {"APPDATA": tmp})
            self.assertEqual(code, 2, "no log folder")
            self.assertIn("no godot*.log", text)
            self._logs_dir(tmp)
            self.assertEqual(self._main([], {"APPDATA": tmp})[0], 2, "an empty log folder")

    def test_no_appdata_exits_2(self) -> None:
        code, text = self._main([], {})
        self.assertEqual(code, 2)
        self.assertIn("APPDATA", text)

    def test_usage_errors_exit_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self._main([str(Path(tmp) / "missing.log")], {})[0], 2, "a missing file")
            log = Path(tmp) / "run.log"
            self._write(log, FULL_RUN, 1000.0)
            self.assertEqual(self._main(["--latest", "1", str(log)], {"APPDATA": tmp})[0], 2, "paths and --latest")
            self.assertEqual(self._main(["--latest", "0"], {"APPDATA": tmp})[0], 2, "--latest 0")

    def test_log_dir_comes_from_appdata(self) -> None:
        self.assertEqual(tool.log_dir({"APPDATA": os.path.join("X", "Roaming")}), Path("X") / "Roaming" / "DEFECTOR" / "logs")
        with self.assertRaises(ValueError):
            tool.log_dir({})

    def test_no_hard_coded_machine_path(self) -> None:
        source = Path(tool.__file__).read_text(encoding="utf-8")
        self.assertNotIn("C:\\Users", source)
        self.assertNotIn("C:/Users", source)


class DataDriftTest(unittest.TestCase):
    """Every id in the manifest exists in game/data, so the manifest can't drift."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.sequences: dict[str, dict] = {}
        for path in sorted((GAME / "data" / "dialogue").glob("*.json")):
            with open(path, encoding="utf-8") as handle:
                cls.sequences.update(json.load(handle)["sequences"])
        cls.levels: dict[int, dict] = {}
        for level in tool.CAMPAIGN_LEVELS:
            with open(GAME / "data" / "levels" / f"level_{level}.json", encoding="utf-8") as handle:
                cls.levels[level] = json.load(handle)
        cls.flags = tool.load_flags()

    def _actions(self, level: int, key: str) -> list[str]:
        out: list[str] = []
        for wave in self.levels[level].get("waves", []):
            for trigger in wave.get("triggers", []):
                out.extend(str(action[key]) for action in trigger.get("actions", []) if key in action)
        return out

    def test_every_sequence_id_exists_in_the_dialogue(self) -> None:
        ids = [beat.sequence for beat in tool.MANIFEST if beat.sequence is not None]
        self.assertEqual(len(ids), 9)
        for sequence in ids:
            self.assertIn(sequence, self.sequences, f"{sequence} is a dialogue sequence")
            self.assertIn(f"'{sequence}'", next(b.pattern.pattern for b in tool.MANIFEST if b.sequence == sequence))

    def test_level_beats_are_referenced_by_their_level(self) -> None:
        for beat in tool.MANIFEST:
            if beat.level is None:
                continue
            data = self.levels[beat.level]
            if beat.event is not None:
                self.assertIn(beat.event, self._actions(beat.level, "story_event"), beat.label)
                continue
            if "outro" in beat.label:
                self.assertEqual(data.get("outro_sequence"), beat.sequence, beat.label)
            elif "Choice" in beat.label:
                options = self.sequences[beat.sequence].get("choice", {}).get("options", [])
                self.assertEqual(len(options), 2, f"{beat.sequence} has the Final Choice")
                self.assertIn(beat.sequence, self._actions(beat.level, "comms") + [str(data.get("outro_sequence"))]
                              + self._flagship_sequences(), beat.label)
            else:
                self.assertIn(beat.sequence, self._actions(beat.level, "comms"), beat.label)

    def _flagship_sequences(self) -> list[str]:
        # The Flagship requests l3_final_choice itself (Flagship.FINAL_CHOICE_SEQUENCE).
        source = (GAME / "entities" / "boss" / "flagship.gd").read_text(encoding="utf-8")
        return ["l3_final_choice"] if '&"l3_final_choice"' in source else []

    def test_scene_flow_stories_are_the_scene_router_constants(self) -> None:
        source = (GAME / "autoloads" / "scene_router.gd").read_text(encoding="utf-8")
        self.assertIn('OPENING_SEQUENCE: StringName = &"opening_main"', source)
        self.assertIn('ENDING_SEQUENCE: StringName = &"ending_council"', source)

    def test_every_flag_exists(self) -> None:
        for beat in tool.MANIFEST:
            if beat.flag is not None:
                self.assertIsInstance(self.flags.get(beat.flag), bool, f"{beat.flag} in flags.json")


class FormatContractTest(unittest.TestCase):
    """The GDScript format strings the patterns rely on are still in the sources."""

    CONTRACT = {
        "scenes/boot/boot.gd": ['Log.info("boot", "Build: %s"', 'return "debug" if debug_build else "release"'],
        "autoloads/save_manager.gd": ['Log.info("save", "No save at %s', 'Log.info("save", "Save loaded from %s'],
        "scenes/level/level.gd": ['Log.info("scene", "Level %d \'%s\' started (%s)%s"',
                                  'return "Kills: %d total, ally %d (%d%%); target %d-%d%%"'],
        "scenes/story/story.gd": ['Log.info("beat", "Story \'%s\'" % _sequence)'],
        "systems/comms/comms_channel.gd": ['Log.info("beat", "Choice \'%s\' picked in \'%s\'" % [id, _requested])'],
        "scenes/end/end_screen.gd": ['Log.info("beat", "End screen: campaign finished %d s after launch (final choice \'%s\')"'],
        "systems/waves/wave_director.gd": [
            'Log.info("beat", "Level %d wave %d: comms \'%s\'"',
            'Log.info("beat", "Level %d wave %d: story event \'%s\'"',
            'Log.info("beat", "Level %d outro \'%s\'"',
        ],
        "systems/story/tarek_fall_scene.gd": [f'Log.info("scene", "{tool.TAREK_SKIPPED}")'],
        "autoloads/log.gd": ['return "[%s][%s] %s" % [level, category, msg]'],
    }

    def test_the_format_strings_are_in_the_game(self) -> None:
        for relative, snippets in self.CONTRACT.items():
            source = (GAME / relative).read_text(encoding="utf-8")
            for snippet in snippets:
                self.assertIn(snippet, source, f"{relative}")


if __name__ == "__main__":
    unittest.main()
