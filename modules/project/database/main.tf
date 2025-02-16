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

data "google_project" "_" {
  project_id = var.project_id
}

data "google_container_cluster" "_" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.cluster_location
}

locals {
  password_length       = 16
  initial_database_user = "root"

  // Create the federated workload identity principal bound to the
  // `${var.kubernetes_default_namespace}/${var.kubernetes_default_service_account}` Kubernetes service account.
  workload_identity_principal = join("",
    [
      "principal://iam.googleapis.com/projects/${data.google_project._.number}/",
      "locations/global/workloadIdentityPools/",
      "${data.google_container_cluster._.workload_identity_config[0].workload_pool}/subject/",
      "ns/${var.kubernetes_default_namespace}/",
      "sa/${var.kubernetes_default_service_account}",
    ]
  )
}

resource "google_sql_database_instance" "_" {
  project          = data.google_project._.project_id
  name             = "default"
  database_version = "POSTGRES_17"
  region           = local.default_region

  settings {
    edition = "ENTERPRISE"
    tier    = "db-g1-small"

    maintenance_window {
      day          = 1
      hour         = 1
      update_track = "canary"
    }

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network_self_link
      enable_private_path_for_google_cloud_services = true
      // Munge our way to the name assigned by the foundation network stage.
      allocated_ip_range = "ga-${regex(
        "\\Avpc\\-(?P<base_name>.*)\\z", local.network_name
      )["base_name"]}-vpc-peering-internal"
    }
  }
}

resource "random_password" "database_password" {
  length = local.password_length
}

resource "google_secret_manager_secret" "database_password" {
  project   = local.environment_secrets_project
  secret_id = "database_password"

  replication {
    auto {
    }
  }
}

resource "google_secret_manager_secret_version" "database_password" {
  secret      = google_secret_manager_secret.database_password.id
  secret_data = random_password.database_password.result
}

resource "google_sql_user" "initial_user" {
  project  = data.google_project._.project_id
  name     = local.initial_database_user
  instance = google_sql_database_instance._.name
  password = random_password.database_password.result
}

// Give pods access to Cloud SQL through the cluster's Workload Identity principal.
resource "google_project_iam_member" "main_project_workload_identity_principal" {
  project = data.google_project._.project_id
  member  = local.workload_identity_principal
  role    = "roles/cloudsql.client"
}
