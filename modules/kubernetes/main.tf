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

resource "local_file" "providers" {
  filename        = "${path.module}/providers.tf"
  file_permission = "0644"
  content = templatefile("${path.module}/providers.tftpl", {
    environments_to_projects = local.environments_to_projects
  })
}

# An example. We advise you to use a separate file to fill these in.
#
# module "the_environment" {
#   source              = "../project/kubernetes"
#   env                 = "the_environment"
#   remote_state_bucket = var.remote_state_bucket
#   providers = {
#     kubernetes = kubernetes.the_environment
#   }
#   project = local.environments_to_projects["the_environment"]
# }
