extends Reference

var DEBUG: bool = false

enum TAG_TYPE { NULL=0, ROOT=1,
	color,
	u, s, i, b, center, right,
	rainbow, tornado, shake, wave, font,
	img
}
const DEFAULT_ALLOWED_TYPES := [TAG_TYPE.color, TAG_TYPE.u, TAG_TYPE.s, TAG_TYPE.b, TAG_TYPE.i]

class BBCodeTag extends Reference:
	var inner: Array = []
	var tag_type: int = TAG_TYPE.NULL
	
	func parse_junk(junk: String):
		return
	
	func _to_string() -> String:
		return get_full(TAG_TYPE.values())
	
	func get_full(allowed_types: Array) -> String:
		var r := ""
		for n in inner:
			if n is String: r += n
			elif n is BBCodeTag: r += n.get_full(allowed_types)
		return r
	
	func get_stripped(preserve_escape:bool=false) -> String:
		var r := ""
		for n in inner:
			if n is String and preserve_escape: r += n
			elif n is String and not preserve_escape: r += n.replace("[lb]","[").replace("[rb]","]")
			elif n is BBCodeTag: r += n.get_stripped()
		return r

class BBCodeColorTag extends BBCodeTag:
	var color: Color = Color.black
	var alpha: bool = false
	var color_name: String = ""
	
	# TODO OOP tricks to make this suck less. static 
	func parse_junk(junk: String):
		var junk_regex := RegEx.new()
		junk_regex.compile("\\s*=\\s*#([0-9A-Fa-f]{8})|\\s*=\\s*#([0-9A-Fa-f]+)|\\s*=\\s*(\\S*)")
		var m := junk_regex.search(junk)
		var alpha_col = m.get_string(1)
		var code_col = m.get_string(2)
		var str_col = m.get_string(3)
		if alpha_col:
			alpha = true
			color = alpha_col
		elif code_col:
			color = code_col
		elif str_col == "transparent":
			alpha = true
			color = Color.transparent
		else:
			color_name = str_col
	
	func get_full(allowed_types: Array) -> String:
		if TAG_TYPE.color in allowed_types:
			var c = color_name if color_name else "#" + color.to_html(alpha)
			return "[color=" + c + "]" + .get_full(allowed_types) + "[/color]"
		else: return .get_full(allowed_types)

class BBCodeUnsafeTag extends BBCodeTag:
	var stuff: String
	func parse_junk(junk: String):
		stuff = junk
	func get_full(allowed_types: Array) -> String:
		var tag_str = TAG_TYPE.keys()[tag_type]
		if tag_type in allowed_types:
			return "[" + tag_str + stuff + "]" + .get_full(allowed_types) + "[/" + tag_str + "]"
		else: return .get_full(allowed_types)

class BBCodeImgTag extends BBCodeUnsafeTag:
	func get_full(allowed_types: Array) -> String:
		if TAG_TYPE.img in allowed_types:
			return .get_full(allowed_types)
		else: return ""
	# get stripped for image adds nothing!
	func get_stripped(preserve_escape:bool=false) -> String:
		return ""

class BBCodeSimpleTag extends BBCodeTag:
	func get_full(allowed_types: Array) -> String:
		var tag_str = TAG_TYPE.keys()[tag_type]
		if tag_type in allowed_types:
			return "["+tag_str+"]" + .get_full(allowed_types) + "[/" + tag_str + "]"
		else: return .get_full(allowed_types)

static func string_to_tag_type(s: String) -> int:
	var t: int = TAG_TYPE.NULL
	if TAG_TYPE.has(s): t = TAG_TYPE[s]
	return t

static func tag_creator(tag_type: int, junk: String) -> BBCodeTag:
	var n: BBCodeTag
	match tag_type:
		TAG_TYPE.color: n = BBCodeColorTag.new()
		TAG_TYPE.img: n = BBCodeImgTag.new()
		TAG_TYPE.s, TAG_TYPE.u, TAG_TYPE.i, TAG_TYPE.b,\
		TAG_TYPE.center, TAG_TYPE.right: n = BBCodeSimpleTag.new()
		TAG_TYPE.rainbow, TAG_TYPE.shake, TAG_TYPE.tornado, TAG_TYPE.wave,\
		TAG_TYPE.font:
			n = BBCodeUnsafeTag.new()
			n.tag_str = TAG_TYPE.keys()[tag_type].to_lower()
		_: n = BBCodeTag.new()
	n.tag_type = tag_type
	if junk != "": n.parse_junk(junk)
	return n

