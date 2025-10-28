#' Create an evaluation task from a samples directory
#'
#' Convenience function that loads a dataset from YAML files and creates a
#' vitals::Task with solver and scorer. This abstracts away the common pattern
#' of loading data, creating solver/scorer, and building a task.
#'
#' @param samples_dir Character string path to directory containing YAML sample files.
#' @param system_prompt Optional character string with system prompt for all samples.
#'   Default is NULL (no system prompt).
#' @param tools_dir Character string path to directory containing tool factory R files
#'   to source. Default is "tools". Set to NULL to disable auto-sourcing (e.g., if
#'   tools are already loaded from a package).
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
#' # Tools automatically sourced from tools/ directory
#' task <- create_task(
#'   samples_dir = "samples/",
#'   system_prompt = "You are a careful analyst."
#' )
#'
#' # Disable auto-sourcing if tools are in a package
#' library(mytools)
#' task <- create_task(
#'   samples_dir = "samples/",
#'   tools_dir = NULL
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
  tools_dir = "tools",
  tool_names = NULL,
  scorer_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  scorer_instructions = default_judge_instructions(),
  grade_levels = c("I", "C"),
  epochs = 1,
  name = "eval",
  dir = "logs",
  ...
) {
  # Auto-source tool files if tools_dir is specified and exists
  if (!is.null(tools_dir)) {
    source_tools(tools_dir)
  }
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
#' # Tools automatically sourced from tools/ directory
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
#'
#' # If tools are in a package, disable auto-sourcing
#' library(mytools)
#' task <- run_eval(
#'   samples_dir = "samples/",
#'   solver_chat = chat,
#'   tools_dir = NULL
#' )
#' }
run_eval <- function(
  samples_dir,
  solver_chat,
  system_prompt = NULL,
  tools_dir = "tools",
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
    tools_dir = tools_dir,
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

#' Source tool factory files from a directory
#'
#' Internal helper to source all R files from a specified directory. This is
#' used to automatically load tool factory functions before running evaluations.
#'
#' @param tools_dir Character string path to directory containing R files.
#'
#' @return Invisibly returns a character vector of sourced file paths.
#' @keywords internal
source_tools <- function(tools_dir) {
  # Check if directory exists
  if (!dir.exists(tools_dir)) {
    cli::cli_alert_warning(
      "Tools directory {.path {tools_dir}} not found. Skipping auto-sourcing."
    )
    cli::cli_text("")
    cli::cli_bullets(c(
      "i" = "Set {.code tools_dir = NULL} if tools are already loaded from a package",
      "i" = "Or create the directory and add your tool files",
      "i" = "Run {.code setup_eval()} to create a template project"
    ))
    return(invisible(character(0)))
  }

  # Find all R files
  r_files <- list.files(
    tools_dir,
    pattern = "\\.[Rr]$",
    full.names = TRUE,
    recursive = FALSE
  )

  if (length(r_files) == 0) {
    cli::cli_inform(
      "No R files found in {.path {tools_dir}}. Skipping auto-sourcing."
    )
    return(invisible(character(0)))
  }

  # Source each file
  cli::cli_inform("Sourcing {length(r_files)} file{?s} from {.path {tools_dir}}")

  sourced <- character(0)
  for (file in r_files) {
    tryCatch(
      {
        source(file, local = FALSE)
        sourced <- c(sourced, file)
      },
      error = function(e) {
        cli::cli_warn(
          "Failed to source {.path {basename(file)}}: {e$message}"
        )
      }
    )
  }

  if (length(sourced) > 0) {
    cli::cli_inform(
      "Successfully sourced: {.file {basename(sourced)}}"
    )
  }

  invisible(sourced)
}
