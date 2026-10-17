# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private report: the repository's *Security* tab, then *Report a vulnerability*. Only the maintainer sees it.

Say what you found, where (file and line), how to reproduce it and what it allows. Do not paste real secrets, subscription or tenant identifiers, or addresses; placeholders are enough.

## Scope

The Terraform modules, the scripts and the GitHub Actions workflows of this repository. This is a template meant to be used from a **private copy** (see the README): a problem in how the workflows handle inputs, credentials or permissions is in scope.

Only `main` is supported.
