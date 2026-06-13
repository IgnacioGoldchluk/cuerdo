[![CI](https://github.com/IgnacioGoldchluk/cuerdo/actions/workflows/ci.yaml/badge.svg)](https://github.com/IgnacioGoldchluk/cuerdo/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/cuerdo)](https://github.com/IgnacioGoldchluk/cuerdo/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/cuerdo.svg)](https://hex.pm/packages/cuerdo)
[![Docs](https://img.shields.io/badge/documentation-gray.svg)](https://cuerdo.hexdocs.pm)

**Still in alpha**. Expect rough edges, cryptic error messages and generally unpolished experience.

# Cuerdo
> **Transform Arazzo documents into executable property-based tests.**

## Installation

Add `:cuerdo` to the list of dependencies in `mix.exs`

```elixir
def deps do
  [
    {:cuerdo, "~> 0.1"}
  ]
end
```

## Features
- Arazzo workflow execution directly in Elixir.
- Property-based test generation from Arazzo document.
- Request and response validation against OpenAPI specifications.
- Customizable input generation, when domain-specific constraints cannot be expressed in JSON Schema.

## Quick Start
Execute workflows with automatically generated input as part of your test suite
```elixir
defmodule MyTest do
  use Cuerdo.ArazzoCase

  arazzo_document_test document: YamlElixir.read_from_file!("arazzo.yaml")
end
```

Or execute a workflow directly
```elixir
iex> inputs = %{"email" => "user@example.com", "password" => "securePassword"}
iex> document = YamlElixir.read_from_file!("arazzo.yaml")
iex> {:ok, context} = Cuerdo.Arazzo.run_workflow(inputs, "createUserWorkflow", document)
iex> Cuerdo.Arazzo.Context.workflow_outputs(context, "createUserWorkflow")
%{"token" => "userSessionToken"}
```

For more in-depth information and guides refer to any of the [useful links](#useful-links)

Contributions are welcome, please read [Contributing](./CONTRIBUTING.md) before creating any issue or pull request.

## Useful links
- [Package Documentation](https://cuerdo.hexdocs.pm)
- [Arazzo Overview](https://www.openapis.org/arazzo-specification)
- [Latest Arazzo Spec](https://spec.openapis.org/arazzo/v1.1.0)
- [Latest OpenAPI Spec](https://spec.openapis.org/oas/v3.2.0.html)


## Unsupported features and limitations

### AsyncAPI
All steps and workflows are assumed to execute synchronously and in the order they are defined.
AsyncAPI features and fields are unsupported as there is no current way of validating that a
message was published to an out-of-band broker or queue

### Workflow
- `dependsOn`: The field is ignored. If a workflow depends on another workflow then it should
  define a step that references the dependency.
- `successActions` and `failureActions` are ignored.

### Step
- `channelPath`, `correlationId`, `action`: Used exclusively by AsyncAPI.
- `onSuccess` and `onFailure`: Same as `successActions` and `failureActions` from [Workflow](#workflow)
- `in: "cookie"`
- `dependsOn`: Same as [Workflow](#workflow)

### Condition and Expression
- `xpath` and any XML functionality is unsupported
- `type` allows only strings. This means that JSONPath supports RFC-9535 version only,
and JSON Pointer (RFC-6901). Non-standard and legacy JSONPath and JSONPointer
versions are unsupported.

Failing cases **do not** shrink at the moment
