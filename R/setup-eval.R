#' Set up a new evaluation project
#'
#' Creates a standard directory structure with template files for starting
#' a new evaluation. This includes creating `tools/` and `samples/` directories
#' and populating them with example files.
#'
#' @param path Character string path to the directory where the evaluation
#'   should be created. Default is current working directory.
#' @param tool_name Character string name for the example tool function.
#'   Default is "tool_create_plot".
#' @param overwrite Logical indicating whether to overwrite existing files.
#'   Default is FALSE.
#'
#' @return Invisibly returns the path to the created directory.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create evaluation in current directory
#' setup_eval()
#'
#' # Create evaluation in a specific directory
#' setup_eval("my-eval/")
#'
#' # Overwrite existing files
#' setup_eval(overwrite = TRUE)
#' }
setup_eval <- function(path = ".", tool_name = "tool_create_plot", overwrite = FALSE) {
  # Create directories
  tools_dir <- file.path(path, "tools")
  samples_dir <- file.path(path, "samples")

  dir.create(tools_dir, showWarnings = FALSE, recursive = TRUE)
  dir.create(samples_dir, showWarnings = FALSE, recursive = TRUE)

  # Tool template
  tool_file <- file.path(tools_dir, paste0(tool_name, ".R"))

  if (!file.exists(tool_file) || overwrite) {
    tool_template <- glue::glue('
# Tool factory for creating plots
# This function creates an ellmer tool that can execute R code to create plots

{tool_name} <- function(env, name = "create_plot") {{
  ellmer::tool(
    function(code) {{
      # Execute code in the provided environment
      result <- tryCatch(
        eval(parse(text = code), envir = env),
        error = function(e) {{
          return(ellmer::ContentToolResult(error = conditionMessage(e)))
        }}
      )

      if (inherits(result, "ContentToolResult")) {{
        return(result)
      }}

      # Check if result is a ggplot
      if (inherits(result, "ggplot")) {{
        temp_file <- tempfile(fileext = ".png")
        ggplot2::ggsave(temp_file, plot = result, width = 7, height = 5)
        return(ellmer::content_image_file(temp_file))
      }}

      # Handle non-ggplot results
      result_type <- if (is.null(result)) "NULL" else paste(class(result), collapse = ", ")
      ellmer::ContentToolResult(
        error = paste0("Code did not return a ggplot. Got: ", result_type)
      )
    }},
    name = name,
    description = "Create a ggplot visualization from R code",
    arguments = list(
      code = ellmer::type_string(
        "R code that begins with library(ggplot2) and creates a ggplot object"
      )
    )
  )
}}
')

    writeLines(tool_template, tool_file)
    cli::cli_alert_success("Created tool template: {.file {tool_file}}")
  } else {
    cli::cli_alert_info("Tool file already exists: {.file {tool_file}}")
  }

  # Sample YAML template
  sample_file <- file.path(samples_dir, "example_sample.yaml")

  if (!file.exists(sample_file) || overwrite) {
    sample_template <- glue::glue('
id: example_positive_correlation
type: baseline
tool:
  name: {tool_name}
  alias: create_plot  # Optional: different name shown to model
input:
  setup: |
    library(ggplot2)
    set.seed(123)
    df <- data.frame(
      x = 1:20,
      y = 2 * (1:20) + rnorm(20, 0, 5)
    )
  teardown: |
    rm(df)
  prompt: |
    Create a scatter plot of the df dataset with x on the x-axis and y on the
    y-axis. Then describe the relationship you observe between the variables.
target: |
  The plot shows a positive correlation between x and y. As x increases,
  y also tends to increase.
')

    writeLines(sample_template, sample_file)
    cli::cli_alert_success("Created sample template: {.file {sample_file}}")
  } else {
    cli::cli_alert_info("Sample file already exists: {.file {sample_file}}")
  }

  # Create a README with instructions
  readme_file <- file.path(path, "README.md")

  if (!file.exists(readme_file) || overwrite) {
    readme_template <- glue::glue('
# Evaluation Project

LLM evaluation using [evaltools](https://github.com/skaltman/evaltools).

## Quick Start

```r
library(evaltools)

task <- run_eval(
  samples_dir = "samples/",
  solver_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929")
)

task$results
task$accuracy()
```

## Structure

- `tools/{tool_name}.R` - Tool function (customize this)
- `samples/` - YAML evaluation samples (add more here)

## Next Steps

1. Edit `tools/{tool_name}.R` for your needs
2. Add more YAML files to `samples/`
3. Run the evaluation

See the [evaltools docs](https://github.com/skaltman/evaltools) for details.
')

    writeLines(readme_template, readme_file)
    cli::cli_alert_success("Created README: {.file {readme_file}}")
  } else {
    cli::cli_alert_info("README already exists: {.file {readme_file}}")
  }

  # Summary message
  cli::cli_rule("Setup Complete!")
  cli::cli_text("")
  cli::cli_bullets(c(
    "v" = "Created {.path {tools_dir}} with example tool",
    "v" = "Created {.path {samples_dir}} with example YAML",
    "v" = "Created {.file README.md} with instructions"
  ))
  cli::cli_text("")
  cli::cli_text("Next steps:")
  cli::cli_ol(c(
    "Customize the tool in {.file {basename(tool_file)}}",
    "Add more samples to {.path {samples_dir}}",
    "Run: {.code run_eval('samples/', solver_chat = ellmer::chat_anthropic(...))}"
  ))

  invisible(path)
}
