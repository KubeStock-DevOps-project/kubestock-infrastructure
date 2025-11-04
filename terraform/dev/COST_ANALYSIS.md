# KubeStock Cost Breakdown & Optimization Guide

## 💰 Detailed Monthly Cost Estimate

### Compute Resources

| Resource | Type | Hours/Month | Unit Cost | Monthly Cost | Notes |
|----------|------|-------------|-----------|--------------|-------|
| Bastion Host | t3.micro | 730 | $0.0104/hr | **$7.59** | Always-on |
| Control Plane | t3.medium | 730 | $0.0416/hr | **$30.37** | Always-on |
| Worker Node (1x) | t3.large | 730 | $0.0832/hr | **$60.74** | Scalable to 2 |
| Worker Node (2x) | t3.large | 730 | $0.0832/hr | **$60.74** | When scaled |
| **Compute Subtotal** | | | | **$98.70 - $159.44** | |

### Storage (EBS)

| Resource | Size | Cost/GB-month | Monthly Cost | Notes |
|----------|------|---------------|--------------|-------|
| Bastion Root | 8 GB | $0.10 | **$0.80** | gp3 volume |
| Control Plane Root | 30 GB | $0.10 | **$3.00** | gp3 volume |
| Worker Root (1x) | 50 GB | $0.10 | **$5.00** | gp3 volume |
| Worker Root (2x) | 50 GB | $0.10 | **$5.00** | When scaled |
| **Storage Subtotal** | | | | **$8.80 - $13.80** | |

### Database (RDS)

| Resource | Type | Configuration | Monthly Cost | Notes |
|----------|------|---------------|--------------|-------|
| RDS PostgreSQL | db.t4g.medium | 2 vCPU, 4GB RAM | **$49.64** | Single-AZ |
| RDS Storage | gp3 | 20 GB | **$2.30** | With autoscaling |
| Backup Storage | 20 GB | First 20GB free | **$0.00** | 7-day retention |
| **Database Subtotal** | | | | **$51.94** | |

### Networking

| Resource | Type | Monthly Cost | Notes |
|----------|------|--------------|-------|
| NAT Gateway | Single NAT | **$32.40** | 730 hours × $0.045/hr |
| NAT Data Processing | Estimated | **$10.00** | ~100 GB × $0.045/GB |
| Network Load Balancer | NLB | **$16.20** | 730 hours × $0.0225/hr |
| NLB LCU Hours | Estimated | **$5.00** | Light usage |
| Data Transfer Out | Estimated | **$20.00** | ~200 GB × $0.09/GB |
| **Networking Subtotal** | | | | **$83.60** | |

### Managed Services

| Resource | Type | Monthly Cost | Notes |
|----------|------|--------------|-------|
| Cognito User Pool | First 50k MAU | **$0.00** | Free tier |
| CloudWatch Logs | Light usage | **$5.00** | Estimated |
| **Managed Services Subtotal** | | | | **$5.00** | |

## 📊 Total Cost Summary

| Scenario | Monthly Cost | Annual Cost |
|----------|--------------|-------------|
| **Minimal (1 Worker)** | **$248.04** | $2,976 |
| **Average (1 Worker + Data)** | **$280-320** | $3,360-3,840 |
| **Scaled (2 Workers)** | **$330-370** | $3,960-4,440 |
| **Budget Ceiling** | **$800** | $9,600 |
| **Remaining Budget** | **$480-520** | $5,760-6,240 |

> ✅ **Conclusion**: The infrastructure is well within the $800/month budget with **60-65% headroom** for additional services, development activities, or unexpected costs.

---

## 🎯 Cost Optimization Strategies

### Already Implemented ✅

1. **Single-AZ Deployment**
   - Savings: ~40% on NAT, RDS, data transfer
   - Trade-off: No high availability

2. **Single NAT Gateway**
   - Savings: $32.40/month (vs 3 NATs = $97.20)
   - Trade-off: Single point of failure

3. **Burstable Instance Types**
   - t3.micro, t3.medium, t3.large
   - Savings: ~50% vs dedicated instances
   - Trade-off: Burst credits for CPU

4. **Conservative Auto Scaling**
   - Min=1, Desired=1, Max=2
   - Savings: Only scale when needed
   - Trade-off: Manual scaling may be needed

5. **Single-AZ RDS**
   - Savings: ~50% vs Multi-AZ
   - Trade-off: No automatic failover

6. **No Application Load Balancer**
   - Using NLB instead
   - Savings: $18/month + data processing
   - Trade-off: Less features (no WAF, path routing)

### Additional Optimizations 💡

#### For Non-Production Hours

```hcl
# Stop instances during non-working hours
# Mon-Fri 8am-6pm = ~200 hours/month vs 730

# Example savings:
# Worker Node: $60.74 → $16.58 (73% savings)
# Control Plane: $30.37 → $8.29 (73% savings)
```

