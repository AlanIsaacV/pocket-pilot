# Pocket Pilot - Agent Context Index

This file is the entry point for all AI agents (Gemini CLI, Claude Code, OpenCode). To maintain consistency, technical documentation and architectural conventions have been moved to the `docs/context/` directory.

## Critical Instructions for Agents
1. **Read the Manifest:** Before starting any task, read [docs/context/MANIFEST.md](docs/context/MANIFEST.md) to identify the relevant files for the current domain.
2. **Follow Conventions:** Adhere strictly to the coding and architectural patterns defined in `docs/context/architecture/` and `docs/context/conventions/`.
3. **Log Changes:** Every technical decision or convention change made during the session **MUST** be logged in [docs/context/.journal.md](docs/context/.journal.md).
4. **Consolidate:** At the end of a session, if the user requests a "save" or "consolidate," update the permanent documentation in `docs/context/` using the entries from `.journal.md`.

## Directory Map
- **Protobuf Contracts:** `proto/`
- **Backend (Go):** `backend/`
- **Frontend (Flutter):** `frontend/`
- **Context Documentation:** `docs/context/`

---
*This file is a pointer to ensure all agents share the same source of truth.*
