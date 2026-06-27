class_name FlatSchema
extends DatabaseSchema

## A schema that performs no grouping at all: every collection is shown at the
## top level as a flat list, in the order the caller supplies. Useful when the
## grouping heuristics get in the way and you want the raw collection list.

## No structure is needed; path_for maps each name straight to a top-level leaf.
func build_structure(_names: Array) -> Array:
	return []


## Every collection sits at the root, so its path is just its own name.
func path_for(_structure: Array, name: String) -> Array:
	return [name]
