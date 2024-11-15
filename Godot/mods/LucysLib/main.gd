extends Node

const NetManager_t := preload("res://mods/LucysLib/net.gd")
const BBCode_t := preload("res://mods/LucysLib/bbcode.gd")

var NetManager: NetManager_t
var BBCode: BBCode_t

var ALLOWED_TAG_TYPES: Array = BBCode_t.DEFAULT_ALLOWED_TYPES
var LOG_MESSAGES: bool = false
var DEBUG: bool = false

# no setting from outside
var HAS_BB_MSG: bool = false setget set_hbbmsg
var HAS_LOG_MSG: bool = false setget set_hlogmsg
func set_hbbmsg(val): pass
func set_hlogmsg(val): pass

func _enter_tree():
	NetManager = NetManager_t.new()
	BBCode = BBCode_t.new()
	#NetManager.DEBUG = true
	#BBCode.DEBUG = true

func _ready():
	print("[LUCYSLIB] LucysLib 0.1.1 ready")
	#BBCode.test()

#func packet_dump(PACKET):
#	print("[PACKET] ", PACKET)
#	print("[PACKET DECOMPRESSED DATA] ", PACKET.data.decompress_dynamic( - 1, Network.COMPRESSION_TYPE))

func register_bb_msg_support():
	if HAS_BB_MSG: return
	print("[LUCYSLIB] registering bbcode message receive support...")
	NetManager.add_network_processor("message", funcref(self, "process_packet_message"), 100)
	HAS_BB_MSG = true

func register_log_msg_support():
	if HAS_LOG_MSG: return
	print("[LUCYSLIB] registering log message support...")
	NetManager.add_network_processor("message", funcref(self, "process_packet_message_log"), -100)
	HAS_LOG_MSG = true

# future use
func process_packet_lucy_packet(DATA, PACKET_SENDER, from_host) -> bool:
	print("[LUCY PACKET] [" + str(PACKET_SENDER) + " " + str(Network._get_username_from_id(PACKET_SENDER)) + "]")
	return true

# message logging
func process_packet_message_log(DATA, PACKET_SENDER, from_host) -> bool:
	if LOG_MESSAGES:
		print("[MSG] [" + str(PACKET_SENDER) + " " + str(Network._get_username_from_id(PACKET_SENDER)) + "] " + str(DATA))
	return false

# bbcode support in messages
func process_packet_message(DATA, PACKET_SENDER, from_host) -> bool:
	var has_bb := true
	if not Network._validate_packet_information(DATA,
		["message", "color", "local", "position", "zone", "zone_owner", "bb_user", "bb_msg"],
		[TYPE_STRING, TYPE_STRING, TYPE_BOOL, TYPE_VECTOR3, TYPE_STRING, TYPE_INT, TYPE_STRING, TYPE_STRING]):
		has_bb = false
		if not Network._validate_packet_information(DATA,
			["message", "color", "local", "position", "zone", "zone_owner"],
			[TYPE_STRING, TYPE_STRING, TYPE_BOOL, TYPE_VECTOR3, TYPE_STRING, TYPE_INT]):
			return true
	
	if PlayerData.players_muted.has(PACKET_SENDER) or PlayerData.players_hidden.has(PACKET_SENDER):
		return false
	
	if not Network._message_cap(PACKET_SENDER): return false
	
	var user_id: int = PACKET_SENDER
	# this is gonna become a real color anyway but...
	# sure, the vanilla escaping is *totally* necessary
	var user_color: String = DATA["color"].left(12).replace('[','')
	var user_message: String = DATA["message"]
	
	var bb_user: String = ""
	var bb_msg: String = ""
	if has_bb:
		bb_user = DATA["bb_user"]
		bb_msg = DATA["bb_msg"]
	
	if not DATA["local"]:
		receive_safe_message(user_id, user_color, user_message, false, bb_msg, bb_user)
	else :
		var dist = DATA["position"].distance_to(Network.MESSAGE_ORIGIN)
		if DATA["zone"] == Network.MESSAGE_ZONE and DATA["zone_owner"] == PlayerData.player_saved_zone_owner:
			if dist < 25.0:
				receive_safe_message(user_id, user_color, user_message, true, bb_msg, bb_user)
	# don't process it again!
	return true

