library(evaltools)
library(ellmer)

source(system.file("examples/tool_create_plot.R", package = "evaltools"))

task <- run_eval(
  samples_dir = system.file("examples/samples", package = "evaltools"),
  solver_chat = 
    ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  name = "interpret_plot"
)

# Run when ready
# task2$eval(solver_chat = ellmer::chat_anthropic(...))

# ============================================================================
# Before vs After Comparison
# ============================================================================

# BEFORE (verbose):
# source("R/tool.R")
# dataset <- load_yaml_dataset("samples/")
# solver <- create_solver(system_prompt = "...")
# scorer <- create_scorer(tool_names = c(...))
# task <- vitals::Task$new(dataset, solver, scorer, epochs = 1)
# task$eval(solver_chat = chat)

# AFTER (concise - tool names auto-detected!):
# source("R/tool.R")
# task <- run_eval("samples/", solver_chat = chat)

# That's it! ✨
