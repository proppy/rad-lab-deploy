# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  env = "main"
}

resource "google_project" "radlab_project" {
  project_id = var.project
  name       = var.project
  lifecycle {
    ignore_changes = all
  }
}

module "radlab_silicon_deploy" {
  source = "./rad-lab/modules/silicon_design"
  name   = "radlab-silicon-${var.env}"
  
  folder_id          = google_project.radlab_project.folder_id
  project_id_prefix  = google_project.radlab_project.name
  billing_account_id = google_project.radlab_project.billing_account

  create_project                  = false
  create_network                  = true
  enable_services                 = true
  set_external_ip_policy          = false
  set_shielded_vm_policy          = false
  set_trustedimage_project_policy = false
  machine_type			  = var.machine_type 

  notebook_count = 1
  notebook_names = [
    "radlab-silicon-demo-${var.env}",
  ]
}