# rust rewrite when
var tag_matcher: RegEx = null
func parse_bbcode_text(text: String) -> BBCodeTag:
	if DEBUG: print("[BB] processing '"  + text + "'")
	var bb_root = BBCodeTag.new()
	bb_root.tag_type = TAG_TYPE.ROOT
	
	if not tag_matcher:
		tag_matcher = RegEx.new()
		tag_matcher.compile("(.*?)(\\[(\\w+)([^\\[\\]]*?)\\]|\\[/(\\w+)\\])")
	
	var linear_matches: Array = tag_matcher.search_all(text)
	# no tags - plaintext
	if linear_matches.empty():
		bb_root.inner = [text]
		if DEBUG: print("[BB] no tags")
		return bb_root
	
	var tag_stack: Array = []
	var last_end: int = 0
	
	# loop variables
	var end: int
	var all: String
	var before: String
	var whole_tag: String
	var tag_open: String
	var junk: String
	var tag_close: String
	var tag: String
	var is_close: bool
	var tag_type: int
	var new_tag: BBCodeTag
	var cur_tag: BBCodeTag = bb_root
	
	for m in linear_matches:
		if DEBUG: print("[BB MATCH] ", m.strings)
		end = m.get_end()
		if end != -1: last_end = end
		all = m.get_string(0)
		before = m.get_string(1)
		whole_tag = m.get_string(2)
		tag_open = m.get_string(3)
		junk = m.get_string(4)
		tag_close = m.get_string(5)
		is_close = tag_open == ""
		tag = tag_close if is_close else tag_open
		tag_type = string_to_tag_type(tag)
		
		# add leading text to current tag
		cur_tag.inner.push_back(before.replace('[','[lb]'))
		
		# special case for [lb] [rb] escapes
		if not is_close and tag == "lb" or tag == "rb":
			cur_tag.inner.push_back("["+tag+"]")
			continue
		
		# unsupported bbcode - treat as text
		if tag_type == TAG_TYPE.NULL:
			var opener = "[lb]" if not is_close else "[lb]/"
			cur_tag.inner.push_back(opener+tag+junk+"[rb]")
			continue
		
		# we got a closing tag, unroll the stack
		# until we get a matching open or root
		if is_close:
			while true:
				# matching! add text to inner, prev tag is new curr
				if cur_tag.tag_type == tag_type:
					cur_tag = tag_stack.pop_back()
					break
				# we're at the root. push as plain text
				elif tag_stack.empty():
					cur_tag.inner.push_back("[lb]/"+tag+"]")
					break
				# not matching. go back one on stack and try again
				else:
					cur_tag = tag_stack.pop_back()
		else:
			# we got an open tag, make a new tag
			new_tag = tag_creator(tag_type, junk)
			if DEBUG: print("[BB NEW TAG] " + tag + " " + str(tag_type) + " " + str(new_tag))
			# push to the current tag's data
			cur_tag.inner.push_back(new_tag)
			# push current to stack
			tag_stack.push_back(cur_tag)
			cur_tag = new_tag
	# end parse loop
	
	# end text isn't caught by the regex
	if last_end != 0:
		var end_str = text.substr(last_end).replace('[','[lb]')
		cur_tag.inner.push_back(end_str)
	# don't need to unroll stack, we have root
	
	if DEBUG: print("[BB FINAL] ", bb_root)
	return bb_root

# this sucks but i need a max_len enforce and am lazy
# TODO rewrite to be better
func parsed_to_text(bbcode: BBCodeTag, allowed_types:Array=DEFAULT_ALLOWED_TYPES, max_len:int=-1) -> String:
	if DEBUG: print("[BB parsed_to_text] ",
		{"bbcode":bbcode,"allowed_types":allowed_types,"max_len":max_len})
	# no length, return full
	if max_len == -1:
		return bbcode.get_full(allowed_types)
	
	# TODO strip better 
	var result: String = bbcode.get_full(allowed_types)
	if result.length() > max_len:
		result = bbcode.get_stripped().left(max_len)
	
	if DEBUG: print("[BB parsed_to_text] ", result)
	return result

