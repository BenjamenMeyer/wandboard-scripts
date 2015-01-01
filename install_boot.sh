#!/bin/bash

declare -u USERS_BOARD_TYPE=""
declare -l USERS_REQUESTED_OS=""

SDCARD_DRIVE=""
ROOTFS_PARTITION=""

BASE_DIR="${PWD}/.wandboard.tmp"
DOWNLOAD_DIR="${BASE_DIR}/downloads"
EXTRACT_DIR="${BASE_DIR}/extractions"
MOUNT_DIR="${BASE_DIR}/mounts"

UBOOT_URL="http://s3.armhf.com/dist/wand/wand-uboot.tar.xz"
UBOOT_FILE="${DOWNLOAD_DIR}/wand-uboot.tar.xz"
UBOOT_FILE_MD5="793bcbd2ed3b97af3c9d1f0170cfa8a9"
UBOOT_EXTRACT_DIR="${EXTRACT_DIR}/uboot"

LINUX_HEADERS_URL="http://s3.armhf.com/dist/wand/linux-headers-3.10.17.1-wand-armhf.com.tar.xz"
LINUX_HEADERS_FILE="${DOWNLOAD_DIR}/linux-headers-3.10.17.1-wand-armhf.com.tar.xz"
LINUX_HEADERS_FILE_MD5="2304a383bd96cf00303b809bf24d4c91"
LINUX_HEADERS_EXTRACT_DIR="${EXTRACT_DIR}/linux_headers"

ROOTFS_MOUNT="${MOUNT_DIR}/rootfs"

DEBIAN_75_ROOTFS_URL="http://s3.armhf.com/dist/wand/debian-wheezy-7.5-rootfs-3.10.17.1-wand-armhf.com.tar.xz"
DEBIAN_75_ROOTFS_FILE="${DOWNLOAD_DIR}/debian-wheezy-7.5-rootfs-3.10.17.1-wand-armhf.com.tar.xz"
DEBIAN_75_ROOTFS_FILE_MD5="10bc1acdb268440f1675eff5e8c44528"
DEBIAN_75_ROOTFS_EXTRACT_DIR="${EXTRACT_DIR}/debian75_rootfs"

UBUNTU_1404_ROOTFS_URL="http://s3.armhf.com/dist/wand/ubuntu-trusty-14.04-rootfs-3.10.17.1-wand-armhf.com.tar.xz"
UBUNTU_1404_ROOTFS_FILE="${DOWNLOAD_DIR}/ubuntu-trusty-14.04-rootfs-3.10.17.1-wand-armhf.com.tar.xz"
UBUNTU_1404_ROOTFS_FILE_MD5="5ed346ebba924c85bd36209ae8875f33"
UBUNTU_1404_ROOTFS_EXTRACT_DIR="${EXTRACT_DIR}/ubuntu1404_rootfs"

printHelp()
	{
	local -i returnValue=0
	if [ -v $1 ]; then
		let -i returnValue=$1
	fi
	echo "install_boot.sh --board-type <board type> --os <os> --sdcard <sdcard drive> --root <root partition>"
	echo
	echo "	<board type> is one of SOLO, DUAL, QUAD"
	echo "	<os> is one of debian75, ubuntu1404"
	echo "	<sdcard drive> is the local drive for the SD Card, f.e /dev/mmcblk0"
	echo "	<root partition> is the partition for the Root FS, f.e /dev/mmcblk0p1"
	echo
	echo "Wandboard Type: ${USERS_BOARD_TYPE}"
	echo "  Requested OS: ${USERS_REQUESTED_OS}"
	echo " SD Card Drive: ${SDCARD_DRIVE}"
	echo "Root Fs Partition: ${ROOTFS_PARTITION}"
	echo
	exit ${returnValue}
	}

checkDir()
	{
	local DIR_TO_CHECK="${1}"
	if [ -d "${DIR_TO_CHECK}" ]; then	
		return 0
	else
		mkdir "${DIR_TO_CHECK}"
		return $?
	fi
	}

checkBaseDir()
	{
	checkDir "${BASE_DIR}"
	}

checkDownloadDir()
	{
	checkBaseDir
	if [ $? -eq 0 ]; then
		checkDir "${DOWNLOAD_DIR}"
		return $?
	else
		return 1
	fi
	}

checkExtractionDir()
	{
	checkBaseDir
	if [ $? -eq 0 ]; then
		checkDir "${EXTRACT_DIR}"
		return $?
	else
		return 1
	fi
	}

