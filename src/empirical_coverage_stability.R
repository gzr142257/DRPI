# Rscript entry; sourcing run_records.R alone does not execute experiments.
.entry_args <- commandArgs(FALSE)
.entry_file <- .entry_args[startsWith(.entry_args, "--file=")]
if (!length(.entry_file)) stop("Use Rscript to run this file.")
.entry_path <- normalizePath(sub("^--file=", "", .entry_file[1]), winslash = "/", mustWork = TRUE)
source(file.path(dirname(.entry_path), "run_records.R"))
.drpi_main <- function() {
  script_dir <- dirname(.entry_path)
## =========================================================
##   Universal-style Toy experiment (Version B) - FIXED
##   G-DRPI only (Global JSU), fixed training set once
##
##   Output: CSV table skeleton same as your figure, but
##           each cell is tau_hat(G-DRPI) instead of n.
## =========================================================

## ------------------------- Configuration -------------------------
n_train <- 10000
n_test  <- 300000
seed_max <- 1000

k_tail <- 2


g_drpi_vi_steps <- 500

if ("--help" %in% commandArgs(TRUE)) {
  cat("--mode=experiment|reference --seed-max=1000 --n-train=10000 --n-test=300000 --cells=1,2,...,48 --export-root=PATH --runs-root=PATH\n")
  return(invisible(NULL))
}
mode <- drpi_cli("mode", "experiment")
if (!mode %in% c("experiment", "reference")) stop("Unknown mode.")
n_train <- as.integer(drpi_cli("n-train", n_train))
n_test <- as.integer(drpi_cli("n-test", n_test))
seed_max <- as.integer(drpi_cli("seed-max", seed_max))
selected_cells <- as.integer(strsplit(drpi_cli("cells", paste(seq_len(48), collapse=",")), ",", fixed=TRUE)[[1]])
if (!length(selected_cells) || anyNA(selected_cells) || any(!selected_cells %in% seq_len(48)) || anyDuplicated(selected_cells)) stop("cells must be distinct integers from 1 to 48.")
if (any(!is.finite(c(n_train,n_test,seed_max))) || min(n_train,n_test,seed_max)<1) stop("Invalid sample sizes.")
out_dir <- drpi_cli("export-root", file.path(.drpi_record$dir, "results"))
out_csv <- file.path(out_dir, "G-DRPI_tau_table.csv")
.drpi_record$output_roots <- out_dir
drpi_config(list(mode=mode,n_train=n_train,n_test=n_test,seed_max=seed_max,training_seed=20260127,lambda=0.5,cells=selected_cells))

p <- 5

cat("Fixed training once: n_train =", n_train, "\n")
cat("Per replicate: n_cal from table; n_test =", n_test, "\n")
cat("seed_max =", seed_max, " (replicates per cell)\n\n")

if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Use stable key formatting to avoid lookup failures caused by floating-point string differences such as as.character(0.005).
key_alpha <- function(a) sprintf("%.2f", as.numeric(a))

key_eps <- function(e) {
  e <- as.numeric(e)
  if (isTRUE(all.equal(e, 0.1)))   return("0.1")
  if (isTRUE(all.equal(e, 0.05)))  return("0.05")
  if (isTRUE(all.equal(e, 0.01)))  return("0.01")
  if (isTRUE(all.equal(e, 0.005))) return("0.005")
  stop(sprintf("Unknown epsilon value: %s", as.character(e)))
}

alpha_grid <- c(0.20, 0.15, 0.10, 0.05)
one_minus_alpha_labels <- c("80%", "85%", "90%", "95%")

epsilon_grid <- c(0.1, 0.05, 0.01, 0.005)
tau_targets <- c(0.90, 0.95, 0.99)

# Store entries with stable keys.
n_cal_table <- list(
  "0.20" = list(
    "0.1"   = c(40,   57,   98),
    "0.05"  = c(170,  241,  418),
    "0.01"  = c(4326, 6142, 10611),
    "0.005" = c(17314,24581,42457)
  ),
  "0.15" = list(
    "0.1"   = c(30,   42,   77),
    "0.05"  = c(134,  189,  330),
    "0.01"  = c(3446, 4893, 8451),
    "0.005" = c(13794,19587,33830)
  ),
  "0.10" = list(
    "0.1"   = c(11,   14,   47),
    "0.05"  = c(90,   128,  227),
    "0.01"  = c(2429, 3448, 5958),
    "0.005" = c(9733, 13821,23875)
  ),
  "0.05" = list(
    "0.1"   = c(19,   19,   29),
    "0.05"  = c(22,   29,   97),
    "0.01"  = c(1270, 1806, 3132),
    "0.005" = c(5125, 7278, 12578)
  )
)


reference <- do.call(rbind, lapply(seq_along(alpha_grid), function(ai) {
  a <- alpha_grid[ai]
  do.call(rbind, lapply(seq_along(epsilon_grid), function(ei) {
    e <- epsilon_grid[ei]
    n <- n_cal_table[[key_alpha(a)]][[key_eps(e)]]
    k <- ceiling((n+1)*(1-a))
    probability <- pbeta(min(1,1-a+e), k, n+1-k) - pbeta(max(0,1-a-e), k, n+1-k)
    data.frame(Alpha=a,Epsilon=e,TargetTau=tau_targets,NCalibration=n,Order=k,ExactSCTau=probability)
  }))
}))
drpi_write_csv(reference, file.path(out_dir, "SC_reference_table1.csv"))
# The reference PDF is optional documentation, not an input to the calculation.
reference_pdf <- file.path(dirname(script_dir), "Real Data", "Universal distribution of the empirical coverage in split conformal prediction.pdf")
if (file.exists(reference_pdf)) drpi_inputs(reference_pdf)
if (mode == "reference") return(invisible(reference))
## -------------------------- Dependencies -------------------------
need_pkg <- c("gamlss.dist")
for (pkg in need_pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg)
}
library(gamlss.dist)

