# PayliteNG DevSecOps Security Pipeline

A complete DevSecOps security pipeline for the PayliteNG application, built as part of the TechRise 3.0 Week 11 Mini Project 3.

The project integrates automated security testing into GitHub Actions to identify vulnerabilities in application code, dependencies, secrets, Docker images, and Infrastructure as Code before insecure changes can reach deployment.

## Project Overview

The goal of this project is to demonstrate how security can be integrated directly into the CI/CD pipeline rather than being performed only after deployment.

The pipeline automatically performs five security checks:

| Security Gate       | Tool       | Purpose                                         |
| ------------------- | ---------- | ----------------------------------------------- |
| Secret Detection    | TruffleHog | Detects exposed secrets and credentials         |
| SAST                | Bandit     | Scans Python source code for security issues    |
| Dependency Scanning | Safety     | Identifies vulnerable Python dependencies       |
| Container Security  | Trivy      | Scans Docker images for known vulnerabilities   |
| IaC Security        | Checkov    | Detects security misconfigurations in Terraform |

All security jobs are configured as pipeline gates. HIGH and CRITICAL findings cause the workflow to fail and require remediation before the changes can proceed.

## Pipeline Architecture

```text
                    Developer
                        |
                        v
                  Git Push / PR
                        |
                        v
              +-------------------+
              |   GitHub Actions  |
              |  Security Pipeline|
              +---------+---------+
                        |
        +---------------+---------------+
        |               |               |
        v               v               v
   TruffleHog         Bandit          Safety
   Secrets            SAST            Dependencies
        |               |               |
        +---------------+---------------+
                        |
                        v
                     Trivy
               Docker Image Scan
                        |
                        v
                    Checkov
                  Terraform Scan
                        |
                        v
              +-------------------+
              | Security Decision |
              +---------+---------+
                        |
             +----------+----------+
             |                     |
          FAIL                  PASS
             |                     |
       Fix findings          Continue CI/CD
             |                     |
             +-----> Re-run <------+
```

## Security Workflow

The pipeline is defined in:

```text
.github/workflows/security.yml
```

The workflow runs the security tools automatically through GitHub Actions.

### 1. TruffleHog — Secret Detection

TruffleHog searches the repository for accidentally committed credentials, API keys, tokens and other sensitive information.

This helps prevent secrets from being pushed into source control.

### 2. Bandit — Python SAST

Bandit performs Static Application Security Testing against the Python application code.

It identifies potentially dangerous coding practices such as weak cryptographic algorithms, unsafe subprocess usage and insecure deserialization.

### 3. Safety — Dependency Scanning

Safety checks Python dependencies for known security vulnerabilities.

This helps identify vulnerable packages before they become part of a deployed application.

### 4. Trivy — Container Scanning

Trivy scans the Docker image for known vulnerabilities in operating-system packages and application dependencies.

The project uses Trivy to identify HIGH and CRITICAL vulnerabilities before the image is considered safe for deployment. Trivy supports vulnerability scanning of OS packages and language-specific dependencies.

Example:

```bash
trivy image --severity HIGH,CRITICAL <image-name>
```

### 5. Checkov — Infrastructure as Code Scanning

Checkov scans Terraform configuration for cloud security misconfigurations.

Examples include publicly accessible resources, insecure storage configurations and overly permissive network rules.

The purpose is to detect infrastructure security problems before Terraform is deployed.

## Security Findings and Remediation

During development, the pipeline initially identified multiple security issues across the application, container and infrastructure configuration.

Examples included:

* Weak MD5 hashing detected by Bandit.
* Vulnerable Python dependencies detected during dependency scanning.
* Vulnerabilities in the Docker base image and installed packages detected by Trivy.
* Terraform security misconfigurations detected by Checkov.
* Hardcoded secrets detected during secret scanning.

The findings were analysed and remediated so that the pipeline could move from a failing security state to a passing state.

This demonstrates an important DevSecOps principle:

> Find security problems early, fix them in code, and prevent insecure builds from progressing.

## Project Structure

```text
.
├── .github/
│   └── workflows/
│       └── security.yml
├── app/
│   └── app.py
├── terraform/
│   └── main.tf
├── Dockerfile
├── requirements.txt
├── .gitignore
└── README.md
```

## Running the Security Checks Locally

### Bandit

```bash
bandit -r app --severity-level medium
```

### Safety

```bash
safety check
```

### Trivy

```bash
docker build -t payliteng:secure .
trivy image --severity HIGH,CRITICAL payliteng:secure
```

### Checkov

```bash
checkov -f terraform/main.tf
```

### TruffleHog

```bash
trufflehog filesystem .
```

The exact commands may vary depending on the installed tool versions and local environment.

## GitHub Actions

The security workflow is triggered by repository changes and runs the configured security gates automatically.

A successful pipeline indicates that the configured security checks have passed.

A failed pipeline indicates that one or more security controls have detected an issue that must be investigated and remediated.

## Learning Objectives

This project demonstrates practical understanding of:

* DevSecOps and shift-left security
* CI/CD security automation
* Static Application Security Testing
* Dependency vulnerability management
* Secret detection
* Docker and container security
* Infrastructure as Code security
* Terraform security scanning
* Vulnerability remediation
* GitHub Actions
* Security gates in CI/CD pipelines

## Project Context

This repository was created for the TechRise 3.0 Cybersecurity & DevSecOps programme, Week 11 Mini Project 3.

The project builds on the Week 11 focus on container security, Docker, Trivy, Infrastructure as Code and Checkov. The training material describes the objective as detecting security issues before they reach production and integrating container and IaC scanning into CI/CD.

## Disclaimer

This project is intended for educational and security-training purposes.

The vulnerable configurations and intentionally vulnerable images used during testing are practice materials. They should not be used in production environments.

## Author

**Blessing Peter Nwankwo**

TechRise 3.0 — Cybersecurity & DevSecOps

