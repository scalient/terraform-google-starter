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

// See https://cloud.google.com/iam/docs/service-agents to understand why we're doing the stuff below.

// Share the `network` foundation stage's VPC with the base project.
resource "google_compute_shared_vpc_service_project" "_" {
  host_project    = local.network_project
  service_project = module.project.project_id
}

// Allow the base project's GKE service agent to operate on the project hosting the shared VPC.
resource "google_project_iam_member" "network_project_container_host_service_agent_user" {
  project = local.network_project
  member  = "serviceAccount:${google_project_service_identity.gke_service_agent.email}"
  role    = "roles/container.hostServiceAgentUser"
}

// Provide access to the host project's shared VPC.
resource "google_project_iam_member" "network_project_compute_network_user" {
  for_each = toset([
    "serviceAccount:${google_project_service_identity.gke_service_agent.email}",
    "serviceAccount:${module.project.project_number}@cloudservices.gserviceaccount.com",
    "serviceAccount:${module.project.service_account_email}",
  ])
  project = local.network_project
  member  = each.key
  role    = "roles/compute.networkUser"
}

// Provide access to the host project's firewall rules.
resource "google_project_iam_member" "network_project_compute_security_admin" {
  project = local.network_project
  member  = "serviceAccount:${google_project_service_identity.gke_service_agent.email}"
  role    = "roles/compute.securityAdmin"
}
