package store

import "testing"

func TestHistoryQueryLimit(t *testing.T) {
	if got := historyQueryLimit(0); got != nil {
		t.Fatalf("complete history must not silently truncate: %v", got)
	}
	if got := historyQueryLimit(15); got != 15 {
		t.Fatalf("positive limit: %v", got)
	}
	if got := historyQueryLimit(-1); got != 20 {
		t.Fatalf("invalid limit retains default: %v", got)
	}
	if got := historyQueryLimit(10000); got != 100 {
		t.Fatalf("positive limit retains cap: %v", got)
	}
}