## -------------------- Key Utilities (robust formatting) -------------------
## -------------------- Frozen Linear Model (fast prediction) -------------------
fit_frozen_lm <- function(X_tr, y_tr) {
  df_tr <- data.frame(y = y_tr, X_tr)
  lm_fit <- lm(y ~ ., data = df_tr)
  co <- coef(lm_fit)
  pred_fun <- function(X_new) as.numeric(co[1] + X_new %*% co[-1])
  list(coef = co, predict = pred_fun, lm_fit = lm_fit)
}

## -------------------- G-DRPI: Global JSU Fit -------------------
fit_jsu_global <- function(resid_vec, n_penalty, maxit = g_drpi_vi_steps) {
  resid <- as.numeric(resid_vec)
  resid <- resid[is.finite(resid)]
  n <- length(resid)
  
  if (!is.finite(n_penalty) || n_penalty <= 0) n_penalty <- n
  
  if (n < 5) {
    mu_r <- mean(resid)
    sigma_r <- sd(resid)
    if (!is.finite(sigma_r) || sigma_r <= 0) sigma_r <- 1
    return(list(mu = mu_r, sigma = sigma_r, nu = 0, tau = 1, converged = FALSE))
  }
  
  mu0 <- median(resid, na.rm = TRUE)
  sigma0 <- IQR(resid, na.rm = TRUE) / 1.349
  if (!is.finite(sigma0) || sigma0 <= 0) sigma0 <- sd(resid, na.rm = TRUE)
  if (!is.finite(sigma0) || sigma0 <= 0) sigma0 <- 1
  
  theta0 <- c(mu0, log(sigma0), 0, log(1))
  
  neg_logpost <- function(theta) {
    mu  <- theta[1]
    sig <- exp(theta[2])
    nu  <- theta[3]
    tau <- exp(theta[4])
    if (!is.finite(sig) || sig <= 0 || !is.finite(tau) || tau <= 0) return(1e12)
    
    ll <- try(sum(log(gamlss.dist::dJSUo(resid, mu = mu, sigma = sig, nu = nu, tau = tau))), silent = TRUE)
    if (inherits(ll, "try-error") || !is.finite(ll)) ll <- -1e10
    
    prior <- -0.5 * ((nu^2)/n_penalty + (theta[4]^2)/n_penalty)
    -(ll + prior)
  }
  
  opt <- try(optim(theta0, neg_logpost, method = "BFGS",
                   control = list(maxit = maxit)), silent = TRUE)
  
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
  
  list(mu = mu_r, sigma = sigma_r, nu = nu_r, tau = tau_r, converged = (opt$convergence == 0))
}

