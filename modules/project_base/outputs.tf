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
  description = "The GKE cluster."
  value       = google_container_cluster._
}

output "kubernetes_default_namespace" {
  description = "The default namespace that pods will run under."
  value       = var.kubernetes_default_namespace
}

output "kubernetes_default_service_account" {
  description = "The default service account that pods will run as."
  value       = var.kubernetes_default_service_account
}

output "database" {
  description = "The Cloud SQL database."
  value       = module.database["_"] != null ? module.database["_"].instance : null
}
