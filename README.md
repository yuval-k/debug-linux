Install build deps. In fedora silverblue, enter a toolsbox first.

```shell
toolbox enter

sudo dnf install -y qemu-img qemu-kvm
sudo dnf install -y gcc pkg-config ncurses-devel flex bison elfutils-libelf-devel openssl-devel dwarves kmod
```

Build VM
```shell
# build a debian image with tools
packer build packer.json
```

We expect linux to be present in a folder called linux. you can get it there for example with
`git clone https://github.com/torvalds/linux.git`

Build linux. if make ask questions, just press enter.
```shell
cp config ./linux/.config
make -C linux
# add linux gdb scripts
mkdir -p ~/.config/gdb/
echo "add-auto-load-safe-path $PWD/linux/scripts/gdb/vmlinux-gdb.py" >> ~/.config/gdb/gdbinit
```

To be able to revert, build a diff qemu image. to revert just run this command again
```shell
qemu-img create -F qcow2 -b qemu-images/my-build.qcow2 -f qcow2 img.qcow2
```

Start the VM. it will not do anything until you connect a debugger to it and hit "continue".

Explanation of args:
  - kernel - the kernel that qemu loads. this means that the kernel in the image is ignored,
    and the kernel headers will not be present, nor can you get them with "apt-get". If config from this repo is used, kernel headers will be available in /proc
  - serial - output serial consul to stdin/stdout. you can use this to login without ssh
  - hda - the disk to use
  - net - create a network interface so we have internet access
  - m - memory
  - nographic - don't open a window
  - append - Arguments to the kernel. important to have nokaslr there for debugging to work.
  - virtfs - make the current directory available to the guest
  - -s start gdb stub
  - -S essentially waits until gdb connects


```shell
qemu-kvm \
  -kernel ./linux/arch/x86/boot/bzImage \
  -serial mon:stdio \
  -hda img.qcow2 \
  -net nic -net user,hostfwd=tcp::10022-:22 \
  -m 8192 -nographic \
  -append "root=/dev/sda1 rdinit=/sbin/init console=ttyS0 nokaslr" \
  -virtfs local,path=$PWD,mount_tag=host0,security_model=mapped,id=host0 \
  -s -S
```

debug with `gdb ./linux/vmlinux -ex "target remote localhost:1234"`. Or with vscode you can `cp launch.json ./.vscode/launch.json` and hit debug.

Ssh into the VM with:

```
ssh -p 10022 debian@localhost
```
Though if you are testing networking, ssh-ing in might add noise.


# Sources

https://superuser.com/questions/628169/how-to-share-a-directory-with-the-host-without-networking-in-qemu