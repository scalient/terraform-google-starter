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

variable "project" {
  description = "The main project."
  type = object({
    project_id = string
    cluster = object({
      name                    = string
      location                = string
      default_namespace       = string
      default_service_account = string
    })
  })
}

variable "env" {
  description = "The environment."
  type        = string
}

variable "remote_state_bucket" {
  description = "The remote tfstate bucket."
  type        = string
}
