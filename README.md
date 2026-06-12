[![CI](https://github.com/IgnacioGoldchluk/cuerdo/actions/workflows/ci.yaml/badge.svg)](https://github.com/IgnacioGoldchluk/cuerdo/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/cuerdo)](https://github.com/IgnacioGoldchluk/cuerdo/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/cuerdo.svg)](https://hex.pm/packages/cuerdo)
[![Docs](https://img.shields.io/badge/documentation-gray.svg)](https://cuerdo.hexdocs.pm)

# Cuerdo

Arazzo workflow runner and automated testing

**Still in alpha**. Expect rough edges, cryptic error messages and generally unpolished experience.

## Installation

Add `:cuerdo` to the list of dependencies in `mix.exs`

```elixir
def deps do
  [
    {:cuerdo, "~> 0.1"}
  ]
end
```

## Usage
Considering the following minimal Arazzo document
```yaml
# specs/arazzo.yaml
arazzo: 1.1.0
info:
  title: Item Creation
  version: 1.0.0

sourceDescriptions:
  - name: ecommerce
    url: https://ecommerce-api.example.com/openapi.yaml
    type: openapi

workflows:
  - workflowId: createItem
    summary: Creates an item and verifies the returned fields match the request
    inputs:
      type: object
      additionalProperties: false
      required: ["item"]
      properties:
        item:
          type: object
          additionalProperties: false
          required: ["sku", "price"]
          properties:
            sku:
              type: string
              pattern: ^SKU-[0-9]+$
            price:
              type: number
              minimum: 0.01
    outputs:
      itemId: $steps.createItemStep.response.body#/id
    steps:
      - stepId: createItemStep
        operationId: createItem
        requestBody:
          contentType: application/json
          payload: $inputs.item
        successCriteria:
          - condition: $statusCode == 201
          - condition: $response.body.sku == $request.body.sku
          - condition: $response.body.price == $request.body.price
```

Manually
```elixir
iex> inputs = %{"sku" => "SKU-123", "price" => 8.99}
iex> document = YamlElixir.read_from_file!("specs/arazzo.yaml")
iex> {:ok, context} = Cuerdo.Arazzo.run_workflow(inputs, "createItem", document)
iex> Cuerdo.Arazzo.Context.workflow_outputs(context, "createItem")
%{"itemId" => "e80dee5a-c59a-4118-ac38-f03d5ffbd028"}
```

As part of a `Cuerdo.ArazzoCase`
```elixir
defmodule MyArazzoTest do
  use Cuerdo.ArazzoCase

  arazzo_document_test document: YamlElixir.read_from_file!("specs/arazzo.yaml"), max_runs: 4
end
  # Randomly generated inputs
  # [
  #   %{"item" => %{"price" => 1.01, "sku" => "SKU-3"}},
  #   %{"item" => %{"price" => 1.01, "sku" => "SKU-4"}},
  #   %{"item" => %{"price" => 4.01, "sku" => "SKU-11"}},
  #   %{"item" => %{"price" => 0.5725, "sku" => "SKU-56"}}
  # ]
```

For more in-depth information and guides refer to any of the [useful links](#useful-links)

Contributions are welcome, please read [Contributing](./CONTRIBUTING.md) before submitting any bug report, feature request or pull request.

## Useful links
- [Package Documentation](https://cuerdo.hexdocs.pm)
- [Arazzo Overview](https://www.openapis.org/arazzo-specification)
- [Latest Arazzo Spec](https://spec.openapis.org/arazzo/v1.1.0)
- [Latest OpenAPI Spec](https://spec.openapis.org/oas/v3.2.0.html)
