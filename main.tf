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