func send_message(message: BBCode_t.BBCodeTag, color: Color, local: bool = false,
		custom_name: BBCode_t.BBCodeTag = null, to: String = "peers"):
	if not message: return
	
	if not Network._message_cap(Network.STEAM_ID):
		Network._update_chat("Sending too many messages too quickly!", false)
		Network._update_chat("Sending too many messages too quickly!", true)
		return
	
	var is_host: bool = Network.GAME_MASTER or Network.PLAYING_OFFLINE
	
	if DEBUG:
		var thing = {"message": message, "color": color, "local": local,
			"custom_name": custom_name, "to": to, "is_host": is_host,
			"ALLOWED_TAG_TYPES": ALLOWED_TAG_TYPES}
		print("[LUCYSLIB send_message] ", thing)
	
	var bb_user: String = ""
	var bb_msg: String = ""
	var default_msg: String = ""
	var color_str: String = ""
	var net_name: String = Network.STEAM_USERNAME.replace('[','').replace(']','')
	
	# verify alpha & name present
	if not is_host:
		BBCode.clamp_alpha(message, 0.7)
		if custom_name:
			BBCode.clamp_alpha(custom_name, 0.7)
			if custom_name.get_stripped() != net_name:
				custom_name = null
		if not BBCode_t.find_in_strings(message,'%u'):
			message.inner.push_front('%u ')
		color.a = max(color.a, 0.7)
	
	# construct message
	if custom_name: bb_user = BBCode.parsed_to_text(custom_name, ALLOWED_TAG_TYPES, 200)
	bb_msg = BBCode.parsed_to_text(message, ALLOWED_TAG_TYPES, 500)
	default_msg = message.get_stripped().left(500)
	color_str = color.to_html(true)
	
	var msg_pos = Network.MESSAGE_ORIGIN.round()
	
	receive_safe_message(Network.STEAM_ID, color_str, default_msg, local,
		bb_msg, bb_user)
	Network._send_P2P_Packet(
		{"type": "message", "message": default_msg, "color": color_str, "local": local,
			"position": Network.MESSAGE_ORIGIN, "zone": Network.MESSAGE_ZONE,
			"zone_owner": PlayerData.player_saved_zone_owner,
			"bb_user": bb_user, "bb_msg": bb_msg},
		to, 2, Network.CHANNELS.GAME_STATE)

var _rsm_color_regex: RegEx = null
func _rsm_construct(user_id: int, color: String, message: String, local: bool,
		bb_msg: String, bb_user: String, srv_msg: bool) -> BBCode_t.BBCodeTag:
	var net_name: String = Network._get_username_from_id(user_id).replace('[','').replace(']','')
	var name := BBCode.parse_bbcode_text(net_name)
	if bb_user != "":
		if not srv_msg:
			# check that name matches net name & clamp alpha
			var user_parse := BBCode.parse_bbcode_text(bb_user)
			BBCode_t.clamp_alpha(user_parse, 0.7)
			if user_parse.get_stripped() == net_name:
				name = user_parse
		else:
			name = BBCode.parse_bbcode_text(bb_user)
	
	var to_parse = bb_msg if bb_msg != "" else message
	if not "%u" in to_parse.left(32) and not srv_msg:
		to_parse = "%u " + to_parse
	var parsed_msg := BBCode.parse_bbcode_text(to_parse)
	
	# make a node with the user's color and name
	var real_color: Color = color
	if not srv_msg: real_color.a = max(real_color.a, 0.7)
	var color_node: BBCode_t.BBCodeColorTag = BBCode_t.tag_creator(BBCode_t.TAG_TYPE.color,"")
	color_node.color = real_color
	color_node.inner = [name]
	
	BBCode.replace_in_strings(parsed_msg,"%u",color_node)
	
	return parsed_msg

func receive_safe_message(user_id: int, color: String, message: String, local: bool = false,
		bb_msg: String = "", bb_user: String = ""):
	# we don't need to check as much stuff from ourselves or host
	var srv_msg: bool = user_id == Network.STEAM_ID or user_id == Steam.getLobbyOwner(Network.STEAM_LOBBY_ID)
	if DEBUG:
		var thing = {"user_id": user_id, "color": color, "message":message, "local": local,
			"bb_msg": bb_msg, "bb_user": bb_user, "srv_msg": srv_msg}
		print("[LUCYSLIB receive_safe_message] ", thing)
	
	# lol lmao it barely even works in vanilla. idc so i'm not rewriting it
	if OptionsMenu.chat_filter:
		message = SwearFilter._filter_string(message)
		bb_msg = SwearFilter._filter_string(bb_msg)
	
	# parse
	var parsed_msg := _rsm_construct(user_id, color, message, local, bb_msg, bb_user, srv_msg)
	
	# stringify
	var final_message = BBCode.parsed_to_text(parsed_msg, ALLOWED_TAG_TYPES, 512)
	
	Network._update_chat(final_message, local)
