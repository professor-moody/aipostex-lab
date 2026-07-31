variable "aws_region" {
  description = "AWS region for lab deployment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block (must cover every range's /24: range K -> 10.0.(K+1).0/24)"
  type        = string
  default     = "10.0.0.0/16"
}

# Multi-range (== proxmox multi-estate GROUP_ID). Each range K gets an ISOLATED subnet
# 10.0.(K+1).0/24 in the shared VPC plus its own security group that only admits
# intra-subnet traffic (+ operator SSH) — the AWS analog of proxmox's per-GROUP_ID
# bridge+subnet. Range 0 keeps unsuffixed resource names + IPs (10.0.1.x) for lab-ready
# AMI back-compat; range K>0 -> names "aipostex-lab-r<K>-<role>" at 10.0.(K+1).x.
variable "range_ids" {
  description = "Estate/range ids to deploy (default single range [0]; con lab uses [0,1,2,3,4])"
  type        = list(number)
  default     = [0]
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for lab access"
  type        = string
}

# Per-role sizing (performance-safe). Only Ollama (dev+ds) is real compute → non-burstable
# c6i; ml is 13 light mocks + Ray; k8s a single-node k3s; app/attack trivial. ARM is blocked
# (Weaviate/Qdrant x86-only), so all x86.
variable "instance_type_ollama" {
  description = "dev + ds — Ollama CPU inference, non-burstable. c6i.xlarge (4 vCPU): c6i.large (2 vCPU) timed out ~13/25 under a 25-simultaneous inference load test; 4 vCPU clears it. Estate stays at 16 vCPU total, under the 32 default quota."
  type        = string
  default     = "c6i.xlarge"
}

variable "instance_type_ml" {
  description = "ml — 13 lightweight Python mocks + Ray (down from oversized t3.xlarge)"
  type        = string
  default     = "t3.large"
}

variable "instance_type_k8s" {
  description = "ailab-k8s — single-node k3s cluster"
  type        = string
  default     = "t3.medium"
}

variable "instance_type_small" {
  description = "app — proxy/agents, trivial load"
  type        = string
  default     = "t3.small"
}

variable "instance_type_attack" {
  description = "attack — hosts ~25 seat shells + the tool; bumped (t3.large, 8GB) for the RTV concurrent-seat load, mirroring the on-prem attack-box bump"
  type        = string
  default     = "t3.large"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into lab instances. REQUIRED (no default) — set to the operator's IP/CIDR, e.g. \"203.0.113.4/32\". This is the SSH/22 isolation boundary: a peer range's subnet is not in this CIDR nor in a range's own /24, so cross-range SSH is dropped at the security group. Must not be 0.0.0.0/0."
  type        = string

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr must not be 0.0.0.0/0 — restrict SSH/22 to the operator IP/CIDR so a compromised range cannot SSH into its peers."
  }
}

variable "wg_ingress_cidr" {
  description = "CIDR allowed to reach the WireGuard attendee entrance (UDP 51820). Defaults to 0.0.0.0/0 because WireGuard IS the public entrance — its security is the key exchange plus per-peer AllowedIPs (the relay iptables scope each tunnel to this range's /24), not IP filtering. Only the attack box terminates wg0; SSH/22 stays operator-CIDR-only. Narrow to the venue egress if desired."
  type        = string
  default     = "0.0.0.0/0"
}

variable "name_prefix" {
  description = "Prefix for all AWS resource names"
  type        = string
  default     = "aipostex-lab"
}
