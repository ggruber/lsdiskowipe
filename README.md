# lsdiskowipe
Tool for quick analysis of physical disks and optionally start of nwipe to erase the content of disks.

## History and Name
The program started its career as eraseHDD. In fact, it should allow a pre-sort of disks that were be prepared for resale.
But disks with reallocated sectors were considered unreliable and sorted out. While [nwipe] (https://github.com/martijnvanbrummelen/nwipe) did the job of actual wiping
the disk, a helper programm for the preflight-checks was needed which would eventually start nwipe with a fitting set of
parameters.
It got named eraseHDD, and did a good job.
Now every now and then a bunch of disks wants to be evaluated. So eraseHDD came back to life and development.
Now it proofed to be a good tool for evaluation of physical disks. Even without firing nwipe up.
Looking for an suitable name lsdisk was considered but found to be in use already. Besides that the name would not contain
the element of disk wiping.
So we have 'ls disks and optionally wipe them" now.

## Description
nwipe gives you an overview over the features and some critical health information about physical disks.
As of version 1.5 the programm lists Linux' /dev/sd* and /dev/nvme* physical devices with a lot of interesting information.
E.g. vendor, model, S/N, firmware version, capacity, interface type and speed, rpm, sectorsize, SMART Health, counted hours of operation,
reallocated sectors, current temperature, remaining lifetime for SSDs, other errors.

As it is written in perl it should be easily expandable.

## Installation
Run INSTALL

Possibly needed programs will get installed.
And the smart database shall get updated.

## Usage
run lsdiskowipe --help

## Status, ToDos
The programm comes as perl program with a simple installer.
It is developed under debian bookworm currently but should run under most Linuxes.
Detection/display of host protected areas and the smart erase feature shall be displayed.

Possibly packages for Debian/Ubuntu, maybe RHEL/Rocky will follow.

The checks of the existence of required/recommended programs and useful reactions can be improved.

## Authors and acknowledgment
eraseHDD was developed by Alexander Pilch.
lsdiskowipe is developed by Alexander Pilch and Gerold Gruber.
 
## License
lsdiskowipe is published under the EU public licencse.
see https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12

