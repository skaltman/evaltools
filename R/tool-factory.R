#' Instantiate a tool from a factory function
#'
#' Creates a tool by calling a factory function with optional name aliasing.
#' The factory function should accept at minimum an `env` parameter for the
#' execution environment, and optionally a `name` parameter for aliasing.
#'
#' @param factory_name Character string naming the factory function to call.
#'   The function should follow the convention of accepting `env` and
#'   optionally `name` parameters.
#' @param env Environment in which the tool's code will execute.
#' @param alias Optional character string to use as the tool's name instead
#'   of the factory's default. If the factory function accepts a `name`
#'   parameter, this will be passed to it.
#'
#' @return An ellmer tool object returned by the factory function.
#'
#' @details
#' Tool factory functions should follow this signature:
#' \code{tool_factory(env, name = NULL)}
#'
#' If \code{name} is NULL, the factory should use its default name.
#' If \code{name} is provided, it should create the tool with that name.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Define a tool factory
#' tool_create_plot <- function(env, name = "create_plot") {
#'   ellmer::tool(
#'     function(code) run_code(code, env),
#'     name = name,
#'     description = "Create a plot from R code"
#'   )
#' }
#'
#' # Instantiate with default name
#' tool1 <- instantiate_tool("tool_create_plot", new.env())
#'
#' # Instantiate with alias
#' tool2 <- instantiate_tool("tool_create_plot", new.env(), alias = "make_plot")
#' }
instantiate_tool <- function(factory_name, env, alias = NULL) {
  # Get the factory function
  factory_fn <- get(factory_name, mode = "function")

  # Check if factory accepts a name parameter
  factory_args <- names(formals(factory_fn))

  if ("name" %in% factory_args && !is.null(alias)) {
    # Call factory with custom name
    tool <- factory_fn(env = env, name = alias)
  } else {
    # Call factory with just env
    tool <- factory_fn(env = env)

    if (!is.null(alias)) {
      cli::cli_warn(
        "Factory {.fn {factory_name}} does not accept a {.arg name} parameter.
        Alias {.val {alias}} will be ignored."
      )
    }
  }

  tool
}

#' Create a standard tool factory wrapper
#'
#' Helper to create tool factory functions that follow evaltools conventions.
#' This ensures consistent handling of name aliasing across all tools.
#'
#' @param executor Function that executes the tool's logic. Should take
#'   appropriate parameters for the tool's operation.
#' @param default_name Default name for the tool if no alias is provided.
#' @param description Description of what the tool does.
#' @param arguments Named list of argument specifications for ellmer::tool().
#'
#' @return A factory function with signature \code{function(env, name = NULL)}.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create a tool factory
#' tool_create_plot <- create_tool_factory(
#'   executor = function(code, env) {
#'     eval(parse(text = code), envir = env)
#'   },
#'   default_name = "create_plot",
#'   description = "Create a plot from R code",
#'   arguments = list(
#'     code = ellmer::type_string("R code to execute")
#'   )
#' )
#'
#' # Use the factory
#' tool <- tool_create_plot(env = new.env(), name = "make_plot")
#' }
create_tool_factory <- function(executor, default_name, description, arguments) {
  function(env, name = NULL) {
    tool_name <- if (!is.null(name)) name else default_name

    # Create a wrapper function that captures the env
    tool_fn <- function(...) {
      executor(..., env = env)
    }

    ellmer::tool(
      tool_fn,
      name = tool_name,
      description = description,
      arguments = arguments
    )
  }
}
