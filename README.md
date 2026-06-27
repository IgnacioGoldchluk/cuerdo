[![CI](https://github.com/IgnacioGoldchluk/cuerdo/actions/workflows/ci.yaml/badge.svg)](https://github.com/IgnacioGoldchluk/cuerdo/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/cuerdo)](https://github.com/IgnacioGoldchluk/cuerdo/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/cuerdo.svg)](https://hex.pm/packages/cuerdo)
[![Docs](https://img.shields.io/badge/documentation-gray.svg)](https://cuerdo.hexdocs.pm)
[![Read the blog post](https://img.shields.io/badge/read%20the%20blog%20post-gray)
](https://ignaciogoldchluk.com/property-based-testing-for-api-workflows/)

> [!IMPORTANT]
> This project is still in alpha/experimental stage. Bug reports and contributions are more than welcome

# Cuerdo
> **Transform Arazzo documents into executable property-based tests.**

![Running an Arazzo Document](https://raw.githubusercontent.com/IgnacioGoldchluk/cuerdo/main/img/demo.gif)

## Why Cuerdo?
APIs are usually tested with a handful of "happy path" examples. Over time, bugs are discovered and added to the test suite manually. This process is slow, and many bugs reach production, impacting users.

*Cuerdo* automatically generates hundreds or thousands of test cases from you Arazzo workflows with automatically generated inputs, validating requests and responses against OpenAPI schemas and discovering edge cases that are commonly missed by example-based testing.

## Features
- Generates hundreds or thousands of test cases for each Arazzo workflow.
- Validates every request and response against your OpenAPI schemas.
- Compatible with latest Arazzo 1.1 specification.
- Supports custom input generation when domain-specific constraints cannot be expressed in JSON Schema.
- Exports HAR-like logs for debugging and reproducing failures.
- Available as command-line tool, Docker image and Elixir library.

## Quick Start

### Executable (recommended)
Download the executable from the [releases](https://github.com/IgnacioGoldchluk/cuerdo/releases) page (no Elixir/Erlang required), and run it as
```sh
./cuerdo_linux_amd64 path/to/arazzo.yaml
```

### Dockerfile
Run `cuerdo` from a Docker image. Keep in mind you need to mount the local files.
```sh
docker run --rm -v "$PWD:/documents" -w /documents igsomething/cuerdo test/support/arazzo.yaml
```

### From Elixir
Add `:cuerdo` to the list of dependencies in `mix.exs`

```elixir
def deps do
  [
    {:cuerdo, "~> 0.1"}
  ]
end
```

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
