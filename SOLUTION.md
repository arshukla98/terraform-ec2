# Terraform EC2 Deployment - Issue & Solution

## Problem Statement

The pipeline attempts to deploy EC2 instances using Terraform, but it **fails during the "Retrieve Instance Information" stage** when trying to access the `instance_names` output.

### Root Cause

In [outputs.tf](outputs.tf), the following output is defined:

```hcl
output "instance_names" {
  description = "Names of the EC2 instances"
  value       = aws_instance.web_server[*].instance_name
}
```

**The issue:** The `aws_instance` resource does **not have an `instance_name` attribute**. This attribute does not exist in the AWS Terraform provider.

### Error Pattern

When the pipeline runs the Terraform Apply stage successfully, the subsequent "Retrieve Instance Information" stage fails with:

```
Error: Unsupported attribute
  on outputs.tf line XX, in output "instance_names":
   XX:   value = aws_instance.web_server[*].instance_name
        
An output value expression must use the value of a managed resource that was
successfully applied, or reference an output value, local value, or variable.
The referenced resource "aws_instance.web_server" does not have an attribute named "instance_name".
```

---

## Solution

### Available Attributes for `aws_instance`

The `aws_instance` resource provides the following useful attributes:

| Attribute | Description |
|-----------|-------------|
| `id` | The instance ID |
| `private_ip` | Private IP address |
| `public_ip` | Public IP address (if applicable) |
| `instance_state` | Instance state (running, stopped, etc.) |
| `tags` | Tags applied to the instance |
| `tags.Name` | The "Name" tag value |

### Recommended Fix

**Option 1: Use the Name tag** (Recommended)

Replace the broken output with:

```hcl
output "instance_names" {
  description = "Names of the EC2 instances"
  value       = aws_instance.web_server[*].tags.Name
}
```

This retrieves the "Name" tag that was assigned in `main.tf`:

```hcl
tags = {
  Name        = "${var.instance_name}-${count.index + 1}"
  Environment = var.environment
  Index       = count.index
}
```

**Option 2: Use instance IDs** (Alternative)

If you just need to identify instances:

```hcl
output "instance_names" {
  description = "IDs of the EC2 instances"
  value       = aws_instance.web_server[*].id
}
```

---

## Implementation Steps

### Step 1: Fix the Output Definition

Edit [outputs.tf](outputs.tf) and replace the broken `instance_names` output:

**Before (Broken):**
```hcl
output "instance_names" {
  description = "Names of the EC2 instances"
  value       = aws_instance.web_server[*].instance_name
}
```

**After (Fixed):**
```hcl
output "instance_names" {
  description = "Names of the EC2 instances"
  value       = aws_instance.web_server[*].tags.Name
}
```

### Step 2: Re-run Terraform Validation

```bash
terraform validate
```

### Step 3: Re-run Pipeline

Trigger the Jenkins pipeline with `TERRAFORM_ACTION=apply`. The pipeline will now successfully:
1. Create EC2 instances
2. Retrieve and display instance names correctly
3. Archive the Terraform state

---

## Verification

After applying the fix, verify the output by running:

```bash
terraform output instance_names
```

Expected output:
```
[
  "web-server-1",
  "web-server-2"
]
```

---

## Key Takeaway

When working with Terraform outputs, always reference **actual resource attributes** from the provider documentation, not assumed attribute names. The AWS provider's `aws_instance` resource documentation should be consulted for valid attributes.

**Resource Reference:** [Terraform AWS Instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
