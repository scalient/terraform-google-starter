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

// TODO: Is it best practice to just copy variables from their respective modules' `variables.tf`s?

// Something we introduce as the very first project from which terraform-example-foundation stages are bootstrapped.
variable "administration_project_name" {
  description = "The name of the administration project from which foundation stages are bootstrapped."
  type        = string
}

variable "org_id" {
  description = "GCP Organization ID"
  type        = string
}

variable "billing_account" {
  description = "The ID of the billing account to associate projects with."
  type        = string
}

variable "groups" {
  description = "Contain the details of the Groups to be created."
  type = object({
    create_required_groups = optional(bool, false)
    create_optional_groups = optional(bool, false)
    billing_project        = optional(string, null)
    required_groups = object({
      group_org_admins     = string
      group_billing_admins = string
      billing_data_users   = string
      audit_data_users     = string
    })
    optional_groups = optional(object({
      gcp_security_reviewer    = optional(string, "")
      gcp_network_viewer       = optional(string, "")
      gcp_scc_admin            = optional(string, "")
      gcp_global_secrets_admin = optional(string, "")
      gcp_kms_admin            = optional(string, "")
    }), {})
  })
}

// Declare these to suppress warning messages. Scalient's own modules don't use these.

// Stage 0: bootstrap.
variable "default_region" {}
variable "default_region_2" {}
variable "default_region_gcs" {}
variable "default_region_kms" {}
variable "project_prefix" {}
variable "folder_prefix" {}
variable "bucket_prefix" {}
// Autogenerated by the run itself, to be read by later stages.
variable "remote_state_bucket" {
  default = null
}

// Stage 1: org.
variable "domains_to_allow" {}
variable "scc_notification_name" {}
variable "essential_contacts_domains_to_allow" {}
variable "log_export_storage_location" {}
variable "billing_export_dataset_location" {}
// Autogenerated by the run itself, to be read by later stages.
variable "access_context_manager_policy_id" {
  default = null
}

// Stage 3: networks-dual-svpc.
variable "domain" {}
variable "perimeter_additional_members" {}
variable "target_name_server_addresses" {}
