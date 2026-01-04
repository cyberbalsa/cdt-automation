#!/bin/bash

# CDT Automation - Linting Check Script
# This script runs linters for both OpenTofu and Ansible

set -e  # Exit on any error

echo "🔍 CDT Automation - Linting Check"
echo "=================================="
echo ""

# Track overall exit status
EXIT_STATUS=0

# Check if tflint is installed
if ! command -v tflint &> /dev/null; then
    echo "❌ tflint is not installed"
    echo "   Install with: curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash"
    EXIT_STATUS=1
else
    echo "📦 tflint found: $(tflint --version | head -n1)"
fi

# Check if ansible-lint is installed
if ! command -v ansible-lint &> /dev/null; then
    echo "❌ ansible-lint is not installed"
    echo "   Install with: pip3 install ansible-lint"
    echo "   or: sudo apt install ansible-lint"
    EXIT_STATUS=1
else
    echo "📦 ansible-lint found: $(ansible-lint --version | head -n1)"
fi

echo ""

# Exit early if linters are not installed
if [ $EXIT_STATUS -ne 0 ]; then
    echo "❌ Please install the missing linters before continuing"
    exit 1
fi

# Run tflint on OpenTofu directory
echo "🔍 Running tflint on opentofu/..."
echo "=================================="
cd opentofu

# Initialize tflint if needed
if [ ! -d .tflint.d ]; then
    echo "Initializing tflint..."
    tflint --init || true
fi

# Run tflint
if tflint --recursive; then
    echo "✅ tflint passed with no errors"
    TFLINT_STATUS=0
else
    echo "❌ tflint found issues"
    TFLINT_STATUS=1
    EXIT_STATUS=1
fi

cd ..

echo ""
echo "🔍 Running ansible-lint on ansible/..."
echo "========================================"
cd ansible

# Find all YAML files in ansible directory and run ansible-lint
ANSIBLE_FILES=$(find . -type f \( -name "*.yml" -o -name "*.yaml" \) -not -path "./.ansible/*" -not -path "./inventory/*")

if [ -z "$ANSIBLE_FILES" ]; then
    echo "⚠️  No Ansible YAML files found"
    ANSIBLE_LINT_STATUS=0
elif ansible-lint $ANSIBLE_FILES; then
    echo "✅ ansible-lint passed with no errors"
    ANSIBLE_LINT_STATUS=0
else
    echo "❌ ansible-lint found issues"
    ANSIBLE_LINT_STATUS=1
    EXIT_STATUS=1
fi

cd ..

# Summary
echo ""
echo "📊 Summary"
echo "=========="
if [ $TFLINT_STATUS -eq 0 ]; then
    echo "✅ OpenTofu/Terraform: PASSED"
else
    echo "❌ OpenTofu/Terraform: FAILED"
fi

if [ $ANSIBLE_LINT_STATUS -eq 0 ]; then
    echo "✅ Ansible: PASSED"
else
    echo "❌ Ansible: FAILED"
fi

echo ""
if [ $EXIT_STATUS -eq 0 ]; then
    echo "🎉 All checks passed!"
else
    echo "⚠️  Some checks failed. Please review the output above."
fi

exit $EXIT_STATUS
