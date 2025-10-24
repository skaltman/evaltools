# Test script for evaltools package
# This demonstrates the basic workflow

library(evaltools)
library(ellmer)

# Source the tool factory
source(system.file("examples/tool_simple_math.R", package = "evaltools"))

# Load the dataset
samples_dir <- system.file("examples/samples", package = "evaltools")
dataset <- load_yaml_dataset(samples_dir)

print("Dataset loaded:")
print(dataset)

# Create solver (no system prompt for this simple test)
solver <- create_solver()

# Create scorer
scorer <- create_scorer(
  tool_names = c("calculate", "simple_math")
)

# Note: To run a full evaluation, you would do:
# library(vitals)
# task <- vitals::Task$new(
#   dataset = dataset,
#   solver = solver,
#   scorer = scorer,
#   epochs = 1,
#   name = "test_eval"
# )
#
# task$eval(
#   solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929")
# )
#
# print(task$results)

print("\nSolver and scorer created successfully!")
print("Package is working correctly.")
