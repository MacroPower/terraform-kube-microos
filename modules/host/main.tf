resource "random_string" "server" {
  length  = 3
  lower   = true
  special = false
  numeric = false
  upper   = false

  keepers = {
    # We re-create the apart of the name changes.
    name = var.name
  }
}

resource "random_string" "identity_file" {
  length  = 20
  lower   = true
  special = false
  numeric = true
  upper   = false
}

resource "null_resource" "pre_k3s_host" {
  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = var.ipv4_address

    # We cannot use different ports here as this runs inside Hetzner Rescue image and thus uses the
    # standard 22 TCP port.
    port = 22
  }

  # Prepare ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      install -b -m 600 /dev/null /tmp/${random_string.identity_file.id}
      echo "${local.ssh_client_identity}" > /tmp/${random_string.identity_file.id}
    EOT
  }

  # Install MicroOS
  provisioner "remote-exec" {
    inline = concat(
      [
        "set -ex",
        "wget --timeout=5 --waitretry=5 --tries=5 --retry-connrefused --inet4-only ${var.opensuse_microos_mirror_link}",
        "apt-get update",
        "apt-get install -y libguestfs-tools",
        "qemu-img convert -p -f qcow2 -O host_device $(ls -a | grep -ie '^opensuse.*microos.*qcow2$') ${var.os_device}",
        "mkdir -p /mnt/disk",
        "mount -o rw,subvol=@/root ${local.root_device} /mnt/disk",
      ],
      formatlist(
        "echo \"%s\" | tee -a /mnt/disk/.ssh/authorized_keys", concat([var.ssh_public_key], var.ssh_additional_public_keys)
      ),
      [
        "chmod 600 /mnt/disk/.ssh/authorized_keys",
      ],
    )
  }

  # Issue a reboot command.
  provisioner "local-exec" {
    command = <<-EOT
      ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} root@${var.ipv4_address} '(sleep 2; reboot)&'; sleep 3
    EOT
  }

  # Wait for MicroOS to reboot and be ready.
  provisioner "local-exec" {
    command = <<-EOT
      until ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} -o ConnectTimeout=2 root@${var.ipv4_address} true 2> /dev/null
      do
        echo "Waiting for MicroOS to reboot and become available..."
        sleep 3
      done
    EOT
  }

  # Cleanup ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      rm /tmp/${random_string.identity_file.id}
    EOT
  }
}

resource "null_resource" "k3s_host" {
  depends_on = [
    null_resource.pre_k3s_host,
  ]

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = var.ipv4_address
    port           = var.ssh_port
  }

  # Prepare ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      install -b -m 600 /dev/null /tmp/${random_string.identity_file.id}
      echo "${local.ssh_client_identity}" > /tmp/${random_string.identity_file.id}
    EOT
  }

  provisioner "remote-exec" {
    connection {
      # We cannot use different ports here as this is pre cloud-init and thus uses the
      # standard 22 TCP port.
      port = 22
    }

    inline = [<<-EOT
      set -ex
      echo "First reboot successful, installing needed packages..."
      transactional-update shell <<< "setenforce 0"
      transactional-update --continue shell <<< "zypper --gpg-auto-import-keys install -y ${local.needed_packages}"
      transactional-update --continue shell <<< "rpm --import https://rpm-testing.rancher.io/public.key"
      transactional-update --continue shell <<< "zypper --no-gpg-checks --non-interactive install https://github.com/k3s-io/k3s-selinux/releases/download/v1.3.testing.4/k3s-selinux-1.3-4.sle.noarch.rpm"
      transactional-update --continue shell <<< "zypper addlock k3s-selinux"
      transactional-update --continue shell <<< "restorecon -Rv /etc/selinux/targeted/policy && restorecon -Rv /var/lib && setenforce 1"
      sleep 1 && udevadm settle && reboot
      EOT
    ]
  }

  # Issue a reboot command.
  provisioner "local-exec" {
    command = <<-EOT
      ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} root@${var.ipv4_address} '(sleep 3; reboot)&'; sleep 3
    EOT
  }

  # Wait for MicroOS to reboot and be ready
  provisioner "local-exec" {
    command = <<-EOT
      until ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} -o ConnectTimeout=2 -p ${var.ssh_port} root@${var.ipv4_address} true 2> /dev/null
      do
        echo "Waiting for MicroOS to reboot and become available..."
        sleep 3
      done
    EOT
  }

  # Cleanup ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      rm /tmp/${random_string.identity_file.id}
    EOT
  }


  provisioner "remote-exec" {
    inline = var.automatically_upgrade_os ? [
      <<-EOT
      echo "Automatic OS updates are enabled"
      EOT
      ] : [
      <<-EOT
      echo "Automatic OS updates are disabled"
      systemctl --now disable transactional-update.timer
      EOT
    ]
  }

  provisioner "file" {
    content     = var.k3s_registries
    destination = "/tmp/registries.yaml"
  }

  provisioner "remote-exec" {
    inline = [var.k3s_registries_update_script]
  }
}

data "cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/templates/cloudinit.yaml.tpl",
      {
        hostname                     = local.name
        sshAuthorizedKeys            = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        cloudinit_write_files_common = var.cloudinit_write_files_common
        cloudinit_runcmd_common      = var.cloudinit_runcmd_common
      }
    )
  }
}
