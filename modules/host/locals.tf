locals {
  # ssh_agent_identity is not set if the private key is passed directly, but if ssh agent is used, the public key tells ssh agent which private key to use.
  # For terraforms provisioner.connection.agent_identity, we need the public key as a string.
  ssh_agent_identity = var.ssh_private_key == null ? var.ssh_public_key : null
  # shared flags for ssh to ignore host keys for all connections during provisioning.
  ssh_args = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o 'IdentitiesOnly yes' -o PubkeyAuthentication=yes"

  # ssh_client_identity is used for ssh "-i" flag, its the private key if that is set, or a public key
  # if an ssh agent is used.
  ssh_client_identity = var.ssh_private_key == null ? var.ssh_public_key : var.ssh_private_key

  needed_packages = join(" ", concat(["restorecond policycoreutils policycoreutils-python-utils setools-console bind-utils wireguard-tools open-iscsi nfs-client xfsprogs cryptsetup lvm2 git cifs-utils"], var.packages_to_install))

  # the hosts name with its unique suffix attached
  name = "${var.name}-${random_string.server.id}"

  root_device = length(regexall(".+[0-9]$", var.os_device)) > 0 ? "${var.os_device}p3" : "${var.os_device}3"

  cloudinit_config = templatefile(
    "${path.module}/templates/cloud.cfg.tpl",
    {}
  )

  cloudinit_userdata_config = templatefile(
    "${path.module}/templates/cloudinit.yaml.tpl",
    {
        hostname                     = local.name
        sshAuthorizedKeys            = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        cloudinit_write_files_common = var.cloudinit_write_files_common
        cloudinit_runcmd_common      = var.cloudinit_runcmd_common
    }
  )
}
