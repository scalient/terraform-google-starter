# frozen_string_literal: true

# Copyright 2025 Scalient LLC
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

require "json"
require "open3"
require "pathname"

require_relative "lib/utilities"

receipts = {}

[
  "migrate",
  "prerequisites",
  "stage_bootstrap",
  "stage_organization",
  "stage_environments",
  "stage_networks_shared_vpc",
  "main",
].each do |name|
  receipts[name] = Pathname.new("receipts/#{name}")
end

current_dir = Pathname.new(".")
overrides_dir = Pathname.new("overrides")
user_tfvars = Pathname.new("terraform.tfvars")
prerequisites_dir = Pathname.new("modules/prerequisites")
prerequisites_tfvars = Pathname.new("00_prerequisites.auto.tfvars.json")
project_dir = Pathname.new("modules/project")
stage_bootstrap_dir = Pathname.new("modules/0-bootstrap")
stage_bootstrap_tfvars = Pathname.new("01_stage_bootstrap.auto.tfvars.json")
stage_organization_tfvars = Pathname.new("02_stage_organization.auto.tfvars.json")
stage_org_dir = Pathname.new("modules/1-org")
stage_org_working_dir = Pathname.new("modules/1-org/envs/shared")
stage_environments_dir = Pathname.new("modules/2-environments")
stage_environments_envs_dir = stage_environments_dir.join("envs")
stage_environments_env_dirs = stage_environments_envs_dir.children
stage_networks_shared_vpc_dir = Pathname.new("modules/3-networks-dual-svpc")
stage_networks_shared_vpc_envs_dir = stage_networks_shared_vpc_dir.join("envs")
stage_networks_shared_vpc_env_dirs = [stage_networks_shared_vpc_envs_dir.join("shared")] +
  stage_environments_envs_dir.children.map do |env_dir|
    environment = env_dir.basename.to_s
    stage_networks_shared_vpc_envs_dir.join(environment)
  end

STAGE_NAME_PATTERN = Regexp.new("\\Amodules/(?:[1-9][0-9]*|0)\\-(?<name>[a-z0-9\\-_]+)")

task "ensure_permissions" do
  Utilities.add_authenticated_user_roles(self)
end

Utilities.create_terraform_tasks(
  self, "prerequisites", receipts["prerequisites"], current_dir,
  [prerequisites_dir, user_tfvars, *current_dir.glob("*.tf")],
) do
  # Apply just the `prerequisites` module because this is the initialization run, and the developer could have added
  # later stage modules in `main.tf`.
  sh "terraform", "apply", "-target", "module.prerequisites"

  child_output = nil

  Open3.popen3("terraform", "output", "-json") do |stdin, stdout, stderr, wait_thr|
    stdin.close

    Thread.new do
      $stderr.print(stderr.read)
    end

    child_output = stdout.read

    if (status = wait_thr.value) != 0
      raise SystemCallError.new("Terraform call failed", status.exitstatus)
    end
  end

  administration_project_id = JSON.parse(child_output)["administration_project_id"]["value"]

  Open3.popen3("terraform", "console", "-var-file", "terraform.tfvars") do |stdin, stdout, stderr, wait_thr|
    # Avoid deadlock.
    Thread.new do
      heredoc_content = <<EOS
jsonencode(var.groups)
EOS
      stdin.write(heredoc_content)
      stdin.close
    end

    Thread.new do
      $stderr.print(stderr.read)
    end

    child_output = stdout.read

    if (status = wait_thr.value) != 0
      raise SystemCallError.new("Terraform call failed", status.exitstatus)
    end
  end

  # First strip away the double quotes, and then parse the JSON.
  groups_json = JSON.parse(JSON.parse(child_output))
  # Inject the detected administration project id as the billing project for the foundation bootstrap stage.
  groups_json["billing_project"] = administration_project_id

  prerequisites_tfvars.open("wb") do |f|
    f.write(JSON.dump({groups: groups_json}))
  end
end

