# Multi-Project Grey Team Infrastructure Design

## Overview

Refactor the existing single-project OpenTofu configuration to support a grey team scenario with three OpenStack projects:

- **Main project (cdtalpha)**: Network infrastructure, RBAC policies, scoring server(s)
- **Blue team project (cdtalpha-cdtbravo)**: Windows DC, Windows members, Linux members
- **Red team project (cdtalpha-cdtcharlie)**: Kali attack boxes

All projects share a single network (10.10.10.0/24) via OpenStack RBAC policies.

## Architecture

### Network Topology

```
                     INTERNET
                         |
                    [MAIN-NAT]        External network (100.65.0.0/16)
                         |
                   [cdt_router]       Router (main project)
                         |
                   [cdt_subnet]       10.10.10.0/24 (main project)
                         |
        +----------------+----------------+----------------+
        |                |                |                |
   [Scoring]        [Blue Team]      [Blue Team]      [Red Team]
   10.10.10.1x      Windows          Linux            Kali
                    10.10.10.2x      10.10.10.3x      10.10.10.4x
```

### IP Address Scheme

| Range | Purpose | Project |
|-------|---------|---------|
| 10.10.10.11-19 | Scoring servers | cdtalpha (main) |
| 10.10.10.21-29 | Blue Windows (DC at .21) | cdtalpha-cdtbravo |
| 10.10.10.31-39 | Blue Linux | cdtalpha-cdtbravo |
| 10.10.10.41-49 | Red Kali boxes | cdtalpha-cdtcharlie |

## Provider Configuration

Three provider aliases using the same credentials with different `tenant_id`:

```hcl
provider "openstack" {
  alias     = "main"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.main_project_id
}

provider "openstack" {
  alias     = "blue"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.blue_project_id
}

provider "openstack" {
  alias     = "red"
  auth_url  = "https://openstack.cyberrange.rit.edu:5000/v3"
  region    = "CyberRange"
  tenant_id = var.red_project_id
}
```

## RBAC Network Sharing

Network created in main project, shared via RBAC policies:

```hcl
resource "openstack_networking_rbac_policy_v2" "share_with_blue" {
  provider      = openstack.main
  action        = "access_as_shared"
  object_id     = openstack_networking_network_v2.cdt_net.id
  object_type   = "network"
  target_tenant = var.blue_project_id
}

resource "openstack_networking_rbac_policy_v2" "share_with_red" {
  provider      = openstack.main
  action        = "access_as_shared"
  object_id     = openstack_networking_network_v2.cdt_net.id
  object_type   = "network"
  target_tenant = var.red_project_id
}
```

## New Variables

### Project IDs

| Variable | Default | Description |
|----------|---------|-------------|
| `main_project_id` | `04846fb2e027424d8898953062787b16` | cdtalpha |
| `blue_project_id` | `d25474b0db314855b36e659c777893c1` | cdtalpha-cdtbravo |
| `red_project_id` | `4cba761707eb4606a750fb7b3de3948d` | cdtalpha-cdtcharlie |

### VM Counts

| Variable | Default | Description |
|----------|---------|-------------|
| `scoring_count` | 1 | Scoring servers |
| `blue_windows_count` | 2 | Blue Windows VMs (first is DC) |
| `blue_linux_count` | 2 | Blue Linux VMs |
| `red_kali_count` | 2 | Red Kali boxes |

### Images

| Variable | Default | Description |
|----------|---------|-------------|
| `scoring_image_name` | `Ubuntu2404Desktop` | Scoring server OS |
| `kali_image_name` | `kali-2024` | Red team attack boxes |

### Hostnames

| Variable | Default | Description |
|----------|---------|-------------|
| `blue_windows_hostnames` | `["dc01"]` | Blue Windows custom names |
| `blue_linux_hostnames` | `["webserver"]` | Blue Linux custom names |

## Security Groups

Security groups must be created in each project (no RBAC sharing):

- **Main project**: `scoring_sg` (SSH, HTTP/HTTPS for scoring)
- **Blue project**: `blue_windows_sg`, `blue_linux_sg`
- **Red project**: `red_linux_sg`

## Resource Mapping

### Existing Resources (renamed)

| Old Name | New Name | Project |
|----------|----------|---------|
| `openstack_compute_instance_v2.windows` | `openstack_compute_instance_v2.blue_windows` | blue |
| `openstack_compute_instance_v2.debian` | `openstack_compute_instance_v2.blue_linux` | blue |
| `openstack_networking_secgroup_v2.windows_sg` | `openstack_networking_secgroup_v2.blue_windows_sg` | blue |
| `openstack_networking_secgroup_v2.linux_sg` | `openstack_networking_secgroup_v2.blue_linux_sg` | blue |

### New Resources

| Resource | Project |
|----------|---------|
| `openstack_compute_instance_v2.scoring` | main |
| `openstack_compute_instance_v2.red_kali` | red |
| `openstack_networking_secgroup_v2.scoring_sg` | main |
| `openstack_networking_secgroup_v2.red_linux_sg` | red |
| `openstack_networking_rbac_policy_v2.share_with_blue` | main |
| `openstack_networking_rbac_policy_v2.share_with_red` | main |

## Ansible Inventory Groups

Generated by `import-tofu-to-ansible.py`:

```ini
[scoring]
scoring-1 ansible_host=10.10.10.11 floating_ip=...

[windows_dc]
dc01 ansible_host=10.10.10.21 floating_ip=...

[blue_windows_members]
blue-win-2 ansible_host=10.10.10.22 floating_ip=...

[blue_linux_members]
webserver ansible_host=10.10.10.31 floating_ip=...

[red_team]
red-kali-1 ansible_host=10.10.10.41 floating_ip=...
red-kali-2 ansible_host=10.10.10.42 floating_ip=...

[windows:children]
windows_dc
blue_windows_members

[blue_team:children]
windows_dc
blue_windows_members
blue_linux_members

[linux_members:children]
blue_linux_members
scoring
red_team
```

## Files to Modify

1. `opentofu/main.tf` - Add provider aliases with tenant_id
2. `opentofu/variables.tf` - Add project IDs, counts, images, hostnames
3. `opentofu/network.tf` - Add provider to resources, add RBAC policies
4. `opentofu/security.tf` - Duplicate security groups per project
5. `opentofu/instances.tf` - Refactor VMs by team, add provider references
6. `opentofu/outputs.tf` - Reorganize outputs by team
7. `import-tofu-to-ansible.py` - Generate new inventory groups

## Migration Notes

This is a breaking change. Existing infrastructure will need to be destroyed and recreated:

```bash
cd opentofu
tofu destroy  # Remove existing single-project infra
tofu apply    # Deploy new multi-project infra
cd ..
python3 import-tofu-to-ansible.py  # Regenerate inventory
```

Alternatively, use `tofu state mv` to migrate resources if preserving VMs is required.

## References

- [OpenStack RBAC Policies](https://docs.openstack.org/neutron/latest/admin/config-rbac.html)
- [Terraform OpenStack Provider - RBAC Policy](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_rbac_policy_v2)
