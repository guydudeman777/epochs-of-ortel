class_name StateHash
extends RefCounted
## Digest of all stored properties, independent of dictionary order. Used by
## determinism and save/load tests.


static func compute(root: Resource) -> String:
	var hasher: HashingContext = HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	_feed(hasher, root)
	return hasher.finish().hex_encode()


static func _feed(hasher: HashingContext, value: Variant) -> void:
	match typeof(value):
		TYPE_OBJECT:
			var res: Resource = value as Resource
			if res == null:
				hasher.update("null;".to_utf8_buffer())
				return
			var props: Array[String] = []
			for prop: Dictionary in res.get_property_list():
				var usage: int = prop["usage"]
				var prop_name: String = prop["name"]
				if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
					props.append(prop_name)
			props.sort()
			for prop_name: String in props:
				hasher.update((prop_name + "=").to_utf8_buffer())
				_feed(hasher, res.get(prop_name))
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var keys: Array = dict.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			hasher.update("{".to_utf8_buffer())
			for key: Variant in keys:
				_feed(hasher, key)
				_feed(hasher, dict[key])
			hasher.update("}".to_utf8_buffer())
		TYPE_ARRAY:
			var list: Array = value
			hasher.update("[".to_utf8_buffer())
			for item: Variant in list:
				_feed(hasher, item)
			hasher.update("]".to_utf8_buffer())
		_:
			hasher.update((var_to_str(value) + ";").to_utf8_buffer())
