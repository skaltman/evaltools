#' Format a prompt for LLM-as-judge evaluation
#'
#' Creates a standardized prompt for an LLM judge to evaluate whether a model's
#' response contains the target observation.
#'
#' @param task Character string describing the task given to the model.
#' @param response Character string of the model's response.
#' @param target Character string describing the expected observation.
#' @param instructions Character string with grading instructions for the judge.
#'   Should specify the grading scale and format. Default uses a binary
#'   Correct/Incorrect scale.
#'
#' @return Character string containing the formatted judge prompt.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' prompt <- format_judge_prompt(
#'   task = "Create a plot of the data",
#'   response = "The plot shows a positive correlation",
#'   target = "The data shows a positive linear relationship",
#'   instructions = default_judge_instructions()
#' )
#' }
format_judge_prompt <- function(task, response, target, instructions = default_judge_instructions()) {
  glue::glue(
    "You are evaluating whether a model accurately described an observation.
    [BEGIN DATA]
    ************
    [Task]: The model was asked the following: {task}
    ************
    [Target Observation]: {target}
    ************
    [Model's Response]: {response}
    ************
    [END DATA]
    The Target Observation describes what should be observed.
    Does the Model's Response contain this observation?
    Ignore any differences in style, grammar, or punctuation.
    {instructions}"
  )
}

#' Default judge instructions
#'
#' Provides default instructions for binary Correct/Incorrect grading.
#' The instructions emphasize that counterintuitive observations should be
#' graded as correct if accurately stated.
#'
#' @return Character string with judge instructions.
#'
#' @export
#'
#' @examples
#' default_judge_instructions()
default_judge_instructions <- function() {
  "IMPORTANT: The target observation describes what should be observed.
  Even if the observation seems counterintuitive, surprising, or unexpected,
  grade it as correct if the response accurately states this observation.

  After assessing the response, reply with 'GRADE: $LETTER' where
  LETTER is one of C or I.
  Please choose ONE option: either 'C' for correct responses or 'I' for
  incorrect responses.
  First explain your reasoning, then end with GRADE: $LETTER.
  Do not format the grading string and do not include any punctuation or
  exposition after it."
}

#' Extract grade from judge response
#'
#' Parses the LLM judge's response to extract the grade. Expects the grade
#' to be in the format "GRADE: X" where X is a single letter.
#'
#' @param response Character string containing the judge's response.
#' @param levels Character vector of valid grade levels. Default is c("I", "C")
#'   for Incorrect/Correct.
#'
#' @return Character string with the extracted grade, or NA if no grade found.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' response <- "The model accurately describes the relationship. GRADE: C"
#' extract_grade(response)  # Returns "C"
#'
#' response <- "The model's description is incorrect. GRADE: I"
#' extract_grade(response)  # Returns "I"
#' }
extract_grade <- function(response, levels = c("I", "C")) {
  # Create pattern from valid levels
  level_pattern <- paste(levels, collapse = "|")
  grade_pattern <- paste0("(?i)GRADE\\s*:\\s*(", level_pattern, ")(.*)$")

  grade_match <- regmatches(
    response,
    regexec(grade_pattern, response, perl = TRUE)
  )[[1]]

  if (length(grade_match) < 2) {
    return(NA_character_)
  }

  # Return uppercased grade (2nd element is the captured group)
  toupper(grade_match[2])
}

#' Check if a chat successfully called a tool
#'
#' Examines the turns in a chat to determine if a specific tool was called
#' successfully (without errors).
#'
#' @param chat An ellmer Chat object.
#' @param tool_names Character vector of tool names to check for. If multiple
#'   names are provided, returns TRUE if any of them were called successfully.
#'
#' @return Logical indicating whether the tool was called successfully.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Check if create_plot tool was called
#' success <- check_tool_called(chat, "create_plot")
#'
#' # Check if any of multiple tools were called
#' success <- check_tool_called(chat, c("create_plot", "make_plot"))
#' }
check_tool_called <- function(chat, tool_names) {
  turns <- chat$get_turns()

  for (turn in turns) {
    if (turn@role != "user") {
      next
    }

    for (content in turn@contents) {
      if (
        inherits(content, "ellmer::ContentToolResult") &&
          content@request@name %in% tool_names &&
          is.null(content@error)
      ) {
        return(TRUE)
      }
    }
  }

  FALSE
}
