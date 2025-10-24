#' Create a solver function for tool-based evaluations
#'
#' Creates a solver function that executes setup code, registers tools,
#' prompts the model, and collects responses. The solver follows the pattern
#' expected by vitals::Task and supports per-sample tool specification with
#' aliasing.
#'
#' @param system_prompt Optional character string with a system prompt to add
#'   to the chat before solving each sample. Default is NULL (no system prompt).
#' @param prompt_field Character string naming the field in input that contains
#'   the task prompt. Default is "prompt".
#' @param setup_field Character string naming the field in input that contains
#'   setup code. Default is "setup".
#' @param teardown_field Character string naming the field in input that contains
#'   teardown code. Default is "teardown".
#' @param tool_factory_field Character string naming the field in input that
#'   specifies the tool factory function. Default is "tool_factory".
#' @param tool_alias_field Character string naming the field in input that
#'   specifies the tool alias. Default is "tool_alias".
#' @param sleep_time Numeric value specifying seconds to sleep between samples.
#'   Default is 15.
#' @param env_parent Environment to use as parent for execution environments.
#'   Default is .GlobalEnv.
#'
#' @return A function with signature \code{function(inputs, ..., solver_chat)}
#'   that can be used as a solver in vitals::Task. Returns a list with:
#'   \describe{
#'     \item{result}{Character vector of model responses}
#'     \item{solver_chat}{List of Chat objects used to generate responses}
#'   }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create a basic solver
#' solver <- create_solver()
#'
#' # Create solver with system prompt
#' solver <- create_solver(
#'   system_prompt = "You are an expert data analyst."
#' )
#'
#' # Create solver with custom field names
#' solver <- create_solver(
#'   prompt_field = "task_prompt",
#'   setup_field = "init_code",
#'   tool_factory_field = "tool_name"
#' )
#' }
create_solver <- function(
  system_prompt = NULL,
  prompt_field = "prompt",
  setup_field = "setup",
  teardown_field = "teardown",
  tool_factory_field = "tool_factory",
  tool_alias_field = "tool_alias",
  sleep_time = 15,
  env_parent = .GlobalEnv
) {
  function(inputs, ..., solver_chat) {
    # Validate solver_chat
    if (!inherits(solver_chat, "Chat")) {
      cli::cli_abort("{.arg solver_chat} must be a {.cls Chat} object.")
    }

    res <- vector("list", length = length(inputs))

    withr::local_options(cli.progress_show_after = 0)
    cli::cli_progress_bar("Solving", total = length(inputs))
    cli::cli_progress_update(inc = 0)

    for (i in seq_along(inputs)) {
      input <- inputs[[i]]

      # Create execution environment
      env <- new.env(parent = env_parent)

      # Run setup code
      run_code(input[[setup_field]], env)

      # Clone chat
      ch_i <- solver_chat$clone()

      # Add system prompt if provided
      if (!is.null(system_prompt)) {
        ch_i$set_system_prompt(system_prompt)
      }

      # Instantiate and register tool
      tool_factory_name <- input[[tool_factory_field]]
      tool_alias <- input[[tool_alias_field]]

      # Handle NA tool_alias (convert to NULL)
      if (length(tool_alias) == 1 && is.na(tool_alias)) {
        tool_alias <- NULL
      }

      tool <- instantiate_tool(
        factory_name = tool_factory_name,
        env = env,
        alias = tool_alias
      )

      ch_i$register_tool(tool)

      # Chat with model
      ch_i$chat(input[[prompt_field]], echo = FALSE)

      # Store result
      res[[i]] <- ch_i

      # Run teardown code
      run_code(input[[teardown_field]], env)

      # Update progress
      cli::cli_progress_update()

      # Sleep between samples
      if (i < length(inputs)) {
        Sys.sleep(sleep_time)
      }
    }

    cli::cli_progress_done()

    list(
      result = purrr::map_chr(res, function(c) c$last_turn()@text),
      solver_chat = res
    )
  }
}

#' Run R code safely
#'
#' Internal helper to evaluate R code in a specified environment with
#' warnings suppressed.
#'
#' @param code Character string containing R code to evaluate.
#' @param env Environment in which to evaluate the code.
#'
#' @return The result of evaluating the code.
#' @keywords internal
run_code <- function(code, env) {
  suppressWarnings(eval(parse(text = code), envir = env))
}
