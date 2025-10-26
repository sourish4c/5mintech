#!/usr/bin/env bash

set -euo pipefail

main() {
    HUGO_VERSION="0.151.2"
    export TZ=Asia/Kolkata

    # Install Hugo
    echo "Installing Hugo v${HUGO_VERSION}..."
    curl -LJO "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_darwin-universal.tar.gz"
    tar -xf "hugo_extended_${HUGO_VERSION}_darwin-universal.tar.gz"
    sudo cp hugo /usr/local/bin/
    rm LICENSE README.md hugo "hugo_extended_${HUGO_VERSION}_darwin-universal.tar.gz"

    # Verify installed versions
    echo "Verifying installations..."
    echo "Hugo: $(hugo version)"
    echo "Node.js: $(node --version)"

    # Clone themes repository
    # echo "Cloning Blowfish..."
    # git submodule update --init --recursive
    # git config core.quotepath false

    # Building the website
    echo "Building the Site..."
    hugo --gc --minify
}

main "$@"