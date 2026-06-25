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

## Returns an array of Dictionaries representing sample documents for a
## collection. Falls back to a generic shape for unknown collections.
static func documents_for(collection: String) -> Array:
	match collection:
		"users":
			return [
				{
					"_id": "ObjectId('64f0a1b2c3d4e5f600000001')",
					"name": "Ada Lovelace",
					"email": "ada@example.com",
					"age": 36,
					"active": true,
					"roles": ["admin", "editor"],
					"address": {"city": "London", "zip": "EC1A"},
				},
				{
					"_id": "ObjectId('64f0a1b2c3d4e5f600000002')",
					"name": "Alan Turing",
					"email": "alan@example.com",
					"age": 41,
					"active": true,
					"roles": ["editor"],
					"address": {"city": "Manchester", "zip": "M1"},
				},
				{
					"_id": "ObjectId('64f0a1b2c3d4e5f600000003')",
					"name": "Grace Hopper",
					"email": "grace@example.com",
					"age": 45,
					"active": false,
					"roles": ["viewer"],
					"address": {"city": "New York", "zip": "10001"},
				},
			]
		"orders":
			return [
				{
					"_id": "ObjectId('64f0b2c3d4e5f60000000101')",
					"user_id": "ObjectId('64f0a1b2c3d4e5f600000001')",
					"total": 129.95,
					"status": "shipped",
					"items": 3,
					"created_at": "2024-01-15T10:22:00Z",
				},
				{
					"_id": "ObjectId('64f0b2c3d4e5f60000000102')",
					"user_id": "ObjectId('64f0a1b2c3d4e5f600000002')",
					"total": 49.0,
					"status": "pending",
					"items": 1,
					"created_at": "2024-01-16T08:05:00Z",
				},
			]
		"products":
			return [
				{
					"_id": "ObjectId('64f0c3d4e5f6000000000201')",
					"sku": "KB-001",
					"name": "Mechanical Keyboard",
					"price": 89.99,
					"in_stock": 120,
					"tags": ["peripherals", "input"],
				},
				{
					"_id": "ObjectId('64f0c3d4e5f6000000000202')",
					"sku": "MS-014",
					"name": "Wireless Mouse",
					"price": 24.5,
					"in_stock": 0,
					"tags": ["peripherals", "input"],
				},
			]
		_:
			return [
				{
					"_id": "ObjectId('000000000000000000000001')",
					"field": "value",
					"count": 1,
				},
				{
					"_id": "ObjectId('000000000000000000000002')",
					"field": "another",
					"count": 2,
				},
			]
