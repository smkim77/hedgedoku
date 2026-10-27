class_name SupaClient
extends Node
## Minimal Supabase REST client: the same views and RPCs as the web version (leaderboard, leaderboard_week,
## submit_score, save_profile, set_nickname). Writes are accepted by the server only from the game's web
## address, so main.gd enables them only when running there.

var url := "https://fteijhmnqkogyqkdjymn.supabase.co"
var key := "sb_publishable_SlunJA77Adja0pgqi-2rUw_nal5aaub"   # publishable (public) key, as in config.js


## Returns {ok, code (HTTP status), data, error (server message or ""), headers (lower-case name -> value), net (true if no response)}.
func request(path: String, method := HTTPClient.METHOD_GET, body = null, extra := []) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	# in a browser the response arrives already unzipped; letting Godot gunzip it again fails
	http.accept_gzip = false
	add_child(http)
	var headers := ["apikey: " + key, "Content-Type: application/json"]
	if key.begins_with("eyJ"):
		headers.append("Authorization: Bearer " + key)
	headers.append_array(extra)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(url + "/rest/v1/" + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null, "error": "", "headers": {}, "net": true}
	var res: Array = await http.request_completed
	http.queue_free()
	var hdrs := {}
	for h in res[2]:
		var k: int = String(h).find(":")
		if k > 0:
			hdrs[String(h).substr(0, k).strip_edges().to_lower()] = String(h).substr(k + 1).strip_edges()
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": 0, "data": null, "error": "", "headers": hdrs, "net": true}
	if res[1] < 200 or res[1] >= 300:
		var msg := ""
		if data is Dictionary:
			msg = str(data.get("message", ""))
		return {"ok": false, "code": res[1], "data": data, "error": msg, "headers": hdrs, "net": false}
	return {"ok": true, "code": res[1], "data": data, "error": "", "headers": hdrs, "net": false}


## Total from a `Prefer: count=exact` response ("0-0/17" -> 17), or -1.
static func count_of(res: Dictionary) -> int:
	var cr: String = res.headers.get("content-range", "")
	var k := cr.find("/")
	if k < 0 or not cr.substr(k + 1).is_valid_int():
		return -1
	return int(cr.substr(k + 1))
