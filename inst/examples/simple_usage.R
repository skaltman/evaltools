library(evaltools)
library(ellmer)

results <- run_eval(
  samples_dir = system.file("examples/samples", package = "evaltools"),
  solver_chat = chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  name = "interpret_plot",
  tools_dir = system.file("examples/tools", package = "evaltools")
)

