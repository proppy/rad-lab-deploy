# rad-lab-deploy

## first deploy

- [bootstrap](bootstrap/) project
- `gcloud init && git config credential.helper gcloud.sh`
- `git remote add $PROJECT_ID https://source.developers.google.com/p/$PROJECT_ID/r/rad-lab-deploy`
- `git push $PROJECT_ID`

## update with latest rad-lab changes

- `git remote add rad-lab https://github.com/proppy/rad-lab.git`
- `git subtree -P rad-lab pull rad-lab tuning --squash`
- `git push https://source.developers.google.com/p/$PROJECT_ID/r/rad-lab-deploy`
