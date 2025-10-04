#!/bin/sh

# Get the current working directory
cwd=$(pwd)

# Define the target platform and Python version for AWS Lambda
target_platform="manylinux2014_x86_64"
python_version="312"

# Create a "package" directory to store dependencies
mkdir -p "$cwd/package"

# Install dependencies for the specified platform
pip install --platform "$target_platform" \
    --target "$cwd/package" \
    --implementation cp \
    --python-version "$python_version" \
    --only-binary=:all: \
    -r requirements.txt

cd "$cwd/package" || exit

# Create a zip archive containing the contents of the package directory
zip -r "$cwd/lambda_function.zip" .

# Add lambda_function.py to the zip file
cd "$cwd" || exit
zip lambda_function.zip lambda_function.py

# Clean up
rm -rf "$cwd/package"