downloadFile()
	{
	local URL="${1}"
	local ON_DISK="${2}"
	local REMOTE_MD5="${3}"
	checkDownloadDir
	if [ $? -eq 0 ]; then
		wget "${URL}" --output-document "${ON_DISK}"
		if [ $? -eq 0 ]; then
			local LOCAL_MD5=`md5sum ${ON_DISK} | cut -f 1 -d ' '`
			if [ "${LOCAL_MD5}" == "${REMOTE_MD5}" ]; then
				return 0
			else
				return 3
			fi
		else
			return 2
		fi
	else
		return 1
	fi
	}

extractData()
	{
	local FILE_TO_EXTRACT="${1}"
	local EXTRACTION_DIR="${2}"
	
	checkExtractionDir
	if [ $? -eq 0 ]; then
		checkDir "${EXTRACTION_DIR}"
		if [ $? -eq 0 ]; then
			pushd "${EXTRACTION_DIR}"
				tar xJvf "${FILE_TO_EXTRACT}"
				let -i returnValue=$?
			popd
			return ${returnValue}
		else
			return 2
		fi
	else
		return 1
	fi
	}

cleanupExtractDir()
	{
	if [ -d "${EXTRACT_DIR}" ]; then
		pushd "${EXTRACT_DIR}"
			rm -Rf *
		popd
	else
		return 0
	fi
	}

writeToSdCard()
	{
	local IMAGE="${1}"
	local BS="${2}"
	local SEEK="${3}"

	dd if="${IMAGE}" of="${SDCARD_DRIVE}" bs=${BS} seek=${SEEK}
	if [ $? -eq 0 ]; then
		sync
		return $?
	else
		return 1
	fi
	}

extractToSdCard()
	{
	local DEV_TO_MOUNT="${1}"
	local FILE_TO_EXTRACT="${2}"
	local MOUNT_LOCATION="${3}"
	checkDir "${MOUNT_DIR}"
	if [ $? -eq 0 ]; then
		checkDir "${MOUNT_LOCATION}"
		if [ $? -eq 0 ]; then
			mount "${DEV_TO_MOUNT}" "${MOUNT_LOCATION}"
			if [ $? -eq 0 ]; then
				extractData "${FILE_TO_EXTRACT}" "${MOUNT_LOCATION}"
				local -i returnValue=$?
				if [ ${returnValue} -eq 0 ]; then
					sync
				fi

				umount "${DIR_TO_MOUNT}"
				return ${returnValue}
			else
				return 3
			fi
		else
			return 2
		fi
	else
		return 1
	fi
	}

getWandboardUboot()
	{
	downloadFile "${UBOOT_URL}" "${UBOOT_FILE}" "${UBOOT_FILE_MD5}"
	return $?
	}

extractWandboardUboot()
	{
	extractData "${UBOOT_FILE}" "${UBOOT_EXTRACT_DIR}"
	return $?
	}

installUBootToSdCard()
	{
	local BOARD_TYPE="${1}"

	IMAGE_FILE=""
	case "${BOARD_TYPE}" in
		"SOLO")
			# Wandboard Solo
			IMAGE_FILE="${UBOOT_EXTRACT_DIR}/wand-uboot/wand-uboot-solo.imx"
			;;
		"DUAL")
			# Wandboard Dual
			IMAGE_FILE="${UBOOT_EXTRACT_DIR}/wand-uboot/wand-uboot-dual.imx"
			;;
		"QUAD")
			# Wandboard Quad
			IMAGE_FILE="${UBOOT_EXTRACT_DIR}/wand-uboot/wand-uboot-quad.imx"
			;;
		*)
			echo "Unknown Wandboard Board Type: ${BOARD_TYPE}" 
			return 1
			;;
	esac

	if [ -n "${IMAGE_FILE}" ]; then
		writeToSdCard "${IMAGE_FILE}" 512 2
		return $?
	else
		return 2
	fi
	}

installUBoot()
	{
	local BOARD_TYPE="${1}"
	getWandboardUboot
	if [ $? -eq 0 ]; then
		extractWandboardUboot
		if [ $? -eq 0 ]; then
			installUBootToSdCard "${BOARD_TYPE}"
			if [ $? -eq 0 ]; then
				return 0
			else
				echo "Failed to write the UBoot Boot Loader"
			fi
		else
			echo "Failed to extract the Uboot Boot Loader"
		fi
	else
		echo "Failed to download Uboot Boot Loader"
	fi
	}

getLinuxHeaders()
	{
	downloadFile "${LINUX_HEADERS_URL}" "${LINUX_HEADERS_FILE}" "${LINUX_HEADERS_FILE_MD5}"
	return $?
	}

