terraform {
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}

module "prerequisites" {
  source = "./modules/prerequisites"

  administration_project_name = var.administration_project_name
  project_prefix              = var.project_prefix
  billing_account             = var.billing_account
  org_id                      = var.org_id
}

# An example. We advise you to use a separate file to fill these in.
#
# locals {
#   environments = []
# }
#
# module "common" {
#   source              = "./modules/common"
#   remote_state_bucket = var.remote_state_bucket
# }
#
# module "projects" {
#   for_each = toset(local.environments)
#   source                    = "./modules/project"
#   env                       = each.key
#   remote_state_bucket       = var.remote_state_bucket
#   administration_project_id = module.prerequisites.administration_project_id
# }
