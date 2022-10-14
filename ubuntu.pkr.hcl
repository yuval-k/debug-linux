
variable "local_ssh_public_key" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "username" {
  type    = string
  default = "ubuntu"
}

locals {
  ssh_key = "${pathexpand(var.local_ssh_public_key)}"
}

source "qemu" "ubuntu_devbox" {

  # these are commented out as they are set in the builder section.
  #  vm_name     = "tbd"
  #  iso_url      = "tbd"
  #  iso_checksum = "tbd"
  #  boot_command = [        "tbd"    ]
  #  output_directory = "tbd"

  # cloud init config files
  http_content = {
    "/user-data"   = templatefile("./user-data", { username = "${var.username}" })
    "/meta-data"   = ""
    "/vendor-data" = ""
  }
  boot_wait = "3s"

  cpus             = 2
  memory           = 2048
  accelerator      = "kvm"
  disk_size        = "40G"
  disk_compression = true
  format           = "qcow2"

  ssh_password = "ubuntu" # this is set in the user-data file.
  ssh_username = "${var.username}"
  # need good amount of retries/attempts here
  ssh_timeout            = "20m"
  ssh_handshake_attempts = "100"
  shutdown_command       = "sudo shutdown -P now"
  # change to false when doing dev and need to see the screen
  headless = true
}

build {
  name = "devbox_build"
  source "source.qemu.ubuntu_devbox" {
    vm_name          = "ubuntu-2204.qcow2"
    output_directory = "output/ubuntu-2204"
    iso_url          = "https://releases.ubuntu.com/22.04.1/ubuntu-22.04.1-live-server-amd64.iso"
    iso_checksum     = "file:https://releases.ubuntu.com/22.04.1/SHA256SUMS"

    boot_command = [
      "<spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait>e<wait><down><down><down><end> ",
      "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
      "<f10>"
    ]
  }

  source "source.qemu.ubuntu_devbox" {
    vm_name          = "ubuntu-2004.qcow2"
    output_directory = "output/ubuntu-2004"
    iso_url          = "https://releases.ubuntu.com/20.04.5/ubuntu-20.04.5-live-server-amd64.iso"
    iso_checksum     = "file:https://releases.ubuntu.com/20.04.5/SHA256SUMS"

    boot_command = [
      "<leftshift><wait><leftshift><wait><leftshift><wait><esc><wait><f6><wait><esc><wait> fsck.mode=skip ",
      "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
      "<enter>"
    ]
  }

  # Wait for cloud init on first-boot to finish.
  provisioner "shell" {
    inline = [
      "until [ -e /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for boot to finish...'; sleep 1; done"
    ]
  }

  # copy over ssh key if its there
  provisioner "file" {
    content     = fileexists("${local.ssh_key}") ? file("${local.ssh_key}") : ""
    destination = "/tmp/authorized_key"
  }
  # append it to authorized_keys if file is of non-zero length
  provisioner "shell" {
    inline = [
      "if [ -s /tmp/authorized_key ]; then cat /tmp/authorized_key >> /home/${var.username}/.ssh/authorized_keys; fi",
      "rm /tmp/authorized_key"
    ]
  }

  # setup dev env!
  provisioner "shell" {
    inline = [
      "sudo DEBIAN_FRONTEND=noninteractive apt update",
      "sudo DEBIAN_FRONTEND=noninteractive apt install -y ipset iptables nftables git make net-tools tcpdump jq",
      "sudo DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common",
      # install clang for ebpf
      "sudo DEBIAN_FRONTEND=noninteractive apt install -y clang libbpf-dev linux-tools-common linux-tools-generic",
      "sudo mkdir -p /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "sudo usermod -aG docker ${var.username}",

      "curl -SsL https://dl.google.com/go/go1.19.2.linux-amd64.tar.gz | sudo tar xzf - -C /usr/local",
      "sudo ln -s /usr/local/go/bin/go /usr/local/bin/go",

      "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.14.0/kind-linux-amd64",
      "chmod +x ./kind",
      "sudo mv ./kind /usr/local/bin/kind",

      "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\"",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",
      "rm kubectl",

      "sudo mkdir /mnt/host",
      "echo \"host0   /mnt/host    9p      trans=virtio,version=9p2000.L   0 0\" | sudo tee -a /etc/fstab",

      "echo 'export GOPATH=$HOME/go' >> $HOME/.bashrc",

      "curl -L \"https://github.com/iovisor/bpftrace/releases/download/v0.15.0/bpftrace\" | sudo tee /usr/local/bin/bpftrace > /dev/null",
      "sudo chmod +x /usr/local/bin/bpftrace"

    ]
  }
}
