# FoundationDB Windows Build Image

This repo contains the GitHub Actions workflow necessary to generate a docker image capable of building FoundationDB on Windows.

The generated image contains the necessary msbuild tools to compile FoundationDB, using CMake and Clang/CL, as well as build the MSI packages.

Latest image will pushed in the [doxense/foundationdb-windows-build](https://hub.docker.com/r/doxense/foundationdb-windows-build/tags?page=1&ordering=last_updated) repository.

> docker pull doxense/foundationdb-windows-build:latest

Build instructions: TBD! (PR pending)
