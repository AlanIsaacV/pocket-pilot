# Coding Standards

This document outlines the coding standards for Go and Dart in the Pocket Pilot project.

## General Principles
- **Clarity over Cleverness:** Write code that is easy to read and understand.
- **Surgical Changes:** Make the minimum changes necessary to fulfill a requirement.

## Go (Backend)
- **Error Handling:** Always check for errors. Prefer wrapping errors with `fmt.Errorf("context: %w", err)` for traceability.
- **Naming:** Follow standard Go naming conventions: `camelCase` for private fields and `PascalCase` for exported ones.
- **Context:** Always pass `context.Context` to database and gRPC calls.
- **Logging:** Use structured logging if available; otherwise, use `log` or `fmt` for debug purposes but remove before merging.
- **Comments:** Use idiomatic Go comments (e.g., `// Handler implements pb.AccountServiceServer`).

## Dart (Frontend)
- **Formatting:** Always run `flutter format` before committing.
- **Typing:** Avoid using `dynamic`. Use strong typing and generics wherever possible.
- **Naming:** Follow Dart's style guide: `camelCase` for variables/methods and `PascalCase` for classes.
- **Models:** Models **MUST** have a `toMap()`, `fromMap()`, `fromProto()`, and `toServerMap()` to handle various data transformations.
- **Async/Await:** Use `async`/`await` for all asynchronous operations. Handle errors with `try`/`catch` blocks in the UI or ViewModels.

## Version Control
- **Commits:** Write clear, concise commit messages starting with a type (e.g., `feat:`, `fix:`, `docs:`, `refactor:`).
- **PRs:** Break large tasks into smaller, manageable pull requests.
