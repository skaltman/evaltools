tool_create_plot <- function(env, name = "create_plot") {
  ellmer::tool(
    function(code) {
      result <- tryCatch(
        eval(parse(text = code), envir = env),
        error = function(e) {
          return(ellmer::ContentToolResult(error = conditionMessage(e)))
        }
      )

      if (inherits(result, "ContentToolResult")) {
        return(result)
      }

      if (inherits(result, "ggplot")) {
        temp_file <- tempfile(fileext = ".png")
        ggplot2::ggsave(temp_file, plot = result, width = 7, height = 5)
        return(ellmer::content_image_file(temp_file))
      }

      result_type <- if (is.null(result)) "NULL" else class(result)
      ellmer::ContentToolResult(
        error = paste0("Code did not return a ggplot. Got: ", result_type)
      )
    },
    name = name,
    description = "Create a plot using ggplot2",
    arguments = list(
      code = ellmer::type_string(
        "R code to create a ggplot. Should start with library(ggplot2) and return a ggplot object."
      )
    )
  )
}