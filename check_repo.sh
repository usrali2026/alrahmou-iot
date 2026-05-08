#!/bin/bash

echo "=== Git Repo Health Check ==="

echo ""
echo "1. Checking nested git repos..."
find . -type d -name ".git" | grep -v "./.git$"

echo ""
echo "2. Large files (>10MB)..."
find . -type f -size +10M

echo ""
echo "3. Git status:"
git status --short

echo ""
echo "Done."
