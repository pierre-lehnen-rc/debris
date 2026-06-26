class_name MockData
extends RefCounted

## Placeholder data so the UI renders real-looking content before any real Mongo
## connection exists. Replace the lookups here with live driver calls later;
## the UI only depends on the shapes returned by the static helpers below.

const CONNECTIONS := [
	{
		"name": "Local",
		"host": "localhost:27017",
		"connected": true,
		"databases": [
			{
				"name": "shop",
				"collections": ["users", "orders", "products", "categories"],
			},
			{
				"name": "analytics",
				"collections": ["events", "sessions"],
			},
			{
				"name": "admin",
				"collections": ["system.users", "system.version"],
			},
		],
	},
	{
		"name": "Staging",
		"host": "staging.db.internal:27017",
		"connected": false,
		"databases": [
			{
				"name": "shop",
				"collections": ["users", "orders", "products"],
			},
		],
	},
]

# Pools used by the deterministic generators below. Keeping them module-level
# means the generated data is stable across calls (no RNG) and easy to tweak.
const _FIRST_NAMES := [
	"Ada", "Alan", "Grace", "Linus", "Margaret", "Dennis", "Barbara", "Ken",
	"Edsger", "Donald", "John", "Katherine", "Tim", "Radia", "Guido", "Bjarne",
	"James", "Anita", "Shafi", "Leslie", "Hedy", "Vint", "Brian", "Frances",
]
const _LAST_NAMES := [
	"Lovelace", "Turing", "Hopper", "Torvalds", "Hamilton", "Ritchie", "Liskov",
	"Thompson", "Dijkstra", "Knuth", "Backus", "Johnson", "Berners-Lee",
	"Perlman", "van Rossum", "Stroustrup", "Gosling", "Borg", "Goldwasser",
	"Lamport", "Lamarr", "Cerf", "Kernighan", "Allen",
]
const _CITIES := [
	{"city": "London", "zip": "EC1A"},
	{"city": "Manchester", "zip": "M1"},
	{"city": "New York", "zip": "10001"},
	{"city": "Berlin", "zip": "10115"},
	{"city": "Tokyo", "zip": "100-0001"},
	{"city": "Paris", "zip": "75001"},
	{"city": "Sydney", "zip": "2000"},
	{"city": "Toronto", "zip": "M5H"},
]
const _ROLE_SETS := [
	["admin", "editor"], ["editor"], ["viewer"], ["editor", "viewer"],
	["admin"], ["viewer", "contributor"],
]
const _ORDER_STATUS := ["shipped", "pending", "delivered", "cancelled", "refunded"]
const _PRODUCT_NAMES := [
	"Mechanical Keyboard", "Wireless Mouse", "USB-C Hub", "27\" Monitor",
	"Webcam 1080p", "Desk Mat", "Laptop Stand", "Noise-Cancelling Headset",
	"Ergonomic Chair", "Standing Desk", "Cable Organizer", "Bluetooth Speaker",
]
const _TAG_SETS := [
	["peripherals", "input"], ["display", "office"], ["audio"],
	["furniture", "ergonomics"], ["accessories"], ["peripherals", "wireless"],
]


## Returns an array of Dictionaries representing sample documents for a
## collection. Falls back to a generic shape for unknown collections. The lists
## are deliberately large so pagination is easy to exercise.
static func documents_for(collection: String) -> Array:
	match collection:
		"users":
			return _make_users(137)
		"orders":
			return _make_orders(84)
		"products":
			return _make_products(63)
		_:
			return _make_generic(40)


static func _oid(prefix: String, n: int) -> String:
	return "ObjectId('%s%08d')" % [prefix, n]


static func _make_users(count: int) -> Array:
	var docs: Array = []
	for i in count:
		var first: String = _FIRST_NAMES[i % _FIRST_NAMES.size()]
		var last: String = _LAST_NAMES[(i * 7) % _LAST_NAMES.size()]
		var handle := ("%s.%s" % [first, last]).to_lower().replace(" ", "")
		docs.append({
			"_id": _oid("64f0a1b2c3d4e5f6", i + 1),
			"name": "%s %s" % [first, last],
			"email": "%s@example.com" % handle,
			"age": 22 + (i * 3) % 45,
			"active": (i % 4) != 0,
			"roles": _ROLE_SETS[i % _ROLE_SETS.size()],
			"address": _CITIES[i % _CITIES.size()],
		})
	return docs


static func _make_orders(count: int) -> Array:
	var docs: Array = []
	for i in count:
		var cents := (i * 1373) % 20000 + 500
		docs.append({
			"_id": _oid("64f0b2c3d4e5f600", i + 1),
			"user_id": _oid("64f0a1b2c3d4e5f6", (i % 137) + 1),
			"total": float(cents) / 100.0,
			"status": _ORDER_STATUS[i % _ORDER_STATUS.size()],
			"items": 1 + (i % 6),
			"created_at": "2024-%02d-%02dT%02d:%02d:00Z" % [
				1 + (i % 12), 1 + (i % 27), (i * 5) % 24, (i * 13) % 60,
			],
		})
	return docs


static func _make_products(count: int) -> Array:
	var docs: Array = []
	for i in count:
		var base: String = _PRODUCT_NAMES[i % _PRODUCT_NAMES.size()]
		docs.append({
			"_id": _oid("64f0c3d4e5f60000", i + 1),
			"sku": "SKU-%04d" % (i + 1),
			"name": base if i < _PRODUCT_NAMES.size() else "%s v%d" % [base, i / _PRODUCT_NAMES.size() + 1],
			"price": float((i * 997) % 25000 + 499) / 100.0,
			"in_stock": (i * 17) % 250,
			"tags": _TAG_SETS[i % _TAG_SETS.size()],
		})
	return docs


static func _make_generic(count: int) -> Array:
	var docs: Array = []
	for i in count:
		docs.append({
			"_id": _oid("0000000000000000", i + 1),
			"field": "value-%d" % (i + 1),
			"count": i + 1,
		})
	return docs
