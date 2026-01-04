#!/usr/bin/env python3
"""
Generate RDP files for all hosts in the Ansible inventory.
Uses RD Gateway at rdp.cyberrange.rit.edu for secure remote access.
"""

import os
import re
import sys
from pathlib import Path


def parse_inventory(inventory_path):
    """Parse Ansible inventory file and extract host information."""
    hosts = []

    try:
        with open(inventory_path, 'r') as f:
            for line in f:
                line = line.strip()
                # Match lines like: dc01 ansible_host=100.65.4.123 internal_ip=10.10.10.21
                match = re.match(r'^(\S+)\s+ansible_host=([0-9.]+)', line)
                if match:
                    hostname = match.group(1)
                    floating_ip = match.group(2)
                    hosts.append({
                        'name': hostname,
                        'ip': floating_ip
                    })
    except FileNotFoundError:
        print(f"Error: Inventory file not found at {inventory_path}")
        print("Please run 'python3 import-tofu-to-ansible.py' first to generate the inventory.")
        sys.exit(1)

    return hosts


def generate_rdp_file(hostname, floating_ip, output_dir):
    """Generate an RDP file with RD Gateway configuration."""
    rdp_content = f"""screen mode id:i:2
use multimon:i:0
desktopwidth:i:1920
desktopheight:i:1080
session bpp:i:32
winposstr:s:0,3,0,0,800,600
compression:i:1
keyboardhook:i:2
audiocapturemode:i:0
videoplaybackmode:i:1
connection type:i:7
networkautodetect:i:1
bandwidthautodetect:i:1
displayconnectionbar:i:1
enableworkspacereconnect:i:0
disable wallpaper:i:0
allow font smoothing:i:0
allow desktop composition:i:0
disable full window drag:i:1
disable menu anims:i:1
disable themes:i:0
disable cursor setting:i:0
bitmapcachepersistenable:i:1
full address:s:{floating_ip}
audiomode:i:0
redirectprinters:i:1
redirectcomports:i:0
redirectsmartcards:i:1
redirectclipboard:i:1
redirectposdevices:i:0
autoreconnection enabled:i:1
authentication level:i:2
prompt for credentials:i:0
negotiate security layer:i:1
remoteapplicationmode:i:0
alternate shell:s:
shell working directory:s:
gatewayhostname:s:rdp.cyberrange.rit.edu
gatewayusagemethod:i:1
gatewayprofileusagemethod:i:1
gatewaycredentialssource:i:0
username:s:CDT\\cyberrange
drivestoredirect:s:
"""

    output_path = output_dir / f"{hostname}.rdp"
    with open(output_path, 'w', newline='\r\n') as f:
        f.write(rdp_content)

    print(f"Generated: {output_path}")


def main():
    # Paths
    script_dir = Path(__file__).parent
    inventory_path = script_dir / "ansible" / "inventory" / "production.ini"
    output_dir = script_dir / "RDP"

    # Allow custom inventory path as argument
    if len(sys.argv) > 1:
        inventory_path = Path(sys.argv[1])

    print(f"Parsing inventory: {inventory_path}")
    hosts = parse_inventory(inventory_path)

    if not hosts:
        print("No hosts found in inventory!")
        sys.exit(1)

    # Create output directory and clean it
    if output_dir.exists():
        # Remove all existing .rdp files
        for rdp_file in output_dir.glob("*.rdp"):
            rdp_file.unlink()
            print(f"Removed old file: {rdp_file}")

    output_dir.mkdir(exist_ok=True)
    print(f"\nGenerating RDP files in: {output_dir}\n")

    # Generate RDP files for all hosts
    for host in hosts:
        generate_rdp_file(host['name'], host['ip'], output_dir)

    print(f"\nSuccessfully generated {len(hosts)} RDP files!")
    print("\nUsage:")
    print("1. Double-click an .rdp file to connect")
    print("2. When prompted by RD Gateway, enter your RIT credentials")
    print("3. When prompted by the remote host, use: CDT\\cyberrange / Cyberrange123!")


if __name__ == "__main__":
    main()