**Implementation:**
```bash
# Stop instances at night (Lambda + EventBridge)
aws lambda create-function --function-name stop-kubestock-instances
aws events put-rule --schedule-expression "cron(0 22 ? * MON-FRI *)"
```

**Monthly Savings**: ~$65-95

#### Use Spot Instances for Workers

```hcl
resource "aws_autoscaling_group" "workers" {
  # Add spot instances
  mixed_instances_policy {
    instances_distribution {
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "lowest-price"
    }
  }
}
```

**Savings**: 60-70% on worker node costs (~$40/month)

#### Reduce RDS Size

```hcl
# If database load is light
instance_class = "db.t4g.micro"  # Instead of db.t4g.medium
# Savings: ~$25/month
```

#### Disable RDS Backups (Dev Only)

```hcl
backup_retention_period = 0
# Savings: ~$5-10/month
```

⚠️ **WARNING**: Only for truly disposable dev environments!

#### Use VPC Endpoints

```hcl
# Avoid NAT for AWS services
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.kubestock_vpc.id
  service_name = "com.amazonaws.us-east-1.s3"
}
```

**Savings**: ~$5-15/month in NAT data processing

---

## 📈 Cost Scaling Scenarios

### Scenario 1: Add More Workers

| Workers | Compute Cost | Total Cost | Change |
|---------|--------------|------------|--------|
| 1 | $98.70 | $248 | Baseline |
| 2 | $159.44 | $309 | +$61 |
| 3 | $220.18 | $370 | +$61 |
| 4 | $280.92 | $431 | +$61 |
| 5 | $341.66 | $492 | +$61 |

**Max Workers @ $800 Budget**: ~10 workers (compute only)

### Scenario 2: Add More Storage

| Storage | Cost/Month | Notes |
|---------|------------|-------|
| +100GB EBS | $10 | Per worker |
| +100GB RDS | $11.50 | gp3 storage |
| +1TB S3 | $23 | Standard storage |

### Scenario 3: Enable Multi-AZ

| Change | Cost Impact | New Total |
|--------|-------------|-----------|
| Multi-AZ RDS | +$50 | $298 |
| 2 More NAT Gateways | +$65 | $363 |
| Cross-AZ Data Transfer | +$20 | $383 |
| **Total Multi-AZ** | **+$135** | **~$385** |

Still within budget, but reduces headroom to ~$415/month.

---

## 🔍 Cost Monitoring & Alerts

### Set Up AWS Budgets

```bash
aws budgets create-budget --account-id YOUR_ACCOUNT_ID \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

**budget.json:**
```json
{
  "BudgetName": "kubestock-dev-monthly",
  "BudgetLimit": {
    "Amount": "800",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

### Recommended Alert Thresholds

| Threshold | Action |
|-----------|--------|
| $600 (75%) | Email notification |
| $700 (87.5%) | Email + SMS notification |
| $750 (93.75%) | Investigate immediately |
| $800 (100%) | Auto-stop non-essential resources |

### Cost Explorer Queries

```bash
# This month's cost by service
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# EC2 costs only
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://ec2-filter.json
```

---

## 💡 Best Practices

1. **Tag Everything**
   - All resources have `Project = "KubeStock"` and `Environment = "dev"`
   - Use Cost Allocation Tags in AWS Billing

2. **Review Monthly**
   - Check Cost Explorer on the 1st of each month
   - Look for unexpected spikes

3. **Clean Up Unused Resources**
   - Terminate stopped instances
   - Delete unattached EBS volumes
   - Clean up old snapshots

4. **Use Free Tier**
   - CloudWatch: 10 custom metrics free
   - Cognito: 50k MAU free
   - NAT: Consider NAT instance (free, but more management)

5. **Reserved Instances (Long-Term)**
   - If committed for 1+ years: ~30-40% savings
   - Recommendation: Wait until infrastructure is stable

---

## 📉 Emergency Cost Reduction Plan

If costs exceed budget:

### Level 1: Quick Wins (~$50-100 savings)
- [ ] Stop worker nodes overnight
- [ ] Reduce RDS to db.t4g.micro
- [ ] Delete CloudWatch logs older than 7 days

### Level 2: Structural Changes (~$100-150 savings)
- [ ] Move to single combined node (no workers)
- [ ] Use RDS Aurora Serverless v2 (if lower workload)
- [ ] Replace NAT Gateway with NAT instance

### Level 3: Nuclear Option (Pause Development)
- [ ] Stop all EC2 instances
- [ ] Snapshot RDS and delete
- [ ] Keep only VPC, security groups, IAM roles
- Monthly cost: ~$40 (NAT + storage)

---

## 🎓 Cost Optimization Resources

- [AWS Cost Optimization Guide](https://aws.amazon.com/pricing/cost-optimization/)
- [AWS Well-Architected Framework - Cost Optimization](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html)
- [EC2 Instance Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- [RDS Pricing Calculator](https://calculator.aws/)

---

**Last Updated**: November 2025  
**Estimated Cost Accuracy**: ±10% based on us-east-1 pricing
