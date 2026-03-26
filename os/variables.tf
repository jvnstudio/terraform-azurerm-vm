variable "vm_os_simple" {
  type    = string
  default = ""
}

variable "standard_os" {
  type = map(string)
  default = {
    "UbuntuServer"  = "Canonical,0001-com-ubuntu-server-jammy,22_04-lts"
    "WindowsServer" = "MicrosoftWindowsServer,WindowsServer,2022-Datacenter"
    "RHEL"          = "RedHat,RHEL,8-lvm-gen2"
    "openSUSE-Leap" = "SUSE,openSUSE-Leap,15-4"
    "CentOS"        = "OpenLogic,CentOS,7_9-gen2"
    "Debian"        = "Debian,debian-11,11-gen2"
    "CoreOS"        = "CoreOS,CoreOS,Stable"
    "SLES"          = "SUSE,SLES,15-sp4-gen2"
  }
}
