# evaltools

Tools for creating LLM evaluations with tool-based tasks. Test language models' ability to use tools correctly and accurately describe their observations.

## Installation

```r
remotes::install_github("skaltman/evaltools")
```

## Quick Start

```r
library(evaltools)

# 1. Create a new project
setup_eval()

# 2. Customize tools/tool_create_plot.R and add samples

# 3. Run evaluation
task <- run_eval(
  samples_dir = "samples/",
  solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929")
)

task$results
task$accuracy()
```

## How It Works

1. **Define tools** in `tools/` - Functions that create ellmer tools for models to use
2. **Create samples** in `samples/` - YAML files describing evaluation scenarios
3. **Run evaluation** - `run_eval()` automatically loads tools, runs samples, and grades with LLM judge

### Example Tool

```r
# tools/tool_create_plot.R
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
    arguments = list(code = ellmer::type_string("R code that creates a ggplot"))
  )
}
```

### Example Sample

```yaml
# samples/sample1.yaml
id: positive_correlation
tool:
  name: tool_create_plot
  alias: make_plot  # Optional: different name shown to model
input:
  setup: |
    df <- data.frame(x = 1:10, y = 1:10 + rnorm(10))
  teardown: |
    rm(df)
  prompt: |
    Create a plot of df and describe what you observe.
target: |
  The plot shows a positive correlation between x and y.
```

## Key Features

- **Automatic tool sourcing** - Place tools in `tools/` and they're auto-loaded
- **Tool name aliasing** - Test different tool names shown to models
- **LLM-as-judge scoring** - Configurable grading with language models
- **YAML-based samples** - Simple format for evaluation scenarios
- **Integrates with vitals** - Works with the vitals evaluation framework

## Main Functions

- `setup_eval()` - Create new project with templates
- `run_eval()` - Run complete evaluation in one step
- `create_task()` - Create task without running (for more control)

See [vignette](vignettes/getting-started.md) for detailed walkthrough.

## Related Packages

- [ellmer](https://github.com/hadley/ellmer) - Chat interface for LLMs
- [vitals](https://github.com/posit-dev/vitals) - Evaluation framework

## License

MIT