Utilities.create_terraform_tasks(
  self, "bootstrap", receipts["stage_bootstrap"], stage_bootstrap_dir,
  [
    receipts["prerequisites"],
    stage_bootstrap_dir,
    *Utilities.find_extra_files(overrides_dir, stage_bootstrap_dir),
  ],
) do
  Utilities.install_extra_files(overrides_dir, stage_bootstrap_dir)

  child_output = nil

  Dir.chdir(stage_bootstrap_dir) do
    # Apply the top-level tfvars, and then override that with the autogenerated one from the `prerequisites` target.
    sh "terraform", "apply",
       "-var-file", "../../terraform.tfvars",
       "-var-file", prerequisites_tfvars.relative_path_from(stage_bootstrap_dir).to_s

    Open3.popen3("terraform", "output", "-json") do |stdin, stdout, stderr, wait_thr|
      stdin.close

      Thread.new do
        $stderr.print(stderr.read)
      end

      child_output = stdout.read

      if (exit_code = wait_thr.value) != 0
        raise SystemCallError("Terraform call failed", exit_code)
      end
    end
  end

  bucket = JSON.parse(child_output)["gcs_bucket_tfstate"]["value"]

  stage_bootstrap_tfvars.open("wb") do |f|
    f.write(JSON.dump({remote_state_bucket: bucket}))
  end
end

task "migrate" => receipts["migrate"]

file receipts["migrate"] => receipts["stage_bootstrap"] do
  bucket = stage_bootstrap_tfvars.open("rb") do |f|
    JSON.parse(f.read)["remote_state_bucket"]
  end

  Utilities.create_terraform_backend(self, Pathname.new("backend.tf.json"), bucket)

  [
    stage_bootstrap_dir,
    stage_org_dir,
  ].each do |stage_dir|
    stage_name = STAGE_NAME_PATTERN.match(stage_dir.to_s)["name"]

    Utilities.create_terraform_backend(
      self, stage_dir.join("backend_override.tf.json"), bucket, prefix: "terraform/#{stage_name}/state",
    )
  end

  stage_environments_envs_dir.children.each do |env_dir|
    environment = env_dir.basename.to_s

    Utilities.create_terraform_backend(
      self, env_dir.join("backend_override.tf.json"), bucket, prefix: "terraform/environments/#{environment}",
    )

    Utilities.create_terraform_backend(
      self, stage_networks_shared_vpc_envs_dir.join("#{environment}/backend_override.tf.json"), bucket,
      prefix: "terraform/networks/#{environment}",
    )
  end

  Utilities.create_terraform_backend(
    self, stage_networks_shared_vpc_envs_dir.join("shared/backend_override.tf.json"), bucket,
    prefix: "terraform/networks/envs/shared",
  )

  Utilities.create_terraform_backend(
    self, kubernetes_terraform_dir.join("backend.tf.json"), bucket,
    prefix: "terraform/kubernetes/state",
  )

  Utilities.migrate_terraform_state(self)

  Dir.chdir(stage_bootstrap_dir) do
    Utilities.migrate_terraform_state(self)
  end

  puts <<EOS.chomp
Terraform state for the bootstrap stage and main project has been migrated. You may now commit the newly created backend
files.
EOS

  touch receipts["migrate"]
end

Utilities.create_terraform_tasks(
  self, "organization", receipts["stage_organization"], stage_org_working_dir,
  [
    receipts["stage_bootstrap"],
    stage_org_dir,
    *Utilities.find_extra_files(overrides_dir, stage_org_dir),
  ],
) do
  Utilities.install_extra_files(overrides_dir, stage_org_dir)

  billing_project_id = prerequisites_tfvars.open("rb") do |f|
    JSON.parse(f.read)["groups"]["billing_project"]
  end

  child_output = nil

  Dir.chdir(stage_org_working_dir) do
    # The below run seems to contain resources that require a quota project.
    ENV["GOOGLE_CLOUD_QUOTA_PROJECT"] = billing_project_id

    # Apply the top-level tfvars, and then override that with the autogenerated one from the `stage_bootstrap` target.
    sh "terraform", "apply",
       "-var-file", "../../../../terraform.tfvars",
       "-var-file", stage_bootstrap_tfvars.relative_path_from(stage_org_working_dir).to_s

    ENV.delete("GOOGLE_CLOUD_QUOTA_PROJECT")

    heredoc_content = <<EOS
