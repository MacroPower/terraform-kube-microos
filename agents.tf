module "agents" {
  source = "./modules/host"

  for_each = local.agent_nodes

  name                         = "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${each.value.nodepool_name}"
  ipv4_address                 = each.value.ipv4_address
  os_device                    = each.value.os_device
  network_interface            = each.value.network_interface
  ssh_port                     = var.ssh_port
  ssh_public_key               = var.ssh_public_key
  ssh_private_key              = var.ssh_private_key
  ssh_additional_public_keys   = var.ssh_additional_public_keys
  packages_to_install          = local.packages_to_install
  base_domain                  = var.base_domain
  dns_servers                  = var.dns_servers
  k3s_registries               = var.k3s_registries
  k3s_registries_update_script = local.k3s_registries_update_script
  cloudinit_write_files_common = local.cloudinit_write_files_common
  cloudinit_runcmd_common      = local.cloudinit_runcmd_common

  automatically_upgrade_os = var.automatically_upgrade_os
}

resource "null_resource" "agents" {
  for_each = local.agent_nodes

  triggers = {
    agent_id = module.agents[each.key].id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = module.agents[each.key].ipv4_address
    port           = var.ssh_port
  }

  # Generating k3s agent config file
  provisioner "file" {
    content = yamlencode({
      node-name     = module.agents[each.key].name
      server        = "https://${module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:6443"
      token         = random_password.k3s_token.result
      kubelet-arg   = local.kubelet_arg
      flannel-iface = module.agents[each.key].network_interface
      node-ip       = module.agents[each.key].private_ipv4_address
      node-label    = each.value.labels
      node-taint    = each.value.taints
      selinux       = true
    })
    destination = "/tmp/config.yaml"
  }

  # Install k3s agent
  provisioner "remote-exec" {
    inline = local.install_k3s_agent
  }

  # Start the k3s agent and wait for it to have started
  provisioner "remote-exec" {
    inline = concat(var.enable_longhorn ? ["systemctl enable --now iscsid"] : [], [
      "systemctl start k3s-agent 2> /dev/null",
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status k3s-agent > /dev/null; do
          systemctl start k3s-agent 2> /dev/null
          echo "Waiting for the k3s agent to start..."
          sleep 2
        done
      EOF
      EOT
    ])
  }

  depends_on = [
    null_resource.first_control_plane,
  ]
}

locals {
  agents_longhorn_devices = flatten([
    for k, v in local.agent_nodes : [
      for device in v.longhorn_devices : {
        agent        = k
        ipv4_address = v.ipv4_address
        device       = device
        name         = "longhorn${replace(device, "/\\//", "_")}"
      }
    ]
  ])
}

resource "null_resource" "agents_longhorn_volumes" {
  for_each = { for x in local.agents_longhorn_devices : "${x.agent}-${x.device}" => x }

  triggers = {
    agent_id = module.agents[each.value.agent].id
  }

  # Start the k3s agent and wait for it to have started
  provisioner "remote-exec" {
    inline = [
      "${var.longhorn_fstype == "ext4" ? "mkfs.ext4" : "mkfs.xfs"} ${each.value.device}",
      "mkdir /var/${each.value.name} >/dev/null 2>&1",
      "mount -o discard,defaults ${each.value.device} /var/${each.value.name}",
      "mount -o discard,defaults ${each.value.device} /var/${each.value.name}",
      "${var.longhorn_fstype == "ext4" ? "resize2fs" : "xfs_growfs"} ${each.value.device}",
      "echo '${each.value.device} /var/longhorn${each.value.name} ${var.longhorn_fstype} discard,nofail,defaults 0 0' >> /etc/fstab",
    ]
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = each.value.ipv4_address
    port           = var.ssh_port
  }
}

resource "hcloud_floating_ip" "agents" {
  for_each = { for k, v in local.agent_nodes : k => v if coalesce(lookup(v, "floating_ip"), false) }

  type          = "ipv4"
  labels        = local.labels
  home_location = each.value.location
}

resource "hcloud_floating_ip_assignment" "agents" {
  for_each = { for k, v in local.agent_nodes : k => v if coalesce(lookup(v, "floating_ip"), false) }

  floating_ip_id = hcloud_floating_ip.agents[each.key].id
  server_id      = module.agents[each.key].id

  depends_on = [
    null_resource.agents
  ]
}

resource "null_resource" "configure_floating_ip" {
  for_each = { for k, v in local.agent_nodes : k => v if coalesce(lookup(v, "floating_ip"), false) }

  triggers = {
    agent_id       = module.agents[each.key].id
    floating_ip_id = hcloud_floating_ip.agents[each.key].id
  }

  provisioner "remote-exec" {
    inline = [
      "echo \"BOOTPROTO='static'\nSTARTMODE='auto'\nIPADDR=${hcloud_floating_ip.agents[each.key].ip_address}/32\nIPADDR_1=${module.agents[each.key].ipv4_address}/32\" > /etc/sysconfig/network/ifcfg-eth0",
      "echo \"172.31.1.1 - 255.255.255.255 eth0\ndefault 172.31.1.1 - eth0 src ${hcloud_floating_ip.agents[each.key].ip_address}\" > /etc/sysconfig/network/ifroute-eth0",

      "ip addr add ${hcloud_floating_ip.agents[each.key].ip_address}/32 dev eth0",
      "ip route replace default via 172.31.1.1 dev eth0 src ${hcloud_floating_ip.agents[each.key].ip_address}",

      # its important: floating IP should be first on the interface IP list
      # move main IP to the second position
      "ip addr del ${module.agents[each.key].ipv4_address}/32 dev eth0",
      "ip addr add ${module.agents[each.key].ipv4_address}/32 dev eth0",
    ]
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = module.agents[each.key].ipv4_address
    port           = var.ssh_port
  }

  depends_on = [
    hcloud_floating_ip_assignment.agents
  ]
}
