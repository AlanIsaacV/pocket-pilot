package migrations

import "embed"

// FS holds every SQL migration file, embedded into the binary so the `migrate`
// entrypoint can apply them on hosts that have no repo checkout and no psql
// toolchain (e.g. the Raspberry Pi, which only runs the published image).
//
// The `.sql` files remain plain files on disk, so `make migrate` (which pipes
// them through psql) keeps working unchanged.
//
//go:embed *.sql
var FS embed.FS
