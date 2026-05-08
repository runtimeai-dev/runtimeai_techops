# TOPS-010: Terraform Variables — AWS

## Specification

Create AWS Terraform variables file (`terraform/aws/variables.tf`) defining all cloud-specific inputs for AWS deployment:
- VPC and networking (CIDR, availability zones, subnet configuration)
- EKS cluster (node count, instance types, Kubernetes version)
- RDS PostgreSQL (instance class, storage, backup retention)
- ElastiCache Redis (node type, parameter group)
- EC2 key pair for SSH access
- Environment tags and default labels

## Acceptance Criteria

- [ ] File created at `terraform/aws/variables.tf`
- [ ] Variables include: region (default: us-east-1), environment, cluster_name
- [ ] Networking: vpc_cidr (10.0.0.0/16), availability_zones (default: [us-east-1a, us-east-1b, us-east-1c])
- [ ] Cluster: node_count (default: 3), instance_type (default: t3.large for staging), instance_type_prod (default: m5.2xlarge)
- [ ] Database: db_instance_class (default: db.t3.micro for staging, db.r5.xlarge for prod)
- [ ] Redis: cache_node_type (default: cache.t3.micro staging, cache.r6g.xlarge prod)
- [ ] All sensitive values marked with `sensitive=true`
- [ ] Validation rules: region must match AWS pattern, environment must be in [rt19, rt01, rt02, etc.]
- [ ] Tags variable with default labels (Environment, Owner, CostCenter)
- [ ] Committed to feature branch `TOPS-010-terraform-aws-variables`

## Effort Estimate

2 hours

## Dependencies

Blocked by: None
Blocks: TOPS-011 (AWS backend), TOPS-012 (AWS outputs)

## Implementation Notes

- AWS uses different instance naming than Azure (t3.large vs Standard_D4s_v3)
- Region defaults to us-east-1; can override for other regions (us-west-2, eu-west-1)
- RDS requires multi-AZ for production (parameter: multi_az = true)
- ElastiCache parameter group for Redis 7.x (supports cluster mode)
- SSH key pair must be created in AWS console or via terraform (not auto-generated)

## Verification

```bash
cd terraform/aws
terraform validate
terraform fmt -check
# List all variables
grep "^variable" variables.tf | wc -l
```
