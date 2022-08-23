# rad-lab-deploy bootstrap

- Ensure that the following roles are assigned to the service account used to authenticate with Terraform:
    - `roles/source.admin` (Source Repository Administrator)
    - `roles/cloudbuild.builds.editor` (Cloud Build Editor)
    - `roles/resourcemanager.projectIamAdmin` (Project IAM Admin)
    - `roles/serviceusage.serviceUsageAdmin` (Service Usage Admin)
- `terraform init`
- `terraform plan -var project=$PROJECT_ID`
- `terraform apply -var project=$PROJECT_ID`
