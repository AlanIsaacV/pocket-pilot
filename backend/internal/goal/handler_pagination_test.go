package goal

import (
	"testing"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
)

func TestParsePage(t *testing.T) {
	limit, offset := parsePage(nil)
	if limit != 20 || offset != 0 {
		t.Fatalf("expected default limit=20 offset=0, got %d %d", limit, offset)
	}

	limit, offset = parsePage(&pb.PageRequest{PageSize: 500, PageToken: "30"})
	if limit != 100 || offset != 30 {
		t.Fatalf("expected clamped limit=100 offset=30, got %d %d", limit, offset)
	}
}

func TestNextPageToken(t *testing.T) {
	if got := nextPageToken(0, 20, 10); got != "" {
		t.Fatalf("expected empty token, got %q", got)
	}
	if got := nextPageToken(20, 20, 20); got != "40" {
		t.Fatalf("expected token 40, got %q", got)
	}
}
