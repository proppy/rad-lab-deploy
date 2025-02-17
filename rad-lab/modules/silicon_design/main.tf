/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
nnn * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  random_id = var.deployment_id != null ? var.deployment_id : random_id.default.0.hex
  project = (var.create_project
    ? try(module.project_radlab_silicon_design.0, null)
    : try(data.google_project.existing_project.0, null)
    )
  project_number = (var.create_project
    ? try(module.project_radlab_silicon_design.0.project_number, null)
    : try(data.google_project.existing_project.0.number, null)
    )
  region = join("-", [split("-", var.zone)[0], split("-", var.zone)[1]])

  network_name = var.network_name != null ? var.network_name : "${var.name}-network"
  subnet_name = var.subnet_name != null ? var.subnet_name : "${var.name}-subnet"

  network = (
    var.create_network
    ? try(module.vpc_ai_notebook.0.network.network, null)
    : try(data.google_compute_network.default.0, null)
  )

  subnet = (
    var.create_network
    ? try(module.vpc_ai_notebook.0.subnets["${local.region}/${local.subnet_name}"], null)
    : try(data.google_compute_subnetwork.default.0, null)
  )

  notebook_sa_project_roles = [
    "roles/artifactregistry.reader",
    "roles/notebooks.admin",
    "roles/compute.instanceAdmin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
    "roles/aiplatform.admin",
  ]

  cloudbuild_sa_project_roles = [
    "roles/compute.admin",
    "roles/storage.admin",
  ]

  image_builder_sa_project_roles = [
    "roles/compute.instanceAdmin",
    "roles/compute.storageAdmin",
    "roles/storage.admin",
  ]

  notebook_names = length(var.notebook_names) > 0 ? var.notebook_names : [for i in range(var.notebook_count): "${var.name}-notebook-${i}"]

  default_apis = [
    "compute.googleapis.com",
    "notebooks.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "aiplatform.googleapis.com",
  ]

  project_services = var.enable_services ? (var.billing_budget_pubsub_topic ? distinct(concat(local.default_apis,["pubsub.googleapis.com"])) : local.default_apis) : []

  gcloud_impersonate_flag = length(var.resource_creator_identity) != 0 ? "--impersonate-service-account=${var.resource_creator_identity}" : ""

  image_tag = var.image_tag != "" ? var.image_tag : formatdate("YYYYMMDDhhmm", timestamp())
}

resource "random_id" "default" {
  count       = var.deployment_id == null ? 1 : 0
  byte_length = 2
}

############################
#  SILICON DESIGN PROJECT  #
############################

data "google_project" "existing_project" {
  count      = var.create_project ? 0 : 1
  project_id = var.project_id_prefix
}

module "project_radlab_silicon_design" {
  count   = var.create_project ? 1 : 0
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 13.0"

  name              = format("%s-%s", var.project_id_prefix, local.random_id)
  random_project_id = false
  folder_id         = var.folder_id
  billing_account   = var.billing_account_id
  org_id            = var.organization_id

  activate_apis = []
}

resource "google_project_service" "enabled_services" {
  for_each                   = toset(local.project_services)
  project                    = local.project.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    module.project_radlab_silicon_design
  ]
}

data "google_compute_network" "default" {
  count   = var.create_network ? 0 : 1
  project = local.project.project_id
  name    = local.network_name
}

data "google_compute_subnetwork" "default" {
  count   = var.create_network ? 0 : 1
  project = local.project.project_id
  name    = local.subnet_name
  region  = local.region
}

module "vpc_ai_notebook" {
  count   = var.create_network ? 1 : 0
  source  = "terraform-google-modules/network/google"
  version = "~> 5.0"

  project_id   = local.project.project_id
  network_name = local.network_name
  routing_mode = "GLOBAL"
  description  = "VPC Network created via Terraform"

