# ── VPC (shared across ranges) ───────────────────────────────
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# One isolated /24 per range: range K -> 10.0.(K+1).0/24. Range 0 keeps the unsuffixed
# name; K>0 -> "-r<K>-subnet".
resource "aws_subnet" "lab" {
  for_each = local.range_keys

  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.${tonumber(each.key) + 1}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = each.key == "0" ? "${var.name_prefix}-subnet" : "${var.name_prefix}-r${each.key}-subnet" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = { Name = "${var.name_prefix}-igw" }
}

# One route table shared by all range subnets. Cross-range L3 is technically routable
# inside the VPC — isolation is enforced by the per-range security group below (a range's
# SG only admits its own /24), the AWS analog of proxmox's per-GROUP_ID bridge.
resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = "${var.name_prefix}-rt" }
}

resource "aws_route_table_association" "lab" {
  for_each = aws_subnet.lab

  subnet_id      = each.value.id
  route_table_id = aws_route_table.lab.id
}

# ── Per-range Security Groups (the isolation boundary) ───────
# Each range's SG admits ONLY its own /24 (all ports) plus operator SSH. A packet from
# range J's 10.0.(J+1).x hitting range K's service port is dropped by K's ingress — estates
# are isolated on every service port. SSH/22 is likewise range-isolated: it admits only
# var.allowed_ssh_cidr (the operator IP/CIDR, required — never 0.0.0.0/0), and a peer range's
# subnet is in neither that CIDR nor range K's own /24, so cross-range SSH is dropped too.
resource "aws_security_group" "lab_internal" {
  for_each = local.range_keys

  name_prefix = each.key == "0" ? "${var.name_prefix}-internal-" : "${var.name_prefix}-r${each.key}-internal-"
  vpc_id      = aws_vpc.lab.id
  description = "Range ${each.key}: intra-subnet traffic + operator SSH"

  # All traffic within this range's own subnet only.
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.${tonumber(each.key) + 1}.0/24"]
    description = "Intra-range traffic (own subnet only)"
  }

  # SSH/22 from the operator CIDR ONLY (var.allowed_ssh_cidr, required, never 0.0.0.0/0).
  # This is also the cross-range SSH isolation boundary: a peer range's subnet is not in
  # this CIDR, so range J cannot SSH into range K.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "Operator SSH (operator CIDR only)"
  }

  # WireGuard attendee entrance (UDP 51820). This is the standing entrance on the attack box's
  # public IP; WireGuard's security is the key exchange + per-peer AllowedIPs (the relay iptables
  # scope each tunnel to this range's own /24), so it can be public. Only the attack box terminates
  # wg0 — the four role hosts and k8s node ignore UDP/51820. SSH/22 stays operator-CIDR-only above.
  ingress {
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = [var.wg_ingress_cidr]
    description = "WireGuard attendee entrance (attack box only)"
  }

  # All outbound.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = { Name = each.key == "0" ? "${var.name_prefix}-internal-sg" : "${var.name_prefix}-r${each.key}-internal-sg" }

  lifecycle {
    create_before_destroy = true
  }
}
