#' Create a scorer function for tool-based evaluations
#'
#' Creates a scorer function that checks for successful tool calls and uses
#' an LLM judge to grade responses. The scorer follows the pattern expected
#' by vitals::Task.
#'
#' @param scorer_chat An ellmer Chat object to use for judging. Default is
#'   Claude Sonnet 4.5.
#' @param tool_names Character vector of tool names to check for successful calls.
#'   The sample is only graded if one of these tools was called successfully.
#' @param prompt_field Character string naming the field in input that contains
#'   the task prompt. Default is "prompt".
#' @param target_field Character string naming the field in samples that contains
#'   the target observation. Default is "target".
#' @param instructions Character string with grading instructions for the judge.
#'   Default uses standard binary Correct/Incorrect instructions.
#' @param grade_levels Character vector of valid grade levels. Default is
#'   c("I", "C") for Incorrect/Correct. The levels should be ordered from
#'   worst to best.
#'
#' @return A function with signature \code{function(samples, ..., scorer_chat)}
#'   that can be used as a scorer in vitals::Task. Returns a list with:
#'   \describe{
#'     \item{score}{Factor vector of scores}
#'     \item{scorer_chat}{List of Chat objects used for grading}
#'     \item{scorer_metadata}{List containing prompts, responses, and metadata}
#'   }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create a scorer that checks for "create_plot" tool
#' scorer <- create_scorer(
#'   tool_names = "create_plot",
#'   prompt_field = "prompt",
#'   target_field = "target"
#' )
#'
#' # Use with custom judge
#' scorer <- create_scorer(
#'   scorer_chat = ellmer::chat_openai(model = "gpt-4"),
#'   tool_names = c("create_plot", "make_plot"),
#'   instructions = custom_instructions()
#' )
#' }
create_scorer <- function(
  scorer_chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  tool_names = "create_plot",
  prompt_field = "prompt",
  target_field = "target",
  instructions = default_judge_instructions(),
  grade_levels = c("I", "C")
) {
  # Capture the default scorer_chat in outer scope
  default_scorer_chat <- scorer_chat

  function(samples, ..., scorer_chat = default_scorer_chat) {
    # Check which samples have successful tool calls
    has_successful_tool <- purrr::map_lgl(
      samples$solver_chat,
      check_tool_called,
      tool_names = tool_names
    )

    # Initialize all grades as incorrect
    grades <- rep(grade_levels[1], nrow(samples))

    # Get indices of samples to grade
    samples_to_grade <- which(has_successful_tool)

    if (length(samples_to_grade) > 0) {
      # Format prompts for judge
      prompts <- purrr::map_chr(samples_to_grade, function(i) {
        format_judge_prompt(
          task = samples$input[[i]][[prompt_field]],
          response = samples$result[i],
          target = samples[[target_field]][i],
          instructions = instructions
        )
      })

      # Get judgments in parallel
      scorer_chat_clone <- scorer_chat$clone()
      responses <- ellmer::parallel_chat(scorer_chat_clone, as.list(prompts))

      # Extract grades (with error handling for failed requests)
      graded <- purrr::map_chr(responses, function(response_chat) {
        tryCatch(
          {
            response_text <- response_chat$last_turn()@text
            extract_grade(response_text, levels = grade_levels)
          },
          error = function(e) {
            # If extraction fails, grade as incorrect
            grade_levels[1]
          }
        )
      })

      grades[samples_to_grade] <- graded

      # Create metadata
      metadata <- purrr::map(seq_len(nrow(samples)), function(i) {
        if (i %in% samples_to_grade) {
          idx <- which(samples_to_grade == i)
          response_text <- tryCatch(
            responses[[idx]]$last_turn()@text,
            error = function(e) paste("Error extracting response:", e$message)
          )
          list(
            prompt = prompts[idx],
            response = response_text,
            had_tool_call = TRUE
          )
        } else {
          list(
            prompt = NA_character_,
            response = NA_character_,
            had_tool_call = FALSE
          )
        }
      })

      # Create scorer chat list
      scorer_chat_list <- purrr::map(seq_len(nrow(samples)), function(i) {
        if (i %in% samples_to_grade) {
          idx <- which(samples_to_grade == i)
          chat <- responses[[idx]]
          # Check if this is a valid Chat object
          if (inherits(chat, "Chat")) {
            chat
          } else {
            create_mock_scorer_chat(scorer_chat, "Scorer request failed")
          }
        } else {
          create_mock_scorer_chat(scorer_chat, "Tool was not called successfully")
        }
      })
    } else {
      # No samples to grade
      metadata <- purrr::map(seq_len(nrow(samples)), function(i) {
        list(
          prompt = NA_character_,
          response = NA_character_,
          had_tool_call = FALSE
        )
      })

      scorer_chat_list <- purrr::map(seq_len(nrow(samples)), function(i) {
        create_mock_scorer_chat(scorer_chat, "Tool was not called successfully")
      })
    }

    # Convert grades to ordered factor
    scores <- factor(grades, levels = grade_levels, ordered = TRUE)

    list(
      score = scores,
      scorer_chat = scorer_chat_list,
      scorer_metadata = metadata
    )
  }
}

#' Create a mock scorer chat for samples not graded
#'
#' Internal helper to create a mock chat for samples that were not graded
#' by the LLM judge (e.g., because tool was not called).
#'
#' @param scorer_chat Template chat object to clone.
#' @param reason Character string explaining why sample was not graded.
#'
#' @return An ellmer Chat object with mock turns.
#' @keywords internal
create_mock_scorer_chat <- function(scorer_chat, reason) {
  chat <- scorer_chat$clone()
  chat$set_turns(list(
    ellmer::Turn(
      role = "user",
      contents = list(ellmer::ContentText("Automatically graded."))
    ),
    ellmer::Turn(
      role = "assistant",
      contents = list(ellmer::ContentText(reason))
    )
  ))
  chat
}
