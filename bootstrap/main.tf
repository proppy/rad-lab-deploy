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
  cloudbuild_sa_project_roles = [
    "roles/notebooks.admin",
    "roles/compute.admin",
    "roles/cloudbuild.builds.editor",
    "roles/artifactregistry.admin",
    "roles/storage.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/serviceusage.serviceUsageAdmin",
  ]
}

resource "google_project_service" "enable_source_repo" {
  project                    = var.project
  service                    = "sourcerepo.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sourcerepo_repository" "rad_lab_deploy_repo" {
  name = "rad-lab-deploy"
  project = var.project

  depends_on = [
    google_project_service.enable_source_repo
  ]
}

resource "google_project_service" "enable_cloud_build" {
  project                    = var.project
  service                    = "cloudbuild.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_service_identity" "sa_cloudbuild_identity" {
  provider = google-beta
  project  = var.project
  service = "cloudbuild.googleapis.com"

  depends_on = [
    google_project_service.enable_cloud_build
  ]
}

resource "google_project_iam_member" "sa_cloudbuild_permissions" {
  for_each = toset(local.cloudbuild_sa_project_roles)
  member   = "serviceAccount:${google_project_service_identity.sa_cloudbuild_identity.email}"
  project  = var.project
  role     = each.value

  depends_on = [
    google_project_service_identity.sa_cloudbuild_identity
  ]
}


resource "google_cloudbuild_trigger" "filename-trigger" {
  project = var.project

  trigger_template {
    branch_name = "^.*$"
    repo_name   = google_sourcerepo_repository.rad_lab_deploy_repo.name
  }

  filename = "cloudbuild.yaml"

  depends_on = [
    google_sourcerepo_repository.rad_lab_deploy_repo,
    google_project_service.enable_cloud_build,
  ]
}

resource "google_project_service" "enable_resource_manager" {
  project                    = var.project
  service                    = "cloudresourcemanager.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_service" "enable_iam" {
  project                    = var.project
  service                    = "iam.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_service" "enable_service_usage" {
  project                    = var.project
  service                    = "serviceusage.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false

  lifecycle {
    prevent_destroy = true
  }
}