.values.root_module.resources[] |
select(.address == "google_access_context_manager_access_policy.access_policy[0]") |
.values.id
EOS

    Open3.pipeline_rw(["terraform", "show", "-json"], ["jq", heredoc_content]) do |first_stdin, last_stdout, wait_thrs|
      first_stdin.close
      child_output = last_stdout.read

      wait_thrs.each do |wait_thr|
        if (status = wait_thr.value) != 0
          raise SystemCallError.new("Terraform call failed", status.exitstatus)
        end
      end
    end
  end

  access_context_manager_policy_id = JSON.parse(child_output)

  stage_organization_tfvars.open("wb") do |f|
    f.write(JSON.dump({access_context_manager_policy_id: access_context_manager_policy_id}))
  end
end

Utilities.create_terraform_tasks(
  self, "environments", receipts["stage_environments"], stage_environments_env_dirs,
  [
    receipts["stage_organization"],
    *stage_environments_env_dirs,
    *Utilities.find_extra_files(overrides_dir, stage_environments_dir),
  ],
) do
  Utilities.install_extra_files(overrides_dir, stage_environments_dir)

  # The below runs seem to contain resources that require a quota project.
  billing_project_id = prerequisites_tfvars.open("rb") do |f|
    JSON.parse(f.read)["groups"]["billing_project"]
  end

  stage_environments_env_dirs.each do |env_dir|
    Dir.chdir(env_dir) do
      ENV["GOOGLE_CLOUD_QUOTA_PROJECT"] = billing_project_id

      # Apply the top-level tfvars, and then override that with the autogenerated one from the `stage_bootstrap` target.
      sh "terraform", "apply",
         "-var-file", "../../../../terraform.tfvars",
         "-var-file", stage_bootstrap_tfvars.relative_path_from(env_dir).to_s

      ENV.delete("GOOGLE_CLOUD_QUOTA_PROJECT")
    end
  end
end

Utilities.create_terraform_tasks(
  self, "networks_shared_vpc", receipts["stage_networks_shared_vpc"], stage_networks_shared_vpc_env_dirs,
  [
    receipts["stage_environments"],
    *stage_networks_shared_vpc_env_dirs,
    *Utilities.find_extra_files(overrides_dir, stage_networks_shared_vpc_dir),
  ],
) do
  Utilities.install_extra_files(overrides_dir, stage_networks_shared_vpc_dir)

  # The below runs seem to contain resources that require a quota project.
  billing_project_id = prerequisites_tfvars.open("rb") do |f|
    JSON.parse(f.read)["groups"]["billing_project"]
  end

  # The foundation stage instructions require the `shared` environment to be provisioned first.
  stage_networks_shared_vpc_env_dirs.each do |env_dir|
    Dir.chdir(env_dir) do
      ENV["GOOGLE_CLOUD_QUOTA_PROJECT"] = billing_project_id

      # Apply the top-level tfvars, and then override that with autogenerated ones.
      sh "terraform", "apply",
         "-var-file", "../../../../terraform.tfvars",
         "-var-file", stage_bootstrap_tfvars.relative_path_from(env_dir).to_s,
         "-var-file", stage_organization_tfvars.relative_path_from(env_dir).to_s

      ENV.delete("GOOGLE_CLOUD_QUOTA_PROJECT")
    end
  end
end

Utilities.create_terraform_tasks(
  self, "default", receipts["main"], current_dir,
  [
    receipts["stage_networks_shared_vpc"],
    prerequisites_dir, project_dir, user_tfvars, *current_dir.glob("*.tf"),
  ],
) do
  sh "terraform", "apply"
end
