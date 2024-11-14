extends Reference

var function: FuncRef
var priority: int

func _init(f: FuncRef, p: int = 0):
	function = f
	priority = p

func _to_string():
	return "(" + str(priority) + "," + function.function + ")"

static func sort(a, b):
	return a.priority < b.priority
