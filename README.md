# LfsOs: Linux From Scratch, OverSimplified

This Repository provides a Shell Script that will build a whole Linux System based on the [Linux From Scratch](https://linuxfromscratch.org/) Book.

## Audience

It is recommended to already be an Lfs Graduate (Ie having successfully built Lfs from the Book and [got yourself Counted](https://www.linuxfromscratch.org/cgi-bin/lfscounter.php) :p). The Script can still be used by people unfamiliar with Lfs though you are on your own if you get stuck somewhere as it is expected that users have the required skill or resolve to successfully perform an Lfs Build by the Book or equivalent.

The script can be useful to people who have completed an Lfs Build and wish to have some already made starting point to automate it. Or even anyone who just wants to build some very Customized Linux without particular interest in Lfs. The Official Automated Lfs is [Jhalfs](https://linuxfromscratch.org/alfs/), however it is more suited to the Lfs Editors and Contributors as being some mix between the book text and commands makes it quite cumbersome to customize.

People considering to study Linux From Scratch can use the Script for a more concrete and straightforward learning approach, like build first Lfs then study the Script and Book, or rerun the Script's Commands one by one. The Script is amply commented with references to the appropriate Lfs Book Section to learn more. I still recommend to study the Lfs Book if not already done.

Musl is used instead of GlibC so those who want a Musl Version of Lfs can look here to find out what changes were required.

## Main Choices and Changes from Lfs

As the names implies, the Script is a simplified Lfs that does not follow all the instructions from the Book, and also took different paths.

* Based on Lfs 13.0.
* Some non essential Packages or steps have been skipped. No Networking nor Gui, only Us Keyboard and no Locales. You may want to reinstate some of them to have desired features or build further Packages for example from BLfs that could require these.
* Patches or Configurations have been reduced to a minimum, just what is needed to compile without Errors, disregarding possible security fixes.
* Anything Legacy not needed for the Build is removed.
* We don't really care here about Docs nor things like Fhs Compilance.
* We do care about Static Libraries.
* The Efi Steps for Grub are followed.
* Nano was chosen instead of Vim.
* The Build is only checked to work on Debian 13 (LxQt Live Usb). It may or may not work with another System but more Systems will not be supported to keep instructions simple and straightforward.
* Only x64 Build was tested for now.

## Usage

### Preparations

If needed, get [Debian 13](https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/) and install it on a powerful enough (recent 8+ Cores and 16+ GiB Ram if possible) computer or Virtual Machine. Building on Live Usb can also work, though there should either be enough Ram to fit the whole build in memory, or some storage accessible from the Live System (another Usb Drive, unused Internal Partition,...). About 15 GiB of Free Disk Space should be enough. The Script will create a 10 GiB Image in which the whole Build will directly be made.

Debian already includes all tools required for the Build except `gawk`, install it with `sudo apt install gawk`. Optionally, `git` can be installed to Clone this Repository, and `wget` to download Source Packages via the Script.

Now, get the `LfsOs.sh` Script in some way or another (Git Clone, Download Zip,...) and put it somewhere. Then, download the Package Source Codes: the Script can download these for you by running `bash LfsOs.sh DownloadPackages` (`wget` is required), however odds that at least one of the Servers is down at any time is quite high and as the Script aims to remain simple a single failure will stop the Script. A [Convenience Archive](https://kdrive.infomaniak.com/app/share/409092/570f767e-3ee0-4517-88fc-1509bd90026b) with all the LfsOs Packages was made. If you can afford running a Server, self hosting the Packages is very practical.

Put the Downloaded Files in a Folder named `LfsOsPackages` next to the Script (by default and if running it directly in its Directory) or edit the Script accourdingly.

### Building

Then run the Script (or take a look at it first) **as root**. If there is no unexpected issue it will perform the whole build and yield a 10 GiB `LfsOs.img` Disk Image. It can be booted in Qemu or used to make a Live Usb. Note that in all cases it was made for Uefi Machines, most x64 machines since about 2011 are Uefi, in the case of Qemu you need to use options that enable Uefi. There is only the Root Account, with `root` as Password.

The Build takes about 25-30 minutes with an Amd Ryzen 9 9950X.

If something went wrong, run `bash LfsOs.sh CleanUp` to delete the possibly present Temporary User and unmount the Kernel File Systems if still Mounted. This will not delete the `LfsOsPackages` nor the `LfsOs.img`, though rerunning the Script will overwrite the Disk Image.

## Maintenance/Contributions

This Script was made as I started working on own Operating System Project, so maintaining it will not be a high priority as I work on my OS, though I will try to update it when a major Lfs Stable Version is released (once every 6 months, usually the 1st of March or September).

Feel free to make Pull Requests to enhance the Script or if it has not been updated for a while since the latest Lfs Stable Version. Do not refactor it too much, keep it easy to directly copy-paste commands one by one.

If you liked the Script, you can show your appreciation by gifting some Coins...

* Riecoins: ric1pttn0uefxlhnzxqpgmh22enhcky0csz72se7k458kh8yplgscgxxsj3n9c7
* Bitcoins: bc1pttn0uefxlhnzxqpgmh22enhcky0csz72se7k458kh8yplgscgxxsa2qr9y

More conventional ways: Revolut `@Pttn`, [PayPal](https://www.paypal.com/paypalme/SteloXyz).

[Donate to the Linux From Scratch Editors](https://linuxfromscratch.org/lfs/contribute.html).

## License and Disclaimers

The Project is released under the [Gpl3](https://www.gnu.org/licenses/gpl-3.0.en.html).

It is recommended to run the Script on a spare or virtualized machine. I am not responsible in case there is some mistake in the Code that causes it to mess with your system as running it as Root allows it to do whatever it wants.
