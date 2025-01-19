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
].each do |name|
  receipts[name] = Pathname.new("receipts/#{name}")
end

user_tfvars = Pathname.new("terraform.tfvars")
prerequisites_tfvars = Pathname.new("00_prerequisites.auto.tfvars.json")
stage_bootstrap_dir = Pathname.new("modules/0-bootstrap")
stage_bootstrap_tfvars = Pathname.new("01_stage_bootstrap.auto.tfvars.json")
stage_org_dir = Pathname.new("modules/1-org/envs/shared")

STAGE_NAME_PATTERN = Regexp.new("\\Amodules/(?:[1-9][0-9]*|0)\\-(?<name>[a-z0-9\\-_]+)")

task "ensure_permissions" do
  Utilities.add_authenticated_user_roles(self)
end

task "prerequisites" => receipts["prerequisites"]

file receipts["prerequisites"] => user_tfvars do
  Utilities.terraform_init(self)
  sh "terraform", "apply"

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

  touch receipts["prerequisites"]
end

task "bootstrap" => receipts["stage_bootstrap"]

file receipts["stage_bootstrap"] => receipts["prerequisites"] do
  child_output = nil

  Dir.chdir(stage_bootstrap_dir) do
    Utilities.terraform_init(self)
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

  touch receipts["stage_bootstrap"]
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

task "organization" => receipts["stage_organization"]

file receipts["stage_organization"] => receipts["migrate"] do
  billing_project_id = prerequisites_tfvars.open("rb") do |f|
    JSON.parse(f.read)["groups"]["billing_project"]
  end

  Dir.chdir(stage_org_dir) do
    # The below run seems to contain resources that require a quota project.
    ENV["GOOGLE_CLOUD_QUOTA_PROJECT"] = billing_project_id

    Utilities.terraform_init(self)
    # Apply the top-level tfvars, and then override that with the autogenerated one from the `stage_bootstrap` target.
    sh "terraform", "apply",
       "-var-file", "../../../../terraform.tfvars",
       "-var-file", stage_bootstrap_tfvars.relative_path_from(stage_org_dir).to_s

    ENV.delete("GOOGLE_CLOUD_QUOTA_PROJECT")
  end

  touch receipts["stage_organization"]
end

task "default" => "organizations"
