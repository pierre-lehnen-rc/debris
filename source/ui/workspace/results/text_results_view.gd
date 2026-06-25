class_name TextResultsView
extends CodeEdit

## Read-only pretty-printed JSON of the current page of documents.


func display(documents: Array) -> void:
	text = JSON.stringify(documents, "  ")
