# Student Checklist - Getting Started with CDT OpenStack Project

Use this checklist to track your progress through the project setup.

## Pre-Project Setup

### Prerequisites
- [ ] I have basic Linux command line knowledge
- [ ] I understand networking concepts (IP addresses, subnets, routers)
- [ ] I can use SSH to connect to remote servers
- [ ] I have access to the OpenStack dashboard

### Software Installation
- [ ] OpenTofu installed and working (`tofu version`)
- [ ] Ansible installed and working (`ansible --version`)
- [ ] Git installed (`git --version`)
- [ ] SSH key pair generated (`ls ~/.ssh/id_rsa*`)

### Access Requirements
- [ ] OpenStack account access confirmed
- [ ] SSH key uploaded to OpenStack (Compute > Key Pairs)
- [ ] Application credentials created in OpenStack
- [ ] Can login to OpenStack dashboard

## Project Setup

### Initial Configuration
- [ ] Project repository cloned locally
- [ ] OpenStack credentials file created and configured
- [ ] Credentials tested with `./quick-start.sh`
- [ ] Variables reviewed in `opentofu/variables.tf`

### Understand the Code
- [ ] Read through `README.md` completely
- [ ] Examined OpenTofu files in `/opentofu/` directory
- [ ] Reviewed Ansible playbooks in `/ansible/` directory
- [ ] Understand the network architecture diagram

## Infrastructure Deployment

### OpenTofu (Infrastructure)
- [ ] Navigate to `opentofu/` directory
- [ ] Run `tofu init` successfully
- [ ] Review planned changes with `tofu plan`
- [ ] Deploy infrastructure with `tofu apply`
- [ ] Verify resources created in OpenStack dashboard
- [ ] Note down floating IP addresses

### Ansible (Configuration)
- [ ] Navigate to `ansible/` directory
- [ ] Update `inventory.ini` with correct IP addresses
- [ ] Test connectivity to Windows servers
- [ ] Test connectivity to Linux servers
- [ ] Run complete setup with `ansible-playbook -i inventory.ini site.yml`

## Verification & Testing

### Infrastructure Verification
- [ ] All VMs visible in OpenStack dashboard
- [ ] All VMs have floating IPs assigned
- [ ] Can SSH to Linux servers using floating IPs
- [ ] Can RDP to Windows servers using floating IPs

### Domain Setup Verification
- [ ] Domain controller (10.10.10.21) accessible
- [ ] Windows servers joined to CDT.local domain
- [ ] Linux servers joined to CDT.local domain
- [ ] Domain users created successfully

### SSH Access Testing
- [ ] Can SSH using domain credentials: `ssh jdoe@CDT.local@<linux-ip>`
- [ ] Domain admin users have sudo access
- [ ] All 5 test users can authenticate

## Learning Exercises

### Beginner Challenges
- [ ] Change the number of Windows servers and redeploy
- [ ] Change the number of Linux servers and redeploy
- [ ] Modify the subnet CIDR range
- [ ] Add a new domain user via Ansible

### Intermediate Challenges
- [ ] Create a new server type (e.g., Ubuntu instead of Debian)
- [ ] Implement custom security group rules
- [ ] Add additional storage volumes to servers
- [ ] Configure a simple web service on Linux servers

### Advanced Challenges
- [ ] Deploy across multiple availability zones
- [ ] Implement a load balancer for web services
- [ ] Add monitoring/logging to the infrastructure
- [ ] Create automated backup procedures

## Troubleshooting Completed

### Common Issues Resolved
- [ ] Fixed OpenStack authentication problems
- [ ] Resolved SSH connectivity issues
- [ ] Fixed Windows WinRM connection problems
- [ ] Resolved Ansible playbook errors
- [ ] Fixed domain join issues

## Documentation & Reflection

### Learning Documentation
- [ ] Created notes on OpenTofu concepts learned
- [ ] Documented Ansible patterns observed
- [ ] Recorded troubleshooting steps taken
- [ ] Listed key commands used

### Project Reflection
- [ ] Identified what worked well
- [ ] Noted areas for improvement
- [ ] Documented lessons learned
- [ ] Prepared questions for discussion

## Next Steps

### Project Extensions
- [ ] Plan additional features to implement
- [ ] Identify areas for automation improvement
- [ ] Consider security enhancements
- [ ] Think about scalability improvements

### Continued Learning
- [ ] Research advanced OpenTofu patterns
- [ ] Explore additional Ansible modules
- [ ] Learn about OpenStack advanced features
- [ ] Study Infrastructure as Code best practices

---

**Congratulations!** 

If you've completed all the core items above, you've successfully:
- Deployed infrastructure with OpenTofu
- Configured services with Ansible  
- Created a working Active Directory domain
- Learned Infrastructure as Code principles

**Total Time Estimate:** 4-8 hours (depending on experience level)

**Questions or Issues?** Check the troubleshooting section in README.md or ask for help!