  subnets = [
    {
      subnet_name           = local.subnet_name
      subnet_ip             = var.ip_cidr_range
      subnet_region         = local.region
      description           = "Subnetwork inside *vpc-silicon-design* VPC network, created via Terraform"
      subnet_private_access = true
    }
  ]

  firewall_rules = [
    {
      name        = "${var.name}-allow-internal"
      description = "Firewall rule to allow traffic on all ports inside *vpc-silicon-design* VPC network."
      priority    = 65534
      ranges      = ["10.0.0.0/8"]
      direction   = "INGRESS"

      allow = [{
	protocol = "tcp"
	ports    = ["0-65535"]
      }]
    }
  ]

  depends_on = [
    module.project_radlab_silicon_design,
    google_project_service.enabled_services,
    time_sleep.wait_120_seconds
  ]
}

resource "google_service_account" "sa_p_notebook" {
  project      = local.project.project_id
  account_id   = "${var.name}-n-sa"
  display_name = "Notebooks in trusted environment"
}

resource "google_project_iam_member" "sa_p_notebook_permissions" {
  for_each = toset(local.notebook_sa_project_roles)
  project  = local.project.project_id
  member   = "serviceAccount:${google_service_account.sa_p_notebook.email}"
  role     = each.value
}

resource "google_service_account_iam_member" "sa_ai_notebook_iam" {
  for_each           = toset(concat(formatlist("user:%s", var.trusted_users), formatlist("group:%s", var.trusted_groups)))
  member             = each.value
  role               = "roles/iam.serviceAccountUser"
  service_account_id = google_service_account.sa_p_notebook.id
}

resource "google_project_iam_member" "module_role1" {
  for_each = toset(concat(formatlist("user:%s", var.trusted_users), formatlist("group:%s", var.trusted_groups)))
  project  = local.project.project_id
  member   = each.value
  role     = "roles/notebooks.admin"
}

resource "google_project_iam_member" "module_role2" {
  for_each = toset(concat(formatlist("user:%s", var.trusted_users), formatlist("group:%s", var.trusted_groups)))
  project  = local.project.project_id
  member   = each.value
  role     = "roles/viewer"
}

resource "google_project_service_identity" "sa_cloudbuild_identity" {
  provider = google-beta
  project  = local.project.project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_project_iam_member" "sa_cloudbuild_permissions" {
  for_each = toset(local.cloudbuild_sa_project_roles)
  project  = local.project.project_id
  member   =  "serviceAccount:${google_project_service_identity.sa_cloudbuild_identity.email}"
  role     = each.value
}

resource "google_service_account_iam_member" "sa_cloudbuild_image_builder_access" {
  member             = "serviceAccount:${google_project_service_identity.sa_cloudbuild_identity.email}"
  role               = "roles/iam.serviceAccountUser"
  service_account_id = google_service_account.sa_image_builder_identity.id
}

resource "google_service_account" "sa_image_builder_identity" {
  project    = local.project.project_id
  account_id = "${var.name}-i-sa"
}

resource "google_project_iam_member" "sa_image_builder_permissions" {
  for_each = toset(local.image_builder_sa_project_roles)
  project  = local.project.project_id
  member   = "serviceAccount:${google_service_account.sa_image_builder_identity.email}"
  role     = each.value
}

resource "google_service_account_iam_member" "sa_ai_notebook_user_iam" {
  for_each           = var.trusted_users
  member             = "user:${each.value}"
  role               = "roles/iam.serviceAccountUser"
  service_account_id = google_service_account.sa_p_notebook.id
}

resource "google_project_iam_member" "ai_notebook_user_role1" {
  for_each = var.trusted_users
  project  = local.project.project_id
  member   = "user:${each.value}"
  role     = "roles/notebooks.admin"
}

resource "google_project_iam_member" "ai_notebook_user_role2" {
  for_each = var.trusted_users
  project  = local.project.project_id
  member   = "user:${each.value}"
  role     = "roles/viewer"
}

