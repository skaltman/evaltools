# evaltools

Functions for creating LLM evaluations with tool-based tasks. Test language models' ability to use tools correctly and accurately describe their observations.

## Installation

```r
remotes::install_github("skaltman/evaltools")
```

## How It Works

1. **Define tools** in `tools/` - Functions that create ellmer tools for models to use
2. **Create samples** in `samples/` - YAML files describing evaluation scenarios
3. **Run evaluation** - `run_eval()` automatically loads tools, runs samples, and grades with LLM judge

You can also run `setup_eval()` to create the necessary directories and a sample YAML file. 

## Example

### 1. Define a tool 

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

### 2. Create samples, stored as YAML files

```yaml
# samples/sample1.yaml
id: positive_correlation
tool:
  name: tool_create_plot
  alias: make_plot  # If you don't want the actual tool name exposed to the model, define an alias
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

### 3. Run eval

```r
results <-
  run_eval(
    samples_dir = "samples/",
    solver_chat = chat_anthropic(model = "claude-sonnet-4-5-20250929"),
    system_prompt = "Accurately describe exactly what you observe in visualizations.",
    name = "plot"
  )
```

```
# A tibble: 1 × 4
  model id                   score metadata        
  <chr> <chr>                <ord> <list>          
1 model positive_correlation C     <tibble [1 × 8]>
```
