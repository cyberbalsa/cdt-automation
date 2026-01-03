#!/usr/bin/env python3
import json
import subprocess
import sys
import os
from pathlib import Path

def get_tofu_output(tofu_dir='opentofu'):
    """Get OpenTofu output in JSON format from specified directory"""
    original_dir = os.getcwd()

    try:
        # Change to OpenTofu directory
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
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error running tofu output: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON output: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Always return to original directory
        os.chdir(original_dir)

def create_inventory(tofu_data, ansible_dir='ansible', inventory_filename='inventory.ini'):
    """Create Ansible inventory file in the ansible directory"""

    # Create ansible directory if it doesn't exist
    Path(ansible_dir).mkdir(parents=True, exist_ok=True)

    output_path = Path(ansible_dir) / inventory_filename

    with open(output_path, 'w') as f:
        # Get VM data
        windows_names = tofu_data.get('windows_vm_names', {}).get('value', [])
        windows_ips = tofu_data.get('windows_vm_ips', {}).get('value', [])
        windows_internal_ips = tofu_data.get('windows_vm_internal_ips', {}).get('value', [])

        debian_names = tofu_data.get('debian_vm_names', {}).get('value', [])
        debian_ips = tofu_data.get('debian_vm_ips', {}).get('value', [])
        debian_internal_ips = tofu_data.get('debian_vm_internal_ips', {}).get('value', [])

        # Windows VMs section (first so windows[0] is the domain controller)
        f.write("[windows]\n")
        for name, ip, internal_ip in zip(windows_names, windows_ips, windows_internal_ips):
            f.write(f"{name} ansible_host={ip} internal_ip={internal_ip}\n")

        # Debian VMs section
        f.write("\n[debian]\n")
        for name, ip, internal_ip in zip(debian_names, debian_ips, debian_internal_ips):
            f.write(f"{name} ansible_host={ip} internal_ip={internal_ip}\n")

        # Dynamic group: windows_dc (first Windows host)
        f.write("\n[windows_dc]\n")
        if windows_names:
            f.write(f"{windows_names[0]}\n")

        # Dynamic group: windows_members (all Windows hosts except first)
        f.write("\n[windows_members]\n")
        for name in windows_names[1:]:
            f.write(f"{name}\n")

        # Dynamic group: linux_members (all Debian hosts)
        f.write("\n[linux_members]\n")
        for name in debian_names:
            f.write(f"{name}\n")

        # Group variables
        f.write("\n[debian:vars]\n")
        f.write("ansible_user=cyberrange\n")
        f.write("ansible_password=Cyberrange123!\n")
        f.write("ansible_python_interpreter=/usr/bin/python3\n")

        f.write("\n[windows:vars]\n")
        f.write("ansible_user=cyberrange\n")
        f.write("ansible_password=Cyberrange123!\n")
        f.write("ansible_connection=winrm\n")
        f.write("ansible_winrm_transport=ntlm\n")
        f.write("ansible_winrm_server_cert_validation=ignore\n")
        f.write("ansible_winrm_proxy=socks5h://ssh.cyberrange.rit.edu:1080\n")

        # All VMs group
        f.write("\n[all_vms:children]\n")
        f.write("debian\n")
        f.write("windows\n")

    print(f"Inventory file created: {output_path}")

def main():
    # Parse command line arguments
    tofu_dir = sys.argv[1] if len(sys.argv) > 1 else 'opentofu'
    ansible_dir = sys.argv[2] if len(sys.argv) > 2 else 'ansible'
    inventory_filename = sys.argv[3] if len(sys.argv) > 3 else 'inventory.ini'

    print(f"Fetching OpenTofu output from '{tofu_dir}' directory...")
    tofu_data = get_tofu_output(tofu_dir)

    print(f"Creating Ansible inventory in '{ansible_dir}' directory...")
    create_inventory(tofu_data, ansible_dir, inventory_filename)

if __name__ == '__main__':
    main()