getDebian75()
	{
	downloadFile "${DEBIAN_75_ROOTFS_URL}" "${DEBIAN_75_ROOTFS_FILE}" "${DEBIAN_75_ROOTFS_FILE_MD5}"
	return $?
	}

extractDebian75()
	{
	extractToSdCard "${ROOTFS_PARTITION}" "${DEBIAN_75_ROOTFS_FILE}" "${ROOTFS_MOUNT}"
	return $?
	}

installDebian75()
	{
	getDebian75
	if [ $? -eq 0 ]; then
		extractDebian75
		if [ $? -eq 0 ]; then
			echo "Successfully installed Debian 7.5 Root FS"
		else
			echo "Failed to extract Debian 7.5 Root FS"
		fi
	else
		echo "Unable to download Debian 7.5"
	fi
	}

getUbuntu1404()
	{
	downloadFile "${UBUNTU_1404_ROOTFS_URL}" "${UBUNTU_1404_ROOTFS_FILE}" "${UBUNTU_1404_ROOTFS_FILE_MD5}"
	return $?
	}

extractUbuntu1404()
	{
	extractToSdCard "${ROOTFS_PARTITION}" "${UBUNTU_1404_ROOTFS_FILE}" "${ROOTFS_MOUNT}"
	return $?
	}

installUbuntu1404()
	{
	getUbuntu1404
	if [ $? -eq 0 ]; then
		extractUbuntu1404
		if [ $? -eq 0 ]; then
			echo "Successfully installed Ubuntu 14.04 Root FS"
		else
			echo "Failed to extract Ubuntu 14.04 Root FS"
		fi
	else
		echo "Unable to download Ubuntu 14.04"
	fi
	}


#
# Check the arguments provided by the user so we know what to do
#
ARG_PARAMETER=""
for argument in ${@}
do
	case "${argument}" in
		"--board-type")
			ARG_PARAMETER="board type"
			;;
		"--os")
			ARG_PARAMETER="os"
			;;
		"--sdcard")
			ARG_PARAMETER="sdcard"
			;;
		"--root")
			ARG_PARAMETER="rootfs"
			;;
		*)
			case "${ARG_PARAMETER}" in
				"board type")
					echo "Setting board type from ${USERS_BOARD_TYPE} to ${argument}"
					USERS_BOARD_TYPE="${argument}"
					unset ARG_PARAMETER
					;;
				"os")
					USERS_REQUESTED_OS="${argument}"
					unset ARG_PARAMETER
					;;
				"sdcard")
					SDCARD_DRIVE="${argument}"
					unset ARG_PARAMETER
					;;
				"rootfs")
					ROOTFS_PARTITION="${argument}"
					unset ARG_PARAMETER
					;;
				*)
					echo "Unknown parameter: ${argument}"
					printHelp 1
					;;
			esac
	esac
done

# let -u UPDATED_USERS_BOARD_TYPE="${USERS_BOARD_TYPE}"
# let -l UPDATED_USERS_REQUESTED_OS="${USERS_REQUESTED_OS}"

# USERS_BOARD_TYPE="${UPDATED_USERS_BOARD_TYPE}"
# USERS_REQUSTED_OS="${UPDATED_USERS_REQUESTED_OS}"

if [ -z "${USERS_BOARD_TYPE}" ]; then
	echo "Unknown board type"
	printHelp 3
elif [ -z "${USERS_REQUESTED_OS}" ]; then
	echo "Unknown OS"
	printHelp 4
elif [ -z "${SDCARD_DRIVE}" ]; then
	echo "Unknown SD Card Drive"
	printHelp 5
elif [ -z "${ROOTFS_PARTITION}" ]; then
	echo "Unknown Root FS Partition"
	printHelp 6
fi

#
# Report what we found to the user before we do it
#
echo "Wandboard Type: ${USERS_BOARD_TYPE}"
echo "  Requested OS: ${USERS_REQUESTED_OS}"
echo " SD Card Drive: ${SDCARD_DRIVE}"
echo "Root Fs Partition: ${ROOTFS_PARTITION}"

#
# Now go ahead and do it
#
installUBoot "${USERS_BOARD_TYPE}"
if [ $? -eq 0 ]; then
	case "${USERS_REQUESTED_OS}" in
		"debian75")
			installDebian75
			exit $?
			;;

		"ubuntu1404")
			installUbuntu1404
			exit $?
			;;
		*)
			echo "Unknown Root FS to install"
			exit 2
			;;
	esac
fi
