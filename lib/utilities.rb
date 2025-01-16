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

  def self.create_terraform_backend_and_migrate(rake_instance, backend_file, bucket, prefix: "")
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

    # Back up the local tfstate for good measure.
    rake_instance.send(:cp, "terraform.tfstate", "terraform.tfstate.backup")

    # Now that the backend file is written, run the migration process by detecting a local tfstate and uploading its
    # contents to the bucket.
    rake_instance.send(:sh, "terraform", "init", "-migrate-state")

    # Stage the new backend file for good measure.
    rake_instance.send(:sh, "git", "add", "--", backend_file.to_s)
  end
end