## -------------------- G-DRPI Single Run: Return Coverage -------------------
run_g_drpi_once <- function(pred_fun, n_cal, n_test, alpha,
                               k_tail = 2) {
  
  n_cal <- as.integer(n_cal)
  if (!is.finite(n_cal) || n_cal <= 0) stop(sprintf("n_cal invalid: %s", as.character(n_cal)))
  n_test <- as.integer(n_test)
  if (!is.finite(n_test) || n_test <= 0) stop(sprintf("n_test invalid: %s", as.character(n_test)))
  
  # calibration
  X_cal <- matrix(runif(n_cal * p, 0, 1), nrow = n_cal, ncol = p)
  colnames(X_cal) <- paste0("x", 1:p)
  eps_cal <- rnorm(n_cal, 0, 1)
  y_cal <- X_cal[,1] + 0.5 * X_cal[,2] + 0.2 * X_cal[,3] + eps_cal
  
  # test
  X_te <- matrix(runif(n_test * p, 0, 1), nrow = n_test, ncol = p)
  colnames(X_te) <- paste0("x", 1:p)
  eps_te <- rnorm(n_test, 0, 1)
  y_te <- X_te[,1] + 0.5 * X_te[,2] + 0.2 * X_te[,3] + eps_te
  
  # frozen predictions
  yhat_cal <- pred_fun(X_cal)
  yhat_te  <- pred_fun(X_te)
  
  # cal residuals
  resid_cal <- as.numeric(y_cal - yhat_cal)
  n_cal_orig <- length(resid_cal)
  
  
  resid_cal_f <- resid_cal
  
  # global JSU fit
  jsu <- fit_jsu_global(resid_cal_f, n_penalty = n_cal_orig, maxit = g_drpi_vi_steps)
  mu_r <- jsu$mu; sigma_r <- jsu$sigma; nu_r <- jsu$nu; tau_r <- jsu$tau
  
  # base resid quantiles (keep your original closed-form JSU quantile formula)
  pL <- alpha / k_tail
  pU <- 1 - alpha / k_tail
  zL <- qnorm(pL)
  zU <- qnorm(pU)
  qL_resid <- mu_r + sigma_r * sinh((zL - nu_r) / tau_r)
  qU_resid <- mu_r + sigma_r * sinh((zU - nu_r) / tau_r)
  
  # conformal slack on calibration
  L0_cal <- yhat_cal + qL_resid
  U0_cal <- yhat_cal + qU_resid
  scores <- pmax(L0_cal - y_cal, y_cal - U0_cal, 0)
  
  k_idx <- ceiling((length(scores) + 1) * (1 - alpha))
  k_idx <- min(max(k_idx, 1), length(scores))
  s_star <- 0.5 * sort(scores, partial = k_idx)[k_idx]
  
  # apply to test
  lower <- yhat_te + qL_resid - s_star
  upper <- yhat_te + qU_resid + s_star
  
  mean(y_te >= lower & y_te <= upper)
}

## =========================================================
## (1) Freeze the training set once (Version B)
## =========================================================
set.seed(20260127)
X_tr <- matrix(runif(n_train * p, 0, 1), nrow = n_train, ncol = p)
colnames(X_tr) <- paste0("x", 1:p)
eps_tr <- rnorm(n_train, 0, 1)
y_tr <- X_tr[,1] + 0.5 * X_tr[,2] + 0.2 * X_tr[,3] + eps_tr

frozen <- fit_frozen_lm(X_tr, y_tr)
pred_fun <- frozen$predict

cat("Frozen LM coefficients:\n")
print(frozen$coef)
cat("\n")

