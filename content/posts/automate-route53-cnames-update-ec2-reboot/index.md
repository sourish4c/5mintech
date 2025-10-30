---
title: Automate Route 53 Record Updates on EC2 Reboot
description: "Learn how to automatically update your AWS EC2 instance’s public DNS as a CNAME record in Route 53 every time it reboots. Ensure your domain always points to the correct public hostname."
slug: "automate-route53-cnames-update-ec2-reboot"
date: 2023-10-27T10:00:00+05:30
draft: false
categories:
    - "AWS"
    - "DevOps"
tags:
    - "AWS-EC2"
    - "Route 53"
    - "Automation"
    - "IAM"
---

Learn how to automatically update your EC2 instance’s dynamic public DNS as a Route 53 CNAME record on every reboot.
<!--more-->

#### TL;DR - Video Overview
{{< youtube "AEc4fI_vhL0" >}}

### Introduction
Managing dynamic IP addresses for AWS EC2 instances can be a challenge, especially when you need a consistent domain name pointing to your server. Every time an EC2 instance reboots, its public DNS hostname might change, breaking your custom domain CNAME record in Route 53. This tutorial provides a robust solution to automatically update your EC2 instance’s public DNS as a CNAME record in AWS Route 53 upon every reboot, ensuring your services remain accessible without manual intervention.

This guide is perfect for system administrators, DevOps engineers, and developers looking to streamline their AWS infrastructure management.

#### TL;DR - Audio Overview
{{<audio src="audio/automate-route53-cnames-update-ec2-reboot.mp3" caption="Listen to this post instead of reading" >}}

---
### Prerequisites

Before you begin, ensure you have the following in place:

- AWS CLI Installed and Configured: You’ll need the AWS Command Line Interface installed on your EC2 instance or a local machine for testing.
- IAM Role or AWS Credentials: Your EC2 instance must have an attached IAM role or configured AWS credentials with the necessary permissions. We’ll detail the exact policy later in this guide.
- Hosted Zone ID: You need the Hosted Zone ID for your domain (e.g., yourdomain.com). 

You can retrieve this using the AWS CLI:

```bash
aws route53 list-hosted-zones-by-name --dns-name yourdomain.com
```
<mark>**Note:**</mark> Replace `yourdomain.com` with your actual domain name.
This command will return a JSON output containing the Hosted Zone ID.

### Steps to Automate CNAME Updates on EC2 Reboot

#### 1. Create the Script File

We’ll create a simple bash script that leverages the EC2 Instance Metadata Service Version 2 (IMDSv2) to securely fetch the instance’s public DNS and then update the Route 53 CNAME record.

Create a new file named /usr/local/bin/update-route53-cname.sh on your EC2 instance:
```bash
sudo nano /usr/local/bin/update-route53-cname.sh
```

#### 2. Add the Following Script to the Script File

```bash
#!/bin/bash

# Add error handling
set -euo pipefail

# Config
HOSTED_ZONE_ID="ZXXXXXXXXXXXX"  # Replace with your actual Hosted Zone ID retrieved earlier
DOMAIN_NAME="sub.yourdomain.com" # Replace with your custom CNAME, e.g., myapp.yourdomain.com
TTL=300 # Time-to-Live for the DNS record in seconds

# Verify AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Get IMDSv2 token for secure metadata access
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 600")

# Get instance ID using IMDSv2
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

# Get public DNS using IMDSv2
PUBLIC_DNS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-hostname)

# Prepare change batch JSON for Route 53
CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "Update CNAME to current public DNS for $INSTANCE_ID",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN_NAME",
        "Type": "CNAME",
        "TTL": $TTL,
        "ResourceRecords": [
          {
            "Value": "$PUBLIC_DNS"
          }
        ]
      }
    }
  ]
}
EOF
)

# Update Route 53 record using AWS CLI
aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "$CHANGE_BATCH"
```

#### 3. Make the Script Executable

```bash
sudo chmod +x /usr/local/bin/update-route53-cname.sh
```


#### 4. Automate the DNS Update on Reboot with Cron

To ensure the script runs every time your EC2 instance reboots, we’ll add an entry to the root user’s crontab.
Edit Root Crontab

Open the root crontab for editing:
```bash
sudo crontab -e
```

Add the following line to the end of the crontab file. This entry tells cron to execute the script every time the system starts up. It also redirects output to a log file for debugging.

```bash
@reboot /usr/local/bin/update-route53-cname.sh >> /var/log/update-route53-cname.log 2>&1
```
Save and exit the crontab editor.


#### 5. IAM Permissions for Route 53 Updates

For your EC2 instance to be able to modify Route 53 records, it needs appropriate permissions. The most secure way to do this is by attaching an IAM role to the EC2 instance with a minimal policy.
Create and Attach IAM Policy

Create an IAM policy with the following permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListHostedZones",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

Add this policy to an IAM role, and then attach that role to your EC2 instance. 

> The `route53:ChangeResourceRecordSets` permission allows the script to update DNS records, `route53:ListHostedZones` is helpful for verifying the hosted zone, and `ec2:DescribeInstances` is included for broader EC2 metadata access, though the script primarily uses IMDSv2 for instance-specific data.

For more details on Route 53 permissions, refer to the official AWS [documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/access-control-overview.html).


#### 6. Testing and Verification

After setting up the script, cron job, and IAM permissions, you can test the setup:

- Reboot your EC2 instance.
- Check the log file: >> After the instance comes back online, check /var/log/update-route53-cname.log for any errors or success messages.
- Verify Route 53: >> Go to the AWS Route 53 console and check your hosted zone to confirm that the CNAME record for yourdomain.com (or your chosen domain) now points to the correct public DNS of your EC2 instance.
- Test the domain: >> Try accessing your service via sub.yourdomain.com to ensure it resolves correctly.


#### 7. Conclusion

By following these steps, you’ve successfully automated the process of updating your EC2 instance’s CNAME record in Route 53 on every reboot. This eliminates manual intervention, reduces potential downtime, and ensures your custom domain always points to the correct EC2 instance, even if its public DNS changes. This automation is a crucial step towards building more resilient and self-healing cloud infrastructures.

For further exploration, consider how you might extend this script to handle multiple CNAMEs or integrate it into a larger infrastructure-as-code (IaC) solution. 

You might also be interested in our list of guide on [AWS](/tags/aws/).

#### 8. References
- [AWS Route 53 Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
- [AWS CLI Command Reference for Route 53](https://docs.aws.amazon.com/cli/latest/reference/route53/index.html)
- [EC2 Instance Metadata Service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
- [AWS IAM Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/welcome.html)

---
{{< alert "twitter" >}}
Thank you for visiting 5 Minutes Tech. [Follow us](https://x.com/sourish4c) for new Updates 🚀
{{< /alert >}}
