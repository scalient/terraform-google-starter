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

module Utilities
  # These are conservatively the union of the IAM roles conferred to Terraform service accounts of the form
  # `sa-terraform-#{foundation_stage}@#{project_id}.iam.gserviceaccount.com`.
  GCP_IAM_ROLES = [
    "roles/accesscontextmanager.policyAdmin",
    "roles/browser",
    "roles/cloudasset.owner",
    "roles/essentialcontacts.admin",
    "roles/logging.configWriter",
    "roles/orgpolicy.policyAdmin",
    "roles/resourcemanager.folderAdmin",
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
    parent_read, child_write = IO.pipe

    rake_instance.send(:sh, "gcloud", "config", "list", "account", "--format", "value(core.account)", out: child_write)

    child_write.close
    authenticated_user = parent_read.read.chomp

    child_read, parent_write = IO.pipe
    parent_read, child_write = IO.pipe

    Thread.new do
      heredoc_content = <<EOS
jsonencode(var.org_id)
EOS
      parent_write.write(heredoc_content)
      parent_write.close
    end

    rake_instance.send(:sh, "terraform", "console", "-var-file", "terraform.tfvars", in: child_read, out: child_write)

    child_write.close

    # First strip away the double quotes, and then parse the JSON.
    organization_id = JSON.parse(JSON.parse(parent_read.read))

    roles.each do |role|
      rake_instance.send(
        :sh, "gcloud", "organizations", "add-iam-policy-binding", organization_id,
        "--member", "user:#{authenticated_user}",
        "--role", role,
      )
    end
  end
end
