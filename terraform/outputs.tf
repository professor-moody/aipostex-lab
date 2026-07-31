# Flat map keyed "<K>/<role>" -> public IP (e.g. "0/ailab-attack").
output "instance_public_ips" {
  description = "Public IPs of all lab instances, keyed <range>/<role>"
  value = {
    for name, inst in aws_instance.lab :
    name => inst.public_ip
  }
}

# Per-range view: subnet, attack-box public IP, and role->IP maps. aws-provision.sh /
# aws-reset-wave.sh discover by Name tag rather than these outputs, but this is the
# human-readable index of what stood up.
output "ranges" {
  description = "Per-range subnet + attack box + role IP maps"
  value = {
    for k in var.range_ids : tostring(k) => {
      subnet         = "10.0.${k + 1}.0/24"
      attack_box_pub = aws_instance.lab["${k}/ailab-attack"].public_ip
      public_ips = {
        for role in keys(local.lab_roles) :
        role => aws_instance.lab["${k}/${role}"].public_ip
      }
      private_ips = {
        for role in keys(local.lab_roles) :
        role => local.range_instances["${k}/${role}"].private_ip
      }
    }
  }
}

output "ssh_command" {
  description = "SSH command to the range-0 attack box (deploy origin)"
  value       = "ssh -i <private-key> labadmin@${aws_instance.lab["0/ailab-attack"].public_ip}"
}
