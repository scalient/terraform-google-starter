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

output "project_id" {
  description = "The main project id."
  value       = module.project.project_id
}

output "cluster" {
  description = "The GKE cluster information (unique with name and location)."
  value = {
    name                    = google_container_cluster._.name
    location                = google_container_cluster._.location
    default_namespace       = var.kubernetes_default_namespace
    default_service_account = var.kubernetes_default_service_account
  }
}
