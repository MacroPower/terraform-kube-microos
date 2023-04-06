<!-- PROJECT LOGO -->
<br />
<p align="center">
  <a href="https://github.com/mysticaltech/kube-hetzner">
    <img src="https://github.com/MacroPower/terraform-kube-microos/raw/master/.images/kube-hetzner-logo.png" alt="Logo" width="112" height="112">
  </a>

  <h2 align="center">Kube-MicroOS</h2>

  <p align="center">
    My fork of <a href="https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner">kube-hetzner</a> with hetzner-specific stuff removed. A highly optimized, easy-to-use, auto-upgradable, HA-default & Load-Balanced, Kubernetes cluster powered by k3s-on-MicroOS.
  </p>
  <hr />
</p>

This readme contains info relevant to this fork only. For full documentation,
you may want to see the [kube-hetzner readme](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner)!

## Usage with Hetzner Robot

Your server needs to be in the rescue system to begin, with a public key added
such that Terraform can login using the provided SSH key.

If you have multiple nodes, this project may not work without modification. You
probably will need to set up a vSwitch at least.

## Usage with other hosts

Obtain a debian-based live image, e.g.:

```sh
wget https://releases.ubuntu.com/22.04.1/ubuntu-22.04.1-live-server-amd64.iso
```

Run it on your node. This gives Terraform a staging area to install MicroOS
properly. Nothing here will be kept after Terraform is run for the first time.

Once in the installer, press CTRL+ALT+F2. Then, run the following:

Now that you have your `kube.tf` file, along with the OS snapshot in Hetzner project, you can start the installation process:

```sh
sudo -i
wget -O - https://github.com/MacroPower.keys >> ~/.ssh/authorized_keys
```

This will allow Terraform to ssh into the server as root.
