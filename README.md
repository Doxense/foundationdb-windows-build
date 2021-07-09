# FoundationDB Windows Build

This repo contains the GitHub Actions workflows necessary to build FoundationDB on Windows:

- **Source Build**: is used to build a specific branch or commit, and produce the binary artefacts (MSI, tools, ...).
- **Windows Build Image**: is used to generate the docker build image that is use by the previous step. This image includes all the tools and compilers necessary to _build_ the FoundationDB code source. Whenever the build environment changes, this build will be generated and pushed to the [doxense/foundationdb-windows-build](https://hub.docker.com/r/doxense/foundationdb-windows-build/tags?page=1&ordering=last_updated) repository.