## =========================================================
## (2) Combination table (using the n_cal values from your figure)
## =========================================================
## =========================================================
## (3) Iterate over all 48 cells and estimate tau_hat(G-DRPI)
## =========================================================
tau_hat_array <- array(NA_real_,
                       dim = c(length(alpha_grid), length(epsilon_grid), length(tau_targets)),
                       dimnames = list(alpha = sprintf("%.2f", alpha_grid),
                                       epsilon = c("0.1","0.05","0.01","0.005"),
                                       tau = c("0.90","0.95","0.99")))

combo_id <- 0L
for (ai in seq_along(alpha_grid)) {
  alpha_level <- alpha_grid[ai]
  target_cov <- 1 - alpha_level
  a_key <- key_alpha(alpha_level)
  
  for (ei in seq_along(epsilon_grid)) {
    epsilon_tol <- epsilon_grid[ei]
    e_key <- key_eps(epsilon_tol)
    
    for (ti in seq_along(tau_targets)) {
      tau_tgt <- tau_targets[ti]
      n_cal <- n_cal_table[[a_key]][[e_key]][ti]
      n_cal <- as.integer(n_cal)
      
      combo_id <- combo_id + 1L
      if (!combo_id %in% selected_cells) next
      cat(sprintf("=== Combo %d/48: alpha=%.2f (target=%.2f), eps=%s, tau_target=%.2f, n_cal=%d ===\n",
                  combo_id, alpha_level, target_cov, e_key, tau_tgt, n_cal))
      
      cov_vec <- numeric(seed_max)
      
      for (s in 1:seed_max) {
        set.seed(1000000L * combo_id + s)
        cov_vec[s] <- run_g_drpi_once(
          pred_fun = pred_fun,
          n_cal = n_cal,
          n_test = n_test,
          alpha = alpha_level,
          k_tail = k_tail
        )
      }
      
      drpi_write_csv(data.frame(Seed=1000000L*combo_id+seq_len(seed_max),
        Alpha=alpha_level,Epsilon=epsilon_tol,TargetTau=tau_tgt,NCalibration=n_cal,
        Coverage=cov_vec,WithinTolerance=abs(cov_vec-target_cov)<=epsilon_tol),
        file.path(out_dir, sprintf("cell_%02d_replicates.csv",combo_id)))
      drpi_event("stability", status="cell_complete", detail=paste("cell",combo_id))
      tau_hat <- mean(abs(cov_vec - target_cov) <= epsilon_tol)
      tau_hat_array[ai, ei, ti] <- tau_hat
      
      cat(sprintf("  -> tau_hat(G-DRPI) = %.4f\n\n", tau_hat))
    }
  }
}

## =========================================================
## (4) Export CSV: same 6x13 layout, with tau_hat values rounded to four decimals
## =========================================================
out_mat <- matrix("", nrow = 6, ncol = 13)

# row 1
out_mat[1,1] <- "τ"
out_mat[1,2:4]   <- "ε = 0.1"
out_mat[1,5:7]   <- "ε = 0.05"
out_mat[1,8:10]  <- "ε = 0.01"
out_mat[1,11:13] <- "ε = 0.005"

# row 2
out_mat[2,1] <- "1-α"
tau_labels <- c("90%", "95%", "99%")
out_mat[2,2:4]   <- tau_labels
out_mat[2,5:7]   <- tau_labels
out_mat[2,8:10]  <- tau_labels
out_mat[2,11:13] <- tau_labels

# data rows
for (ai in seq_along(alpha_grid)) {
  out_mat[2 + ai, 1] <- one_minus_alpha_labels[ai]
  col_cursor <- 2
  for (ei in seq_along(epsilon_grid)) {
    for (ti in seq_along(tau_targets)) {
      val <- tau_hat_array[ai, ei, ti]
      out_mat[2 + ai, col_cursor] <- if (is.finite(val)) sprintf("%.4f", val) else ""
      col_cursor <- col_cursor + 1
    }
  }
}

write.table(out_mat, file = out_csv, sep = ",", row.names = FALSE, col.names = FALSE, quote = FALSE)

cat("============================================\n")
cat("Done. Output CSV saved to:\n")
cat(out_csv, "\n")
cat("============================================\n")

}
drpi_logged(.drpi_main, .entry_path)
