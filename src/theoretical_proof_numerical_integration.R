# Rscript entry; sourcing run_records.R alone does not execute experiments.
.entry_args <- commandArgs(FALSE)
.entry_file <- .entry_args[startsWith(.entry_args, "--file=")]
if (!length(.entry_file)) stop("Use Rscript to run this file.")
.entry_path <- normalizePath(sub("^--file=", "", .entry_file[1]), winslash = "/", mustWork = TRUE)
source(file.path(dirname(.entry_path), "run_records.R"))
.drpi_main <- function() {
  script_dir <- dirname(.entry_path)
# =========================================
# Variance of interval lengths: split conformal vs MLE quantile
# Assumption: calibration residuals R_i are i.i.d. N(0, sigma^2)
# Standard SCP uses k = ceil((n + 1)(1 - alpha))
# Numerical integration is performed with stats::integrate()
#   - globally adaptive subdivision with Gauss-Kronrod quadrature
#   - Wynn's epsilon extrapolation
#   - based on QUADPACK dqags/dqagi (see ?integrate)
# =========================================

var_L_MLE <- function(n, alpha, sigma = 1) {
  # L_MLE = 2 z_{1-a/2} * tau_hat, where tau_hat^2 = (1/n) sum (R_i - Rbar)^2
  if (n < 2) stop("n must be >= 2.")
  if (!(alpha > 0 && alpha < 1)) stop("alpha must be in (0,1).")
  
  nu <- n - 1
  z  <- qnorm(1 - alpha/2)
  c  <- 2 * z
  
  # Variance of Chi_nu: nu - 2*(Gamma((nu+1)/2)/Gamma(nu/2))^2
  log_ratio <- lgamma((nu + 1)/2) - lgamma(nu/2)
  ratio <- exp(log_ratio)
  var_chi <- nu - 2 * (ratio^2)
  
  (c^2 * sigma^2 / n) * var_chi
}

var_L_SCP <- function(n, alpha, sigma = 1,
                      rel.tol = 1e-10, abs.tol = 0, subdivisions = 200) {
  # L_SCP = 2 S_(k), where S_i = |R_i| is half-normal and k = ceil((n + 1)(1 - alpha))
  if (n < 1) stop("n must be >= 1.")
  if (!(alpha > 0 && alpha < 1)) stop("alpha must be in (0,1).")
  
  k <- ceiling((n + 1) * (1 - alpha))
  k <- max(1, min(n, k))  # safety clipping
  
  a <- k
  b <- n - k + 1
  
  g <- function(u) qnorm((u + 1) / 2)  # g(u)=Phi^{-1}((u+1)/2)
  
  # E[g(U)] and E[g(U)^2] for U ~ Beta(a, b)
  integrand1 <- function(u) g(u) * dbeta(u, a, b)
  integrand2 <- function(u) (g(u)^2) * dbeta(u, a, b)
  
  # NOTE: These terms generally have no simple closed form, so numerical integration is required.
  Eg  <- integrate(integrand1, lower = 0, upper = 1,
                   rel.tol = rel.tol, abs.tol = abs.tol,
                   subdivisions = subdivisions)$value
  
  Eg2 <- integrate(integrand2, lower = 0, upper = 1,
                   rel.tol = rel.tol, abs.tol = abs.tol,
                   subdivisions = subdivisions)$value
  
  var_g <- Eg2 - Eg^2
  var_Sk <- sigma^2 * var_g
  var_L  <- 4 * var_Sk
  
  list(var_L_SCP = var_L, k = k, Eg = Eg, Eg2 = Eg2)
}

compare_variances <- function(n, alpha, sigma = 1,
                              rel.tol = 1e-10, abs.tol = 0, subdivisions = 200) {
  
  v_mle <- var_L_MLE(n, alpha, sigma)
  
  scp <- var_L_SCP(n, alpha, sigma,
                   rel.tol = rel.tol, abs.tol = abs.tol, subdivisions = subdivisions)
  v_scp <- scp$var_L_SCP
  
  ratio <- v_scp / v_mle
  comp <- if (ratio > 1) "Var(L_SCP) > Var(L_MLE)" else if (ratio < 1) "Var(L_SCP) < Var(L_MLE)" else "Equal"
  
  list(
    n = n,
    alpha = alpha,
    k = scp$k,
    Var_L_MLE = v_mle,
    Var_L_SCP = v_scp,
    Ratio_VarSCP_over_VarMLE = ratio,
    Comparison = comp,
    Integration = list(method = "stats::integrate (QUADPACK dqags; adaptive Gauss–Kronrod + Wynn epsilon)",
                       rel.tol = rel.tol, abs.tol = abs.tol, subdivisions = subdivisions)
  )
}


if ("--help" %in% commandArgs(TRUE)) {
  cat("--mode=table|single --n=10 --alpha=0.05 --subdivisions=1000 --export-root=PATH --runs-root=PATH\n")
  return(invisible(NULL))
}
mode <- drpi_cli("mode", "table")
if (!mode %in% c("table", "single")) stop("Unknown mode.")
ns <- if(mode=="table") c(50,100,500,1000,2000,5000,10000,50000,100000) else as.integer(drpi_cli("n",10))
alphas <- if(mode=="table") c(0.2,0.1,0.05) else as.numeric(drpi_cli("alpha",0.05))
subdivisions <- as.integer(drpi_cli("subdivisions",1000))
out_dir <- drpi_cli("export-root",file.path(.drpi_record$dir,"results"))
.drpi_record$output_roots <- out_dir
drpi_config(list(mode=mode,n=ns,alpha=alphas,subdivisions=subdivisions,scale="estimated mean MLE; df=n-1"))
values <- do.call(rbind,lapply(ns,function(n) do.call(rbind,lapply(alphas,function(a) {
  res <- compare_variances(n,a,subdivisions=subdivisions)
  drpi_event("theory",status="cell_complete",detail=paste("n",n,"alpha",a))
  data.frame(N=n,Alpha=a,Order=res$k,VarMLE=res$Var_L_MLE,
    VarSCP=res$Var_L_SCP,Ratio=res$Ratio_VarSCP_over_VarMLE)
}))))
drpi_write_csv(values,file.path(out_dir,"gaussian_variance_ratios.csv"))
print(values)

}
drpi_logged(.drpi_main, .entry_path)
