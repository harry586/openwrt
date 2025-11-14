#!/bin/bash

get_device_config() {
    local device=$1
    case $device in
        "ac42u")
            echo "asus_rt-ac42u"
            ;;
        *)
            echo ""
            ;;
    esac
}

validate_device_support() {
    local build_dir=$1
    local platform=$2
    local device=$3
    
    if [ -f "$build_dir/target/linux/$platform/image/generic.mk" ]; then
        if grep -q "define Device.*$device" "$build_dir/target/linux/$platform/image/generic.mk"; then
            return 0
        fi
    fi
    return 1
}
