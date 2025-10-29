#' Create an evaluation task
#'
#' Load YAML samples and create a task with solver and scorer. Usually you'll
#' use \code{run_eval()} instead, which calls this function and runs the
#' evaluation automatically.
#'
#' @param samples_dir Path to directory with YAML sample files.
#' @param system_prompt System prompt to prepend to all samples. Default NULL.
#' @param tools_dir Path to directory with tool R files to source. Default "tools".
#'   Set to NULL if tools are already loaded (e.g., from a package).
#' @param tool_names Tool names to check in scorer. Default NULL auto-detects from
#'   YAML files.
#' @param scorer_chat Chat object for LLM judge. Default uses Claude Sonnet 4.5.
#' @param scorer_instructions Custom instructions for the judge. Default uses
#'   Correct/Incorrect grading.
#' @param grade_levels Valid grades. Default \code{c("I", "C")}.
#' @param epochs Number of evaluation runs. Default 1.
#' @param name Task name. Default "eval".
#' @param dir Logging directory. Default "logs".
#' @param view Open interactive viewer after running? Default FALSE. If you get
#'   port conflicts, use \code{vitals::vitals_view(port = custom_port)} instead.
#' @param ... Additional arguments for \code{create_solver()} (e.g., prompt_field,
#'   setup_field, sleep_time).
#'
#' @return A Task object. Call \code{task$eval(solver_chat)} to run it.
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

#' Run an evaluation
#'
#' Run an evaluation and get results as a tibble. Point it at your samples
#' directory and provide one or more language model chat objects. Results
#' include a model column, scores for each sample, and detailed metadata.
#'
#' @inheritParams create_task
#' @param solver_chat A chat object, or a named list of chat objects to test
#'   multiple models at once (e.g., \code{list(sonnet = chat1, opus = chat2)}).
#'
#' @return A tibble with one row per sample per model, containing:
#'   \itemize{
#'     \item \code{model}: Which model produced the result
#'     \item \code{id}: Sample ID from YAML file
#'     \item \code{epoch}: Evaluation epoch number
#'     \item \code{score}: Grade ("C" for Correct, "I" for Incorrect, etc.)
#'     \item \code{metadata}: List column with solver and scorer details
#'   }
#'   Task objects are stored in \code{attr(results, "tasks")} for advanced use.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Single model evaluation
#' results <- run_eval(
#'   samples_dir = "samples/",
#'   solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929")
#' )
#'
#' # Calculate accuracy
#' results |>
#'   dplyr::summarize(accuracy = mean(score == "C"))
#'
#' # Multiple models at once
#' results <- run_eval(
#'   samples_dir = "samples/",
#'   solver_chat = list(
#'     sonnet = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
#'     opus = ellmer::chat_anthropic(model = "claude-opus-4-20250514")
#'   )
#' )
#'
#' # Compare accuracy by model
#' results |>
#'   dplyr::group_by(model) |>
#'   dplyr::summarize(accuracy = mean(score == "C"))
#'
#' # Access original Task objects if needed
#' tasks <- attr(results, "tasks")
#' tasks$sonnet$accuracy()
#'
#' # If you need to view results and have port conflicts:
#' results <- run_eval(
#'   samples_dir = "samples/",
#'   solver_chat = chat_anthropic(model = "claude-sonnet-4-5-20250929"),
#'   view = FALSE  # Disable automatic viewer
#' )
#' # Then manually view with custom port
#' vitals::vitals_view(port = 8888)
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
  view = FALSE,
  ...
) {
  # Normalize solver_chat to named list
  if (!is.list(solver_chat) || inherits(solver_chat, "Chat")) {
    # Single Chat object - wrap in named list
    model_name <- tryCatch(
      {
        m <- solver_chat$turns()$system_prompt[[1]]$model
        if (is.null(m)) "model" else m
      },
      error = function(e) "model"
    )
    solver_chats <- list(model_name)
    names(solver_chats) <- model_name
    solver_chats[[1]] <- solver_chat
  } else {
    # Already a list - validate it's named
    solver_chats <- solver_chat
    if (is.null(names(solver_chats)) || any(names(solver_chats) == "")) {
      cli::cli_abort(
        "When {.arg solver_chat} is a list, it must be a named list.
        Example: {.code list(sonnet = chat1, opus = chat2)}"
      )
    }
  }

  # Run evaluation for each model
  n_models <- length(solver_chats)
  if (n_models > 1) {
    cli::cli_alert_info("Running evaluation for {n_models} model{?s}")
  }

  tasks <- list()
  for (i in seq_along(solver_chats)) {
    model_name <- names(solver_chats)[i]
    chat <- solver_chats[[i]]

    if (n_models > 1) {
      cli::cli_h2("Evaluating model: {model_name}")
    }

    # Only source tools for the first model
    task <- create_task(
      samples_dir = samples_dir,
      system_prompt = system_prompt,
      tools_dir = if (i == 1) tools_dir else NULL,
      tool_names = tool_names,
      scorer_chat = scorer_chat,
      scorer_instructions = scorer_instructions,
      grade_levels = grade_levels,
      epochs = epochs,
      name = paste0(name, "_", model_name),
      dir = dir,
      ...
    )

    task$eval(solver_chat = chat, view = view)
    tasks[[model_name]] <- task
  }

  if (n_models > 1) {
    cli::cli_alert_success("Completed evaluation for all models")
  }

  # Combine results using vitals_bind()
  results <- do.call(vitals::vitals_bind, tasks)

  # Rename "task" column to "model"
  results <- dplyr::rename(results, model = task)

  # Store Task objects as attribute
  attr(results, "tasks") <- tasks

  results
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
