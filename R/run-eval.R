#' Create an evaluation task from a samples directory
#'
#' Convenience function that loads a dataset from YAML files and creates a
#' vitals::Task with solver and scorer. This abstracts away the common pattern
#' of loading data, creating solver/scorer, and building a task.
#'
#' @param samples_dir Character string path to directory containing YAML sample files.
#' @param system_prompt Optional character string with system prompt for all samples.
#'   Default is NULL (no system prompt).
#' @param tool_names Character vector of tool names to check for in scorer.
#'   If NULL (default), automatically extracts tool names from the dataset's
#'   tool aliases. You only need to specify this if you want to check for
#'   additional tool names beyond what's in the YAML files.
#' @param scorer_chat Optional ellmer Chat object for judging. Default uses
#'   Claude Sonnet 4.5.
#' @param scorer_instructions Optional custom instructions for the LLM judge.
#'   Default uses standard Correct/Incorrect instructions.
#' @param grade_levels Character vector of valid grade levels. Default is
#'   c("I", "C") for Incorrect/Correct.
#' @param epochs Number of evaluation epochs. Default is 1.
#' @param name Name for the evaluation task. Default is "eval".
#' @param dir Directory for logging results. Default is "logs".
#' @param ... Additional arguments passed to create_solver() (e.g., prompt_field,
#'   setup_field, sleep_time).
#'
#' @return A vitals::Task object ready to run with `task$eval(solver_chat)`.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create task (still need to source tool factories first!)
#' source("R/tool_create_plot.R")
#'
#' # Tool names are auto-detected from YAML files
#' task <- create_task(
#'   samples_dir = "samples/",
#'   system_prompt = "You are a careful analyst."
#' )
#'
#' # Run evaluation
#' task$eval(solver_chat = ellmer::chat_anthropic(...))
#'
#' # View results
#' task$results
#' task$accuracy()
#' }
create_task <- function(
  samples_dir,
  system_prompt = NULL,
  tool_names = NULL,
  scorer_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  scorer_instructions = default_judge_instructions(),
  grade_levels = c("I", "C"),
  epochs = 1,
  name = "eval",
  dir = "logs",
  ...
) {
  # Load dataset
  dataset <- load_yaml_dataset(samples_dir)

  # Auto-detect tool names from dataset if not provided
  if (is.null(tool_names)) {
    tool_names <- extract_tool_names(dataset)
    cli::cli_inform("Auto-detected tool names: {.val {tool_names}}")
  }

  # Create solver
  solver <- create_solver(system_prompt = system_prompt, ...)

  # Create scorer
  scorer <- create_scorer(
    scorer_chat = scorer_chat,
    tool_names = tool_names,
    instructions = scorer_instructions,
    grade_levels = grade_levels
  )

  # Create and return task
  vitals::Task$new(
    dataset = dataset,
    solver = solver,
    scorer = scorer,
    epochs = epochs,
    name = name,
    dir = dir
  )
}

#' Run a complete evaluation in one step
#'
#' Convenience function that creates a task from YAML samples and immediately
#' runs the evaluation. This is the simplest way to run an eval - just point
#' it at your samples directory and provide a chat object.
#'
#' @inheritParams create_task
#' @param solver_chat An ellmer Chat object to use for solving samples.
#'
#' @return A vitals::Task object with evaluation results already computed.
#'   Access results with `task$results` and `task$accuracy()`.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Source your tool factories first!
#' source("R/tool_create_plot.R")
#'
#' # Run evaluation in one line (tool names auto-detected!)
#' task <- run_eval(
#'   samples_dir = "samples/",
#'   solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
#'   system_prompt = "You are a careful analyst."
#' )
#'
#' # Results are ready
#' print(task$results)
#' print(task$accuracy())
#' }
run_eval <- function(
  samples_dir,
  solver_chat,
  system_prompt = NULL,
  tool_names = NULL,
  scorer_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  scorer_instructions = default_judge_instructions(),
  grade_levels = c("I", "C"),
  epochs = 1,
  name = "eval",
  dir = "logs",
  ...
) {
  # Create task
  task <- create_task(
    samples_dir = samples_dir,
    system_prompt = system_prompt,
    tool_names = tool_names,
    scorer_chat = scorer_chat,
    scorer_instructions = scorer_instructions,
    grade_levels = grade_levels,
    epochs = epochs,
    name = name,
    dir = dir,
    ...
  )

  # Run evaluation
  task$eval(solver_chat = solver_chat)

  # Return completed task
  task
}

#' Extract tool names from dataset
#'
#' Internal helper to extract unique tool names from a dataset's tool_alias
#' and tool_factory fields. Prefers aliases when available, falls back to
#' factory names.
#'
#' @param dataset A tibble with input column containing tool_alias and
#'   tool_factory fields.
#'
#' @return Character vector of unique tool names.
#' @keywords internal
extract_tool_names <- function(dataset) {
  # Get all tool aliases and factories
  tool_info <- purrr::map(dataset$input, function(inp) {
    alias <- inp$tool_alias
    factory <- inp$tool_factory

    # Prefer alias if it exists and is not NA
    if (length(alias) == 1 && !is.na(alias)) {
      return(alias)
    }

    # Otherwise use factory name as fallback
    # This won't be perfect since we don't know the default name,
    # but it's better than nothing
    factory
  })

  # Get unique names
  unique_names <- unique(unlist(tool_info))

  # Remove NA values
  unique_names <- unique_names[!is.na(unique_names)]

  # Warn if no tool names found
  if (length(unique_names) == 0) {
    cli::cli_warn(
      "Could not extract any tool names from the dataset.
      You may need to specify {.arg tool_names} manually."
    )
  }

  unique_names
}
