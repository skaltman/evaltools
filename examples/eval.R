source("examples/R/tool_create_plot.R")

# Load dataset from YAML files
dataset <- load_yaml_dataset("examples/samples/")

# Create solver with optional system prompt
solver <- create_solver(
  system_prompt = 
    "Write 3 word answers. Do not write more than 3 words."
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