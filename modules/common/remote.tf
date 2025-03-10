/**
 * Copyright 2025 Scalient LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  org_id                       = data.terraform_remote_state.bootstrap.outputs.common_config.org_id
  billing_account              = data.terraform_remote_state.bootstrap.outputs.common_config.billing_account
  default_region               = data.terraform_remote_state.bootstrap.outputs.common_config.default_region
  project_prefix               = data.terraform_remote_state.bootstrap.outputs.common_config.project_prefix
  folder_prefix                = data.terraform_remote_state.bootstrap.outputs.common_config.folder_prefix
  common_folder                = data.terraform_remote_state.organization.outputs.common_folder_name
  dns_hub_project              = data.terraform_remote_state.organization.outputs.dns_hub_project_id
  organization_secrets_project = data.terraform_remote_state.organization.outputs.org_secrets_project_id
}

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"

  config = {
    bucket = var.remote_state_bucket
    prefix = "terraform/bootstrap/state"
  }
}

data "terraform_remote_state" "organization" {
  backend = "gcs"

  config = {
    bucket = var.remote_state_bucket
    prefix = "terraform/org/state"
  }
}
