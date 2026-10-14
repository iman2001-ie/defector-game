extends SceneTree
## Story 8.5: write the Godot engine's licence notice for the release zip.
##
## Godot's licence-compliance docs require a redistributed game to carry the
## engine's MIT notice and the notices of the third-party code compiled into it
## (FreeType, mbedTLS, ENet and the rest). This script asks the running engine
## for them, so they always match the build that exports the game, and writes
## them in the layout of Godot's own COPYRIGHT.txt.
##
## Run it from the repo root with the 4.7.2 console build (no project needed):
##
##     "<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --script tools/godot_copyright.gd -- release/GODOT_COPYRIGHT.txt
##
## The output path comes after `--`. The file is written with CRLF line endings
## (it ends up in the zip's CREDITS.txt, read in Notepad). tools/package_release.py
## appends it to CREDITS.txt. Exit 0 when written, 1 when the file can't be
## written, 2 with no output path.

const EOL: String = "\r\n"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or args[0].strip_edges().is_empty():
		printerr("godot_copyright: pass the output path after --")
		quit(2)
		return
	var out_path: String = args[0]
	var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("godot_copyright: can't write %s (%s)" % [out_path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	var text: String = notice_text()
	file.store_string(text)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		printerr("godot_copyright: writing %s failed (%s)" % [out_path, error_string(write_error)])
		quit(1)
		return
	print("godot_copyright: wrote %s (%d bytes, Godot %s)" % [out_path, text.to_utf8_buffer().size(), Engine.get_version_info().get("string", "?")])
	quit(0)


## The whole notice: the engine's MIT licence, every copyright component and
## every licence text, joined with CRLF.
static func notice_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var version: String = str(Engine.get_version_info().get("string", ""))
	lines.append("Godot Engine %s" % version)
	lines.append("")
	lines.append("Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/")
	lines.append("Upstream-Name: Godot Engine")
	lines.append("Source: https://github.com/godotengine/godot")
	lines.append("")
	lines.append("This game uses the Godot Engine, available under the following license:")
	lines.append("")
	for line: String in normalized(Engine.get_license_text()).split("\n"):
		lines.append(line)
	lines.append("")
	lines.append("")
	lines.append("The engine and the third-party components compiled into it:")
	for component: Dictionary in Engine.get_copyright_info():
		for part: Dictionary in component.get("parts", []):
			lines.append("")
			lines.append("Files: %s" % ", ".join(PackedStringArray(part.get("files", []))))
			lines.append("Comment: %s" % str(component.get("name", "")))
			var copyrights: PackedStringArray = PackedStringArray(part.get("copyright", []))
			for i: int in copyrights.size():
				lines.append(("Copyright: %s" if i == 0 else " %s") % copyrights[i])
			lines.append("License: %s" % str(part.get("license", "")))
	var licenses: Dictionary = Engine.get_license_info()
	var names: Array = licenses.keys()
	names.sort()
	for lic_name: Variant in names:
		lines.append("")
		lines.append("License: %s" % str(lic_name))
		for line: String in normalized(str(licenses[lic_name])).split("\n"):
			lines.append(" ." if line.strip_edges().is_empty() else " " + line)
	return EOL.join(lines) + EOL


static func normalized(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n").strip_edges(false, true)
