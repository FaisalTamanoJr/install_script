#!/bin/sh
# Luke's Auto Rice Boostrapping Script (LARBS)
# by Luke Smith <luke@lukesmith.xyz>
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

dotfilesrepo="https://github.com/FaisalTamanoJr/dotfiles.git"
progsfile="https://raw.githubusercontent.com/FaisalTamanoJr/install_script/master/progs.csv"
aurhelper="yay"
repobranch="master"

### FUNCTIONS ###

installpkg() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

gitclonefast() {
	# Wrapper around `git clone` for minimal and silent clone.
	git clone --depth 1 --single-branch --no-tags -q "${@}"
}

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

welcomemsg() {
	dialog --title "Welcome!" \
		--msgbox "Welcome to Luke's Auto-Rice Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured Linux desktop, which I use as my main machine.\\n\\n-Luke" 10 60

dialog --colors --title "Important Note!" --yes-label "All ready!" \
		--no-label "Return..." \
		--yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

getuserandpass() {
	# Prompts user for new username an password.
	name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

usercheck() {
	! { id -u "$name" >/dev/null 2>&1; } ||
		dialog --colors --title "WARNING!" --yes-label "CONTINUE" \
			--no-label "No wait..." \
			--yesno "The user \`$name\` already exists on this system. LARBS can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nLARBS will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that LARBS will change $name's password to the one you just gave." 14 70
}

preinstallmsg() {
	dialog --title "Let's get this party started!" --yes-label "Let's go!" \
		--no-label "No, nevermind!" \
		--yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit 1; }
}

adduserandpass() {
	# Adds user `$name` with password $pass1.
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 \
		|| usermod -a -G wheel,audio,video,optical,storage "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	export repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

refreshkeys() {
	case "$(readlink -f /sbin/init)" in
		*systemd* )
			dialog --infobox "Refreshing Arch Keyring..." 4 40
			pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
			;;
		*)
			dialog --infobox "Enabling Arch Repositories..." 4 40
			if ! grep -q "^\[universe\]" /etc/pacman.conf; then
				echo "[universe]
Server = https://universe.artixlinux.org/\$arch
Server = https://mirror1.artixlinux.org/universe/\$arch
Server = https://mirror.pascalpuffke.de/artix-universe/\$arch
Server = https://artixlinux.qontinuum.space/artixlinux/universe/os/\$arch
Server = https://mirror1.cl.netactuate.com/artix/universe/\$arch
Server = https://ftp.crifo.org/artix-universe/" >> /etc/pacman.conf
			pacman -Sy --noconfirm >/dev/null 2>&1
			fi
			pacman --noconfirm --needed -S \
				artix-keyring artix-archlinux-support >/dev/null 2>&1
			for repo in extra community; do
				grep -q "^\[$repo\]" /etc/pacman.conf ||
					echo "[$repo]
Include = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
			done
			pacman -Sy >/dev/null 2>&1
			pacman-key --populate archlinux >/dev/null 2>&1
			;;
	esac
}

newperms() {
	# Set special sudoers settings for install (or after).
	sed -i "/#LARBS/d" /etc/sudoers
	echo "$* #LARBS" >> /etc/sudoers
}

manualinstall() {
	# Installs $1 manually. Used only for AUR helper here.
	# Should be run after repodir is created and var is set.
	dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{ cd "$repodir/$1" || return 1 ; sudo -u "$name" git pull --force origin master ;}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" -D "$repodir/$1" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	# Installs all needed programs from main repo.
	dialog --title "LARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	installpkg "$1"
}

gitmakeinstall() {
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	dialog --title "LARBS Installation" \
		--infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{ cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master ;}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

aurinstall() {
	dialog --title "LARBS Installation" \
		--infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	dialog --title "LARBS Installation" \
		--infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	yes | pip install "$1"
}

installationloop() {
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) \
		|| curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" \
			&& comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv
}

putgitrepo() {
	# Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	dialog --infobox "Downloading and installing config files..." 4 60
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 \
		--single-branch --no-tags -q --recursive -b "$branch" \
		--recurse-submodules "$1" "$dir"
	sudo -u "$name" cp -rfT "$dir" "$2"
}

vimplugininstall() {
	# Installs vim plugins.
	dialog --infobox "Installing neovim plugins..." 7 60
	mkdir -p "/home/$name/.config/nvim/autoload"
	curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" >  "/home/$name/.config/nvim/autoload/plug.vim"
	chown -R "$name:wheel" "/home/$name/.config/nvim"
	sudo -u "$name" nvim -c "PlugInstall|q|q"
}

systembeepoff() {
	dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

finalize(){
	dialog --infobox "Preparing welcome message..." 4 50
	dialog --title "All done!" \
		--msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n.t Luke" 12 80
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy dialog \
	|| error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome user and pick dotfiles.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys \
	|| error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl ca-certificates base-devel git ntp zsh ; do
	dialog --title "LARBS Installation" \
		--infobox "Installing \`$x\` which is required to install and configure other programs." 5 70
	installpkg "$x"
done

dialog --title "LARBS Installation" \
	--infobox "Synchronizing system time to ensure successful and secure installation of software..." 4 70
ntpdate 0.us.pool.ntp.org >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

manualinstall yay || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

dialog --title "LARBS Installation" \
	--infobox "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes." 5 70
pacman -Qs libxft-bgra-git ||
       yes | sudo -u "$name" $aurhelper -S libxft-bgra-git >/dev/null 2>&1

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -f "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Install vim plugins if not alread present.
[ ! -f "/home/$name/.config/nvim/autoload/plug.vim" ] && vimplugininstall

# make git ignore deleted LICENSE & README.md files
git update-index --assume-unchanged "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Most important command! Get rid of the beep!
systembeepoff

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# dbus UUID must be generated for Artix runit.
dbus-uuidgen > /var/lib/dbus/machine-id

# Use system notifications for Brave on Artix
echo "export \$(dbus-launch)" > /etc/profile.d/dbus.sh

# Tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-larbs-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/light,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm" >/etc/sudoers.d/01-larbs-cmds-without-password

# Last message! Install complete!
finalize
clear
