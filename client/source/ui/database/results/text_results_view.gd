class_name TextResultsView
extends CodeEdit

## Read-only pretty-printed JSON of the current page of documents.


func display(documents: Array) -> void:
	text = JSON.stringify(documents, "  ")


## Pretty-print an arbitrary value verbatim (used for endpoint results, which show
## the raw response body rather than a coerced array of documents).
func display_value(value: Variant) -> void:
	text = JSON.stringify(value, "  ")
