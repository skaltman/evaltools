# Quickstart Demo for evaltools
# This is a complete, runnable example showing the basics

library(evaltools)
library(ellmer)
library(ggplot2)

# ============================================================================
# STEP 1: Define a tool factory
# ============================================================================

# This tool creates ggplot visualizations
# It MUST accept 'env' and optionally 'name' parameters
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

      result_type <- if (is.null(result)) "NULL" else paste(class(result), collapse = ", ")
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

# ============================================================================
# STEP 2: Create sample YAML files
# ============================================================================

# For this demo, we'll create YAML files in a temp directory
demo_dir <- tempdir()
samples_dir <- file.path(demo_dir, "samples")
dir.create(samples_dir, showWarnings = FALSE)

# Write sample 1
writeLines(
  "id: positive_correlation
type: baseline
tool:
  factory: tool_create_plot
  alias: make_viz
input:
  setup: |
    library(ggplot2)
    set.seed(123)
    df <- data.frame(x = 1:10, y = 1:10 + rnorm(10, 0, 2))
  teardown: |
    rm(df)
  prompt: |
    Use the make_viz tool to create a scatter plot of df with x on the x-axis
    and y on the y-axis. Then describe what you observe.
target: |
  The plot shows a positive correlation between x and y.",
  file.path(samples_dir, "positive_correlation.yaml")
)

# Write sample 2
writeLines(
  "id: negative_correlation
type: baseline
tool:
  factory: tool_create_plot
  alias: make_viz
input:
  setup: |
    library(ggplot2)
    set.seed(456)
    df <- data.frame(x = 1:10, y = 20 - (1:10) + rnorm(10, 0, 1))
  teardown: |
    rm(df)
  prompt: |
    Use the make_viz tool to create a scatter plot of df with x on the x-axis
    and y on the y-axis. Then describe what you observe.
target: |
  The plot shows a negative correlation between x and y.",
  file.path(samples_dir, "negative_correlation.yaml")
)

cat("Created sample YAML files in:", samples_dir, "\n\n")

# ============================================================================
# STEP 3: Load dataset
# ============================================================================

dataset <- load_yaml_dataset(samples_dir)
cat("Loaded dataset:\n")
print(dataset)
cat("\n")

# ============================================================================
# STEP 4: Create solver and scorer
# ============================================================================

solver <- create_solver(
  system_prompt = "You are a data analyst. Describe patterns you observe accurately."
)

scorer <- create_scorer(
  tool_names = c("create_plot", "make_viz"),  # Accept both names
  instructions = default_judge_instructions()
)

cat("Solver and scorer created successfully!\n\n")

# ============================================================================
# STEP 5: Create and run task (commented out - requires API key)
# ============================================================================

cat("To run the evaluation, uncomment and execute the following code:\n\n")
cat('
# Make sure you have ANTHROPIC_API_KEY set, then run:

library(vitals)

task <- vitals::Task$new(
  dataset = dataset,
  solver = solver,
  scorer = scorer,
  epochs = 1,
  name = "quickstart_demo",
  dir = tempdir()
)

task$eval(
  solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929")
)

# View results
print(task$results)
task$accuracy()

# Inspect a specific sample
task$results$result[1]  # Model\'s response
task$results$score[1]   # Grade (I/C)
task$results$scorer_metadata[[1]]  # Judge\'s reasoning
')

cat("\n============================================================================\n")
cat("Demo setup complete! The YAML files are in:", samples_dir, "\n")
cat("============================================================================\n")
