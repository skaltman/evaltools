#' Load evaluation dataset from YAML files
#'
#' Reads YAML files from a directory and creates a tibble suitable for use
#' with vitals::Task. Each YAML file should define one evaluation sample
#' with required fields for tool-based evaluation.
#'
#' @param path Character string path to directory containing YAML files,
#'   or a character vector of paths to individual YAML files.
#' @param required_fields Character vector of field names that must be present
#'   in each sample's input. Default is c("setup", "teardown", "prompt").
#' @param validate Logical indicating whether to validate the dataset structure.
#'   Default is TRUE.
#'
#' @return A tibble with columns:
#'   \describe{
#'     \item{id}{Unique identifier for the sample}
#'     \item{type}{Optional type/category of the sample}
#'     \item{input}{List-column containing input data (prompt, setup, teardown, tool spec)}
#'     \item{target}{Expected observation for scoring}
#'     \item{...}{Any additional columns from metadata fields in the YAML}
#'   }
#'
#' @details
#' Each YAML file should have the following structure:
#' \preformatted{
#' id: sample_id
#' type: baseline              # optional
#' tool:
#'   name: tool_create_plot     # R function name
#'   alias: make_plot           # optional
#' metadata:                    # optional - custom fields
#'   difficulty: easy
#'   n_geoms: 2
#'   any_custom_field: value
#' input:
#'   setup: |
#'     # R code
#'   teardown: |
#'     # R code
#'   prompt: |
#'     # Instructions
#' target: |
#'   # Expected observation
#' }
#'
#' Any fields in the \code{metadata} section will be added as columns
#' in the returned tibble, allowing you to store and analyze additional
#' information about each sample.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Load all YAML files from a directory
#' dataset <- load_yaml_dataset("path/to/samples/")
#'
#' # Load specific YAML files
#' dataset <- load_yaml_dataset(c("sample1.yaml", "sample2.yaml"))
#' }
load_yaml_dataset <- function(
  path,
  required_fields = c("setup", "teardown", "prompt"),
  validate = TRUE
) {
  # Get YAML file paths
  if (length(path) == 1 && dir.exists(path)) {
    yaml_files <- list.files(
      path,
      pattern = "\\.ya?ml$",
      full.names = TRUE
    )
  } else {
    yaml_files <- path
  }

  if (length(yaml_files) == 0) {
    cli::cli_abort("No YAML files found at {.path {path}}")
  }

  # Read and process YAML files
  dataset <- purrr::map(yaml_files, function(file) {
    sample <- tryCatch(
      yaml::read_yaml(file),
      error = function(e) {
        cli::cli_abort(
          "Failed to read {.path {file}}: {e$message}",
          parent = e
        )
      }
    )

    # Validate sample structure
    if (validate) {
      validate_sample(sample, file, required_fields)
    }

    # Create base tibble row
    row <- tibble::tibble(
      id = sample$id,
      type = if (!is.null(sample$type)) sample$type else NA_character_,
      input = list(
        tibble::tibble(
          prompt = sample$input$prompt,
          setup = sample$input$setup,
          teardown = sample$input$teardown,
          tool_factory = sample$tool$name,
          tool_alias = if (!is.null(sample$tool$alias)) {
            sample$tool$alias
          } else {
            NA_character_
          }
        )
      ),
      target = sample$target
    )

    # Add metadata fields if present
    if (!is.null(sample$metadata)) {
      for (meta_field in names(sample$metadata)) {
        row[[meta_field]] <- sample$metadata[[meta_field]]
      }
    }

    row
  })

  # Combine into single tibble
  dataset <- purrr::list_rbind(dataset)

  # Sort by id
  dataset <- dataset[order(dataset$id), ]

  dataset
}

#' Validate evaluation sample structure
#'
#' Internal function to validate that a sample has required fields.
#'
#' @param sample List parsed from YAML.
#' @param file Path to the YAML file (for error messages).
#' @param required_fields Character vector of required field names in input.
#'
#' @return NULL (called for side effects of aborting on error).
#' @keywords internal
validate_sample <- function(sample, file, required_fields) {
  # Check top-level required fields
  if (is.null(sample$id)) {
    cli::cli_abort("Sample in {.path {file}} is missing required field {.field id}")
  }

  if (is.null(sample$input)) {
    cli::cli_abort("Sample in {.path {file}} is missing required field {.field input}")
  }

  if (is.null(sample$target)) {
    cli::cli_abort("Sample in {.path {file}} is missing required field {.field target}")
  }

  if (is.null(sample$tool)) {
    cli::cli_abort("Sample in {.path {file}} is missing required field {.field tool}")
  }

  # Check tool structure
  if (is.null(sample$tool$name)) {
    cli::cli_abort(
      "Sample in {.path {file}} has tool specification without {.field name}"
    )
  }

  # Check input fields
  for (field in required_fields) {
    if (is.null(sample$input[[field]])) {
      cli::cli_abort(
        "Sample in {.path {file}} is missing required input field {.field {field}}"
      )
    }
  }

  invisible(NULL)
}
