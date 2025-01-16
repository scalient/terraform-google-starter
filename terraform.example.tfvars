/**
 * Copyright 2023 Google LLC
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

// Modified by Scalient as a consolidated variable definitions file for all stages.

// From stage 0: bootstrap.

org_id = "REPLACE_ME" # format "000000000000"

billing_account = "REPLACE_ME" # format "000000-000000-000000"

// Something we introduce to be used below by something like `groups.billing_project`.
administration_project_name = "administration"

groups = {
  create_required_groups = true
  // Commented out. Provided dynamically.
  // billing_project     = "administration-0000"
  required_groups = {
    group_org_admins     = "admins@example.com"
    group_billing_admins = "billing-admins@example.com"
    billing_data_users   = "billing-data@example.com"
    audit_data_users     = "audit-data@example.com"
  }
}

default_region     = "us-central1"
default_region_2   = "us-east1"
default_region_gcs = "US"
default_region_kms = "us"
folder_prefix      = "fldr"
project_prefix     = "prj"
bucket_prefix      = "bkt"
