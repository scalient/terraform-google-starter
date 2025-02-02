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

resource "google_container_cluster" "_" {
  name                = "default"
  project             = module.project.project_id
  location            = local.default_region
  network             = local.network_self_link
  subnetwork          = local.subnetwork_self_links[0]
  initial_node_count  = 1
  enable_autopilot    = true
  deletion_protection = false

  cluster_autoscaling {
    auto_provisioning_defaults {
      // Use the project default service account that we created.
      service_account = module.project.service_account_email

      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
      ]
    }
  }

  ip_allocation_policy {
    // Some string munging to find the secondary ranges that the `network` foundation stage already created and named.
    cluster_secondary_range_name  = "rn-${regex("\\Asb-(.*)\\z", local.subnetwork_names[0])[0]}-gke-pod"
    services_secondary_range_name = "rn-${regex("\\Asb-(.*)\\z", local.subnetwork_names[0])[0]}-gke-svc"
  }

  // Private nodes for a private network.
  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes    = true
    // From a size 18 netmask (https://cloud.google.com/architecture/security-foundations/networking) to 28, as mandated
    // by the Kubernetes master network. Increment the second octet by 1, apply the `/28` netmask, and increment the
    // fourth octet by one. For example, 100.73.192.0/18 would become 100.74.192.16/28.
    master_ipv4_cidr_block = cidrsubnet(
      "${tonumber(regex(
        "\\A(.*)\\..*\\..*\\..*/.*\\z",
        local.subnetwork_secondary_range_lists[0][length(local.subnetwork_secondary_range_lists[0]) - 1].ip_cidr_range
      )[0])}.${tonumber(regex(
        "\\A.*\\.(.*)\\..*\\..*/.*\\z",
        local.subnetwork_secondary_range_lists[0][length(local.subnetwork_secondary_range_lists[0]) - 1].ip_cidr_range
      )[0]) + 1}.${tonumber(regex(
        "\\A.*\\..*\\.(.*)\\..*/.*\\z",
        local.subnetwork_secondary_range_lists[0][length(local.subnetwork_secondary_range_lists[0]) - 1].ip_cidr_range
      )[0])}.${tonumber(regex(
        "\\A.*\\..*\\..*\\.(.*)/.*\\z",
        local.subnetwork_secondary_range_lists[0][length(local.subnetwork_secondary_range_lists[0]) - 1].ip_cidr_range
      )[0])}/${tonumber(regex(
        "\\A.*\\..*\\..*\\..*/(.*)\\z",
        local.subnetwork_secondary_range_lists[0][length(local.subnetwork_secondary_range_lists[0]) - 1].ip_cidr_range
      )[0])}",
      10, 1
    )
  }

  node_pool_auto_config {
    // The NAT provisioned by the `network` foundation stage requires resources to be tagged like this.
    network_tags {
      tags = ["egress-internet"]
    }
  }

  depends_on = [
    // Make sure that the Shared VPC is already hosting, with this as the service project.
    google_compute_shared_vpc_service_project._,
    // Make sure that the GKE service agent and other service accounts have enough permissions first.
    google_project_iam_member.base_project_container_service_agent,
    google_project_iam_member.network_project_container_host_service_agent_user,
    google_project_iam_member.network_project_compute_network_user_gcp_service_agent,
    google_project_iam_member.network_project_compute_network_user_gke_service_agent,
    google_project_iam_member.network_project_compute_security_admin,
    // Allow assignment of external-facing IPs.
    google_project_organization_policy.allow_external_ips,
  ]
}
