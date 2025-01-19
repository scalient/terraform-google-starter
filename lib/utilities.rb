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

module Utilities
  # These are conservatively the union of the IAM roles conferred to Terraform service accounts of the form
  # `sa-terraform-#{foundation_stage}@#{project_id}.iam.gserviceaccount.com`.
  GCP_IAM_ROLES = [
    "roles/accesscontextmanager.policyAdmin",
    "roles/browser",
    "roles/cloudasset.owner",
    "roles/compute.networkAdmin",
    "roles/compute.orgSecurityPolicyAdmin",
    "roles/compute.orgSecurityResourceAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.xpnAdmin",
    "roles/dns.admin",
    "roles/essentialcontacts.admin",
    "roles/logging.configWriter",
    "roles/orgpolicy.policyAdmin",
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.folderViewer",
    "roles/resourcemanager.organizationAdmin",
    "roles/resourcemanager.organizationViewer",
    # Don't declare because the `bootstrap` foundation stage mandates that only stage-specific Terraform service
    # accounts be organization project creators.
    # "roles/resourcemanager.projectCreator",
    "roles/resourcemanager.tagAdmin",
    "roles/resourcemanager.tagUser",
    "roles/securitycenter.notificationConfigEditor",
    "roles/securitycenter.sourcesEditor",
    "roles/serviceusage.serviceUsageConsumer",
  ].freeze

  def self.terraform_init(rake_instance)
    rake_instance.send(:sh, "terraform", "init")
    # Potentially rewrite the lock file to include cross-architecture providers.
    rake_instance.send(
      :sh, "terraform", "providers", "lock",
      "-platform", "linux_amd64",
      "-platform", "linux_arm64",
      "-platform", "darwin_amd64",
      "-platform", "darwin_arm64",
    )
  end

  def self.create_terraform_backend(rake_instance, backend_file, bucket, prefix: "terraform/state")
    backend_file.open("wb") do |f|
      f.write(
        JSON.dump(
          {
            terraform: {
              backend: {
                gcs: {
                  bucket: bucket,
                  prefix: prefix,
                },
              },
            },
          },
        ),
      )
    end

    # Stage the new backend file for good measure. Add the `-f` option in case the file happens to be `.gitignore`'d.
    rake_instance.send(:sh, "git", "add", "-f", "--", backend_file.to_s)
  end

  def self.migrate_terraform_state(rake_instance)
    # Back up the local tfstate for good measure.
    rake_instance.send(:cp, "terraform.tfstate", "terraform.tfstate.backup")

    # Now that the backend file is written, run the migration process by detecting a local tfstate and uploading its
    # contents to the bucket.
    rake_instance.send(:sh, "terraform", "init", "-migrate-state")
  end

  def self.add_authenticated_user_roles(rake_instance, roles: GCP_IAM_ROLES)
    child_output = nil

    Open3.popen3(
      "gcloud", "config", "list", "account", "--format", "value(core.account)",
    ) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      Thread.new do
        $stderr.print(stderr.read)
      end

      child_output = stdout.read

      if (status = wait_thr.value) != 0
        raise SystemCallError.new("Terraform call failed", status.exitstatus)
      end
    end

    authenticated_user = child_output.chomp

    Open3.popen3(
      "terraform", "output", "-json",
    ) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      Thread.new do
        $stderr.print(stderr.read)
      end

      child_output = stdout.read

      if (status = wait_thr.value) != 0
        raise SystemCallError.new("Terraform call failed", status.exitstatus)
      end
    end

    organization_id = JSON.parse(child_output)["organization_id"]["value"]

    heredoc_content = <<EOS
.bindings[] | select(.members[] | index("user:#{authenticated_user}")) | .role
EOS

    Open3.pipeline_rw(
      ["gcloud", "organizations", "get-iam-policy", organization_id.to_s, "--format", "json"],
      ["jq", heredoc_content],
    ) do |first_stdin, last_stdout, wait_thrs|
      first_stdin.close
      child_output = last_stdout.read

      wait_thrs.each do |wait_thr|
        if (status = wait_thr.value) != 0
          raise SystemCallError.new("Terraform call failed", status.exitstatus)
        end
      end
    end

    # Set subtract to determine which roles the authenticated user is missing for Terraform to finish without 403's.
    (roles - child_output.chomp.split("\n", -1).map { |line| JSON.parse(line) }).each do |role|
      rake_instance.send(
        :sh, "gcloud", "organizations", "add-iam-policy-binding", organization_id,
        "--member", "user:#{authenticated_user}",
        "--role", role,
      )
    end
  end
end