resource "google_notebooks_instance" "ai_notebook" {
  count        = var.notebook_count
  project      = local.project.project_id
  name         = local.notebook_names[count.index]
  location     = var.zone
  machine_type = var.machine_type

  container_image {
    repository = "${google_artifact_registry_repository.containers_repo.location}-docker.pkg.dev/${local.project.project_id}/${google_artifact_registry_repository.containers_repo.repository_id}/${var.image_name}"
    tag        = local.image_tag
  }

  service_account = google_service_account.sa_p_notebook.email

  install_gpu_driver = false
  boot_disk_type     = var.boot_disk_type
  boot_disk_size_gb  = var.boot_disk_size_gb
  data_disk_type     = var.data_disk_type
  data_disk_size_gb  = var.data_disk_size_gb
  no_remove_data_disk = true

  no_public_ip    = false
  no_proxy_access = false

  network = local.network.self_link
  subnet  = local.subnet.self_link

  post_startup_script = "gs://${google_storage_bucket.staging_bucket.name}/copy-notebooks.sh"

  labels = {
    module = "silicon-design"
  }

  metadata = {
    terraform  = "true"
    proxy-mode = "service_account"
  }
  depends_on = [
    time_sleep.wait_120_seconds,
    null_resource.build_and_push_image,
  ]
}

resource "google_artifact_registry_repository" "containers_repo" {
  provider = google-beta

  project       = local.project.project_id
  location      = local.region
  repository_id = "${var.name}-containers"
  description   = "container image repository"
  format        = "DOCKER"

  depends_on = [
    google_project_service.enabled_services
  ]
}

resource "google_storage_bucket" "staging_bucket" {
  project                     = local.project.project_id
  name                        = "${local.project.project_id}-${var.name}-staging"
  location                    = local.region
  force_destroy               = true
  uniform_bucket_level_access = true
}

# Locally build container for notebook container and push to container registry #
resource "null_resource" "build_and_push_image" {
  triggers = {
    image_tag           = local.image_tag
    cloudbuild_yaml_sha = filesha1("${path.module}/scripts/build/cloudbuild.yaml")
    workflow_sha        = filesha1("${path.module}/scripts/build/images/compute_image.wf.json")
    dockerfile_sha      = filesha1("${path.module}/scripts/build/images/Dockerfile")
    provision_sha       = filesha1("${path.module}/scripts/build/images/provision.sh")
    profile_sha         = filesha1("${path.module}/scripts/build/images/provision/profile.sh")
    papermill_sha       = filesha1("${path.module}/scripts/build/images/provision/papermill-launcher")
    notebook_sha        = sha1(join("", [for f in fileset(path.cwd, "scripts/build/notebooks/**/*"): filesha1(f)]))
  }

  provisioner "local-exec" {
    working_dir = path.module
    command     = "gcloud ${local.gcloud_impersonate_flag} --project=${local.project.project_id} builds submit . --config ./scripts/build/cloudbuild.yaml --substitutions \"_ZONE=${var.zone},_COMPUTE_IMAGE=${var.image_name},_CONTAINER_IMAGE=${google_artifact_registry_repository.containers_repo.location}-docker.pkg.dev/${local.project.project_id}/${google_artifact_registry_repository.containers_repo.repository_id}/${var.image_name},_STAGING_BUCKET=${google_storage_bucket.staging_bucket.name},_COMPUTE_NETWORK=${local.network.id},_COMPUTE_SUBNET=${local.subnet.id},_IMAGE_TAG=${local.image_tag},_CLOUD_BUILD_SA=${google_service_account.sa_image_builder_identity.email}\""
  }

  depends_on = [
    time_sleep.wait_120_seconds,
    google_artifact_registry_repository.containers_repo,
    google_storage_bucket.staging_bucket,
    google_project_iam_member.sa_image_builder_permissions,
    google_project_iam_member.sa_cloudbuild_permissions,
    google_service_account_iam_member.sa_cloudbuild_image_builder_access,
    module.vpc_ai_notebook,
  ]
}
