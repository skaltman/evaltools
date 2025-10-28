library(evaltools)
library(ellmer)

# Note: For package examples, we manually source since tools are in inst/examples
# In normal usage, tools would be in tools/ and auto-sourced
source(system.file("examples/tool_create_plot.R", package = "evaltools"))

task <- run_eval(
  samples_dir = system.file("examples/samples", package = "evaltools"),
  solver_chat =
    ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  name = "interpret_plot",
  tools_dir = NULL  # Disable auto-sourcing since we manually sourced above
)

# ============================================================================
# Before vs After Comparison
# ============================================================================

# BEFORE (verbose):
# dataset <- load_yaml_dataset("samples/")
# solver <- create_solver(system_prompt = "...")
# scorer <- create_scorer(tool_names = c(...))
# task <- vitals::Task$new(dataset, solver, scorer, epochs = 1)
# task$eval(solver_chat = chat)

# AFTER (concise - tools auto-sourced from tools/!):
# task <- run_eval("samples/", solver_chat = chat)

# That's it! ✨
