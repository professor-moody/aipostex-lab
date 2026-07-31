# ── Lab Instances ────────────────────────────────────────────
# Mirrors the Proxmox lab topology, per range. Host octet is shared across ranges
# (matches proxmox 172.16.(50+K).<octet>); range K lands the role at 10.0.(K+1).<octet>:
#   ailab-dev    .10   ailab-ml   .20   ailab-ds  .30
#   ailab-app    .40   ailab-k8s  .50   ailab-attack .99

locals {
  # Per-role config; identical across ranges except for the subnet the range pins it into.
  lab_roles = {
    "ailab-dev" = {
      octet         = 10
      instance_type = var.instance_type_ollama
      role_dir      = "dev-workstation"
      volume_size   = 20
    }
    "ailab-ml" = {
      octet         = 20
      instance_type = var.instance_type_ml
      role_dir      = "ml-platform"
      volume_size   = 40
    }
    "ailab-ds" = {
      octet         = 30
      instance_type = var.instance_type_ollama
      role_dir      = "data-sci"
      volume_size   = 20
    }
    "ailab-app" = {
      octet         = 40
      instance_type = var.instance_type_small
      role_dir      = "app-platform"
      volume_size   = 20
    }
    "ailab-k8s" = {
      octet         = 50
      instance_type = var.instance_type_k8s
      role_dir      = "k8s-node"
      volume_size   = 30
    }
    "ailab-attack" = {
      octet         = 99
      instance_type = var.instance_type_attack
      role_dir      = "attack-box"
      volume_size   = 20
    }
  }

  # String range keys for for_each on the per-range subnet/SG resources.
  range_keys = toset([for k in var.range_ids : tostring(k)])

  # Flattened instance map keyed "<K>/<role>" (e.g. "0/ailab-dev", "1/ailab-attack").
  # Range 0 keeps unsuffixed Name tags (lab-ready AMI back-compat); K>0 -> "-r<K>-".
  range_instances = merge([
    for k in var.range_ids : {
      for role, cfg in local.lab_roles :
      "${k}/${role}" => {
        range_id      = k
        role          = role
        private_ip    = "10.0.${k + 1}.${cfg.octet}"
        instance_type = cfg.instance_type
        role_dir      = cfg.role_dir
        volume_size   = cfg.volume_size
        name_tag      = k == 0 ? "${var.name_prefix}-${role}" : "${var.name_prefix}-r${k}-${role}"
      }
    }
  ]...)
}

resource "aws_network_interface" "lab" {
  for_each = local.range_instances

  subnet_id       = aws_subnet.lab[tostring(each.value.range_id)].id
  private_ips     = [each.value.private_ip]
  security_groups = [aws_security_group.lab_internal[tostring(each.value.range_id)].id]

  tags = { Name = "${each.value.name_tag}-eni" }
}

resource "aws_instance" "lab" {
  for_each = local.range_instances

  ami           = data.aws_ami.ubuntu.id
  instance_type = each.value.instance_type
  key_name      = aws_key_pair.lab.key_name

  network_interface {
    network_interface_id = aws_network_interface.lab[each.key].id
    device_index         = 0
  }

  user_data = templatefile("${path.module}/cloud-init.tftpl", {
    hostname           = each.value.role
    ssh_authorized_key = trimspace(file(var.ssh_public_key_path))
    # Only THIS range's hosts go in /etc/hosts — a range must not name-resolve peers in
    # another estate. Join with a 6-space indent so continuation lines stay inside the
    # `content: |` YAML block scalar in cloud-init.tftpl — a flat "\n" join drops later
    # lines to column 1, which makes cloud-init reject the ENTIRE cloud-config (no labadmin).
    hosts_entries = join("\n      ", [
      for key, inst in local.range_instances :
      "${inst.private_ip} ${inst.role}"
      if inst.range_id == each.value.range_id
    ])
  })

  root_block_device {
    volume_size = each.value.volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = each.value.name_tag
    Role = each.value.role_dir
  }
}