static func clamp_alpha(bbcode: BBCodeTag, min_alpha: float):
	if bbcode is BBCodeColorTag:
		if bbcode.alpha: bbcode.color.a = max(bbcode.color.a, min_alpha)
	for n in bbcode.inner: if n is BBCodeTag: clamp_alpha(n, min_alpha)

static func apply_allowed(bbcode: BBCodeTag, allowed_tags: Array):
	if not bbcode.tag_type in allowed_tags and bbcode.tag_type != TAG_TYPE.ROOT:
		bbcode.tag_type = TAG_TYPE.NULL
	for n in bbcode.inner: if n is BBCodeTag: apply_allowed(n, allowed_tags)

func replace_in_strings(bbcode: BBCodeTag, find: String, replace) -> bool:
	var l: int
	for i in bbcode.inner.size():
		if bbcode.inner[i] is String:
			l = bbcode.inner[i].find(find)
			if l != -1:
				if DEBUG: print("[BB REPLACE] ", {"l":l,"i":i,"bbcode.inner":bbcode.inner})
				var b = bbcode.inner[i].substr(0,l)
				var a = bbcode.inner[i].substr(l+find.length())
				bbcode.inner[i] = b
				bbcode.inner.insert(i+1,replace)
				bbcode.inner.insert(i+2,a)
				if DEBUG: print("[BB REPLACE] ", {"b":b,"replace":replace,"a":a,"inner":bbcode.inner})
				return true
		elif bbcode.inner[i] is BBCodeTag:
			if replace_in_strings(bbcode.inner[i], find, replace): return true
	return false

static func find_in_strings(bbcode: BBCodeTag, find: String) -> bool:
	for n in bbcode.inner:
		if n is String:
			if find in n: return true
		elif n is BBCodeTag:
			if find_in_strings(n, find): return true
	return false

func test():
	var tests := [
		"[haha i am very cool]",
		"[b]foo[img=500]test1[/img]bar[img]test2[i]a[/i][/img][/b]",
		"foo [lb]bar[rb]",
		"foo [u]foobar[/u] bar",
		"foo [color=red]foobar[/u] bar",
		"foo [color=#10ffffff]fo[lb]obar[/u] bar",
		"foo [color=#ffffff]foobar[/u] bar",
		"foo [color=#1111111111111]foobar[/u] bar",
		"foo [color=transparent]foobar[/u] bar",
		"foo [invalid]foobar[/u] bar",
		"foo [NULL]foobar[/u] bar",
		"foo [ROOT]foobar[/u] bar",
		"foo [u][s][u]foo[/u]bar[/s] bar[/u]",
		"[color]foo [u][s][u]foo[/u]bar[/s] bar[/u]",
		"foo [u][s][u]foo[/u]bar[/u] bar[/u]",
		"[wave amp=8]test",
		"foo [u][s][u]foo[/u]bar[/s] [rainbow]bar[/u]",
		"[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a[u]a",
		"[u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u][u]a[/u]",
	]
	for test in tests:
		print("[BB TEST] ", test)
		var r := parse_bbcode_text(test)
		print("[BB TEST FULL DEFAULT] ", r.get_full(DEFAULT_ALLOWED_TYPES))
		print("[BB TEST FULL ALL] ", r.get_full(TAG_TYPE.values()))
		print("[BB TEST U] ", r.get_full([TAG_TYPE.u]))
		print("[BB TEST STRIPPED] ", r.get_stripped())
		print("[BB TEST STRIPPED(true)] ", r.get_stripped(true))
		print("[BB TEST LEN 10] ", parsed_to_text(r, DEFAULT_ALLOWED_TYPES, 10))
		clamp_alpha(r, 0.5)
		print("[BB TEST ALPHA] ", r.get_full([TAG_TYPE.color]))
