# TOPS-012: Terraform Outputs — AWS

## Specification

Create AWS Terraform outputs file (`terraform/aws/outputs.tf`) exporting cluster endpoints, database connections, and resource identifiers for downstream use.

Outputs include:
- EKS cluster endpoint and kubeconfig
- RDS PostgreSQL FQDN and connection string
- ElastiCache Redis endpoint and security group ID
- VPC and subnet IDs
- Security group IDs
- IAM role ARNs
- CloudWatch log group names

## Acceptance Criteria

- [ ] File created at `terraform/aws/outputs.tf`
- [ ] Output: eks_cluster_endpoint (sensitive=true)
- [ ] Output: eks_cluster_name, eks_cluster_id, eks_node_group_id
- [ ] Output: eks_kubeconfig_raw (sensitive=true) — full kubeconfig for kubectl
- [ ] Output: rds_endpoint (FQDN), rds_engine, rds_engine_version
- [ ] Output: rds_connection_string (sensitive=true) — postgres://user:pass@host:5432/db
- [ ] Output: redis_endpoint (host:port), redis_engine_version
- [ ] Output: vpc_id, vpc_cidr, subnet_ids (map of name => id)
- [ ] Output: security_group_ids (map of purpose => id)
- [ ] Output: iam_role_arns (map of role_name => arn)
- [ ] Output: cloudwatch_log_groups (map of service => log_group_name)
- [ ] Output: environment_info summary (region, cluster_name, node_count, instance_type, db_instance, redis_node_type)
- [ ] Committed to feature branch `TOPS-012-terraform-aws-outputs`

## Effort Estimate

1.5 hours

## Dependencies

Blocked by: TOPS-010, TOPS-011
Blocks: Deployment scripts, KubeCTL configuration

## Implementation Notes

- EKS kubeconfig_raw must be base64-decoded before use (AWS SDK requirement)
- RDS connection string uses default port 5432 (PostgreSQL standard)
- Redis endpoint can be used directly in application config (host:port)
- Security group IDs exported to allow inbound rules configuration in dependent resources
- IAM role ARNs used for cross-account access and pod IRSA (IAM Roles for Service Accounts)
- CloudWatch log groups named per service for centralized logging

## Verification

```bash
cd terraform/aws
terraform validate
terraform plan -out=tfplan | grep "^Outputs:"
# Check for sensitive marking on critical outputs
grep "sensitive.*true" outputs.tf
```
