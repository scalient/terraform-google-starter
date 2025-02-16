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

variable "env" {
  description = "The environment."
  type        = string
}

variable "remote_state_bucket" {
  description = "The remote tfstate bucket."
  type        = string
}

variable "project_id" {
  description = "The main project id."
  type        = string
}

variable "cluster_name" {
  description = "The GKE cluster name (unique with the location)."
  type        = string
}

variable "cluster_location" {
  description = "The GKE cluster location (unique with the name)."
  type        = string
}

variable "kubernetes_default_namespace" {
  description = "The default namespace that pods will run under."
  default     = "default"
}

variable "kubernetes_default_service_account" {
  description = "The default service account that pods will run as."
  default     = "default"
}
