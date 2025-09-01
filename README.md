# lsdiskowipe
Tool for quick analysis of physical disks and optionally start of nwipe to erase the content of disks.

## History and Name
The program started its career as eraseHDD. In fact, it should allow a pre-sort of disks that were to be prepared for resale.
Disks with reallocated sectors were considered unreliable and trashed. While [nwipe] (https://github.com/martijnvanbrummelen/nwipe) did the job of actual wiping
the disk, a helper programm for the preflight-checks was needed which would eventually start nwipe with a fitting set of
parameters. But this helper program offered the chance to identify disks that were not worth the time to try to wipe them, only to have to find after a time comsuming operation 
that the disk was broken. So these could be swapped before starting nwipe.
This tool got named eraseHDD, and did a good job.
Today every now and then a bunch of disks wants to be evaluated. So eraseHDD came back to life and development.
Now it proofed to be a good tool for evaluation of physical disks. Even without firing nwipe up.
Looking for an suitable name lsdisk was considered but found to be in use already. Besides that the name would not contain
the element of disk wiping.
So we have 'ls disks and optionally wipe them" now.

## Description
nwipe gives you an overview of the features and some critical health information about physical disks.
As of version 1.5 the programm lists Linux' /dev/sd* and /dev/nvme* physical devices with a lot of interesting information.
E.g. vendor, model, S/N, firmware version, capacity, interface type and speed, rpm, sectorsize, SMART Health, counted hours of operation,
reallocated sectors, current temperature, remaining lifetime for SSDs, other errors.
Version 1.8 added slot information for disks on supported HBAs, 1.11 added support for disks in LIS/Avago/Broadcom RAIDs and FARM reading for Seagate disks.

As it is written in perl it should be easily expandable.

## Installation
Run INSTALL

Possibly needed programs will get installed.
And the smart database shall get updated. Except when INSTALL is called with -C.

## Usage
run lsdiskowipe --help

## Status, ToDos
The programm comes as perl program with a simple installer to make sure needed tools are available and to drop the perl modules in a right place.
It is developed under debian bookworm currently but should run under most Linuxes.
Detection/display of host protected areas and the availability of a smart erase feature shall be displayed.

Possibly packages for Debian/Ubuntu, maybe RHEL/Rocky will follow.

The checks of the existence of required/recommended programs and useful reactions can be improved.

## Authors and acknowledgment
eraseHDD was developed by Alexander Pilch.
lsdiskowipe is developed by Alexander Pilch and Gerold Gruber.
 
## License
lsdiskowipe is published under the EU public licencse.
see https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12

