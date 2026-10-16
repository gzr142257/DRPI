# Rscript entry; sourcing run_records.R alone does not execute experiments.
.entry_args <- commandArgs(FALSE)
.entry_file <- .entry_args[startsWith(.entry_args, "--file=")]
if (!length(.entry_file)) stop("Use Rscript to run this file.")
.entry_path <- normalizePath(sub("^--file=", "", .entry_file[1]), winslash = "/", mustWork = TRUE)
source(file.path(dirname(.entry_path), "run_records.R"))
.drpi_main <- function() {
  script_dir <- dirname(.entry_path)
# Unified conformal prediction pipeline with ACPI, DNCP, and DNCP-mini variants.
# Real datasets kept in this script: Diabetes, WineRed, Concrete, and Boston.

# Configuration

RUN_SPLIT_CP   <- TRUE
RUN_LCP_G      <- TRUE 
RUN_LCP_K      <- TRUE 
RUN_LWCI       <- TRUE
RUN_WCP        <- TRUE 
RUN_DNCP       <- TRUE
RUN_ACPI       <- TRUE
RUN_DNCP_MINI  <- TRUE

n_seeds       <- 100
start_seed_no <- 1
make_plots    <- FALSE
alpha_level   <- 0.10
k_tail        <- 2
dataset_name  <- "Diabetes"
# Supported dataset_name values: sim1, sim2, sim3, sim_NO, Diabetes, WineRed, Concrete, Boston.

base_model   <- "elastic_net"
alpha_en     <- 0.5
rf_ntree     <- 100

acpi_scan_steps <- 40
acpi_nodesize   <- 10

dncp_family  <- "JSUo"
dncp_ntree   <- 100

dncpmini_optim_maxit <- 500
dncpmini_lambda <- 0.5

lcp_bandwidth  <- NULL
lcp_k          <- 100

wcp_method     <- "logistic"
wcp_cap_ratio  <- 50

diabetes_path <- file.path(dirname(script_dir), "Real Data", "diabetes.csv")
concrete_path <- file.path(dirname(script_dir), "Real Data", "concrete.csv")

wine_red_path   <- file.path(dirname(script_dir), "Real Data", "red_wine.csv")

# Command-line export defaults. These are overridden by --export-root and
# --mirror-export-root when the script is launched from the provided CMD files.
export_root <- file.path(.drpi_record$dir, "results")
mirror_export_root <- NULL
legacy_result_names <- TRUE



# Explicit experiment and method entries.
cli_args <- commandArgs(TRUE)
.cli_value <- drpi_cli
.cli_bool <- function(name, default = FALSE) {
  value <- tolower(.cli_value(name, as.character(default)))
  if (!value %in% c("true", "false", "1", "0")) stop("Invalid boolean: ", name)
  value %in% c("true", "1")
}
if ("--help" %in% cli_args) {
  cat("--stage=main|case337|frequency --dataset=sim_NO|sim1|sim2|sim3|Diabetes|Concrete|WineRed|Boston\n",
      "--base-model=elastic_net|random_forest|ols --method=all|both|splitcp|lcp-gaussian|lcp-knn|lwci|wcp|acpi|dncp|dncp-mini\n",
      "Comma-separated methods are supported. --n-seeds=100 --start-seed=1 --alpha=0.1\n",
      "--data-root=PATH --export-root=PATH --runs-root=PATH --legacy-names=true\n",
      "--case-id=337 --case-seed-start=485 --case-seed-end=974 --case-expected-count=100\n")
  return(invisible(NULL))
}
stage <- .cli_value("stage", "main")
if (!stage %in% c("main", "case337", "frequency")) stop("Unknown stage.")
dataset_name <- .cli_value("dataset", dataset_name)
base_model <- .cli_value("base-model", base_model)
n_seeds <- as.integer(.cli_value("n-seeds", n_seeds))
start_seed_no <- as.integer(.cli_value("start-seed", start_seed_no))
alpha_level <- as.numeric(.cli_value("alpha", alpha_level))
dncpmini_lambda <- as.numeric(.cli_value("dncpmini-lambda", dncpmini_lambda))
data_root <- .cli_value("data-root", file.path(dirname(script_dir), "Real Data"))
diabetes_path <- .cli_value("diabetes-path", file.path(data_root, "diabetes.csv"))
concrete_path <- .cli_value("concrete-path", file.path(data_root, "concrete.csv"))
wine_red_path <- .cli_value("wine-red-path", file.path(data_root, "red_wine.csv"))
boston_path <- .cli_value("boston-path", file.path(data_root, "Boston.csv"))
export_root <- .cli_value("export-root", export_root)
legacy_result_names <- .cli_bool("legacy-names", TRUE)
lambda_sensitivity_output <- .cli_bool("lambda-sensitivity-output", FALSE)
if (.cli_bool("local-output", FALSE)) export_root <- file.path(script_dir, "experiment_results")
if (lambda_sensitivity_output) export_root <- .cli_value("export-root", file.path(.drpi_record$dir, "sensitivity"))
selected_method <- tolower(.cli_value("method", "all"))
methods <- trimws(strsplit(selected_method, ",", fixed = TRUE)[[1]])
methods[methods == "c-drpi"] <- "dncp"
methods[methods %in% c("g-drpi", "dncpmini", "mini")] <- "dncp-mini"
if ("all" %in% methods) methods <- c("splitcp", "lcp-gaussian", "lcp-knn", "lwci", "wcp", "acpi", "dncp", "dncp-mini")
if ("both" %in% methods) methods <- unique(c(setdiff(methods, "both"), "dncp", "dncp-mini"))
if (any(!methods %in% c("splitcp", "lcp-gaussian", "lcp-knn", "lwci", "wcp", "acpi", "dncp", "dncp-mini"))) stop("Unknown method.")
RUN_SPLIT_CP <- "splitcp" %in% methods
RUN_LCP_G <- "lcp-gaussian" %in% methods
RUN_LCP_K <- "lcp-knn" %in% methods
RUN_LWCI <- "lwci" %in% methods
RUN_WCP <- "wcp" %in% methods
RUN_ACPI <- "acpi" %in% methods
RUN_DNCP <- "dncp" %in% methods
RUN_DNCP_MINI <- "dncp-mini" %in% methods
case_id <- as.integer(.cli_value("case-id", 337))
case_seed_start <- as.integer(.cli_value("case-seed-start", 485))
case_seed_end <- as.integer(.cli_value("case-seed-end", 974))
case_expected_count <- as.integer(.cli_value("case-expected-count", 100))
if (!is.finite(n_seeds) || n_seeds < 1 || !is.finite(start_seed_no) || start_seed_no < 1) stop("Invalid seed configuration.")
if (!is.finite(alpha_level) || alpha_level <= 0 || alpha_level >= 1) stop("alpha must be in (0,1).")
if (!is.finite(dncpmini_lambda) || dncpmini_lambda < 0) stop("lambda must be nonnegative.")
if (!base_model %in% c("elastic_net", "random_forest", "ols")) stop("Unknown base model.")
if (!is.finite(case_id) || case_id < 1 || !is.finite(case_seed_start) || !is.finite(case_seed_end) || case_seed_start < 1 || case_seed_end < case_seed_start || !is.finite(case_expected_count) || case_expected_count < 1) stop("Invalid case configuration.")
if (stage != "main" && (dataset_name != "Diabetes" || base_model != "elastic_net")) stop("Case/frequency entries require Diabetes + elastic_net.")
.drpi_record$output_roots <- export_root
drpi_config(as.list(environment())[c("stage", "dataset_name", "base_model", "methods", "n_seeds", "start_seed_no", "alpha_level", "dncpmini_lambda", "data_root", "export_root", "case_id", "case_seed_start", "case_seed_end", "case_expected_count", "alpha_en", "rf_ntree", "dncp_ntree", "lcp_k", "dncpmini_optim_maxit", "legacy_result_names")])
cat("Stage:", stage, "Dataset:", dataset_name, "Model:", base_model, "Methods:", paste(methods, collapse=","), "\n")
if (.cli_bool("check-config", FALSE)) {
  drpi_write_csv(data.frame(Method=c("splitcp","lcp-gaussian","lcp-knn","lwci","wcp","acpi","dncp","dncp-mini"),
    Enabled=c(RUN_SPLIT_CP,RUN_LCP_G,RUN_LCP_K,RUN_LWCI,RUN_WCP,RUN_ACPI,RUN_DNCP,RUN_DNCP_MINI)),
    file.path(.drpi_record$dir,"method_flags.csv"))
  return(invisible(NULL))
}

# Dependencies
need_pkg <- c("glmnet","randomForest","dplyr","MASS",
              "gamlss","gamlss.dist","partykit","disttree",
              "nortest","quantregForest")
for (p in need_pkg) if (!requireNamespace(p, quietly = TRUE)) try(install.packages(p), silent = TRUE)
suppressPackageStartupMessages({
  library(glmnet); library(randomForest); library(dplyr); library(MASS)
  library(gamlss); library(gamlss.dist); library(partykit); library(disttree)
  library(nortest)
})

# Utility helpers
ensure_dir <- function(path) if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
weighted_quantile <- function(v, prob, w = NULL, sorted = FALSE) {
  if (is.null(w)) w <- rep(1, length(v))
  if (!sorted) { o <- order(v); v <- v[o]; w <- w[o] }
  cs <- cumsum(w/sum(w)); i <- which(cs >= prob)[1]; if (is.na(i)) return(Inf); v[i]
}
to_numeric_vector <- function(x, n = NULL) {
  if (is.list(x) && !is.data.frame(x)) x <- unlist(x, use.names = FALSE)
  if (is.factor(x)) x <- as.character(x)
  suppressWarnings(xn <- as.numeric(x))
  if (!is.null(n) && length(xn) != n) xn <- rep_len(xn, n)
  xn[!is.finite(xn)] <- NA_real_
  xn
}
make_numeric_df <- function(df, exclude = character(0)) {
  stopifnot(is.data.frame(df))
  n <- nrow(df)
  for (nm in setdiff(names(df), exclude)) df[[nm]] <- to_numeric_vector(df[[nm]], n)
  keep <- vapply(df, function(col) {
    col <- as.numeric(col)
    all_na <- all(is.na(col))
    if (all_na) return(FALSE)
    sd_val <- suppressWarnings(sd(col, na.rm = TRUE))
    isTRUE(is.finite(sd_val)) && sd_val > 0
  }, logical(1))
  if (any(!keep)) df <- df[, keep, drop = FALSE]
  df
}
to_df_safe <- function(x) {
  if (is.data.frame(x)) {
    x2 <- lapply(x, function(col) to_numeric_vector(col, length(col)))
    return(as.data.frame(x2, optional = TRUE, check.names = FALSE))
  }
  if (is.matrix(x)) return(as.data.frame(x, check.names = FALSE))
  if (is.list(x))   return(as.data.frame(lapply(x, function(col) to_numeric_vector(col)), optional = TRUE, check.names = FALSE))
  data.frame(val = to_numeric_vector(x))
}
prepare_with_dummies <- function(df, yname) {
  df2 <- df %>% dplyr::filter(!is.na(.data[[yname]]))
  mat <- model.matrix(as.formula(paste0("~ . - 1")), data = df2 %>% dplyr::select(-all_of(yname)))
  y <- df2[[yname]]; list(X = mat, y = y)
}
.normalize_name <- function(s) { s <- tolower(trimws(as.character(s))); gsub("[^a-z0-9_]", "", s) }

.get_family <- function(tag) {
  switch(tag,
         "NO"   = NO(),
         "TF"   = TF(),
         "JSUo" = JSUo(),
         "SN1"  = SN1(),
         stop("Unknown dncp_family ('NO','TF','JSUo','SN1')."))
}
.get_param_names <- function(tag) {
  switch(tag,
         "NO"   = c("mu","sigma"),
         "TF"   = c("mu","sigma","nu"),
         "JSUo" = c("mu","sigma","nu","tau"),
         "SN1"  = c("mu","sigma","nu"),
         stop("Unknown distribution"))
}
.get_qfun <- function(tag)  get(paste0("q", tag),  mode="function")
.dncp_family_for_dataset <- function(dataset, default_family = dncp_family) {
  if (dataset == "sim_NO") return("NO")
  return(default_family)
}
.dncpmini_family_for_dataset <- function(dataset) {
  if (dataset == "sim_NO") return("NO")
  return("JSUo")
}
.align_to <- function(newdf, feat_names) {
  newdf <- as.data.frame(newdf, check.names = FALSE)
  miss <- setdiff(feat_names, names(newdf))
  if (length(miss) > 0) for (m in miss) newdf[[m]] <- 0
  newdf <- newdf[, feat_names, drop = FALSE]
  newdf
}
full_rank_design <- function(M) {
  M <- as.matrix(M)
  stopifnot(ncol(M) >= 1)
  if (ncol(M) == 1) return(list(M = M, idx = 1L))
  nz_idx <- 1L
  if (ncol(M) > 1) {
    nz <- which(apply(M[, -1, drop = FALSE], 2, function(col) sd(col) > 0)) + 1L
    nz_idx <- unique(c(1L, nz))
  }
  M1 <- M[, nz_idx, drop = FALSE]
  qx <- qr(M1); keep <- qx$pivot[1:qx$rank]
  list(M = M1[, keep, drop = FALSE], idx = nz_idx[keep])
}
.iso_monotone <- function(v) { v <- as.numeric(v); iso <- isoreg(seq_along(v), v); as.numeric(pmin(pmax(iso$yf, 0), 1)) }

# Base prediction helpers
fit_and_predict <- function(base_model, x_tr, y_tr, x_pred, alpha_en=0.5, rf_ntree=100) {
  if (base_model == "elastic_net") {
    grid <- 10^seq(1, -4, length = 100)
    fit_path <- glmnet(x_tr, y_tr, alpha = alpha_en, lambda = grid, standardize = TRUE)
    mse_tr <- colMeans((predict(fit_path, newx = x_tr, s = grid) - y_tr)^2)
    bestlam <- grid[which.min(mse_tr)]
    as.numeric(predict(fit_path, newx = x_pred, s = bestlam))
  } else if (base_model == "ols") {
    if (is.null(colnames(x_tr))) colnames(x_tr) <- paste0("X", 1:ncol(x_tr))
    colnames(x_pred) <- colnames(x_tr)
    df_tr <- data.frame(y = y_tr, x_tr, check.names = FALSE)
    as.numeric(predict(lm(y ~ ., data = df_tr), newdata = as.data.frame(x_pred, check.names = FALSE)))
  } else if (base_model == "random_forest") {
    df_tr <- as.data.frame(x_tr, check.names = FALSE)
    feat_names <- colnames(df_tr)
    rf_fit <- randomForest(x = df_tr, y = y_tr, ntree = rf_ntree, keep.forest = TRUE)
    as.numeric(predict(rf_fit, newdata = .align_to(as.data.frame(x_pred, check.names = FALSE), feat_names)))
  } else stop("Unknown base_model")
}

.train_base_predictor_from_base_model <- function(base_model, x_tr, y_tr, seed,
                                                  alpha_en=0.5, rf_ntree=100) {
  set.seed(seed)
  if (base_model == "elastic_net") {
    grid <- 10^seq(1, -4, length = 100)
    fit_path <- glmnet::glmnet(x_tr, y_tr, alpha = alpha_en, lambda = grid, standardize = TRUE)
    mse_tr <- colMeans((predict(fit_path, newx = x_tr, s = grid) - y_tr)^2)
    bestlam <- grid[which.min(mse_tr)]
    base_fit <- fit_path
    function(X) {
      X_mat <- as.matrix(X)
      as.numeric(predict(base_fit, newx = X_mat, s = bestlam))
    }
  } else if (base_model == "ols") {
    X_tr_df <- as.data.frame(x_tr, check.names = FALSE)
    if (is.null(colnames(X_tr_df))) colnames(X_tr_df) <- paste0("X", 1:ncol(X_tr_df))
    feat_names <- colnames(X_tr_df)
    df_tr <- data.frame(y = y_tr, X_tr_df, check.names = FALSE)
    ols_fit <- lm(y ~ ., data = df_tr)
    function(X) {
      X_df <- as.data.frame(X, check.names = FALSE)
      if (is.null(colnames(X_df))) {
        colnames(X_df) <- feat_names
      } else {
        miss <- setdiff(feat_names, colnames(X_df))
        if (length(miss) > 0) {
          for (m in miss) X_df[[m]] <- 0
        }
        X_df <- X_df[, feat_names, drop = FALSE]
      }
      as.numeric(predict(ols_fit, newdata = X_df))
    }
  } else if (base_model == "random_forest") {
    base_fit <- randomForest::randomForest(
      x = as.data.frame(x_tr, check.names = FALSE), y = y_tr,
      ntree = rf_ntree, keep.forest = TRUE
    )
    function(X) as.numeric(predict(base_fit, newdata = as.data.frame(X, check.names = FALSE)))
  } else stop("ACPI only supports base_model values 'elastic_net', 'ols', or 'random_forest'.")
}

.euclid_dist <- function(A, b) sqrt(rowSums((A - matrix(b, nrow(A), ncol(A), byrow = TRUE))^2))
.gaussian_kernel <- function(d, h) exp(-(d^2) / (2 * h^2))
smooth.spline.funs <- function(df=NULL, spar=NULL, cv=TRUE, tol.fact=1e-6) {
  if (!is.null(df)) {
    train.fun <- function(x,y) suppressWarnings(smooth.spline(x, y, df=df, spar=spar, tol=tol.fact*IQR(x)))
  } else {
    train.fun <- function(x,y) suppressWarnings(smooth.spline(x, y, spar=spar, cv=cv, tol=tol.fact*IQR(x)))
  }
  predict.fun <- function(out,newx) predict(out, newx)$y
  special.fun <- function(x,y,out) {
    n <- length(x); s <- if (length(out$lev)==n) out$lev else approx(out$x, out$lev, xout=x)$y
    (y - predict(out, x)$y) / (1 - s)
  }
  active.fun <- function(out) list(1)
  list(train.fun=train.fun, predict.fun=predict.fun, special.fun=special.fun, active.fun=active.fun)
}
.acpi_internal_calibration <- function(x_cal, y_cal, base_pred_cal,
                                       target_cov, seed, steps = 40,
                                       qrf_ntree = 100, qrf_nodesize = 5) {
  r_cal <- abs(as.numeric(y_cal) - as.numeric(base_pred_cal))
  set.seed(seed)
  n <- nrow(x_cal); perm <- sample.int(n); half <- floor(n/2)
  idx_tr <- perm[seq_len(half)]
  idx_val <- perm[(half+1):n]
  x_tr_res <- x_cal[idx_tr,,drop=FALSE]; r_tr <- r_cal[idx_tr]
  x_val_res <- x_cal[idx_val,,drop=FALSE]; r_val <- r_cal[idx_val]
  qrf_residual <- quantregForest::quantregForest(
    x = as.data.frame(x_tr_res, check.names = FALSE),
    y = r_tr, ntree = qrf_ntree, nodesize = qrf_nodesize, keep.inbag = FALSE
  )
  cand <- seq(from = target_cov, to = 1.0, length.out = steps)
  alpha_star <- tail(cand, 1)
  for (a in cand) {
    r_hat_val <- as.numeric(predict(qrf_residual, newdata = as.data.frame(x_val_res, check.names = FALSE), what = a))
    cov_val <- mean(r_val <= r_hat_val)
    if (is.finite(cov_val) && cov_val >= target_cov) { alpha_star <- a; break }
  }
  qrf_full <- quantregForest::quantregForest(
    x = as.data.frame(x_cal, check.names = FALSE),
    y = r_cal, ntree = qrf_ntree, nodesize = qrf_nodesize, keep.inbag = FALSE
  )
  list(qrf = qrf_full, alpha_star = alpha_star)
}
.run_acpi <- function(base_model, x_tr, y_tr, x_cal, y_cal, x_te, y_te,
                      alpha, seed,
                      alpha_en = 0.5, rf_ntree = 100,
                      qrf_nodesize = 5, steps = 40) {
  base_predict <- .train_base_predictor_from_base_model(
    base_model, x_tr, y_tr, seed,
    alpha_en = alpha_en, rf_ntree = rf_ntree
  )
  y_cal_hat <- base_predict(x_cal)
  y_te_hat  <- base_predict(x_te)
  calib <- .acpi_internal_calibration(
    x_cal, y_cal, y_cal_hat,
    target_cov = 1 - alpha, seed = seed, steps = steps,
    qrf_ntree = rf_ntree, qrf_nodesize = qrf_nodesize
  )
  r_te_hat <- as.numeric(predict(calib$qrf, newdata = as.data.frame(x_te, check.names = FALSE),
                                 what = calib$alpha_star))
  lower <- y_te_hat - r_te_hat
  upper <- y_te_hat + r_te_hat
  covered <- as.numeric(y_te >= lower & y_te <= upper)
  cov <- mean(covered); leng <- mean(upper - lower)
  list(coverage = cov, length = leng, lower = lower, upper = upper,
       center = y_te_hat, alpha_star = calib$alpha_star)
}

# DNCP-mini residual distribution fit
fit_jsu_mle_global <- function(
    resid_vec,
    n_cal = NULL,
    optim_maxit = dncpmini_optim_maxit
) {
  resid <- as.numeric(resid_vec)
  resid <- resid[is.finite(resid)]
  n <- length(resid)
  if (is.null(n_cal)) n_cal <- n
  n_cal <- as.numeric(n_cal)
  if (!is.finite(n_cal) || n_cal <= 0) n_cal <- n
  if (n < 5) {
    mu_r <- mean(resid)
    sigma_r <- sd(resid)
    if (!is.finite(sigma_r) || sigma_r <= 0) sigma_r <- 1
    return(list(mu = mu_r, sigma = sigma_r, nu = 0, tau = 1, converged = FALSE))
  }
  mu0 <- median(resid, na.rm = TRUE)
  sigma0 <- IQR(resid, na.rm = TRUE) / 1.349
  if (!is.finite(sigma0) || sigma0 <= 0) {
    sigma0 <- sd(resid, na.rm = TRUE)
  }
  if (!is.finite(sigma0) || sigma0 <= 0) sigma0 <- 1
  theta0 <- c(mu0, log(sigma0), 0, log(1))
  neg_logpost <- function(theta) {
    mu  <- theta[1]
    sig <- exp(theta[2])
    nu  <- theta[3]
    tau <- exp(theta[4])
    if (!is.finite(sig) || sig <= 0 || !is.finite(tau) || tau <= 0) return(1e12)
    ll <- try(sum(log(gamlss.dist::dJSUo(resid, mu = mu, sigma = sig, nu = nu, tau = tau))),
              silent = TRUE)
    if (inherits(ll, "try-error") || !is.finite(ll)) ll <- -1e10
    prior <- -0.5 * ( (nu^2)/n_cal + (theta[4]^2)/n_cal )
    
    -(ll + prior)
  }
  opt <- try(optim(theta0, neg_logpost, method = "BFGS",
                   control = list(maxit = optim_maxit)), silent = TRUE)
  if (inherits(opt, "try-error")) {
    mu_r <- mean(resid)
    sigma_r <- sd(resid)
    if (!is.finite(sigma_r) || sigma_r <= 0) sigma_r <- 1
    return(list(mu = mu_r, sigma = sigma_r, nu = 0, tau = 1, converged = FALSE))
  }
  th <- opt$par
  mu_r    <- th[1]
  sigma_r <- exp(th[2])
  nu_r    <- th[3]
  tau_r   <- exp(th[4])
  if (!is.finite(sigma_r) || sigma_r <= 0) {
    sigma_r <- sd(resid); if (!is.finite(sigma_r) || sigma_r <= 0) sigma_r <- 1
  }
  if (!is.finite(tau_r) || tau_r <= 0) tau_r <- 1
  list(mu = mu_r, sigma = sigma_r, nu = nu_r, tau = tau_r,
       converged = (opt$convergence == 0))
}

fit_normal_mle_global <- function(resid_vec) {
  resid <- as.numeric(resid_vec)
  resid <- resid[is.finite(resid)]
  if (length(resid) == 0) {
    return(list(mu = 0, sigma = 1, nu = NA_real_, tau = NA_real_, converged = FALSE))
  }
  mu_r <- mean(resid)
  sigma_r <- sqrt(mean((resid - mu_r)^2))
  if (!is.finite(sigma_r) || sigma_r <= 0) sigma_r <- sd(resid)
  if (!is.finite(sigma_r) || sigma_r <= 0) sigma_r <- 1
  list(mu = mu_r, sigma = sigma_r, nu = NA_real_, tau = NA_real_, converged = TRUE)
}

fit_residual_mle_global <- function(resid_vec, family = "JSUo", n_cal = NULL,
                                    optim_maxit = dncpmini_optim_maxit) {
  family <- match.arg(family, c("JSUo", "NO"))
  if (family == "NO") return(fit_normal_mle_global(resid_vec))
  fit_jsu_mle_global(resid_vec, n_cal = n_cal, optim_maxit = optim_maxit)
}

.run_dncpmini <- function(
    x_ca, y_ca,
    x_te, y_te,
    yhat_ca, yhat_te,
    alpha = 0.10, k_tail = 2,
    lambda = dncpmini_lambda,
    family = "JSUo",
    seed = 1
) {
  t0 <- proc.time()
  
  resid_ca <- as.numeric(y_ca - yhat_ca)
  n_cal_orig <- length(resid_ca)
  
  
  
  resid_ca_f <- resid_ca
  
  family <- match.arg(family, c("JSUo", "NO"))
  resid_fit <- fit_residual_mle_global(resid_ca_f, family = family, n_cal = n_cal_orig)
  mu_r    <- resid_fit$mu
  sigma_r <- resid_fit$sigma
  nu_r    <- resid_fit$nu
  tau_r   <- resid_fit$tau
  
  pL <- alpha / k_tail
  pU <- 1 - alpha / k_tail
  if (family == "NO") {
    qL_resid <- qnorm(pL, mean = mu_r, sd = sigma_r)
    qU_resid <- qnorm(pU, mean = mu_r, sd = sigma_r)
  } else {
    zL <- qnorm(pL)
    zU <- qnorm(pU)
    qL_resid <- mu_r + sigma_r * sinh((zL - nu_r) / tau_r)
    qU_resid <- mu_r + sigma_r * sinh((zU - nu_r) / tau_r)
  }
  
  L0_ca <- as.numeric(yhat_ca) + qL_resid
  U0_ca <- as.numeric(yhat_ca) + qU_resid
  
  scores <- pmax(L0_ca - y_ca, y_ca - U0_ca, 0)
  
  k_idx <- ceiling((length(scores) + 1) * (1 - alpha))
  k_idx <- min(max(k_idx, 1), length(scores))
  q_corr <- sort(scores, partial = k_idx)[k_idx]
  s_star <- lambda * q_corr
  
  yhat_te <- as.numeric(yhat_te)
  lower <- yhat_te + qL_resid - s_star
  upper <- yhat_te + qU_resid + s_star
  
  y_te <- as.numeric(y_te)
  covered <- as.numeric(y_te >= lower & y_te <= upper)
  cov  <- mean(covered, na.rm = TRUE)
  leng <- mean(upper - lower, na.rm = TRUE)
  t_elapsed <- as.numeric((proc.time() - t0)[["elapsed"]])
  
  cat(sprintf(
    "DNCP-mini | residuals=%d | ",
    n_cal_orig
  ))
  if (family == "NO") {
    cat(sprintf(
      "family=NO mu=%.4f sigma=%.4f | pL=%.4f pU=%.4f | lambda=%.4f q_corr=%.4f s*=%.4f | coverage=%.4f, length=%.4f, time=%.3fs\n",
      mu_r, sigma_r, pL, pU, lambda, q_corr, s_star, cov, leng, t_elapsed
    ))
  } else {
    cat(sprintf(
      "family=JSUo mu=%.4f sigma=%.4f nu=%.4f tau=%.4f | pL=%.4f pU=%.4f | lambda=%.4f q_corr=%.4f s*=%.4f | coverage=%.4f, length=%.4f, time=%.3fs\n",
      mu_r, sigma_r, nu_r, tau_r, pL, pU, lambda, q_corr, s_star, cov, leng, t_elapsed
    ))
  }
  
  list(
    coverage = cov,
    length  = leng,
    time    = t_elapsed,
    lower   = lower,
    upper   = upper
  )
}

# Data loading
concrete_ycol <- NULL

if (dataset_name == "sim1") {
  set.seed(1)
  n_sim <- 2000
  p_sim <- 30
  X_sim <- matrix(rnorm(n_sim * p_sim), ncol = p_sim)
  colnames(X_sim) <- paste0("X", 1:p_sim)
  beta_true <- c(1, 0.5, rep(0, p_sim - 2))
  eps <- rt(n_sim, df = 3)
  y_sim <- scale(X_sim %*% beta_true + eps)
  x_all <- X_sim
  y_all <- as.numeric(y_sim)
} else if (dataset_name == "sim2") {
  set.seed(1)
  n_sim <- 2000
  p_sim <- 30
  X_sim <- matrix(rnorm(n_sim * p_sim), ncol = p_sim)
  colnames(X_sim) <- paste0("X", 1:p_sim)
  beta_true <- c(1, 0.5, rep(0, p_sim - 2))
  epsilon <- exp(rnorm(n_sim, mean = 0, sd = 1))
  y_sim <- as.numeric(X_sim %*% beta_true + epsilon)
  x_all <- X_sim
  y_all <- y_sim
  cat("=== sim2 data loaded ===\n")
  cat(sprintf("Samples/features: n=%d, p=%d\n", nrow(x_all), ncol(x_all)))
} else if (dataset_name == "sim3") {
  set.seed(1)
  n_sim <- 2000
  p_sim <- 30
  X_sim <- matrix(rnorm(n_sim * p_sim), nrow = n_sim, ncol = p_sim)
  colnames(X_sim) <- paste0("X", 1:p_sim)
  eps <- rnorm(n_sim, 0, 1)
  y_sim <- X_sim[, 1] + 0.5 * X_sim[, 2] + (1 + abs(X_sim[, 1])) * eps
  x_all <- X_sim
  y_all <- as.numeric(y_sim)
  cat("=== sim3 data loaded ===\n")
  cat(sprintf("Samples/features: n=%d, p=%d\n", nrow(x_all), ncol(x_all)))
} else if (dataset_name == "sim_NO") {
  set.seed(1)
  n_sim <- 2000
  p_sim <- 30
  X_sim <- matrix(rnorm(n_sim * p_sim), ncol = p_sim)
  colnames(X_sim) <- paste0("X", 1:p_sim)
  beta_true <- c(1.0, 0.5, rep(0, p_sim - 2))
  epsilon <- rnorm(n_sim)
  y_sim <- as.numeric(X_sim %*% beta_true + epsilon)
  x_all <- X_sim
  y_all <- y_sim
  cat("=== sim_NO data loaded ===\n")
  cat(sprintf("Samples/features: n=%d, p=%d\n", nrow(x_all), ncol(x_all)))
} else if (dataset_name == "Concrete") {
  if (!file.exists(concrete_path)) stop(sprintf("Concrete CSV not found: %s", concrete_path))
  conc_df <- read.csv(concrete_path, header = TRUE, stringsAsFactors = FALSE)
  y_colname <- if (!is.null(concrete_ycol)) {
    stopifnot(concrete_ycol %in% names(conc_df))
    concrete_ycol
  } else {
    names(conc_df)[ncol(conc_df)]
  }
  res_conc <- prepare_with_dummies(conc_df, y_colname)
  x_all <- res_conc$X
  y_all <- res_conc$y
  colnames(x_all) <- make.names(colnames(x_all), unique = TRUE)
  cat("=== Concrete data loaded ===\n")
  cat("CSV path:", concrete_path, "\n")
  cat(sprintf("Samples/features: n=%d, p=%d\n", nrow(x_all), ncol(x_all)))
} else if (dataset_name == "Diabetes") {
  if (!file.exists(diabetes_path)) stop(sprintf("Diabetes CSV not found: %s", diabetes_path))
  ddf <- read.csv(diabetes_path, header = TRUE, stringsAsFactors = FALSE)
  ycol <- if ("target" %in% names(ddf)) "target" else tail(names(ddf), 1)
  ddf[] <- lapply(ddf, function(z) to_numeric_vector(z, nrow(ddf)))
  res_diab <- prepare_with_dummies(ddf, ycol)
  x_all <- res_diab$X
  y_all <- res_diab$y
  colnames(x_all) <- make.names(colnames(x_all), unique = TRUE)
  cat("=== Diabetes data loaded ===\n")
  cat("CSV path:", diabetes_path, "\n")
  cat(sprintf("Samples/features: n=%d, p=%d\n", nrow(x_all), ncol(x_all)))
} else if (dataset_name == "WineRed") {
  if (!file.exists(wine_red_path)) stop(sprintf("Red Wine CSV not found: %s", wine_red_path))
  wdf <- read.csv(wine_red_path, header = TRUE, stringsAsFactors = FALSE)
  wdf[] <- lapply(wdf, function(z) to_numeric_vector(z, nrow(wdf)))
  y_col <- if ("quality" %in% names(wdf)) "quality" else tail(names(wdf), 1)
  X_cols <- setdiff(names(wdf), y_col)
  Xdf <- make_numeric_df(wdf[, X_cols, drop = FALSE])
  keep_rows <- complete.cases(Xdf) & is.finite(wdf[[y_col]])
  Xdf <- Xdf[keep_rows, , drop = FALSE]
  yvec <- to_numeric_vector(wdf[[y_col]][keep_rows], sum(keep_rows))
  x_all <- as.matrix(Xdf)
  y_all <- as.numeric(yvec)
  colnames(x_all) <- make.names(colnames(x_all), unique = TRUE)
  cat("=== Red Wine data loaded ===\n")
  cat("CSV path:", wine_red_path, "\n")
  cat(sprintf("Samples/features: n=%d, p=%d | target=quality\n", nrow(x_all), ncol(x_all)))
} else if (dataset_name == "Boston") {
  if (!file.exists(boston_path)) stop("Boston CSV not found: ", boston_path)
  bdf <- read.csv(boston_path, check.names = FALSE)
  res_boston <- prepare_with_dummies(bdf, "medv")
  x_all <- res_boston$X
  y_all <- res_boston$y
  colnames(x_all) <- make.names(colnames(x_all), unique = TRUE)
  cat("=== Boston data loaded ===\n")
  cat(sprintf("Samples/features: n=%d, p=%d | target=medv\n", nrow(x_all), ncol(x_all)))
} else {
  stop('dataset_name must be one of "sim1", "sim2", "sim3", "sim_NO", "Diabetes", "WineRed", "Concrete", or "Boston".')
}

if (!is.matrix(x_all)) x_all <- model.matrix(~ . - 1, data = as.data.frame(x_all))
if (is.null(colnames(x_all))) colnames(x_all) <- paste0("X", seq_len(ncol(x_all)))
colnames(x_all) <- make.names(colnames(x_all), unique = TRUE)
storage.mode(x_all) <- "double"

cat("Dataset:", dataset_name, " | n =", nrow(x_all), " p =", ncol(x_all), "\n")
dncp_family_active <- .dncp_family_for_dataset(dataset_name)
dncpmini_family_active <- .dncpmini_family_for_dataset(dataset_name)
cat(sprintf("DNCP residual family: %s\n", dncp_family_active))
cat(sprintf("DNCP-mini residual family: %s\n", dncpmini_family_active))

input_path <- switch(dataset_name, Diabetes=diabetes_path, Concrete=concrete_path, WineRed=wine_red_path, Boston=boston_path, "")
if (nzchar(input_path)) drpi_inputs(input_path)
drpi_event("data", detail = sprintf("n=%d p=%d", nrow(x_all), ncol(x_all)))
if (any(!is.finite(x_all)) || any(!is.finite(y_all))) stop("Input contains nonfinite values; fix the input data explicitly.")

if (stage == "main") {
# Result containers
valid_original_seeds <- integer(0)
SplitCP_Coverage <- SplitCP_Length <- SplitCP_Time <- numeric(0)
LCPG_Coverage <- LCPG_Length <- LCPG_Time <- numeric(0)
LCPK_Coverage <- LCPK_Length <- LCPK_Time <- numeric(0)
LWCI_Coverage <- LWCI_Length <- LWCI_Time <- numeric(0)
WCP_Coverage  <- WCP_Length  <- WCP_Time  <- numeric(0)
DNCP_Coverage <- DNCP_Length <- DNCP_Time <- numeric(0)
DNCPmini_Coverage <- DNCPmini_Length <- DNCPmini_Time <- numeric(0)
ACPI_Coverage <- ACPI_Length <- ACPI_Time <- numeric(0)

ensure_dir <- function(path) if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)

# Main experiment loop
valid_count  <- 0
current_seed <- start_seed_no

while (valid_count < n_seeds) {
  cat(sprintf("\n==================== Original seed %d ====================\n", current_seed))
  set.seed(current_seed)
  n <- nrow(x_all); idx <- sample.int(n)
  n_train <- floor(0.4 * n); n_cal <- floor(0.4 * n)
  train_id <- idx[1:n_train]; cal_id <- idx[(n_train + 1):(n_train + n_cal)]
  test_id  <- idx[(n_train + n_cal + 1):n]
  drpi_split("main", current_seed, train_id, cal_id, test_id)
  
  x_tr <- x_all[train_id, , drop = FALSE]; y_tr <- y_all[train_id]
  x_ca <- x_all[cal_id,   , drop = FALSE]; y_ca <- y_all[cal_id]
  x_te <- x_all[test_id,  , drop = FALSE]; y_te <- y_all[test_id]
  colnames(x_tr) <- colnames(x_all); colnames(x_ca) <- colnames(x_all); colnames(x_te) <- colnames(x_all)
  tr_keep <- which(is.finite(y_tr)); ca_keep <- which(is.finite(y_ca)); te_keep <- which(is.finite(y_te))
  if (length(tr_keep) < 5 || length(ca_keep) < 5 || length(te_keep) < 5) { 
    cat("Too few finite y values in this subset; skipping this seed.\n")
    current_seed <- current_seed + 1
    next 
  }
  x_tr <- x_tr[tr_keep,,drop=FALSE]; y_tr <- y_tr[tr_keep]
  x_ca <- x_ca[ca_keep,,drop=FALSE]; y_ca <- y_ca[ca_keep]
  x_te <- x_te[te_keep,,drop=FALSE]; y_te <- y_te[te_keep]
  
  need_yhat <- any(c(RUN_SPLIT_CP, RUN_LCP_G, RUN_LCP_K, RUN_LWCI, RUN_WCP, RUN_DNCP, RUN_DNCP_MINI))
  if (need_yhat) {
    yhat_tr <- fit_and_predict(base_model, x_tr, y_tr, x_tr, alpha_en, rf_ntree)
    yhat_ca <- fit_and_predict(base_model, x_tr, y_tr, x_ca, alpha_en, rf_ntree)
    yhat_te <- fit_and_predict(base_model, x_tr, y_tr, x_te, alpha_en, rf_ntree)
  }
  
  tmp_SplitCP_Coverage <- tmp_SplitCP_Length <- tmp_SplitCP_Time <- numeric(0)
  tmp_LCPG_Coverage <- tmp_LCPG_Length <- tmp_LCPG_Time <- numeric(0)
  tmp_LCPK_Coverage <- tmp_LCPK_Length <- tmp_LCPK_Time <- numeric(0)
  tmp_LWCI_Coverage <- tmp_LWCI_Length <- tmp_LWCI_Time <- numeric(0)
  tmp_WCP_Coverage  <- tmp_WCP_Length  <- tmp_WCP_Time <- numeric(0)
  tmp_DNCP_Coverage <- tmp_DNCP_Length <- tmp_DNCP_Time <- numeric(0)
  tmp_DNCPmini_Coverage <- tmp_DNCPmini_Length <- tmp_DNCPmini_Time <- numeric(0)
  tmp_ACPI_Coverage <- tmp_ACPI_Length <- tmp_ACPI_Time <- numeric(0)
  
  if (RUN_SPLIT_CP) {
    t0 <- proc.time()
    res_ca_abs <- abs(y_ca - yhat_ca)
    k_idx <- ceiling((length(res_ca_abs) + 1) * (1 - alpha_level))
    q_hat <- sort(res_ca_abs, partial = k_idx)[k_idx]
    lower_const <- yhat_te - q_hat; upper_const <- yhat_te + q_hat
    covered_const <- as.numeric(y_te >= lower_const & y_te <= upper_const)
    orig_coverage_s <- mean(covered_const); orig_length_s <- mean(upper_const - lower_const)
    t_split <- as.numeric((proc.time() - t0)[["elapsed"]])
    cat(sprintf("Split-CP | coverage = %.4f, length = %.4f, time = %.3fs\n", orig_coverage_s, orig_length_s, t_split))
    tmp_SplitCP_Coverage <- c(tmp_SplitCP_Coverage, orig_coverage_s)
    tmp_SplitCP_Length   <- c(tmp_SplitCP_Length,   orig_length_s)
    tmp_SplitCP_Time     <- c(tmp_SplitCP_Time,     t_split)
  }
  
  if (RUN_LCP_G) {
    t0 <- proc.time()
    abs_resid_cal <- abs(y_ca - yhat_ca)
    lower_lcp_g <- upper_lcp_g <- numeric(length(y_te))
    for (j in seq_along(y_te)) {
      dists <- .euclid_dist(x_ca, x_te[j, , drop = FALSE])
      h <- if (!is.null(lcp_bandwidth)) lcp_bandwidth else median(dists)
      W <- .gaussian_kernel(dists, h)
      W_test <- 1; total_weight <- sum(W) + W_test
      target_weight <- (1 - alpha_level) * total_weight
      ord <- order(abs_resid_cal); cumw <- cumsum(W[ord])
      idx_thr <- which(cumw >= target_weight)[1]; if (is.na(idx_thr)) idx_thr <- length(ord)
      Q_alpha <- abs_resid_cal[ord[idx_thr]]
      lower_lcp_g[j] <- yhat_te[j] - Q_alpha; upper_lcp_g[j] <- yhat_te[j] + Q_alpha
    }
    covered_lcp_g <- as.numeric(y_te >= lower_lcp_g & y_te <= upper_lcp_g)
    lcpG_cov <- mean(covered_lcp_g); lcpG_len <- mean(upper_lcp_g - lower_lcp_g)
    t_lcpg <- as.numeric((proc.time() - t0)[["elapsed"]])
    cat(sprintf("LCP-Gaussian | coverage = %.4f, length = %.4f, time = %.3fs\n", lcpG_cov, lcpG_len, t_lcpg))
    tmp_LCPG_Coverage <- c(tmp_LCPG_Coverage, lcpG_cov)
    tmp_LCPG_Length   <- c(tmp_LCPG_Length,   lcpG_len)
    tmp_LCPG_Time     <- c(tmp_LCPG_Time,     t_lcpg)
  }
  
  if (RUN_LCP_K) {
    t0 <- proc.time()
    abs_resid_cal <- abs(y_ca - yhat_ca)
    lower_lcp_k <- upper_lcp_k <- numeric(length(y_te))
    for (j in seq_along(y_te)) {
      dists <- .euclid_dist(x_ca, x_te[j, , drop = FALSE])
      k_val <- min(lcp_k, length(dists))
      idx_k <- order(dists)[1:k_val]
      resid_k <- sort(abs_resid_cal[idx_k])
      q_idx2 <- ceiling((length(resid_k) + 1) * (1 - alpha_level)); q_idx2 <- min(q_idx2, length(resid_k))
      Q_alpha2 <- resid_k[q_idx2]
      lower_lcp_k[j] <- yhat_te[j] - Q_alpha2; upper_lcp_k[j] <- yhat_te[j] + Q_alpha2
    }
    covered_lcp_k <- as.numeric(y_te >= lower_lcp_k & y_te <= upper_lcp_k)
    lcpK_cov <- mean(covered_lcp_k); lcpK_len <- mean(upper_lcp_k - lower_lcp_k)
    t_lcpk <- as.numeric((proc.time() - t0)[["elapsed"]])
    cat(sprintf("LCP-kNN | coverage = %.4f, length = %.4f, time = %.3fs\n", lcpK_cov, lcpK_len, t_lcpk))
    tmp_LCPK_Coverage <- c(tmp_LCPK_Coverage, lcpK_cov)
    tmp_LCPK_Length   <- c(tmp_LCPK_Length,   lcpK_len)
    tmp_LCPK_Time     <- c(tmp_LCPK_Time,     t_lcpk)
  }
  
  if (RUN_LWCI) {
    t0 <- proc.time()
    yhat_tr <- fit_and_predict(base_model, x_tr, y_tr, x_tr, alpha_en, rf_ntree)
    res_tr_abs <- abs(y_tr - yhat_tr)
    scale_fit <- smooth.spline(yhat_tr, res_tr_abs)
    yhat_ca <- fit_and_predict(base_model, x_tr, y_tr, x_ca, alpha_en, rf_ntree)
    yhat_te <- fit_and_predict(base_model, x_tr, y_tr, x_te, alpha_en, rf_ntree)
    scale_ca <- pmax(predict(scale_fit, yhat_ca)$y, 1e-8)
    scale_te <- pmax(predict(scale_fit, yhat_te)$y, 1e-8)
    res_ca_scaled <- abs(y_ca - yhat_ca) / scale_ca
    k_idx3 <- ceiling((length(res_ca_scaled) + 1) * (1 - alpha_level))
    q_scaled <- sort(res_ca_scaled, partial = k_idx3)[k_idx3]
    lower_lwci <- yhat_te - q_scaled * scale_te; upper_lwci <- yhat_te + q_scaled * scale_te
    covered_lwci <- as.numeric(y_te >= lower_lwci & y_te <= upper_lwci)
    lwci_cov <- mean(covered_lwci); lwci_len <- mean(upper_lwci - lower_lwci)
    t_lwci <- as.numeric((proc.time() - t0)[["elapsed"]])
    cat(sprintf("LWCI (spline) | coverage = %.4f, length = %.4f, time = %.3fs\n", lwci_cov, lwci_len, t_lwci))
    tmp_LWCI_Coverage <- c(tmp_LWCI_Coverage, lwci_cov)
    tmp_LWCI_Length   <- c(tmp_LWCI_Length,   lwci_len)
    tmp_LWCI_Time     <- c(tmp_LWCI_Time,     t_lwci)
  }
  
  if (RUN_WCP) {
    t0 <- proc.time()
    est_density_ratio <- function(x_cal, x_test, method = "logistic", cap = 50) {
      Xc <- as.data.frame(x_cal, check.names = FALSE); Xt <- as.data.frame(x_test, check.names = FALSE)
      Xc$.__LABEL__ <- 0; Xt$.__LABEL__ <- 1; XX <- rbind(Xc, Xt)
      ylab <- XX$.__LABEL__; XX$.__LABEL__ <- NULL
      if (method == "logistic") {
        x_mat <- model.matrix(~ . - 1, data = XX)
        cvfit <- glmnet::cv.glmnet(x_mat, ylab, family = "binomial", alpha = 0, nlambda = 100)
        p_hat <- as.numeric(predict(cvfit, newx = x_mat, s = "lambda.min", type = "response"))
      } else stop("Unknown wcp_method")
      pi_test <- mean(ylab == 1); odds <- p_hat / pmax(1 - p_hat, 1e-8)
      ratio <- odds * ((1 - pi_test) / pmax(pi_test, 1e-8))
      r_cal <- ratio[1:nrow(x_cal)]; r_test <- ratio[(nrow(x_cal)+1):(nrow(x_cal)+nrow(x_test))]
      r_cal <- pmin(r_cal, cap); r_test <- pmin(r_test, cap); list(r_cal = r_cal, r_test = r_test)
    }
    yhat_ca <- fit_and_predict(base_model, x_tr, y_tr, x_ca, alpha_en, rf_ntree)
    yhat_te <- fit_and_predict(base_model, x_tr, y_tr, x_te, alpha_en, rf_ntree)
    res_ca_abs <- abs(y_ca - yhat_ca)
    dr <- est_density_ratio(x_ca, x_te, method = wcp_method, cap = wcp_cap_ratio)
    o <- order(res_ca_abs); r_sorted <- res_ca_abs[o]; w_sorted <- dr$r_cal[o]
    lower_wcp <- upper_wcp <- numeric(length(y_te))
    for (i in seq_along(y_te)) {
      q_w <- weighted_quantile(c(r_sorted, Inf), 1 - alpha_level, w = c(w_sorted, dr$r_test[i]), sorted = TRUE)
      lower_wcp[i] <- yhat_te[i] - q_w; upper_wcp[i] <- yhat_te[i] + q_w
    }
    covered_wcp <- as.numeric(y_te >= lower_wcp & y_te <= upper_wcp)
    wcp_cov <- mean(covered_wcp); wcp_len <- mean(upper_wcp - lower_wcp)
    t_wcp <- as.numeric((proc.time() - t0)[["elapsed"]])
    cat(sprintf("WCP | coverage = %.4f, length = %.4f, time = %.3fs\n", wcp_cov, wcp_len, t_wcp))
    tmp_WCP_Coverage <- c(tmp_WCP_Coverage, wcp_cov)
    tmp_WCP_Length   <- c(tmp_WCP_Length,   wcp_len)
    tmp_WCP_Time     <- c(tmp_WCP_Time,     t_wcp)
  }
  
  if (RUN_DNCP) {
      t0 <- proc.time()
      yhat_ca <- fit_and_predict(base_model, x_tr, y_tr, x_ca, alpha_en, rf_ntree)
      yhat_te <- fit_and_predict(base_model, x_tr, y_tr, x_te, alpha_en, rf_ntree)
      res_ca_signed <- y_ca - yhat_ca
      df_x_ca <- as.data.frame(x_ca, check.names = FALSE); colnames(df_x_ca) <- colnames(x_all)
      df_ca_resid <- data.frame(resid = res_ca_signed, df_x_ca, check.names = FALSE)
      df_ca_resid_f <- df_ca_resid
      
      ncal_f <- nrow(df_ca_resid_f)
      ctrl_forest_resid <- disttree_control(minsplit = max(20,floor(0.2 * ncal_f)),
                                            minbucket = max(10,floor(0.2 * ncal_f)),
                                            mincriterion = 0.9)
      set.seed(current_seed)
      gamlss_fam <- .get_family(dncp_family_active); param_names <- .get_param_names(dncp_family_active); qFUN <- .get_qfun(dncp_family_active)
      df_resid_model <- distforest(resid ~ ., data = df_ca_resid_f,
                                   family = gamlss_fam, ntree = dncp_ntree,
                                   control = ctrl_forest_resid, trace = FALSE)
      df_x_te <- as.data.frame(x_te, check.names = FALSE); colnames(df_x_te) <- colnames(x_all)
      par_te <- to_df_safe(predict(df_resid_model, newdata = df_x_te, type = "parameter"))
      par_te <- par_te[, param_names, drop = FALSE]; par_te <- as.data.frame(lapply(par_te, function(z) to_numeric_vector(z, nrow(par_te))))
      if ("sigma" %in% names(par_te)) par_te$sigma <- pmax(par_te$sigma, 1e-6)
      if ("tau"   %in% names(par_te)) par_te$tau   <- pmax(par_te$tau,   1e-6)
      pL <- alpha_level / k_tail; pU <- 1 - alpha_level / k_tail
      qL_resid <- vapply(seq_len(nrow(par_te)), function(i) do.call(qFUN, c(list(p = pL), as.list(par_te[i, , drop = FALSE]))), numeric(1))
      qU_resid <- vapply(seq_len(nrow(par_te)), function(i) do.call(qFUN, c(list(p = pU), as.list(par_te[i, , drop = FALSE]))), numeric(1))
      mu_resid <- par_te$mu; y_center <- yhat_te + mu_resid
      lower_pers <- y_center + (qL_resid - mu_resid); upper_pers <- y_center + (qU_resid - mu_resid)
      covered_pers <- as.numeric(y_te >= lower_pers & y_te <= upper_pers)
      pers_cov <- mean(covered_pers); pers_len <- mean(upper_pers - lower_pers)
      t_dncp <- as.numeric((proc.time() - t0)[["elapsed"]])
      cat(sprintf("DNCP | coverage = %.4f, length = %.4f, time = %.3fs\n", pers_cov, pers_len, t_dncp))
      tmp_DNCP_Coverage <- c(tmp_DNCP_Coverage, pers_cov)
      tmp_DNCP_Length   <- c(tmp_DNCP_Length,   pers_len)
      tmp_DNCP_Time     <- c(tmp_DNCP_Time,     t_dncp)
  }
  
  
  if (RUN_ACPI) {
    t0 <- proc.time()
    acpi <- .run_acpi(
      base_model = base_model,
      x_tr = x_tr, y_tr = y_tr, x_cal = x_ca, y_cal = y_ca, x_te = x_te, y_te = y_te,
      alpha = alpha_level, seed = current_seed,
      alpha_en = alpha_en, rf_ntree = rf_ntree,
      qrf_nodesize = acpi_nodesize, steps = acpi_scan_steps
    )
    t_acpi <- as.numeric((proc.time() - t0)[["elapsed"]])
    cat(sprintf("ACPI(%s) | coverage = %.4f, length = %.4f, time = %.3fs | alpha* = %.4f\n",
                base_model, acpi$coverage, acpi$length, t_acpi, acpi$alpha_star))
    tmp_ACPI_Coverage <- c(tmp_ACPI_Coverage, acpi$coverage)
    tmp_ACPI_Length   <- c(tmp_ACPI_Length,   acpi$length)
    tmp_ACPI_Time     <- c(tmp_ACPI_Time,     t_acpi)
  }
  
  if (RUN_DNCP_MINI) {
    dncpmini_res <- .run_dncpmini(
      x_ca    = x_ca, y_ca = y_ca,
      x_te    = x_te, y_te = y_te,
      yhat_ca = yhat_ca, yhat_te = yhat_te,
      alpha   = alpha_level, k_tail = k_tail,
      lambda  = dncpmini_lambda,
      family  = dncpmini_family_active,
      seed    = current_seed
    )
    tmp_DNCPmini_Coverage <- c(tmp_DNCPmini_Coverage, dncpmini_res$coverage)
    tmp_DNCPmini_Length   <- c(tmp_DNCPmini_Length,   dncpmini_res$length)
    tmp_DNCPmini_Time     <- c(tmp_DNCPmini_Time,     dncpmini_res$time)
  }
  
  
  if (RUN_SPLIT_CP) { 
    SplitCP_Coverage <- c(SplitCP_Coverage, tmp_SplitCP_Coverage)
    SplitCP_Length   <- c(SplitCP_Length,   tmp_SplitCP_Length)
    SplitCP_Time     <- c(SplitCP_Time,     tmp_SplitCP_Time) 
  }
  if (RUN_LCP_G) {
    LCPG_Coverage <- c(LCPG_Coverage, tmp_LCPG_Coverage)
    LCPG_Length   <- c(LCPG_Length,   tmp_LCPG_Length)
    LCPG_Time     <- c(LCPG_Time,     tmp_LCPG_Time)
  }
  if (RUN_LCP_K) {
    LCPK_Coverage <- c(LCPK_Coverage, tmp_LCPK_Coverage)
    LCPK_Length   <- c(LCPK_Length,   tmp_LCPK_Length)
    LCPK_Time     <- c(LCPK_Time,     tmp_LCPK_Time)
  }
  if (RUN_LWCI) {
    LWCI_Coverage <- c(LWCI_Coverage, tmp_LWCI_Coverage)
    LWCI_Length   <- c(LWCI_Length,   tmp_LWCI_Length)
    LWCI_Time     <- c(LWCI_Time,     tmp_LWCI_Time)
  }
  if (RUN_WCP) {
    WCP_Coverage  <- c(WCP_Coverage,  tmp_WCP_Coverage)
    WCP_Length    <- c(WCP_Length,    tmp_WCP_Length)
    WCP_Time      <- c(WCP_Time,      tmp_WCP_Time)
  }
  if (RUN_DNCP) {
    DNCP_Coverage <- c(DNCP_Coverage, tmp_DNCP_Coverage)
    DNCP_Length   <- c(DNCP_Length,   tmp_DNCP_Length)
    DNCP_Time     <- c(DNCP_Time,     tmp_DNCP_Time)
  }
  if (RUN_DNCP_MINI) {
    DNCPmini_Coverage <- c(DNCPmini_Coverage, tmp_DNCPmini_Coverage)
    DNCPmini_Length   <- c(DNCPmini_Length,   tmp_DNCPmini_Length)
    DNCPmini_Time     <- c(DNCPmini_Time,     tmp_DNCPmini_Time)
  }
  if (RUN_ACPI) {
    ACPI_Coverage <- c(ACPI_Coverage, tmp_ACPI_Coverage)
    ACPI_Length   <- c(ACPI_Length,   tmp_ACPI_Length)
    ACPI_Time     <- c(ACPI_Time,     tmp_ACPI_Time)
  }
  drpi_event("main", current_seed, "accepted")
  valid_original_seeds <- c(valid_original_seeds, current_seed)
  valid_count <- valid_count + 1
  cat(sprintf(">>> Seed %d accepted. Collected %d/%d valid.\n", current_seed, valid_count, n_seeds))
  
  current_seed <- current_seed + 1
}

results <- data.frame(Valid_Seed_Index = seq_along(valid_original_seeds),
                      Original_Seed    = valid_original_seeds)
add_col <- function(df, name, vec) { if (length(vec)>0) cbind(df, setNames(list(vec), name)) else df }

if (RUN_SPLIT_CP){ results <- add_col(results, "SplitCP_Cov",  SplitCP_Coverage)
results <- add_col(results, "SplitCP_Len",  SplitCP_Length)
results <- add_col(results, "SplitCP_Time", SplitCP_Time) }
if (RUN_LCP_G)   { results <- add_col(results, "LCPG_Cov",  LCPG_Coverage)
results <- add_col(results, "LCPG_Len",  LCPG_Length)
results <- add_col(results, "LCPG_Time", LCPG_Time) }
if (RUN_LCP_K)   { results <- add_col(results, "LCPK_Cov",  LCPK_Coverage)
results <- add_col(results, "LCPK_Len",  LCPK_Length)
results <- add_col(results, "LCPK_Time", LCPK_Time) }
if (RUN_LWCI)    { results <- add_col(results, "LWCI_Cov",  LWCI_Coverage)
results <- add_col(results, "LWCI_Len",  LWCI_Length)
results <- add_col(results, "LWCI_Time", LWCI_Time) }
if (RUN_WCP)     { results <- add_col(results, "WCP_Cov",  WCP_Coverage)
results <- add_col(results, "WCP_Len",  WCP_Length)
results <- add_col(results, "WCP_Time", WCP_Time) }
if (RUN_DNCP)   { results <- add_col(results, "DNCP_Cov",  DNCP_Coverage)
results <- add_col(results, "DNCP_Len",  DNCP_Length)
results <- add_col(results, "DNCP_Time", DNCP_Time) }
if (RUN_DNCP_MINI){ results <- add_col(results, "DNCP-mini_Cov",  DNCPmini_Coverage)
results <- add_col(results, "DNCP-mini_Len",  DNCPmini_Length)
results <- add_col(results, "DNCP-mini_Time", DNCPmini_Time) }
if (RUN_ACPI){ results <- add_col(results, "ACPI_Cov",  ACPI_Coverage)
results <- add_col(results, "ACPI_Len",  ACPI_Length)
results <- add_col(results, "ACPI_Time", ACPI_Time) }

cat("\n==================== Head of results (valid seeds only) ====================\n")
print(head(results, 10), row.names = FALSE)

# Performance summary
mavg <- function(x) if (length(x)) mean(x, na.rm = TRUE) else NA_real_
msd  <- function(x) if (length(x)) sd(x,   na.rm = TRUE) else NA_real_

cat("\n—— Summary over VALID seeds ——\n")
cat(sprintf("Valid seeds: %d / %d\n", length(valid_original_seeds), n_seeds))

pr <- function(name, cov_vec, len_vec, time_vec) {
  cat(sprintf("%-28s: cov = %.6f ± %.6f | len = %.6f ± %.6f | time = %.3f s\n",
              name, mavg(cov_vec), msd(cov_vec), mavg(len_vec), msd(len_vec), mavg(time_vec)))
}
safe_pr <- function(enabled, name, cov_vec, len_vec, time_vec) {
  if (!enabled) return(invisible(NULL))
  if (length(cov_vec) > 0 && length(len_vec) > 0 && length(time_vec) > 0) pr(name, cov_vec, len_vec, time_vec)
  else cat(sprintf("%-28s: (no valid seeds)\n", name))
}

cat("\n—— Model Performance ——\n")
safe_pr(RUN_SPLIT_CP,   "Split-CP",                 SplitCP_Coverage, SplitCP_Length, SplitCP_Time)
safe_pr(RUN_LCP_G,      "LCP (Gaussian)",           LCPG_Coverage,    LCPG_Length,    LCPG_Time)
safe_pr(RUN_LCP_K,      "LCP (kNN)",                LCPK_Coverage,    LCPK_Length,    LCPK_Time)
safe_pr(RUN_LWCI,       "LWCI (spline)",            LWCI_Coverage,    LWCI_Length,    LWCI_Time)
safe_pr(RUN_WCP,        "WCP",                      WCP_Coverage,     WCP_Length,     WCP_Time)
safe_pr(RUN_ACPI,       "ACPI",                     ACPI_Coverage,    ACPI_Length,    ACPI_Time)
safe_pr(RUN_DNCP,       "DNCP",       DNCP_Coverage,     DNCP_Length,     DNCP_Time)
safe_pr(RUN_DNCP_MINI,  "DNCP-mini",  DNCPmini_Coverage, DNCPmini_Length, DNCPmini_Time)

# Per-seed CSV export
export_dir <- file.path(export_root, paste0(dataset_name, base_model))
ensure_dir(export_dir)

seed_df <- data.frame(Seed = valid_original_seeds)

write_method_csv <- function(enabled, method_name, cov_vec, len_vec) {
  if (!enabled) return(invisible(NULL))
  if (length(cov_vec) == 0 || length(len_vec) == 0) return(invisible(NULL))
  
  out <- data.frame(
    Seed     = seed_df$Seed,
    Coverage = as.numeric(cov_vec),
    Length   = as.numeric(len_vec)
  )
  
  fn <- file.path(export_dir, paste0(method_name, ".csv"))
  write.csv(out, fn, row.names = FALSE, fileEncoding = "UTF-8")
  file.copy(fn, file.path(.drpi_record$dir, basename(fn)), overwrite = TRUE)
  cat(sprintf("Saved CSV: %s\n", fn))

  if (!is.null(mirror_export_root) && nzchar(mirror_export_root)) {
    mirror_dir <- file.path(mirror_export_root, paste0(dataset_name, base_model))
    ensure_dir(mirror_dir)
    mirror_fn <- file.path(mirror_dir, paste0(method_name, ".csv"))
    if (!file.copy(fn, mirror_fn, overwrite = TRUE)) {
      stop(sprintf("Failed to synchronize mirror CSV: %s", mirror_fn))
    }
    cat(sprintf("Synced mirror CSV: %s\n", mirror_fn))
  }
}

write_method_csv(RUN_SPLIT_CP, "SplitCP",          SplitCP_Coverage, SplitCP_Length)
write_method_csv(RUN_LCP_G,    "LCP_Gaussian",     LCPG_Coverage,    LCPG_Length)
write_method_csv(RUN_LCP_K,    "LCP_kNN",          LCPK_Coverage,    LCPK_Length)
write_method_csv(RUN_LWCI,     "LWCI",             LWCI_Coverage,    LWCI_Length)
write_method_csv(RUN_WCP,      "WCP",              WCP_Coverage,     WCP_Length)
write_method_csv(RUN_ACPI,     "ACPI",             ACPI_Coverage,    ACPI_Length)
dncp_export_name <- if (legacy_result_names) "DRF" else "DNCP"
lambda_tag <- format(dncpmini_lambda, scientific = FALSE, trim = TRUE)
dncpmini_export_name <- if (exists("lambda_sensitivity_output") && lambda_sensitivity_output) {
  paste0("DNCPmini_lambda_", lambda_tag)
} else if (legacy_result_names) {
  "MAP_DNCPmini"
} else {
  "DNCP-mini"
}
write_method_csv(RUN_DNCP,       dncp_export_name,     DNCP_Coverage,     DNCP_Length)
write_method_csv(RUN_DNCP_MINI,  dncpmini_export_name, DNCPmini_Coverage, DNCPmini_Length)

cat(sprintf("\n>>> Export folder: %s\n", export_dir))

}

