# evaltools

Tools for creating LLM evaluations with tool-based tasks. This package provides abstractions for building evaluations that test language models' ability to use tools correctly and accurately describe their observations.

## Overview

`evaltools` simplifies the creation of LLM evaluations by providing:

- **Generic solver factory**: Handles setup code execution, tool registration with aliasing, and response collection
- **Generic scorer factory**: Checks tool usage and employs LLM-as-judge for grading
- **YAML dataset loader**: Loads evaluation samples from structured YAML files
- **Tool factory utilities**: Support for tool creation with name aliasing
- **LLM judge utilities**: Reusable components for grading with language models

All components integrate with the `vitals::Task` system for running evaluations.

## Installation

```r
# Install from GitHub
remotes::install_github("skaltman/evaltools")
```

## Quick Start

### Setup a New Project

The easiest way to get started is with `setup_eval()`:

```r
library(evaltools)

# Create a new evaluation project with templates
setup_eval()
```

This creates:
- `tools/` directory with an example tool
- `samples/` directory with an example YAML file
- `README.md` with instructions

### Project Structure

A typical evaluation project looks like this:

```
my-eval/
├── tools/
│   └── tool_create_plot.R    # Your tool functions
└── samples/
    ├── sample1.yaml          # Evaluation samples
    └── sample2.yaml
```

### 1. Define a Tool Factory

Create a function that generates an ellmer tool. The function should accept `env` (execution environment) and optionally `name` (for aliasing):

```r
# Save as: tools/tool_create_plot.R
library(ellmer)

tool_create_plot <- function(env, name = "create_plot") {
  ellmer::tool(
    function(code) {
      result <- eval(parse(text = code), envir = env)
      if (inherits(result, "ggplot")) {
        temp_file <- tempfile(fileext = ".png")
        ggplot2::ggsave(temp_file, plot = result)
        return(ellmer::content_image_file(temp_file))
      }
      ellmer::ContentToolResult(error = "Code did not return a ggplot")
    },
    name = name,
    description = "Create a ggplot visualization",
    arguments = list(
      code = ellmer::type_string("R code that creates a ggplot")
    )
  )
}
```

### 2. Create YAML Samples

Each sample should specify the tool to use, setup code, a prompt, and expected target:

```yaml
# samples/sample1.yaml
id: positive_correlation
type: baseline
tool:
  name: tool_create_plot
  alias: make_plot  # Optional: name shown to model
input:
  setup: |
    df <- data.frame(x = 1:10, y = 1:10 + rnorm(10))
  teardown: |
    rm(df)
  prompt: |
    Create a plot of df with x on the x-axis and y on the y-axis.
    Describe what you observe.
target: |
  The plot shows a positive correlation between x and y.
```

### 3. Run the Evaluation

```r
library(evaltools)

# Run evaluation - tools automatically sourced from tools/ directory!
task <- run_eval(
  samples_dir = "samples/",
  solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  system_prompt = "You are an expert data analyst.",
  name = "my_eval"
)

# View results
task$results
task$accuracy()
```

**That's it!** The `run_eval()` function automatically:
- Sources tool functions from the `tools/` directory
- Loads YAML files from `samples/`
- Detects tool names from the YAML
- Creates solver/scorer and runs the evaluation

<details>
<summary>Advanced: Custom setup options</summary>

```r
# If your tools are in a package, disable auto-sourcing
library(evaltools)
library(mytools)  # Package with your tool functions

task <- run_eval(
  samples_dir = "samples/",
  solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  tools_dir = NULL  # Disable auto-sourcing
)

# Custom tools directory (e.g., for R package structure)
task <- run_eval(
  samples_dir = "samples/",
  solver_chat = chat,
  tools_dir = "R/"  # Use R/ for package-based evaluations
)

# Full manual control
library(vitals)

source("tools/tool_create_plot.R")

dataset <- load_yaml_dataset("samples/")
solver <- create_solver(system_prompt = "You are an expert data analyst.")
scorer <- create_scorer(tool_names = c("create_plot", "make_plot"))

task <- vitals::Task$new(
  dataset = dataset,
  solver = solver,
  scorer = scorer,
  epochs = 1,
  name = "my_eval"
)

task$eval(solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"))
```

</details>


## Key Features

### Tool Name Aliasing

Tools can have an internal name (in the R function) and a different name exposed to the model:

```yaml
tool:
  name: tool_make_blank_plot  # Internal R function
  alias: create_plot          # Name shown to model
```

This is useful for:
- Testing if models rely on tool names for understanding
- Creating controlled experiments with different tool names
- A/B testing tool naming conventions

### Global System Prompts

Add a system prompt that applies to all samples:

```r
solver <- create_solver(
  system_prompt = "You are a careful data analyst. Always describe exactly what you observe, even if it seems counterintuitive."
)
```

### Flexible Grading

Customize the LLM judge's instructions:

```r
custom_instructions <- function() {
  "Grade responses as Correct (C) if they mention the key pattern.
  Grade as Incorrect (I) otherwise.
  Reply with GRADE: C or GRADE: I."
}

scorer <- create_scorer(
  instructions = custom_instructions(),
  grade_levels = c("I", "C")
)
```

### Per-Sample Tool Specification

Different samples can use different tools:

```yaml
# sample1.yaml
tool:
  name: tool_create_plot

# sample2.yaml
tool:
  name: tool_create_table
```

## YAML Schema

Each YAML file should follow this structure:

```yaml
id: unique_identifier          # Required
type: category                  # Optional
tool:                          # Required
  name: tool_function_name     # Required: R function that creates the tool
  alias: exposed_name          # Optional: Name shown to model
input:                         # Required
  setup: |                     # Required: R code to run before prompt
    # Setup code
  teardown: |                  # Required: R code to run after response
    # Cleanup code
  prompt: |                    # Required: Instructions for model
    # Task description
target: |                      # Required: Expected observation for grading
  # What the model should observe
```

## Functions

### Setup Functions

- `setup_eval()`: Create a new evaluation project with template files and directory structure

### High-Level Functions (Recommended)

- `run_eval()`: Run a complete evaluation in one step (loads YAML, creates task, runs eval)
- `create_task()`: Create a task from YAML samples (like `run_eval()` but doesn't run it yet)

### Component Functions (For Advanced Usage)

- `create_solver()`: Create a solver function for vitals::Task
- `create_scorer()`: Create a scorer function for vitals::Task
- `load_yaml_dataset()`: Load YAML samples into a tibble

### Utility Functions

- `instantiate_tool()`: Call a tool factory with optional aliasing
- `create_tool_factory()`: Helper for creating standardized tool factories
- `format_judge_prompt()`: Format prompts for LLM judges
- `extract_grade()`: Parse grades from judge responses
- `check_tool_called()`: Verify successful tool usage
- `default_judge_instructions()`: Standard grading instructions

## Related Packages

- [ellmer](https://github.com/hadley/ellmer): Chat interface for LLMs
- [vitals](https://github.com/posit-dev/vitals): Evaluation framework

## License

MIT
