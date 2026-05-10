# TOPS-011: Terraform Backend Configuration — AWS

## Specification

Create AWS Terraform backend configuration (`terraform/aws/backend.tf`) storing remote state in S3 with locking via DynamoDB.

Backend provides:
- Remote state stored in S3 (with versioning enabled)
- State locking via DynamoDB (prevents concurrent applies)
- Encryption at rest (S3 default AWS KMS)
- Encryption in transit (HTTPS)
- AWS provider configuration with default regions and assume-role support

## Acceptance Criteria

- [ ] File created at `terraform/aws/backend.tf`
- [ ] Backend type: s3 with bucket `runtimeai-terraform-state-<account-id>`
- [ ] Key: `aws/rt19.tfstate` (can override per environment)
- [ ] S3 versioning enabled
- [ ] DynamoDB table: `runtimeai-terraform-lock` with `LockID` primary key
- [ ] Encryption: enabled (uses AWS KMS default key)
- [ ] Access logging enabled (optional: log to S3 bucket)
- [ ] AWS provider configured with region variable
- [ ] Support for assume-role (cross-account deployments)
- [ ] Required version: terraform >= 1.5
- [ ] Committed to feature branch `TOPS-011-terraform-aws-backend`

## Effort Estimate

1.5 hours

## Dependencies

Blocked by: TOPS-010 (variables)
Blocks: TOPS-012 (outputs)

## Implementation Notes

- S3 bucket and DynamoDB table must be created manually before terraform init (security best practice)
- Bucket name must be globally unique; use account ID suffix to guarantee uniqueness
- DynamoDB table requires on-demand billing or provisioned capacity (1 read, 1 write unit sufficient)
- For cross-account deployments, use role_arn under assume_role block
- State file contains all resource details; ensure bucket has restricted access (Block Public Access)

## Verification

```bash
cd terraform/aws
terraform fmt -check backend.tf
# Dry run (requires S3/DynamoDB pre-created)
# terraform init -backend=false
# terraform plan -out=tfplan
grep "backend" backend.tf | head -1
```
