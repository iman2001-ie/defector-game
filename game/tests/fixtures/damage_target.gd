extends Area2D
## Test double: records every apply_damage call as {"amount", "source"}.

var calls: Array[Dictionary] = []


func apply_damage(amount: int, source: Node) -> void:
	calls.append({"amount": amount, "source": source})
