# Dev VMs
Install build deps. In fedora silverblue, enter a toolbox first.

```shell
toolbox enter # only on silverblue

sudo dnf install -y qemu-img qemu-kvm
sudo dnf install -y gcc pkg-config ncurses-devel flex bison elfutils-libelf-devel openssl-devel dwarves kmod cpio
```

To be able to ssh to the vm, make sure you have an ssh key set up. use `ssh-keygen` to create a new one.
Packer will try to use `~/.ssh/id_rsa.pub` by default. use `local_ssh_public_key` packer variable to customize that.
If the file does not exist, you can still ssh to the vm with user/password ubuntu/ubuntu (see user-data file as to how the password is set).

Build VM
```shell
# build a ubuntu images with tools.
packer build ubuntu.pkr.hcl
```

# Linux Kernel
We expect linux to be present in a folder called linux. you can get it there for example with
`git clone https://github.com/torvalds/linux.git`

Build linux. if make ask questions, just press enter.
If tweaking config, for easy debugging build things into kernel and not as modules.
```shell
cp config ./linux/.config
make -C linux
# add linux gdb scripts
mkdir -p ~/.config/gdb/
echo "add-auto-load-safe-path $PWD/linux/scripts/gdb/vmlinux-gdb.py" >> ~/.config/gdb/gdbinit
```

To be able to revert, build a diff qemu image. to revert just run this command again
```shell
qemu-img create -F qcow2 -b output/ubuntu-2204/ubuntu-2204.qcow2 -f qcow2 img.qcow2
```

# Run the vm with built kernel

Start the VM. it will not do anything until you connect a debugger to it and hit "continue".

Explanation of args:
  - kernel - the kernel that qemu loads. this means that the kernel in the image is ignored,
    and the kernel headers will not be present, nor can you get them with "apt-get". If config from this repo is used, kernel headers will be available in /proc
  - serial - output serial consul to stdin/stdout. you can use this to login without ssh
  - drive - the disk to use
  - net - create a network interface so we have internet access
  - m - memory
  - nographic - don't open a window
  - append - Arguments to the kernel. important to have nokaslr there for debugging to work. We also add `net.ifnames=0 biosdevname=0` to have the network interface be `eth0` as this is how it is configured in the `user-data` file.
  - virtfs - make the current directory available to the guest
  - -s start gdb stub
  - -S wait until gdb connects



```shell
qemu-kvm \
  -kernel ./linux/arch/x86/boot/bzImage \
  -serial mon:stdio \
  -drive file=file=img.qcow2,if=virtio,cache=writeback,discard=ignore,format=qcow2 \
  -net nic -net user,hostfwd=tcp::10022-:22 \
  -m 8192 -nographic \
  -append "root=/dev/vda2 ro rdinit=/sbin/init net.ifnames=0 biosdevname=0 console=ttyS0 nokaslr" \
  -virtfs local,path=$PWD,mount_tag=host0,security_model=mapped,id=host0 \
  -s
``` 

bpftool is in `/usr/lib/linux-tools/<ORIGINAL_KERNEL_VERSION>/bpftool` (for example `/usr/lib/linux-tools/5.4.0-128-generic/bpftool`). Note that because we are using a custom built kernel, just running `bpftool` will return an error.

debug with `gdb ./linux/vmlinux -ex "target remote localhost:1234"`. Or with vscode you can `ln -s ../launch.json ./.vscode/launch.json` and hit debug.

Ssh into the VM with:

```
ssh -p 10022 debian@localhost
```
Though if you are testing networking, ssh-ing in might add noise.

For easy ssh, add this to your `~/.ssh/config` file. then `ssh debug-linux` should work.
```
Host debug-linux
    HostName localhost
    User ubuntu
    IdentityFile ~/.ssh/id_rsa
    Port 10022
```


# Sources

https://superuser.com/questions/628169/how-to-share-a-directory-with-the-host-without-networking-in-qemu