# Post-hoc sample-wise correctness frequency for Diabetes + elastic_net
if (stage == "frequency") {
  
  export_root2 <- file.path(export_root, "frequency")
  ensure_dir(export_root2)
  
  n_all <- nrow(x_all)
  
  .init_counter <- function(enabled) {
    if (!enabled) return(NULL)
    list(total = integer(n_all), correct = integer(n_all))
  }
  
  .update_counter <- function(counter, test_ids, covered01) {
    if (is.null(counter)) return(counter)
    if (length(test_ids) == 0) return(counter)
    if (length(covered01) != length(test_ids)) covered01 <- rep_len(covered01, length(test_ids))
    
    idx <- as.integer(test_ids)
    good <- is.finite(idx) & idx >= 1 & idx <= n_all
    idx <- idx[good]
    cov01 <- as.integer(as.numeric(covered01[good]) > 0.5)
    
    counter$total[idx]   <- counter$total[idx]   + 1L
    counter$correct[idx] <- counter$correct[idx] + cov01
    counter
  }
  
  cnt_SplitCP <- .init_counter(RUN_SPLIT_CP)
  cnt_LCPG    <- .init_counter(RUN_LCP_G)
  cnt_LCPK    <- .init_counter(RUN_LCP_K)
  cnt_LWCI    <- .init_counter(RUN_LWCI)
  cnt_WCP     <- .init_counter(RUN_WCP)
  cnt_DNCP    <- .init_counter(RUN_DNCP)
  cnt_DNCPmini <- .init_counter(RUN_DNCP_MINI)
  cnt_ACPI    <- .init_counter(RUN_ACPI)
  
  cat("\n==================== Post-hoc sample-wise frequency ====================\n")
  cat(sprintf("Re-run %d valid seeds to compute per-sample correctness frequency...\n",
              length(valid_original_seeds)))
  
  for (ss in valid_original_seeds) {
    set.seed(ss)
    
    n <- nrow(x_all)
    idx <- sample.int(n)
    n_train <- floor(0.4 * n)
    n_cal   <- floor(0.4 * n)
    
    train_id <- idx[1:n_train]
    cal_id   <- idx[(n_train + 1):(n_train + n_cal)]
    test_id  <- idx[(n_train + n_cal + 1):n]
    drpi_split("frequency", ss, train_id, cal_id, test_id)
    
    x_tr <- x_all[train_id, , drop = FALSE]; y_tr <- y_all[train_id]
    x_ca <- x_all[cal_id,   , drop = FALSE]; y_ca <- y_all[cal_id]
    x_te <- x_all[test_id,  , drop = FALSE]; y_te <- y_all[test_id]
    
    tr_keep <- which(is.finite(y_tr))
    ca_keep <- which(is.finite(y_ca))
    te_keep <- which(is.finite(y_te))
    if (length(tr_keep) < 5 || length(ca_keep) < 5 || length(te_keep) < 5) next
    
    x_tr <- x_tr[tr_keep,,drop=FALSE]; y_tr <- y_tr[tr_keep]
    x_ca <- x_ca[ca_keep,,drop=FALSE]; y_ca <- y_ca[ca_keep]
    x_te <- x_te[te_keep,,drop=FALSE]; y_te <- y_te[te_keep]
    test_id_kept <- test_id[te_keep]
    
    need_yhat <- any(c(RUN_SPLIT_CP, RUN_LCP_G, RUN_LCP_K, RUN_LWCI, RUN_WCP, RUN_DNCP, RUN_DNCP_MINI))
    if (need_yhat) {
      yhat_ca <- fit_and_predict(base_model, x_tr, y_tr, x_ca, alpha_en, rf_ntree)
      yhat_te <- fit_and_predict(base_model, x_tr, y_tr, x_te, alpha_en, rf_ntree)
    }
    
    if (RUN_SPLIT_CP) {
      res_ca_abs <- abs(y_ca - yhat_ca)
      k_idx <- ceiling((length(res_ca_abs) + 1) * (1 - alpha_level))
      k_idx <- min(max(k_idx, 1), length(res_ca_abs))
      q_hat <- sort(res_ca_abs, partial = k_idx)[k_idx]
      lower <- yhat_te - q_hat
      upper <- yhat_te + q_hat
      covered <- as.numeric(y_te >= lower & y_te <= upper)
      cnt_SplitCP <- .update_counter(cnt_SplitCP, test_id_kept, covered)
    }
    
    if (RUN_LCP_G) {
      abs_resid_cal <- abs(y_ca - yhat_ca)
      lower_lcp_g <- upper_lcp_g <- numeric(length(y_te))
      for (j in seq_along(y_te)) {
        dists <- .euclid_dist(x_ca, x_te[j, , drop = FALSE])
        h <- if (!is.null(lcp_bandwidth)) lcp_bandwidth else median(dists)
        W <- .gaussian_kernel(dists, h)
        W_test <- 1; total_weight <- sum(W) + W_test
        target_weight <- (1 - alpha_level) * total_weight
        ord <- order(abs_resid_cal); cumw <- cumsum(W[ord])
        idx_thr <- which(cumw >= target_weight)[1]; if (is.na(idx_thr)) idx_thr <- length(ord)
        Q_alpha <- abs_resid_cal[ord[idx_thr]]
        lower_lcp_g[j] <- yhat_te[j] - Q_alpha
        upper_lcp_g[j] <- yhat_te[j] + Q_alpha
      }
      covered <- as.numeric(y_te >= lower_lcp_g & y_te <= upper_lcp_g)
      cnt_LCPG <- .update_counter(cnt_LCPG, test_id_kept, covered)
    }
    
    if (RUN_LCP_K) {
      abs_resid_cal <- abs(y_ca - yhat_ca)
      lower_lcp_k <- upper_lcp_k <- numeric(length(y_te))
      for (j in seq_along(y_te)) {
        dists <- .euclid_dist(x_ca, x_te[j, , drop = FALSE])
        k_val <- min(lcp_k, length(dists))
        idx_k <- order(dists)[1:k_val]
        resid_k <- sort(abs_resid_cal[idx_k])
        q_idx2 <- ceiling((length(resid_k) + 1) * (1 - alpha_level))
        q_idx2 <- min(max(q_idx2, 1), length(resid_k))
        Q_alpha2 <- resid_k[q_idx2]
        lower_lcp_k[j] <- yhat_te[j] - Q_alpha2
        upper_lcp_k[j] <- yhat_te[j] + Q_alpha2
      }
      covered <- as.numeric(y_te >= lower_lcp_k & y_te <= upper_lcp_k)
      cnt_LCPK <- .update_counter(cnt_LCPK, test_id_kept, covered)
    }
    
    if (RUN_LWCI) {
      yhat_tr2 <- fit_and_predict(base_model, x_tr, y_tr, x_tr, alpha_en, rf_ntree)
      res_tr_abs <- abs(y_tr - yhat_tr2)
      scale_fit <- smooth.spline(yhat_tr2, res_tr_abs)
      
      scale_ca <- pmax(predict(scale_fit, yhat_ca)$y, 1e-8)
      scale_te <- pmax(predict(scale_fit, yhat_te)$y, 1e-8)
      
      res_ca_scaled <- abs(y_ca - yhat_ca) / scale_ca
      k_idx3 <- ceiling((length(res_ca_scaled) + 1) * (1 - alpha_level))
      k_idx3 <- min(max(k_idx3, 1), length(res_ca_scaled))
      q_scaled <- sort(res_ca_scaled, partial = k_idx3)[k_idx3]
      
      lower <- yhat_te - q_scaled * scale_te
      upper <- yhat_te + q_scaled * scale_te
      covered <- as.numeric(y_te >= lower & y_te <= upper)
      cnt_LWCI <- .update_counter(cnt_LWCI, test_id_kept, covered)
    }
    
    if (RUN_WCP) {
      est_density_ratio <- function(x_cal, x_test, method = "logistic", cap = 50) {
        Xc <- as.data.frame(x_cal, check.names = FALSE); Xt <- as.data.frame(x_test, check.names = FALSE)
        Xc$.__LABEL__ <- 0; Xt$.__LABEL__ <- 1; XX <- rbind(Xc, Xt)
        ylab <- XX$.__LABEL__; XX$.__LABEL__ <- NULL
        x_mat <- model.matrix(~ . - 1, data = XX)
        cvfit <- glmnet::cv.glmnet(x_mat, ylab, family = "binomial", alpha = 0, nlambda = 100)
        p_hat <- as.numeric(predict(cvfit, newx = x_mat, s = "lambda.min", type = "response"))
        pi_test <- mean(ylab == 1)
        odds <- p_hat / pmax(1 - p_hat, 1e-8)
        ratio <- odds * ((1 - pi_test) / pmax(pi_test, 1e-8))
        r_cal <- ratio[1:nrow(x_cal)]
        r_test <- ratio[(nrow(x_cal)+1):(nrow(x_cal)+nrow(x_test))]
        r_cal <- pmin(r_cal, cap); r_test <- pmin(r_test, cap)
        list(r_cal = r_cal, r_test = r_test)
      }
      res_ca_abs <- abs(y_ca - yhat_ca)
      dr <- est_density_ratio(x_ca, x_te, method = wcp_method, cap = wcp_cap_ratio)
      
      o <- order(res_ca_abs); r_sorted <- res_ca_abs[o]; w_sorted <- dr$r_cal[o]
      lower <- upper <- numeric(length(y_te))
      for (i in seq_along(y_te)) {
        q_w <- weighted_quantile(c(r_sorted, Inf), 1 - alpha_level,
                                 w = c(w_sorted, dr$r_test[i]), sorted = TRUE)
        lower[i] <- yhat_te[i] - q_w
        upper[i] <- yhat_te[i] + q_w
      }
      covered <- as.numeric(y_te >= lower & y_te <= upper)
      cnt_WCP <- .update_counter(cnt_WCP, test_id_kept, covered)
    }
    
    if (RUN_DNCP) {
      res_ca_signed <- y_ca - yhat_ca
      df_x_ca <- as.data.frame(x_ca, check.names = FALSE)
      df_ca_resid <- data.frame(resid = res_ca_signed, df_x_ca, check.names = FALSE)
      df_ca_resid_f <- df_ca_resid
      
      
      
      ncal_f <- nrow(df_ca_resid_f)
      ctrl <- disttree_control(minsplit = max(20,floor(0.2 * ncal_f)),
                               minbucket = max(10,floor(0.2 * ncal_f)),
                               mincriterion = 0.9)
      
      set.seed(ss)
      fam <- .get_family(dncp_family_active)
      param_names <- .get_param_names(dncp_family_active)
      qFUN <- .get_qfun(dncp_family_active)
      
      df_resid_model <- distforest(resid ~ ., data = df_ca_resid_f,
                                   family = fam, ntree = dncp_ntree,
                                   control = ctrl, trace = FALSE)
      
      df_x_te <- as.data.frame(x_te, check.names = FALSE)
      par_te <- to_df_safe(predict(df_resid_model, newdata = df_x_te, type = "parameter"))
      par_te <- par_te[, param_names, drop = FALSE]
      par_te <- as.data.frame(lapply(par_te, function(z) to_numeric_vector(z, nrow(par_te))))
      if ("sigma" %in% names(par_te)) par_te$sigma <- pmax(par_te$sigma, 1e-6)
      if ("tau"   %in% names(par_te)) par_te$tau   <- pmax(par_te$tau,   1e-6)
      
      pL <- alpha_level / k_tail
      pU <- 1 - alpha_level / k_tail
      qL <- vapply(seq_len(nrow(par_te)), function(i) do.call(qFUN, c(list(p = pL), as.list(par_te[i,,drop=FALSE]))), numeric(1))
      qU <- vapply(seq_len(nrow(par_te)), function(i) do.call(qFUN, c(list(p = pU), as.list(par_te[i,,drop=FALSE]))), numeric(1))
      
      mu_resid <- par_te$mu
      y_center <- yhat_te + mu_resid
      lower <- y_center + (qL - mu_resid)
      upper <- y_center + (qU - mu_resid)
      
      covered <- as.numeric(y_te >= lower & y_te <= upper)
      cnt_DNCP <- .update_counter(cnt_DNCP, test_id_kept, covered)
    }
    
    
    if (RUN_DNCP_MINI) {
      dncpmini_res <- .run_dncpmini(
        x_ca    = x_ca, y_ca = y_ca,
        x_te    = x_te, y_te = y_te,
        yhat_ca = yhat_ca, yhat_te = yhat_te,
        alpha   = alpha_level, k_tail = k_tail,
        lambda  = dncpmini_lambda,
        family  = dncpmini_family_active,
        seed    = ss
      )
      covered <- as.numeric(y_te >= dncpmini_res$lower & y_te <= dncpmini_res$upper)
      cnt_DNCPmini <- .update_counter(cnt_DNCPmini, test_id_kept, covered)
    }
    
    
    if (RUN_ACPI) {
      acpi <- .run_acpi(
        base_model = base_model,
        x_tr = x_tr, y_tr = y_tr, x_cal = x_ca, y_cal = y_ca, x_te = x_te, y_te = y_te,
        alpha = alpha_level, seed = ss,
        alpha_en = alpha_en, rf_ntree = rf_ntree,
        qrf_nodesize = acpi_nodesize, steps = acpi_scan_steps
      )
      covered <- as.numeric(y_te >= acpi$lower & y_te <= acpi$upper)
      cnt_ACPI <- .update_counter(cnt_ACPI, test_id_kept, covered)
    }
    
  }
  
  .freq <- function(counter) {
    if (is.null(counter)) return(NULL)
    out <- rep(NA_real_, n_all)
    ok <- counter$total > 0
    out[ok] <- counter$correct[ok] / counter$total[ok]
    out
  }
  
  freq_df <- data.frame(SampleIndex = 1:n_all)
  
  if (RUN_SPLIT_CP) freq_df$SplitCP      <- .freq(cnt_SplitCP)
  if (RUN_LCP_G)    freq_df$LCP_Gaussian <- .freq(cnt_LCPG)
  if (RUN_LCP_K)    freq_df$LCP_kNN      <- .freq(cnt_LCPK)
  if (RUN_LWCI)     freq_df$LWCI         <- .freq(cnt_LWCI)
  if (RUN_WCP)      freq_df$WCP          <- .freq(cnt_WCP)
  if (RUN_ACPI)     freq_df$ACPI         <- .freq(cnt_ACPI)
  if (RUN_DNCP)      freq_df$DNCP          <- .freq(cnt_DNCP)
  if (RUN_DNCP_MINI) freq_df[["DNCP-mini"]] <- .freq(cnt_DNCPmini)
  
  alg_cols <- setdiff(names(freq_df), "SampleIndex")
  sd_vec <- vapply(alg_cols, function(nm) sd(freq_df[[nm]], na.rm = TRUE), numeric(1))
  sd_df <- data.frame(Algorithm = alg_cols, SD_of_Frequency = sd_vec)
  
  out_fn1 <- file.path(export_root2, paste0("Diabetes", base_model, "correct_prediction_frequency.csv"))
  out_fn2 <- file.path(export_root2, paste0("Diabetes", base_model, "correct_prediction_frequency_dispersion_sd.csv"))
  
  write.csv(freq_df, out_fn1, row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(sd_df,   out_fn2, row.names = FALSE, fileEncoding = "UTF-8")
  
  cat(sprintf("\nSaved per-sample frequency CSV: %s\n", out_fn1))
  cat(sprintf("Saved dispersion(SD) CSV:       %s\n", out_fn2))
}

# Post-hoc console summary for Diabetes + elastic_net
if (stage == "frequency") {
  
  cat("\n================ Sample-wise stability summary ================\n")
  cat("Condition: Diabetes + elastic_net\n\n")
  
  if (!exists("freq_df")) {
    stop("freq_df does not exist; make sure the correct-prediction-frequency block has run.")
  }
  
  alg_cols <- setdiff(names(freq_df), "SampleIndex")
  
  summary_list <- lapply(alg_cols, function(alg) {
    freq <- freq_df[[alg]]
    
    data.frame(
      SampleIndex     = freq_df$SampleIndex,
      Algorithm       = alg,
      CorrectFreq     = freq,
      AlwaysCorrect   = as.integer(!is.na(freq) & freq == 1),
      AlwaysWrong     = as.integer(!is.na(freq) & freq == 0)
    )
  })
  
  summary_df <- do.call(rbind, summary_list)
  
  print(head(summary_df, 20), row.names = FALSE)
  
  extreme_summary <- do.call(rbind, lapply(alg_cols, function(alg) {
    freq <- freq_df[[alg]]
    data.frame(
      Algorithm        = alg,
      AlwaysCorrect_N  = sum(freq == 1, na.rm = TRUE),
      AlwaysWrong_N    = sum(freq == 0, na.rm = TRUE),
      Mixed_N          = sum(freq > 0 & freq < 1, na.rm = TRUE),
      SD_Frequency     = sd(freq, na.rm = TRUE)
    )
  }))
  
  cat("\n================ Algorithm-level extreme behavior ================\n")
  print(extreme_summary, row.names = FALSE)
  
  cat("\nInterpretation notes:\n")
  cat("- AlwaysCorrect: samples covered in every random split.\n")
  cat("- AlwaysWrong: samples missed in every random split.\n")
  cat("- Mixed: samples whose coverage depends on the split.\n")
  cat("- SD_Frequency: dispersion of sample-level coverage frequency.\n")
}

# Post-hoc frequency/variance summary for sample 337 under Diabetes + elastic_net
if (stage == "case337") {
  
  export_root3 <- file.path(export_root, "case337")
  ensure_dir(export_root3)
  
  n_all <- nrow(x_all)
  seeds_all <- seq.int(case_seed_start, case_seed_end)
  target_id <- case_id
  
  if (target_id < 1 || target_id > n_all) stop("target_id out of range.")
  
  .init_vec_store <- function(enabled) {
    if (!enabled) return(NULL)
    list(correct = integer(0), length = numeric(0), seed = integer(0), lower = numeric(0), upper = numeric(0))
  }
  
  store_SplitCP <- .init_vec_store(RUN_SPLIT_CP)
  store_LCPG    <- .init_vec_store(RUN_LCP_G)
  store_LCPK    <- .init_vec_store(RUN_LCP_K)
  store_LWCI    <- .init_vec_store(RUN_LWCI)
  store_WCP     <- .init_vec_store(RUN_WCP)
  store_DNCP    <- .init_vec_store(RUN_DNCP)
  store_DNCPmini <- .init_vec_store(RUN_DNCP_MINI)
  store_ACPI    <- .init_vec_store(RUN_ACPI)
  
  seed_hist_target <- integer(0)
  
  .append_target <- function(store, corr, len, lower, upper) {
    if (is.null(store)) return(store)
    store$correct <- c(store$correct, as.integer(corr))
    store$length  <- c(store$length,  as.numeric(len))
    store$seed <- c(store$seed, ss)
    store$lower <- c(store$lower, lower)
    store$upper <- c(store$upper, upper)
    store
  }
  
  
  cat("\n==================== seeds 485-974 | target sample 337 ====================\n")
  
  for (ss in seeds_all) {
    set.seed(ss)
    
    n <- nrow(x_all)
    idx <- sample.int(n)
    n_train <- floor(0.4 * n)
    n_cal   <- floor(0.4 * n)
    
    train_id <- idx[1:n_train]
    cal_id   <- idx[(n_train + 1):(n_train + n_cal)]
    test_id  <- idx[(n_train + n_cal + 1):n]
    
    drpi_split("case337", ss, train_id, cal_id, test_id)
    if (!(target_id %in% test_id)) { drpi_event("case337", ss, "not_in_test"); next }
    
    x_tr <- x_all[train_id, , drop = FALSE]; y_tr <- y_all[train_id]
    x_ca <- x_all[cal_id,   , drop = FALSE]; y_ca <- y_all[cal_id]
    x_te <- x_all[test_id,  , drop = FALSE]; y_te <- y_all[test_id]
    
    tr_keep <- which(is.finite(y_tr))
    ca_keep <- which(is.finite(y_ca))
    te_keep <- which(is.finite(y_te))
    if (length(tr_keep) < 5 || length(ca_keep) < 5 || length(te_keep) < 5) next
    
    x_tr <- x_tr[tr_keep,,drop=FALSE]; y_tr <- y_tr[tr_keep]
    x_ca <- x_ca[ca_keep,,drop=FALSE]; y_ca <- y_ca[ca_keep]
    x_te <- x_te[te_keep,,drop=FALSE]; y_te <- y_te[te_keep]
    
    test_id_kept <- test_id[te_keep]
    
    pos <- match(target_id, test_id_kept)
    if (is.na(pos)) next
    
    seed_hist_target <- c(seed_hist_target, ss)
    
    need_yhat <- any(c(RUN_SPLIT_CP, RUN_LCP_G, RUN_LCP_K, RUN_LWCI, RUN_WCP, RUN_DNCP, RUN_DNCP_MINI))
    if (need_yhat) {
      yhat_ca <- fit_and_predict(base_model, x_tr, y_tr, x_ca, alpha_en, rf_ntree)
      yhat_te <- fit_and_predict(base_model, x_tr, y_tr, x_te, alpha_en, rf_ntree)
    }
    
    if (RUN_SPLIT_CP) {
      res_ca_abs <- abs(y_ca - yhat_ca)
      k_idx <- ceiling((length(res_ca_abs) + 1) * (1 - alpha_level))
      k_idx <- min(max(k_idx, 1), length(res_ca_abs))
      q_hat <- sort(res_ca_abs, partial = k_idx)[k_idx]
      lower <- yhat_te - q_hat
      upper <- yhat_te + q_hat
      lenv  <- upper - lower
      corr  <- (y_te >= lower) & (y_te <= upper)
      store_SplitCP <- .append_target(store_SplitCP, corr[pos], lenv[pos], lower[pos], upper[pos])
    }
    
    if (RUN_LCP_G) {
      abs_resid_cal <- abs(y_ca - yhat_ca)
      lower_g <- upper_g <- numeric(length(y_te))
      for (j in seq_along(y_te)) {
        dists <- .euclid_dist(x_ca, x_te[j, , drop = FALSE])
        h <- if (!is.null(lcp_bandwidth)) lcp_bandwidth else median(dists)
        Ww <- .gaussian_kernel(dists, h)
        W_test <- 1; total_weight <- sum(Ww) + W_test
        target_weight <- (1 - alpha_level) * total_weight
        ord <- order(abs_resid_cal); cumw <- cumsum(Ww[ord])
        idx_thr <- which(cumw >= target_weight)[1]; if (is.na(idx_thr)) idx_thr <- length(ord)
        Q <- abs_resid_cal[ord[idx_thr]]
        lower_g[j] <- yhat_te[j] - Q
        upper_g[j] <- yhat_te[j] + Q
      }
      lenv <- upper_g - lower_g
      corr <- (y_te >= lower_g) & (y_te <= upper_g)
      store_LCPG <- .append_target(store_LCPG, corr[pos], lenv[pos], lower_g[pos], upper_g[pos])
    }
    
    if (RUN_LCP_K) {
      abs_resid_cal <- abs(y_ca - yhat_ca)
      lower_k <- upper_k <- numeric(length(y_te))
      for (j in seq_along(y_te)) {
        dists <- .euclid_dist(x_ca, x_te[j, , drop = FALSE])
        k_val <- min(lcp_k, length(dists))
        idx_k <- order(dists)[1:k_val]
        resid_k <- sort(abs_resid_cal[idx_k])
        q_idx2 <- ceiling((length(resid_k) + 1) * (1 - alpha_level))
        q_idx2 <- min(max(q_idx2, 1), length(resid_k))
        Q <- resid_k[q_idx2]
        lower_k[j] <- yhat_te[j] - Q
        upper_k[j] <- yhat_te[j] + Q
      }
      lenv <- upper_k - lower_k
      corr <- (y_te >= lower_k) & (y_te <= upper_k)
      store_LCPK <- .append_target(store_LCPK, corr[pos], lenv[pos], lower_k[pos], upper_k[pos])
    }
    
    if (RUN_LWCI) {
      yhat_tr2 <- fit_and_predict(base_model, x_tr, y_tr, x_tr, alpha_en, rf_ntree)
      res_tr_abs <- abs(y_tr - yhat_tr2)
      scale_fit <- smooth.spline(yhat_tr2, res_tr_abs)
      scale_ca <- pmax(predict(scale_fit, yhat_ca)$y, 1e-8)
      scale_te <- pmax(predict(scale_fit, yhat_te)$y, 1e-8)
      res_ca_scaled <- abs(y_ca - yhat_ca) / scale_ca
      k_idx3 <- ceiling((length(res_ca_scaled) + 1) * (1 - alpha_level))
      k_idx3 <- min(max(k_idx3, 1), length(res_ca_scaled))
      q_scaled <- sort(res_ca_scaled, partial = k_idx3)[k_idx3]
      lower <- yhat_te - q_scaled * scale_te
      upper <- yhat_te + q_scaled * scale_te
      lenv  <- upper - lower
      corr  <- (y_te >= lower) & (y_te <= upper)
      store_LWCI <- .append_target(store_LWCI, corr[pos], lenv[pos], lower[pos], upper[pos])
    }
    
    if (RUN_WCP) {
      est_density_ratio <- function(x_cal, x_test, method = "logistic", cap = 50) {
        Xc <- as.data.frame(x_cal, check.names = FALSE); Xt <- as.data.frame(x_test, check.names = FALSE)
        Xc$.__LABEL__ <- 0; Xt$.__LABEL__ <- 1; XX <- rbind(Xc, Xt)
        ylab <- XX$.__LABEL__; XX$.__LABEL__ <- NULL
        x_mat <- model.matrix(~ . - 1, data = XX)
        cvfit <- glmnet::cv.glmnet(x_mat, ylab, family = "binomial", alpha = 0, nlambda = 100)
        p_hat <- as.numeric(predict(cvfit, newx = x_mat, s = "lambda.min", type = "response"))
        pi_test <- mean(ylab == 1)
        odds <- p_hat / pmax(1 - p_hat, 1e-8)
        ratio <- odds * ((1 - pi_test) / pmax(pi_test, 1e-8))
        r_cal <- ratio[1:nrow(x_cal)]
        r_test <- ratio[(nrow(x_cal)+1):(nrow(x_cal)+nrow(x_test))]
        r_cal <- pmin(r_cal, cap); r_test <- pmin(r_test, cap)
        list(r_cal = r_cal, r_test = r_test)
      }
      res_ca_abs <- abs(y_ca - yhat_ca)
      dr <- est_density_ratio(x_ca, x_te, method = wcp_method, cap = wcp_cap_ratio)
      o <- order(res_ca_abs); r_sorted <- res_ca_abs[o]; w_sorted <- dr$r_cal[o]
      lower <- upper <- numeric(length(y_te))
      for (i2 in seq_along(y_te)) {
        q_w <- weighted_quantile(c(r_sorted, Inf), 1 - alpha_level,
                                 w = c(w_sorted, dr$r_test[i2]), sorted = TRUE)
        lower[i2] <- yhat_te[i2] - q_w
        upper[i2] <- yhat_te[i2] + q_w
      }
      lenv <- upper - lower
      corr <- (y_te >= lower) & (y_te <= upper)
      store_WCP <- .append_target(store_WCP, corr[pos], lenv[pos], lower[pos], upper[pos])
    }
    
    if (RUN_DNCP) {
      res_ca_signed <- y_ca - yhat_ca
      df_x_ca <- as.data.frame(x_ca, check.names = FALSE)
      df_ca_resid <- data.frame(resid = res_ca_signed, df_x_ca, check.names = FALSE)
      df_ca_resid_f <- df_ca_resid
      
      ncal_f <- nrow(df_ca_resid_f)
      ctrl <- disttree_control(minsplit = max(20,floor(0.2 * ncal_f)),
                               minbucket = max(10,floor(0.2 * ncal_f)),
                               mincriterion = 0.9)
      set.seed(ss)
      fam <- .get_family(dncp_family_active)
      param_names <- .get_param_names(dncp_family_active)
      qFUN <- .get_qfun(dncp_family_active)
      
      df_resid_model <- distforest(resid ~ ., data = df_ca_resid_f,
                                   family = fam, ntree = dncp_ntree,
                                   control = ctrl, trace = FALSE)
      
      df_x_te <- as.data.frame(x_te, check.names = FALSE)
      par_te <- to_df_safe(predict(df_resid_model, newdata = df_x_te, type = "parameter"))
      par_te <- par_te[, param_names, drop = FALSE]
      par_te <- as.data.frame(lapply(par_te, function(z) to_numeric_vector(z, nrow(par_te))))
      if ("sigma" %in% names(par_te)) par_te$sigma <- pmax(par_te$sigma, 1e-6)
      if ("tau"   %in% names(par_te)) par_te$tau   <- pmax(par_te$tau,   1e-6)
      
      pL <- alpha_level / k_tail
      pU <- 1 - alpha_level / k_tail
      qL <- vapply(seq_len(nrow(par_te)), function(ii) do.call(qFUN, c(list(p = pL), as.list(par_te[ii,,drop=FALSE]))), numeric(1))
      qU <- vapply(seq_len(nrow(par_te)), function(ii) do.call(qFUN, c(list(p = pU), as.list(par_te[ii,,drop=FALSE]))), numeric(1))
      mu_resid <- par_te$mu
      y_center <- yhat_te + mu_resid
      lower <- y_center + (qL - mu_resid)
      upper <- y_center + (qU - mu_resid)
      
      lenv <- upper - lower
      corr <- (y_te >= lower) & (y_te <= upper)
      store_DNCP <- .append_target(store_DNCP, corr[pos], lenv[pos], lower[pos], upper[pos])
    }
    
    
    if (RUN_DNCP_MINI) {
      dncpmini_res <- .run_dncpmini(
        x_ca    = x_ca, y_ca = y_ca,
        x_te    = x_te, y_te = y_te,
        yhat_ca = yhat_ca, yhat_te = yhat_te,
        alpha   = alpha_level, k_tail = k_tail,
        lambda  = dncpmini_lambda,
        family  = dncpmini_family_active,
        seed    = ss
      )
      lower <- as.numeric(dncpmini_res$lower)
      upper <- as.numeric(dncpmini_res$upper)
      lenv  <- upper - lower
      corr  <- (y_te >= lower) & (y_te <= upper)
      store_DNCPmini <- .append_target(store_DNCPmini, corr[pos], lenv[pos], lower[pos], upper[pos])
    }
    
    
    if (RUN_ACPI) {
      acpi <- .run_acpi(
        base_model = base_model,
        x_tr = x_tr, y_tr = y_tr, x_cal = x_ca, y_cal = y_ca, x_te = x_te, y_te = y_te,
        alpha = alpha_level, seed = ss,
        alpha_en = alpha_en, rf_ntree = rf_ntree,
        qrf_nodesize = acpi_nodesize, steps = acpi_scan_steps
      )
      lower <- as.numeric(acpi$lower)
      upper <- as.numeric(acpi$upper)
      lenv  <- upper - lower
      corr  <- (y_te >= lower) & (y_te <= upper)
      store_ACPI <- .append_target(store_ACPI, corr[pos], lenv[pos], lower[pos], upper[pos])
    }
    
  }
  
  cat(sprintf("Target sample %d appeared in test %d times within seeds %d..%d\n",
              target_id, length(seed_hist_target), min(seeds_all), max(seeds_all)))
  if (length(seed_hist_target) > 0) {
    cat("Seeds where target appeared in test (kept):\n")
    print(seed_hist_target)
  }
  
  .summ_one <- function(store) {
    if (is.null(store)) return(c(freq = NA_real_, varlen = NA_real_))
    if (length(store$correct) == 0) return(c(freq = NA_real_, varlen = NA_real_))
    if (any(is.na(store$correct)) || any(is.na(store$length))) {
      return(c(freq = NA_real_, varlen = NA_real_))
    }
    c(freq = mean(as.numeric(store$correct)),
      varlen = stats::var(as.numeric(store$length)))
  }
  
  out_one <- data.frame(
    Algorithm = character(0),
    Correct_Frequency = numeric(0),
    Repetitions = integer(0),
    Var_Length = numeric(0),
    stringsAsFactors = FALSE
  )
  
  add_row <- function(enabled, name, store) {
    if (!enabled) return(invisible(NULL))
    s <- .summ_one(store)
    drpi_write_csv(data.frame(Seed=store$seed, RowID=target_id, Response=y_all[target_id],
      Covered=store$correct, Lower=store$lower, Upper=store$upper, Length=store$length),
      file.path(export_root3, paste0(name, "_replicates.csv")))
    out_one <<- rbind(out_one, data.frame(
      Algorithm = name,
      Correct_Frequency = s["freq"],
      Repetitions = length(store$correct),
      Var_Length = s["varlen"],
      stringsAsFactors = FALSE
    ))
  }
  
  add_row(RUN_SPLIT_CP, "SplitCP",      store_SplitCP)
  add_row(RUN_LCP_G,    "LCP_Gaussian", store_LCPG)
  add_row(RUN_LCP_K,    "LCP_kNN",      store_LCPK)
  add_row(RUN_LWCI,     "LWCI",         store_LWCI)
  add_row(RUN_WCP,      "WCP",          store_WCP)
  add_row(RUN_ACPI,     "ACPI",         store_ACPI)
  add_row(RUN_DNCP,       "DNCP",        store_DNCP)
  add_row(RUN_DNCP_MINI,  "DNCP-mini",   store_DNCPmini)
  
  cat("\n==================== Summary for sample_id=337 ====================\n")
  print(out_one, row.names = FALSE)
  
  out_fn <- file.path(export_root3, paste0("Diabetes_", base_model, "_seed", case_seed_start, "_", case_seed_end, "_sample", target_id, "_freq_var.csv"))
  write.csv(out_one, out_fn, row.names = FALSE, fileEncoding = "UTF-8")
  cat(sprintf("\nSaved: %s\n", out_fn))
}

if (stage == "case337") {
  actual_count <- length(seed_hist_target)
  drpi_event("case337", status = if (actual_count == case_expected_count) "count_verified" else "count_mismatch",
    detail = sprintf("expected=%d actual=%d", case_expected_count, actual_count))
  if (actual_count != case_expected_count) stop("Case repetition count differs from the paper; raw results retained for inspection.")
}

}
drpi_logged(.drpi_main, .entry_path)
