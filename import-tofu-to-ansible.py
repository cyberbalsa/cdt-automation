#!/usr/bin/env python3
"""
==============================================================================
OPENTOFU TO ANSIBLE INVENTORY GENERATOR
==============================================================================
This script bridges OpenTofu (infrastructure) and Ansible (configuration).

HOW IT WORKS:
1. Runs 'tofu output -json' to get VM information from OpenTofu
2. Parses the JSON to extract hostnames, IPs, and floating IPs
3. Generates an Ansible inventory file with proper groups

WHY THIS MATTERS FOR CTF:
- OpenTofu creates VMs but doesn't configure them
- Ansible configures VMs but needs to know their IPs
- This script connects the two by translating OpenTofu outputs into
  an Ansible-readable inventory file

MULTI-PROJECT CTF STRUCTURE:
This script creates inventory groups matching the CTF team structure:

  [scoring]              - Grey Team scoring servers
  [windows_dc]           - Blue Team Domain Controller (first Windows VM)
  [blue_windows_members] - Blue Team Windows member servers
  [blue_linux_members]   - Blue Team Linux servers
  [red_team]             - Red Team Kali attack VMs

Group hierarchies for convenience:
  [windows:children]     - All Windows VMs (DC + members)
  [blue_team:children]   - All Blue Team VMs (Windows + Linux)
  [linux_members:children] - All Linux VMs (Blue Linux + Red Kali)

USAGE:
  python3 import-tofu-to-ansible.py [tofu_dir] [ansible_dir] [inventory_file]

EXAMPLES:
  python3 import-tofu-to-ansible.py
  python3 import-tofu-to-ansible.py opentofu ansible inventory/production.ini

==============================================================================
"""

import json
import subprocess
import sys
import os
from pathlib import Path


