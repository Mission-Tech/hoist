# Vercel Frontend Module

This module creates DNS records for Vercel-hosted frontend applications.

## What It Does

Creates a Route53 CNAME record pointing your custom domain to Vercel's infrastructure.

**Example:**
- Input: `public_app_name = "pantry"`, `domain_cname_value = "cname.vercel-dns.com"`
- In dev: Creates `pantry.missiontechdev.org` → `cname.vercel-dns.com`
- In prod: Creates `pantry.missiontech.org` → `cname.vercel-dns.com`

## Usage

```hcl
module "pantry_frontend" {
  source = "../../hoist/tf/modules/vercel_frontend"

  app                = "pantry"
  env                = var.env
  public_app_name    = "pantry"
  domain_cname_value = "cname.vercel-dns.com"  # Get this from Vercel project settings
}
```

## Variables

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `app` | Name of the application | `string` | Yes |
| `env` | Environment (dev or prod) | `string` | Yes |
| `public_app_name` | Subdomain for the custom domain (e.g., "pantry") | `string` | Yes |
| `domain_cname_value` | Vercel CNAME target from project settings | `string` | Yes |

## Outputs

| Name | Description |
|------|-------------|
| `frontend_fqdn` | The FQDN of the Route53 record (e.g., `pantry.missiontechdev.org`) |

## Setup Process

1. **Deploy this Terraform module** to create the DNS record
2. **In Vercel project settings:**
   - Go to Settings → Domains
   - Add your custom domain (e.g., `pantry.missiontechdev.org`)
   - Vercel will provide you with a CNAME value (e.g., `cname.vercel-dns.com`)
   - Use this value for the `domain_cname_value` variable
3. **Wait for DNS propagation** (usually < 5 minutes)
4. **Verify** by visiting your custom domain

## Notes

- The module reads the primary hosted zone from CoreInfra SSM parameters
- CNAME records have a TTL of 300 seconds (5 minutes)
- The domain will be `{public_app_name}.{primary_domain}` where primary_domain comes from CoreInfra
