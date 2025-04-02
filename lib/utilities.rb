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

  def self.ensure_command(*args)
    command = args.first

    begin
      Open3.popen3(*args) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        Thread.new do
          stderr.read
        end

        stdout.read

        if (status = wait_thr.value) != 0
          raise SystemCallError.new("#{command} call failed", status.exitstatus)
        end
      end
    rescue SystemCallError
      raise ArgumentError, "Please install #{command}"
    end
  end

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

  def self.export_terraform_outputs(rake_instance, outputs_file)
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

      outputs_file.open("wb") do |f|
        f.write(child_output)
      end

      # Stage the output file for good measure. Add the `-f` option in case the file happens to be `.gitignore`'d.
      rake_instance.send(:sh, "git", "add", "-f", "--", outputs_file.to_s)

      JSON.parse(child_output)
    end
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

    outputs = Pathname.new("modules/0-bootstrap/outputs.json").open("rb") do |f|
      JSON.parse(f.read)
    end

    organization_id = outputs["common_config"]["value"]["org_id"]

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

  def self.find_extra_files(extra_dir, dst_subdir)
    if !dst_subdir.relative?
      raise ArgumentError, "Directory path must be relative"
    end

    extra_subdir = extra_dir.join(*dst_subdir.each_filename.to_a[1..])

    if extra_subdir.exist?
      extra_subdir.find.select(&:file?)
    else
      []
    end
  end

  def self.install_extra_files(extra_dir, dst_subdir)
    if !extra_dir.relative? || !dst_subdir.relative?
      raise ArgumentError, "Directory path must be relative"
    end

    dst_dir = Pathname.new(dst_subdir.each_filename.to_a.first)

    find_extra_files(extra_dir, dst_subdir).each do |extra_file|
      dst_link = dst_dir.join(*extra_file.each_filename.to_a[1..])
      FileUtils.ln_sf(extra_file.relative_path_from(dst_link.parent), dst_link)
    end
  end

  def self.create_terraform_tasks(rake_instance, target, receipt_file, working_dirs, dependencies = [], &block)
    if !dependencies.is_a?(Array)
      dependencies = [dependencies]
    end

    case working_dirs
    when Pathname
      working_dirs = [working_dirs]
    when String
      working_dirs = [Pathname.new(working_dirs)]
    end

    dot_terraform_dirs = working_dirs.map do |working_dir|
      dot_terraform_dir = working_dir.join(".terraform")

      rake_instance.send(:directory, dot_terraform_dir) do
        Dir.chdir(working_dir) do
          terraform_init(rake_instance)
        end
      end

      dot_terraform_dir
    end

    computed_dependencies = dependencies.map do |dependency|
      if dependency.is_a?(String)
        dependency = Pathname.new(dependency)
      end

      if dependency.directory?
        dependency.glob("**/*.{json,tf,tfvars}")
      else
        dependency
      end
    end.tap(&:flatten!).tap(&:uniq!)

    if receipt_file
      rake_instance.send(:task, target => receipt_file)

      rake_instance.send(:file, receipt_file => [*dot_terraform_dirs, *computed_dependencies]) do
        block.call

        rake_instance.send(:touch, receipt_file)
      end
    else
      rake_instance.send(:task, target => [*dot_terraform_dirs, *computed_dependencies], &block)
    end
  end

  def self.run_secret_action(environment: nil, &block)
    if !environment
      terraform_output_key_prefix = "org"
      terraform_dir = Pathname.new("modules/1-org/envs/shared")
    else
      terraform_output_key_prefix = "env"
      terraform_dir = Pathname.new("modules/2-environments/envs/#{environment}")
    end

    Dir.chdir(terraform_dir) do
      outputs = Pathname.new("outputs.json").open("rb") do |f|
        JSON.parse(f.read)
      end

      project_id = outputs["#{terraform_output_key_prefix}_secrets_project_id"]["value"]

      block.call(project_id)
    end
  end

  def self.secret_create(key, value, environment: nil)
    if !key
      raise ArgumentError, "Please provide the secret's key"
    end

    if !value
      raise ArgumentError, "Please provide the secret's value"
    end

    run_secret_action(environment: environment) do |project_id|
      Open3.popen3(
        "gcloud", "secrets", "create", "--project", project_id, "--data-file", "-", "--", key,
      ) do |stdin, stdout, stderr, wait_thr|
        Thread.new do
          stdin.write(value)
          stdin.close
        end

        Thread.new do
          $stderr.print(stderr.read)
        end

        stdout.read

        if (status = wait_thr.value) != 0
          raise SystemCallError.new("gcloud call failed", status.exitstatus)
        end
      end
    end
  end

  def self.secret_delete(key, environment: nil)
    if !key
      raise ArgumentError, "Please provide the secret's key"
    end

    run_secret_action(environment: environment) do |project_id|
      Open3.popen3(
        "gcloud", "secrets", "delete", "--project", project_id, "--quiet", "--", key,
      ) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        Thread.new do
          $stderr.print(stderr.read)
        end

        stdout.read

        if (status = wait_thr.value) != 0
          raise SystemCallError.new("gcloud call failed", status.exitstatus)
        end
      end
    end
  end

  def self.secret_access(key, version, environment: nil)
    if !key
      raise ArgumentError, "Please provide the secret's key"
    end

    run_secret_action(environment: environment) do |project_id|
      Open3.popen3(
        "gcloud", "secrets", "versions", "access", "--project", project_id, "--secret", key, "--", version,
      ) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        Thread.new do
          $stderr.print(stderr.read)
        end

        Thread.new do
          puts stdout.read
        end

        if (status = wait_thr.value) != 0
          raise SystemCallError.new("gcloud call failed", status.exitstatus)
        end
      end
    end
  end

  def self.secret_list(environment: nil)
    run_secret_action(environment: environment) do |project_id|
      Open3.popen3(
        "gcloud", "secrets", "list", "--project", project_id,
      ) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        Thread.new do
          $stderr.print(stderr.read)
        end

        Thread.new do
          puts stdout.read
        end

        if (status = wait_thr.value) != 0
          raise SystemCallError.new("gcloud call failed", status.exitstatus)
        end
      end
    end
  end
end
