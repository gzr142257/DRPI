# Shared execution records. This file only defines helpers; sourcing it runs no experiment.
drpi_cli <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(tail(hit, 1), nchar(prefix) + 1L)
}
drpi_script_path <- function() {
  hit <- commandArgs(FALSE)[startsWith(commandArgs(FALSE), "--file=")]
  if (!length(hit)) stop("Run this entry with Rscript.")
  normalizePath(sub("^--file=", "", hit[1]), winslash = "/", mustWork = TRUE)
}
drpi_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}
drpi_config <- function(values) {
  saveRDS(values, file.path(.drpi_record$dir, "config.rds"))
  dput(values, file = file.path(.drpi_record$dir, "config.R"))
}
drpi_inputs <- function(paths) {
  paths <- unique(paths[nzchar(paths)])
  if (!length(paths)) return(invisible(NULL))
  if (any(!file.exists(paths))) stop("Missing input: ", paste(paths[!file.exists(paths)], collapse = ", "))
  info <- file.info(paths)
  drpi_write_csv(data.frame(Path = normalizePath(paths, winslash = "/"),
    Bytes = info$size, MD5 = unname(tools::md5sum(paths))), file.path(.drpi_record$dir, "inputs.csv"))
}
drpi_event <- function(stage, seed = NA_integer_, status = "ok", detail = "") {
  row <- data.frame(UTC = format(Sys.time(), tz = "UTC", usetz = TRUE),
    Stage = stage, Seed = seed, Status = status, Detail = detail)
  path <- file.path(.drpi_record$dir, "events.csv")
  write.table(row, path, append = file.exists(path), sep = ",", row.names = FALSE,
    col.names = !file.exists(path), qmethod = "double", fileEncoding = "UTF-8")
}
drpi_split <- function(stage, seed, train, held, test) {
  path <- file.path(.drpi_record$dir, paste0("splits_", stage, ".csv"))
  row <- data.frame(Seed = seed, Subset = rep(c("train", "held", "test"),
    c(length(train), length(held), length(test))), RowID = c(train, held, test))
  write.table(row, path, append = file.exists(path), sep = ",", row.names = FALSE,
    col.names = !file.exists(path), qmethod = "double", fileEncoding = "UTF-8")
}
drpi_logged <- function(action, script_path) {
  script_dir <- dirname(script_path)
  runs_root <- drpi_cli("runs-root", file.path(script_dir, "runs"))
  id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_", Sys.getpid())
  record_dir <- file.path(runs_root, paste0(tools::file_path_sans_ext(basename(script_path)), "_", id))
  dir.create(record_dir, recursive = TRUE, showWarnings = FALSE)
  .drpi_record <<- new.env(parent = emptyenv())
  .drpi_record$dir <- normalizePath(record_dir, winslash = "/", mustWork = TRUE)
  .drpi_record$output_roots <- character()
  .drpi_record$started <- Sys.time()
  .drpi_record$status <- "running"
  .drpi_record$error <- ""
  code_paths <- c(script_path, file.path(script_dir, "run_records.R"))
  drpi_write_csv(data.frame(Path = code_paths, MD5 = unname(tools::md5sum(code_paths))),
    file.path(record_dir, "source.csv"))
  file.copy(file.path(script_dir, "run_records.R"), file.path(record_dir, "run_records.R"))
  file.copy(script_path, file.path(record_dir, basename(script_path)))
  dput(commandArgs(TRUE), file = file.path(record_dir, "arguments.R"))
  stdout <- file(file.path(record_dir, "stdout.log"), open = "wt", encoding = "UTF-8")
  stderr <- file(file.path(record_dir, "stderr.log"), open = "wt", encoding = "UTF-8")
  output_depth <- sink.number()
  message_sink <- sink.number(type = "message")
  sink(stdout, split = TRUE); sink(stderr, type = "message")
  on.exit({
    writeLines(capture.output(sessionInfo()), file.path(record_dir, "sessionInfo.txt"))
    drpi_write_csv(data.frame(Status = .drpi_record$status,
      StartedUTC = format(.drpi_record$started, tz = "UTC", usetz = TRUE),
      EndedUTC = format(Sys.time(), tz = "UTC", usetz = TRUE),
      Error = .drpi_record$error), file.path(record_dir, "status.csv"))
    files <- unique(unlist(lapply(.drpi_record$output_roots, function(p)
      list.files(p, recursive = TRUE, full.names = TRUE))))
    files <- files[file.exists(files) & !dir.exists(files)]
    if (length(files)) drpi_write_csv(data.frame(Path = normalizePath(files, winslash = "/"),
      Bytes = file.info(files)$size, MD5 = unname(tools::md5sum(files))),
      file.path(record_dir, "outputs.csv"))
    while (sink.number() > output_depth) sink()
    if (message_sink == 2L) sink(type = "message") else sink(message_sink, type = "message")
    close(stdout); close(stderr)
    cat("Run records: ", .drpi_record$dir, "\n", sep = "")
  }, add = TRUE)
  drpi_event("run", status = "started")
  result <- tryCatch(withCallingHandlers(action(), warning = function(w) {
    drpi_event("warning", status = "warning", detail = conditionMessage(w))
  }), error = function(e) {
    .drpi_record$status <- "failed"
    .drpi_record$error <- conditionMessage(e)
    drpi_event("run", status = "failed", detail = conditionMessage(e))
    stop(e)
  })
  .drpi_record$status <- "complete"
  drpi_event("run", status = "complete")
  invisible(result)
}
