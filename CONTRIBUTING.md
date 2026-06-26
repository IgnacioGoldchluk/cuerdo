# Contributing to this project

Contributions are welcome. Before opening an Issue or Pull Request please read this document. If you used AI and/or coding agents to write part of the Issue or PR please mention so.

## Commands
Same commands as most Elixir projects:
- Fetch dependencies with `mix deps.get`.
- Run tests with `mix test`.
- There are some integration tests that rely on a demo app running live, you don't have to run them and they can be left as skipped.
- Generate docs with `mix docs`.
- Run the linter with `mix credo --strict`

## Bug Reports
1. Provide a minimal reproducible case, if the failing case includes an Arazzo/OpenAPI/AsyncAPI document (when applicable) then better.
2. Specify the current and expected behavior, including the section of the Arazzo/OpenAPI/AsyncAPI specification that states the expected behavior.
3. List the Elixir, Erlang and Operating System versions if you consider them relevant.

## Feature Requests
1. Mention whether the feature is part of Arazzo specification.
2. Explain your use case and why you need the feature.

## Pull Requests
1. All Pull Requests must have an associated Issue. This is done in order to avoid wasting your time with unplanned features or false positive bugs.
2. Include tests for new features, bug fixes and refactors.
3. Follow the existing coding and documentation styles.
