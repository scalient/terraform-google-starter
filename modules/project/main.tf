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
  project_unique_suffix = regex("\\-(?P<suffix>[0-9a-f]+)\\z", module.project.project_id)["suffix"]
}

module "project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.0"

  name              = "${local.project_prefix}-${var.env}"
  random_project_id = true
  org_id            = local.org_id
  billing_account   = local.billing_account
  folder_id         = local.env_folder
  activate_apis = setunion(
    var.activate_apis,
    [
      // Enable GCE so that GKE can spin up nodes.
      "compute.googleapis.com",
      // Enable GKE.
      "container.googleapis.com",
      // Enable shared VPC manipulation.
      "servicenetworking.googleapis.com",
    ],
    (var.include_database ? [
      // Needed to provision a database.
      "sql-component.googleapis.com",
      "sqladmin.googleapis.com",
    ] : []),
  )

  // Instantiate the GKE IAM service agent. This allows GKE to access things like shared VPC infrastructure. Disable
  // this convenience attribute for now because its associated resources conflict with what we're trying to do, in
  // particular how IAM roles are assigned (thrashing will occur if we independently try to assign another member to a
  // role that already has its members declared).
  // activate_api_identities = [
  //   {
  //     api = "container.googleapis.com"
  //     roles = [
  //       "roles/container.serviceAgent",
  //     ]
  //   },
  // ]

  // We're using Shared VPC as a networking scheme. This is the project that hosts it. Disable this convenience
  // attribute for the reason described above.
  // svpc_host_project_id = local.network_project
}

resource "google_project_service_identity" "gke_service_agent" {
  provider = google-beta
  project  = module.project.project_id
  service  = "container.googleapis.com"
}

resource "google_project_iam_member" "base_project_container_service_agent" {
  project = module.project.project_id
  member  = "serviceAccount:${google_project_service_identity.gke_service_agent.email}"
  role    = "roles/container.serviceAgent"
}

resource "google_project_iam_member" "_" {
  for_each = toset(
    setunion(
      var.default_service_account_iam_roles,
      // The default service account must be able to manipulate GKE nodes (see
      // https://cloud.google.com/kubernetes-engine/docs/how-to/service-accounts#default-gke-service-agent).
      [
        "roles/container.defaultNodeServiceAccount",
      ]
    )
  )

  project = module.project.project_id
  member  = "serviceAccount:${module.project.service_account_email}"
  role    = each.key
}

// Override the organization-wide policy set in the `organization` foundation stage.
resource "google_project_organization_policy" "allow_external_ips" {
  project    = module.project.project_id
  constraint = "compute.vmExternalIpAccess"

  list_policy {
    allow {
      all = true
    }
  }
}

module "database" {
  source = "./database"
  for_each = toset(var.include_database ? ["_"] : [])

  env                                = var.env
  remote_state_bucket                = var.remote_state_bucket
  project_id                         = module.project.project_id
  cluster_name                       = google_container_cluster._.name
  cluster_location                   = google_container_cluster._.location
  kubernetes_default_namespace       = var.kubernetes_default_namespace
  kubernetes_default_service_account = var.kubernetes_default_service_account
}
