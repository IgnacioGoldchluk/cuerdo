# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## 0.3.0 [2026-06-27]
- New CLI with better workflow progress information, summary, etc.
- Always generate HAR file

## 0.2.3 [2026-06-24]
- breaking: Replace `max_runs` for `num_runs` and `halt_on_error` options in `arazzo_document_test`
- feat: `Cuerdo.Arazzo.run_workflow/4` accepts a document and the `Context` build arguments
- fix: Cache OpenAPI schemas and Arazzo documents between workflows iteration
- fix: Print final error message before exiting
- feat: Store request/response history (HAR) in JSON report
- feat: Validate `workflow_inputs` argument matches `inputs` JSON schema
- fix: Use `json_schema_resolver` when validating workflow inputs, request body schema and response body schema

## 0.1.1 [2026-06-13]
- internal: Add evaluated expression for `FailedCriterion` `"simple"` and `"regex"` type

## 0.1.0 [2026-06-12]
Initial version
