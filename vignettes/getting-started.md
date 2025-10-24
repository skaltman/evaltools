# Getting Started with evaltools

This guide walks through creating a complete evaluation from scratch.

## Step 1: Install evaltools

```r
remotes::install_local("/Users/saraa/GitHub/skaltman/evaltools")
library(evaltools)
library(ellmer)
library(vitals)
```

## Step 2: Create a Tool Factory

A tool factory is a function that creates an ellmer tool. It must accept `env` (execution environment) and optionally `name` (for aliasing).

```r
# Save this as: R/tool_create_plot.R

tool_create_plot <- function(env, name = "create_plot") {
  ellmer::tool(
    function(code) {
      result <- tryCatch(
        eval(parse(text = code), envir = env),
        error = function(e) {
          return(ellmer::ContentToolResult(error = conditionMessage(e)))
        }
      )

      if (inherits(result, "ContentToolResult")) {
        return(result)
      }

      if (inherits(result, "ggplot")) {
        temp_file <- tempfile(fileext = ".png")
        ggplot2::ggsave(temp_file, plot = result, width = 7, height = 5)
        return(ellmer::content_image_file(temp_file))
      }

      result_type <- if (is.null(result)) "NULL" else class(result)
      ellmer::ContentToolResult(
        error = paste0("Code did not return a ggplot. Got: ", result_type)
      )
    },
    name = name,
    description = "Create a ggplot visualization from R code",
    arguments = list(
      code = ellmer::type_string(
        "R code that begins with library(ggplot2) and creates a ggplot object"
      )
    )
  )
}
```

**Important**: The tool factory function must be accessible when you run the evaluation. Either:
- Source it before loading the dataset
- Put it in a package and load that package

## Step 3: Create YAML Samples

Each YAML file defines one evaluation sample. Create a directory like `samples/`:

```yaml
# samples/positive_correlation.yaml
id: positive_correlation
type: baseline
tool:
  factory: tool_create_plot  # Name of your R function
  alias: make_plot           # Optional: name shown to model
input:
  setup: |
    library(ggplot2)
    set.seed(123)
    df <- data.frame(
      x = 1:20,
      y = 2 * (1:20) + rnorm(20, 0, 5)
    )
  teardown: |
    rm(df)
  prompt: |
    Create a plot showing the relationship between x and y in the df dataset.
    Describe what you observe.
target: |
  The plot shows a positive correlation between x and y. As x increases,
  y also increases.
```

```yaml
# samples/negative_correlation.yaml
id: negative_correlation
type: baseline
tool:
  factory: tool_create_plot
  alias: make_plot
input:
  setup: |
    library(ggplot2)
    set.seed(456)
    df <- data.frame(
      x = 1:20,
      y = 40 - 2 * (1:20) + rnorm(20, 0, 3)
    )
  teardown: |
    rm(df)
  prompt: |
    Create a plot showing the relationship between x and y in the df dataset.
    Describe what you observe.
target: |
  The plot shows a negative correlation between x and y. As x increases,
  y decreases.
```

## Step 4: Set Up and Run the Evaluation

```r
# Load the tool factory first!
source("R/tool_create_plot.R")

# Load dataset from YAML files
dataset <- load_yaml_dataset("samples/")
print(dataset)

# Create solver with optional system prompt
solver <- create_solver(
  system_prompt = "You are a data analyst. Describe exactly what you observe in visualizations."
)

# Create scorer
scorer <- create_scorer(
  tool_names = c("create_plot", "make_plot"),  # Accept either name
  prompt_field = "prompt",
  target_field = "target"
)

# Create task
task <- vitals::Task$new(
  dataset = dataset,
  solver = solver,
  scorer = scorer,
  epochs = 1,
  name = "my_plot_eval",
  dir = "logs"
)

# Run evaluation
task$eval(
  solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929")
)

# View results
print(task$results)
task$accuracy()
```

## Step 5: Inspect Results

```r
# Get detailed results
results <- task$results

# See model responses
results$result

# See scores
results$score

# See scorer metadata (judge prompts and responses)
results$scorer_metadata[[1]]

# View chat history for a sample
results$solver_chat[[1]]$get_turns()
```

## Customization Options

### Custom Judge Instructions

```r
my_instructions <- function() {
  "Grade as Correct (C) if the response mentions the key trend.
  Grade as Incorrect (I) otherwise.
  Reply with GRADE: C or GRADE: I."
}

scorer <- create_scorer(
  tool_names = "create_plot",
  instructions = my_instructions()
)
```

### Different Tool per Sample

```yaml
# samples/sample1.yaml
tool:
  factory: tool_create_plot

# samples/sample2.yaml
tool:
  factory: tool_create_table
```

Just make sure both tool factories are sourced before loading the dataset.

### Run Subset of Samples

```r
# Load full dataset
dataset <- load_yaml_dataset("samples/")

# Run only baseline samples
baseline_dataset <- dataset[dataset$type == "baseline", ]

task <- vitals::Task$new(
  dataset = baseline_dataset,
  solver = solver,
  scorer = scorer,
  epochs = 1
)
```

### Custom Field Names

If your YAML uses different field names:

```r
solver <- create_solver(
  prompt_field = "task_description",  # Instead of "prompt"
  setup_field = "init_code"           # Instead of "setup"
)

scorer <- create_scorer(
  tool_names = "create_plot",
  prompt_field = "task_description",
  target_field = "expected_answer"
)
```

## Complete Working Example

See `inst/examples/test_evaltools.R` in the package for a complete working example with a simple math tool.

## Tips

1. **Test your tool factory independently** before running the full eval:
   ```r
   source("R/tool_create_plot.R")
   env <- new.env()
   env$x <- 5
   tool <- tool_create_plot(env)
   # Test it with a chat
   ```

2. **Start with a small dataset** (1-2 samples) to test your setup

3. **Use descriptive targets** in YAML - they become the grading criteria

4. **Check solver_metadata** if samples are graded as Incorrect to see why:
   ```r
   results$scorer_metadata[[1]]$response  # See judge's reasoning
   ```

5. **Tool aliasing is powerful** for experiments - you can test if models behave differently when a tool is named `create_blank_plot` vs `create_plot`
