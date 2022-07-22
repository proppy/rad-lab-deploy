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
  name = var.project
  lifecycle {
    ignore_changes = all
  }
}

module "catx_demo_radlab_deployment" {
  source = "../../rad-lab/modules/silicon_design"

  billing_account_id = google_project.radlab_project.billing_account
  folder_id          = google_project.radlab_project.folder_id
#  organization_id    = google_project.radlab_project.organization_id
  
  create_project  = false
  project_name    = google_project.radlab_project.name
  enable_services = true

  network_name = "${google_project.radlab_project.name}-silicon-network"
  subnet_name = "${google_project.radlab_project.name}-silicon-subnet"
  
  set_external_ip_policy          = false
  set_shielded_vm_policy          = false
  set_trustedimage_project_policy = false

  notebook_count = 1
}
