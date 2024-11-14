extends Reference

const PriorityFuncRef := preload("res://mods/LucysLib/priorityfuncref.gd")

var DEBUG: bool = false

var network_processors: Dictionary = {}

func add_network_processor(packet_type: String, function: FuncRef, priority: int = 0) -> bool:
	if not packet_type: return false
	if not function: return false
	
	if not network_processors.has(packet_type):
		network_processors[packet_type] = []
	
	if function != null:
		var pf: PriorityFuncRef = PriorityFuncRef.new(function, priority)
		var arr: Array = network_processors[packet_type]
		arr.append(pf)
		arr.sort_custom(PriorityFuncRef, "sort")
		if DEBUG:
			print("[LUCYSLIB NET] Added Network Processor for '" + packet_type + "': " + str(pf) + " new list: " + str(arr))
		return true
	return false

func clean_processor_arr(processors: Array) -> Array:
	var n: Array = []
	var pf: PriorityFuncRef
	for p in processors:
		pf = p
		if pf.function.is_valid():
			n.append(pf)
	return n

func process_packet(DATA, PACKET_SENDER, from_host) -> bool:
	if not network_processors.has(DATA["type"]): return false
	
	var processors: Array = network_processors[DATA["type"]]
	if DEBUG:
		print("[LUCYSLIB NET] Running processors for ", DATA["type"], ": ", processors)
	var pf: PriorityFuncRef
	var reject: bool = false
	var do_cleanup: bool = false
	for p in processors:
		# i want static types
		pf = p
		# call func if it exists
		if pf.function.is_valid():
			if DEBUG:
				print("[LUCYSLIB NET] processor ", pf, "...")
			reject = pf.function.call_func(DATA, PACKET_SENDER, from_host)
			if DEBUG:
				print("[LUCYSLIB NET] processor ", pf, " rejected packet: ", reject)
		else: do_cleanup = true
		# function consumed packet, no more processors
		if reject: break
	if do_cleanup:
		network_processors[DATA["type"]] = clean_processor_arr(processors)
	return reject
