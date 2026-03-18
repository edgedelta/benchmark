# HTTP Input Benchmark Comparison

Benchmark comparison of HTTP log ingestion performance across **Edge Delta**, **Bindplane**, and **Cribl**. Each platform is tested under identical conditions (pass-through, filter, mask, and lookup pipeline types) using synthetic nginx-style logs.

## Latest Benchmark Results

📊 **[View Latest Benchmark Report](https://github.com/edgedelta/benchmark/releases/latest)**

## Purpose

This repository helps developers evaluate and compare HTTP input throughput for three observability pipeline platforms. Benchmarks run on a single EC2 instance with consistent load profiles (80, 100, and 120 workers) and a 1-minute test duration per run.

## Prerequisites

- **Terraform** >= 1.0 (for AWS infrastructure)
- **AWS credentials** configured (e.g., `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or `aws configure`)
- **jq** and **curl** (for API scripts)
- **Bindplane CLI** installed and configured
- **SSH** access from your machine (Terraform restricts EC2 SSH to your public IP)

## Required Environment Variables

Set these before running `./run.sh`:

### Edge Delta

| Variable      | Description                    |
|---------------|--------------------------------|
| `ED_ORG_ID`   | Edge Delta organization ID     |
| `ED_API_TOKEN`| Edge Delta API token           |

### Cribl

| Variable              | Description                         |
|-----------------------|-------------------------------------|
| `CRIBL_WORKSPACE`     | Cribl Cloud workspace name          |
| `CRIBL_ORG`           | Cribl Cloud organization ID         |
| `CRIBL_WORKER_GROUP`  | Cribl worker group (e.g., `default`)|
| `CRIBL_CLIENT_ID`     | Cribl API client ID                 |
| `CRIBL_CLIENT_SECRET` | Cribl API client secret             |
| `CRIBL_LEADER_TOKEN`  | Cribl leader token (for agent install)|

### Bindplane

Bindplane uses the CLI profile rather than environment variables. Install the [Bindplane CLI](https://docs.bindplane.observiq.com/docs/bindplane-cli) and configure it with your API key:

```bash
bindplane profile set --apiKey YOUR_API_KEY
```

## Directory Structure

```
.
├── aws_resources/          # Terraform: EC2, S3, IAM
├── benchmark_scripts/      # Load generation and trigger scripts (run on EC2)
├── pipelines/              # Pipeline configs per platform
│   ├── bindplane/          # Bindplane YAML configs
│   ├── cribl/              # Cribl JSON configs and API helper
│   └── edgedelta/          # Edge Delta YAML configs and API helper
├── scripts/                # Agent install scripts (generated/dynamic)
├── benchmark_results/      # Downloaded results (gitignored)
├── run.sh                  # Main entry point
└── functions.sh            # Shared utilities
```

## Setup

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd benchmark
   ```

2. Set all required environment variables (see above).

3. Ensure the Bindplane CLI is installed and configured.

4. Ensure Terraform and AWS credentials are ready. The script will create:
   - EC2 instance (c8i.2xlarge, Ubuntu 24.04, 50 GB gp3)
   - S3 bucket for log output
   - IAM resources for S3 access
   - SSH key pair (stored under `aws_resources/`)

## How to Run

From the repository root:

```bash
./run.sh
```

**What `run.sh` does:**

1. **Checks prerequisites** – Validates env vars and Bindplane CLI config
2. **Creates AWS resources** – Runs `terraform apply` in `aws_resources/`
3. **Prepares EC2** – Uploads benchmark scripts and lookup CSV
4. **Runs benchmarks** – For each platform (Edge Delta → Bindplane → Cribl):
   - Installs or configures the agent
   - For each pipeline type (pass-through, filter, mask, lookup):
     - Applies the pipeline config
     - Runs loadgen with 80, 100, and 120 workers (1 min each)
     - Captures logs
5. **Downloads results** – Saves to `benchmark_results/<YYYYMMDD_HHMMSS>/`
6. **Cleans up** – Deletes pipelines and runs `terraform destroy`

**Note:** Run from the repository root. The script sources `functions.sh` and expects to execute from that directory.

## Benchmark Types

| Type         | Description                                                  |
|--------------|--------------------------------------------------------------|
| pass-through | Minimal processing; baseline throughput                      |
| filter       | Exclude events where `attributes["color"] == "Green"`        |
| mask         | PII masking (IP, email, credit card, etc.)                   |
| lookup       | CSV lookup to enrich events (e.g., ip → region)              |

## Results

Results are written to `benchmark_results/<timestamp>/` with one log file per platform and pipeline type. File prefixes map to products: `edgedelta` = Edge Delta, `bindplane` = Bindplane, `cribl` = Cribl.

```
benchmark_results/
└── 20260226_135850/
    ├── edgedelta_pass-through.log
    ├── edgedelta_filter.log
    ├── edgedelta_mask.log
    ├── edgedelta_lookup.log
    ├── bindplane_pass-through.log
    ├── bindplane_filter.log
    ├── bindplane_mask.log
    ├── bindplane_lookup.log
    ├── cribl_pass-through.log
    ├── cribl_filter.log
    ├── cribl_mask.log
    └── cribl_lookup.log
```

Each log contains loadgen output with throughput (logs/sec), CPU/memory usage, and error counts.

## Cost Considerations

Running `./run.sh` creates billable AWS resources (EC2 c8i.2xlarge, S3, etc.). The script tears everything down at the end. Expect roughly 30–60 minutes of runtime; any interruption may leave resources running until you manually run `terraform destroy` in `aws_resources/`.