def get_tofu_output(tofu_dir='opentofu'):
    """
    Get OpenTofu output in JSON format from specified directory.

    This runs 'tofu output -json' which returns all outputs defined in
    outputs.tf as a JSON object. Each output has a 'value' key containing
    the actual data.

    Args:
        tofu_dir: Directory containing OpenTofu configuration files

    Returns:
        dict: Parsed JSON output from OpenTofu
    """
    original_dir = os.getcwd()

    try:
        # Change to OpenTofu directory (tofu output only works from there)
        os.chdir(tofu_dir)

        result = subprocess.run(
            ['tofu', 'output', '-json'],
            capture_output=True,
            text=True,
            check=True
        )

        return json.loads(result.stdout)

    except FileNotFoundError:
        print(f"Error: Directory '{tofu_dir}' not found", file=sys.stderr)
        print("Make sure you're running this from the project root directory.", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error running tofu output: {e}", file=sys.stderr)
        print("\nPossible causes:", file=sys.stderr)
        print("  - OpenTofu not initialized (run: cd opentofu && tofu init)", file=sys.stderr)
        print("  - No infrastructure deployed (run: tofu apply)", file=sys.stderr)
        print("  - Credentials not loaded (run: source app-cred-openrc.sh)", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON output: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Always return to original directory
        os.chdir(original_dir)


def create_inventory(tofu_data, ansible_dir='ansible', inventory_filename='inventory/production.ini'):
    """
    Create Ansible inventory file from OpenTofu output data.

    This creates an INI-format inventory file that Ansible uses to know:
    - Which hosts exist
    - How to connect to them (IP, credentials)
    - Which groups they belong to

    Args:
        tofu_data: Dictionary from get_tofu_output()
        ansible_dir: Directory to create inventory in
        inventory_filename: Path within ansible_dir for the inventory file
    """

    # Create ansible directory if it doesn't exist
    Path(ansible_dir).mkdir(parents=True, exist_ok=True)

    # Create full path and ensure parent directories exist
    output_path = Path(ansible_dir) / inventory_filename
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # ===========================================================================
    # EXTRACT DATA FROM OPENTOFU OUTPUTS
    # ===========================================================================
    # Each output is a dict with 'value' key containing the actual data.
    # We use .get() with empty list default to handle missing outputs gracefully.

    # Scoring servers (Grey Team)
    scoring_names = tofu_data.get('scoring_names', {}).get('value', [])
    scoring_ips = tofu_data.get('scoring_ips', {}).get('value', [])
    scoring_floating_ips = tofu_data.get('scoring_floating_ips', {}).get('value', [])

    # Blue Team Windows VMs
    blue_windows_names = tofu_data.get('blue_windows_names', {}).get('value', [])
    blue_windows_ips = tofu_data.get('blue_windows_ips', {}).get('value', [])
    blue_windows_floating_ips = tofu_data.get('blue_windows_floating_ips', {}).get('value', [])

    # Blue Team Linux VMs
    blue_linux_names = tofu_data.get('blue_linux_names', {}).get('value', [])
    blue_linux_ips = tofu_data.get('blue_linux_ips', {}).get('value', [])
    blue_linux_floating_ips = tofu_data.get('blue_linux_floating_ips', {}).get('value', [])

    # Red Team Kali VMs
    red_kali_names = tofu_data.get('red_kali_names', {}).get('value', [])
    red_kali_ips = tofu_data.get('red_kali_ips', {}).get('value', [])
    red_kali_floating_ips = tofu_data.get('red_kali_floating_ips', {}).get('value', [])

    # ===========================================================================
    # SERVICE CONFIGURATION
    # ===========================================================================
    # Read service-to-host mappings from OpenTofu output.
    # Empty lists get expanded to default hosts based on OS type.

    service_hosts = tofu_data.get('service_hosts', {}).get('value', {})

    # Build lookup sets for default expansion
    all_linux_hosts = set(scoring_names + blue_linux_names)
    all_windows_hosts = set(blue_windows_names)
    all_hosts = all_linux_hosts | all_windows_hosts

    # Expand empty service lists to defaults
    expanded_services = {}
    for service, hosts in service_hosts.items():
        if hosts:  # Explicit host list provided
            expanded_services[service] = hosts
        elif service == 'ping':
            expanded_services[service] = list(all_hosts)
        elif service in ('ssh',):
            expanded_services[service] = list(all_linux_hosts)
        elif service in ('winrm', 'rdp'):
            expanded_services[service] = list(all_windows_hosts)
        else:
            expanded_services[service] = []  # No default for other services

    # Build reverse mapping: hostname -> list of services
    host_to_services = {}
    for service, hosts in expanded_services.items():
        for host in hosts:
            if host not in host_to_services:
                host_to_services[host] = []
            host_to_services[host].append(service)

    # Sort services for consistent output
    for host in host_to_services:
        host_to_services[host].sort()

    with open(output_path, 'w') as f:
        # =====================================================================
        # INVENTORY FILE HEADER
        # =====================================================================
        f.write("# ===========================================================================\n")
        f.write("# ANSIBLE INVENTORY - AUTO-GENERATED FROM OPENTOFU\n")
        f.write("# ===========================================================================\n")
        f.write("# DO NOT EDIT MANUALLY - Changes will be overwritten!\n")
        f.write("# To regenerate: python3 import-tofu-to-ansible.py\n")
        f.write("#\n")
        f.write("# CTF TEAM STRUCTURE:\n")
        f.write("#   - Grey Team (scoring): Competition infrastructure\n")
        f.write("#   - Blue Team (windows_dc, blue_*): Defenders\n")
        f.write("#   - Red Team (red_team): Attackers\n")
        f.write("# ===========================================================================\n\n")

        # =====================================================================
        # SCORING SERVERS (Grey Team)
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# SCORING SERVERS (Grey Team)\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# Grey Team runs the competition: scoring engine, monitoring, infrastructure.\n")
        f.write("[scoring]\n")
        for name, floating_ip, internal_ip in zip(scoring_names, scoring_floating_ips, scoring_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
        f.write("\n")

        # =====================================================================
        # BLUE TEAM WINDOWS VMS
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# BLUE TEAM WINDOWS VMS\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# Windows VMs for Blue Team to defend. First VM is Domain Controller.\n")
        f.write("[blue_windows]\n")
        for name, floating_ip, internal_ip in zip(blue_windows_names, blue_windows_floating_ips, blue_windows_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
        f.write("\n")

        # =====================================================================
        # BLUE TEAM LINUX VMS
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# BLUE TEAM LINUX VMS\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# Linux servers for Blue Team to defend (web, database, etc.)\n")
        f.write("[blue_linux]\n")
        for name, floating_ip, internal_ip in zip(blue_linux_names, blue_linux_floating_ips, blue_linux_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
        f.write("\n")

        # =====================================================================
        # RED TEAM KALI VMS
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# RED TEAM KALI VMS\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# Kali attack machines for Red Team. Pre-loaded with pentesting tools.\n")
        f.write("[red_team]\n")
        for name, floating_ip, internal_ip in zip(red_kali_names, red_kali_floating_ips, red_kali_ips):
            f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip}\n")
        f.write("\n")

        # =====================================================================
        # ROLE-BASED GROUPS
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# ROLE-BASED GROUPS\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# These groups organize VMs by their role in the domain.\n\n")

        # Domain Controller (first Blue Windows VM)
        f.write("# Domain Controller - the first Blue Windows VM\n")
        f.write("[windows_dc]\n")
        if blue_windows_names:
            f.write(f"{blue_windows_names[0]}\n")
        f.write("\n")

        # Windows member servers (all Blue Windows except first)
        f.write("# Windows member servers (domain members, not DC)\n")
        f.write("[blue_windows_members]\n")
        for name in blue_windows_names[1:]:
            f.write(f"{name}\n")
        f.write("\n")

        # Linux members (Blue Linux VMs that join the domain)
        f.write("# Linux domain members (join Active Directory)\n")
        f.write("[blue_linux_members]\n")
        for name in blue_linux_names:
            f.write(f"{name}\n")
        f.write("\n")

        # =====================================================================
        # GROUP HIERARCHIES (using :children)
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# GROUP HIERARCHIES\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# :children syntax creates parent groups containing other groups.\n")
        f.write("# This allows running playbooks against broad categories.\n\n")

        # All Windows VMs (DC + members)
        f.write("# All Windows VMs (for Windows-specific playbooks)\n")
        f.write("[windows:children]\n")
        f.write("windows_dc\n")
        f.write("blue_windows_members\n")
        f.write("\n")

        # All Blue Team VMs
        f.write("# All Blue Team VMs (for Blue Team configuration)\n")
        f.write("[blue_team:children]\n")
        f.write("blue_windows\n")
        f.write("blue_linux\n")
        f.write("\n")

        # All Linux VMs (Blue + Red - useful for common Linux config)
        f.write("# All Linux VMs (for Linux-specific playbooks)\n")
        f.write("[linux_members:children]\n")
        f.write("blue_linux_members\n")
        f.write("red_team\n")
        f.write("scoring\n")
        f.write("\n")

        # =====================================================================
        # SERVICE GROUPS
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# SERVICE GROUPS (auto-generated from OpenTofu service_hosts)\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# These groups are created from the service_hosts variable in variables.tf.\n")
        f.write("# Use them to target playbooks: ansible-playbook playbooks/setup-web.yml\n")
        f.write("# The playbook automatically runs against hosts in the [web] group.\n\n")

        # Write each service group
        for service in sorted(expanded_services.keys()):
            hosts = expanded_services[service]
            if hosts:  # Only write groups that have hosts
                f.write(f"[{service}]\n")
                for host in sorted(hosts):
                    f.write(f"{host}\n")
                f.write("\n")

        # All VMs in the competition
        f.write("# All VMs in the CTF\n")
        f.write("[all_vms:children]\n")
        f.write("scoring\n")
        f.write("blue_team\n")
        f.write("red_team\n")
        f.write("\n")

        # =====================================================================
        # GROUP VARIABLES
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# GROUP VARIABLES\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# Connection settings for each group. These can be overridden in group_vars/\n\n")

        # Scoring server variables (Linux)
        f.write("[scoring:vars]\n")
        f.write("ansible_user=cyberrange\n")
        f.write("ansible_password=Cyberrange123!\n")
        f.write("ansible_python_interpreter=/usr/bin/python3\n")
        f.write("\n")

        # Blue Linux variables
        f.write("[blue_linux:vars]\n")
        f.write("ansible_user=cyberrange\n")
        f.write("ansible_password=Cyberrange123!\n")
        f.write("ansible_python_interpreter=/usr/bin/python3\n")
        f.write("\n")

        # Red Team variables (Kali default user is 'kali')
        f.write("[red_team:vars]\n")
        f.write("ansible_user=cyberrange\n")
        f.write("ansible_password=Cyberrange123!\n")
        f.write("ansible_python_interpreter=/usr/bin/python3\n")
        f.write("# Note: Kali may use 'kali' as default user depending on image\n")
        f.write("\n")

        # Blue Windows variables (WinRM connection)
        f.write("[blue_windows:vars]\n")
        f.write("ansible_user=cyberrange\n")
        f.write("ansible_password=Cyberrange123!\n")
        f.write("ansible_connection=winrm\n")
        f.write("ansible_winrm_transport=ntlm\n")
        f.write("ansible_winrm_server_cert_validation=ignore\n")
        f.write("ansible_winrm_proxy=socks5h://ssh.cyberrange.rit.edu:1080\n")
        f.write("# WinRM uses SOCKS proxy through jump host for access\n")
        f.write("\n")

        # =====================================================================
        # USAGE EXAMPLES
        # =====================================================================
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# USAGE EXAMPLES\n")
        f.write("# ---------------------------------------------------------------------------\n")
        f.write("# Run playbook on all Blue Team VMs:\n")
        f.write("#   ansible-playbook -i inventory/production.ini playbooks/site.yml --limit blue_team\n")
        f.write("#\n")
        f.write("# Run playbook on Domain Controller only:\n")
        f.write("#   ansible-playbook -i inventory/production.ini playbooks/setup-domain-controller.yml --limit windows_dc\n")
        f.write("#\n")
        f.write("# Test connectivity to all Windows VMs:\n")
        f.write("#   ansible windows -i inventory/production.ini -m win_ping\n")
        f.write("#\n")
        f.write("# Test connectivity to Red Team VMs:\n")
        f.write("#   ansible red_team -i inventory/production.ini -m ping\n")
        f.write("# ---------------------------------------------------------------------------\n")

    print(f"Inventory file created: {output_path}")
    print(f"\nSummary:")
    print(f"  Scoring servers:      {len(scoring_names)}")
    print(f"  Blue Windows VMs:     {len(blue_windows_names)} (1 DC + {len(blue_windows_names)-1} members)")
    print(f"  Blue Linux VMs:       {len(blue_linux_names)}")
    print(f"  Red Team Kali VMs:    {len(red_kali_names)}")
    print(f"  Total VMs:            {len(scoring_names) + len(blue_windows_names) + len(blue_linux_names) + len(red_kali_names)}")


def main():
    """
    Main entry point for the inventory generator.

    Command line arguments:
      1. tofu_dir:          Directory containing OpenTofu files (default: 'opentofu')
      2. ansible_dir:       Directory to create inventory in (default: 'ansible')
      3. inventory_filename: Inventory file path within ansible_dir (default: 'inventory/production.ini')
    """
    # Parse command line arguments
    tofu_dir = sys.argv[1] if len(sys.argv) > 1 else 'opentofu'
    ansible_dir = sys.argv[2] if len(sys.argv) > 2 else 'ansible'
    inventory_filename = sys.argv[3] if len(sys.argv) > 3 else 'inventory/production.ini'

    print("=" * 70)
    print("OpenTofu to Ansible Inventory Generator")
    print("=" * 70)
    print(f"\nFetching OpenTofu output from '{tofu_dir}' directory...")

    tofu_data = get_tofu_output(tofu_dir)

    print(f"Creating Ansible inventory in '{ansible_dir}/{inventory_filename}'...")
    create_inventory(tofu_data, ansible_dir, inventory_filename)

    print("\nDone! You can now run Ansible playbooks against the inventory.")
    print("Example: cd ansible && ansible-playbook playbooks/site.yml")


if __name__ == '__main__':
    main()
