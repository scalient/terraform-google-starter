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
  environment_code = substr(var.env, 0, 1)
}

// The Google foundation stage's policies are too restrictive. Allow all egress.
resource "google_compute_firewall" "egress_all" {
  project     = local.network_project
  name        = "fw-${local.environment_code}-shared-base-5000-e-a-all"
  network     = local.network_name
  description = "Allow all egress."
  direction   = "EGRESS"
  priority    = 5000

  allow {
    protocol = "all"
  }

  destination_ranges = [
    "0.0.0.0/0"
  ]
}

// Allow ingress to secondary CIDRs, which the Google foundation stage doesn't seem to do.
resource "google_compute_firewall" "ingress_secondary_ranges" {
  project     = local.network_project
  name        = "fw-${local.environment_code}-shared-base-10000-i-a-secondary-ranges"
  network     = local.network_name
  description = "Allow ingress to secondary CIDRs."
  direction   = "INGRESS"
  priority    = 10000

  allow {
    protocol = "all"
  }

  source_ranges = flatten([
    for subnetwork_secondary_ranges in local.subnetwork_secondary_range_lists : [
      for subnetwork_secondary_range in subnetwork_secondary_ranges : subnetwork_secondary_range.ip_cidr_range
    ]
  ])
}
