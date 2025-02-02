terraform {
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}

locals {
  // TODO: Fill this in to activate various environments.
  environments = []
}

module "prerequisites" {
  source = "./modules/prerequisites"

  administration_project_name = var.administration_project_name
  project_prefix              = var.project_prefix
  billing_account             = var.billing_account
  org_id                      = var.org_id
}

// Modify the environment-specific project base module below.

module "projects" {
  for_each = toset(local.environments)
  source              = "./modules/project_base"
  env                 = each.key
  remote_state_bucket = var.remote_state_bucket
}
