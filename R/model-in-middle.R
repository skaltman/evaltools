#' Interpret a plot using a fresh model context
#'
#' Uses a "model-in-the-middle" approach where a fresh chat context (cloned from
#' the solver_chat) interprets a plot image and returns a text description instead
#' of the image itself. This helps isolate visual interpretation from contextual
#' priors and expectations.
#'
#' The interpretation includes:
#' - Axis ranges
#' - Distribution and shape of plotted data
#' - Additional relevant context (facets, anomalies, etc.)
#' - A reflection prompt asking the solver to note expectation alignment
#'
#' @param plot_file Path to a plot image file (PNG, JPG, etc.)
#' @param solver_chat An ellmer Chat object to clone for fresh context
#' @param prompt_file Optional path to a custom interpretation prompt. If NULL,
#'   uses the default prompt from inst/prompts/interpret_plot.md
#'
#' @return An ellmer ContentToolResult with formatted text description of the plot
#'
#' @export
#'
#' @examples
#' \dontrun{
#' chat <- ellmer::chat("anthropic/claude-sonnet-4-5-20250929")
#' result <- interpret_plot("plot.png", chat)
#' }
interpret_plot <- function(plot_file, solver_chat, prompt_file = NULL) {
  # Load the image
  image_content <- ellmer::content_image_file(plot_file)

  # Create fresh chat context
  ch <- solver_chat$clone()
  ch$set_turns(list())

  # Load interpretation prompt
  if (is.null(prompt_file)) {
    prompt_file <- system.file(
      "prompts/interpret_plot.md",
      package = "evaltools"
    )
  }

  if (!file.exists(prompt_file)) {
    cli::cli_abort(
      "Interpretation prompt file not found: {.path {prompt_file}}"
    )
  }

  prompt_text <- paste(readLines(prompt_file), collapse = "\n")
  ch$set_system_prompt(prompt_text)

  # Get structured interpretation
  interpretation <- ch$chat_structured(
    image_content,
    type = ellmer::type_object(
      distribution = ellmer::type_string(
        "Exactly two sentences describing the distribution and shape of the plotted data elements. Focus on describing the actual first-order patterns you observe in the plotted data itself, ignoring any modeled results such as smoothed lines or trend curves. Describe what you see in the raw data."
      ),
      axes = ellmer::type_string(
        "The limits of the x and y axes, described in a single sentence. For example: 'The x-axis ranges from 0 to 100, and the y-axis ranges from 20 to 80.'"
      ),
      additional_context = ellmer::type_string(
        "Any additional context beyond axis limits and distribution that is necessary to understand the plot. For example, note if there are multiple faceted plots rather than one, if any modeled result (like a smooth line) fails to capture the shape of the actual plotted data, if there are discontinuities in trends (and their ranges or changepoints, if so), if there are obvious issues with the plotting approach, if any anomalies or surprising results are shown, or if notable theming or styling has been applied. Omit repeating information from plot labels or titles.",
        required = FALSE
      )
    ),
    echo = FALSE
  )

  # Format output
  output_parts <- c(
    "A ggplot2 displaying:",
    "",
    paste0("**Axes:** ", interpretation$axes),
    paste0("**Distribution:** ", interpretation$distribution)
  )

  if (
    !is.null(interpretation$additional_context) &&
      nzchar(interpretation$additional_context)
  ) {
    output_parts <- c(
      output_parts,
      paste0("**Additional context:** ", interpretation$additional_context)
    )
  }

  output_parts <- c(
    output_parts,
    "",
    "Begin your reply with a **one-sentence** reflection on whether the image content aligns with your expectation of what you thought you'd see in a <reflection> tag. That reflection will not be shown to the user. **IMPORTANTLY, the description of the image content is factual**; if the contents do not match your expectations, note both the contents as well as the fact that it doesn't align with your expectations in your reply to the user."
  )

  ellmer::ContentToolResult(
    value = paste(output_parts, collapse = "\n\n")
  )
}

#' Strip reflection tags from model responses
#'
#' Removes <reflection>...</reflection> tags from text, typically used to
#' strip internal reasoning that shouldn't be shown to users or scored.
#'
#' @param text Character string containing text with optional reflection tags
#'
#' @return Character string with reflection tags removed
#'
#' @export
#'
#' @examples
#' text <- "<reflection>I expected X</reflection> The plot shows Y"
#' strip_reflection(text)
#' # Returns: "The plot shows Y"
strip_reflection <- function(text) {
  gsub("(?s)<reflection>.*?</reflection>\\s*", "", text, perl = TRUE)
}
