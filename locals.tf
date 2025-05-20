# locals.tf
locals {
  # Mark as sensitive so it’s redacted in CLI output & state diff
  pull_secret = sensitive(trimspace(file("${path.module}/pull-secret.txt")))
}
