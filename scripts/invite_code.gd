extends RefCounted
## Packs WebRTC connection details (SDP + ICE candidates) into a short text
## code players can paste over WhatsApp, and back. Format: "BUNK-" + base64(gzip(json)).

const PREFIX := "BUNK-"


static func encode(data: Dictionary) -> String:
	var raw := JSON.stringify(data).to_utf8_buffer()
	return PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))


## Returns {} if the text isn't a valid code (typo, cut off, wrong thing pasted).
static func decode(code: String) -> Dictionary:
	var text := code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	var at := text.find(PREFIX)
	if at == -1:
		return {}
	var raw := Marshalls.base64_to_raw(text.substr(at + PREFIX.length()))
	if raw.is_empty():
		return {}
	var unpacked := raw.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_GZIP)
	if unpacked.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(unpacked.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}
