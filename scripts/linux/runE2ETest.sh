#!/bin/bash

###############################################################################
# This script is used to streamline running E2E tests for Linux.
###############################################################################
set -e

function clean_up() {
    print_highlighted_message 'Clean up'

    echo 'Stop IoT Edge services'
    systemctl stop iotedge.socket iotedge.mgmt.socket || true
    systemctl kill iotedge || true
    systemctl stop iotedge || true

    echo 'Remove IoT Edge and config file'
    apt-get purge libiothsm-std --yes || true
    rm -rf /var/lib/iotedge/
    rm -rf /var/run/iotedge/
    rm -rf /etc/iotedge/config.yaml

    echo 'Do docker system prune'
    docker system prune -af || true
}

function create_iotedge_service_config {
    print_highlighted_message 'Create IoT Edge service config'
    mkdir /etc/systemd/system/iotedge.service.d/ || true
    bash -c "echo '[Service]
Environment=IOTEDGE_LOG=edgelet=debug' > /etc/systemd/system/iotedge.service.d/override.conf"
}

function get_image_architecture_label() {
    local arch
    arch="$(uname -m)"
    local label

    case "$arch" in
        'x86_64' ) label='amd64';;
        'armv71' ) label='arm32v7';;
        *) print_error "Unsupported OS architecture: $arch"; exit 1;;
    esac

    echo "$label"
}

function get_iotedge_quickstart_artifact_file() {
    local path
    if [ "$image_architecture_label" = 'amd64' ]; then
        path="$E2E_TEST_DIR/artifacts/core-linux/IotEdgeQuickstart.linux-x64.tar.gz"
    else
        path="$E2E_TEST_DIR/artifacts/core-linux/IotEdgeQuickstart.linux-arm.tar.gz"
    fi

    echo "$path"
}

function get_iotedged_artifact_folder() {
    local path
    if [ "$image_architecture_label" = 'amd64' ]; then
        path="$E2E_TEST_DIR/artifacts/iotedged-ubuntu-amd64"
    else
        path="$E2E_TEST_DIR/artifacts/iotedged-ubuntu-armhf"
    fi

    echo "$path"
}

function get_leafdevice_artifact_file() {
    local path
    if [ "$image_architecture_label" = 'amd64' ]; then
        path="$E2E_TEST_DIR/artifacts/core-linux/LeafDevice.linux-x64.tar.gz"
    else
        path="$E2E_TEST_DIR/artifacts/core-linux/LeafDevice.linux-arm.tar.gz"
    fi

    echo "$path"
}

function prepare_test_from_artifacts() {
    print_highlighted_message 'Prepare test from artifacts'

    echo 'Remove working folder'
    rm -rf "$working_folder"
    mkdir -p "$working_folder"

    declare -a pkg_list=( $iotedged_artifact_folder/*.deb )
    iotedge_package="${pkg_list[*]}"
    echo "iotedge_package=$iotedge_package"
    
    echo 'Extract quickstart to working folder'
    mkdir -p "$quickstart_working_folder"
    tar -C "$quickstart_working_folder" -xzf "$iotedge_quickstart_artifact_file"

    if [[ "${TEST_NAME,,}" == 'quickstartcerts' ]]; then
        echo 'Extract leaf device to working folder'
        mkdir -p "$leafdevice_working_folder"
        tar -C "$leafdevice_working_folder" -xzf "$leafdevice_artifact_file"
    fi

    if [[ "${TEST_NAME,,}" == directmethod* ]] ||
       [[ "${TEST_NAME,,}" == 'longhaul' ]] ||
       [[ "${TEST_NAME,,}" == 'stress' ]] ||
       [[ "${TEST_NAME,,}" == 'tempfilter' ]] ||
       [[ "${TEST_NAME,,}" == 'tempfilterfunctions' ]]; then
        case "${TEST_NAME,,}" in
            'directmethodamqp')
                echo "Copy deployment file from $dm_module_to_module_deployment_artifact_file"
                cp "$dm_module_to_module_deployment_artifact_file" "$deployment_working_file"

                sed -i -e "s@<UpstreamProtocol>@Amqp@g" "$deployment_working_file"
                sed -i -e "s@<ClientTransportType>@Amqp_Tcp_Only@g" "$deployment_working_file";;
            'directmethodamqpws')
                echo "Copy deployment file from $dm_module_to_module_deployment_artifact_file"
                cp "$dm_module_to_module_deployment_artifact_file" "$deployment_working_file"

                sed -i -e "s@<UpstreamProtocol>@Amqpws@g" "$deployment_working_file"
                sed -i -e "s@<ClientTransportType>@Amqp_WebSocket_Only@g" "$deployment_working_file";;
            'directmethodmqtt')
                echo "Copy deployment file from $dm_module_to_module_deployment_artifact_file"
                cp "$dm_module_to_module_deployment_artifact_file" "$deployment_working_file"

                if [[ $image_architecture_label == 'arm32v7' ]]; then
                    sed -i -e "s@<MqttEventsProcessorThreadCount>@1@g" "$deployment_working_file"
                fi
                sed -i -e "s@<UpstreamProtocol>@Mqtt@g" "$deployment_working_file"
                sed -i -e "s@<ClientTransportType>@Mqtt_Tcp_Only@g" "$deployment_working_file";;
            'directmethodmqttws')
                echo "Copy deployment file from $dm_module_to_module_deployment_artifact_file"
                cp "$dm_module_to_module_deployment_artifact_file" "$deployment_working_file"
                
                if [[ $image_architecture_label == 'arm32v7' ]]; then
                    sed -i -e "s@<MqttEventsProcessorThreadCount>@1@g" "$deployment_working_file"
                fi
                sed -i -e "s@<UpstreamProtocol>@Mqttws@g" "$deployment_working_file"
                sed -i -e "s@<ClientTransportType>@Mqtt_WebSocket_Only@g" "$deployment_working_file";;
            'longhaul' | 'stress')
                if [[ "${TEST_NAME,,}" == 'longhaul' ]]; then
                    echo "Copy deployment file from $long_haul_deployment_artifact_file"
                    cp "$long_haul_deployment_artifact_file" "$deployment_working_file"
                    sed -i -e "s@<LoadGen.TransportType>@$LOADGEN_TRANSPORT_TYPE@g" "$deployment_working_file"
                    sed -i -e "s@<ServiceClientConnectionString>@$IOTHUB_CONNECTION_STRING@g" "$deployment_working_file"
                else
                    echo "Copy deployment file from $stress_deployment_artifact_file"
                    cp "$stress_deployment_artifact_file" "$deployment_working_file"
                    sed -i -e "s@<LoadGen1.TransportType>@$LOADGEN1_TRANSPORT_TYPE@g" "$deployment_working_file"
                    sed -i -e "s@<LoadGen2.TransportType>@$LOADGEN2_TRANSPORT_TYPE@g" "$deployment_working_file"
                    sed -i -e "s@<LoadGen3.TransportType>@$LOADGEN3_TRANSPORT_TYPE@g" "$deployment_working_file"
                    sed -i -e "s@<LoadGen4.TransportType>@$LOADGEN4_TRANSPORT_TYPE@g" "$deployment_working_file"
                fi

                local escapedSnitchAlertUrl
                local escapedSnitchBuildId
                sed -i -e "s@<Analyzer.EventHubConnectionString>@$EVENTHUB_CONNECTION_STRING@g" "$deployment_working_file"
                sed -i -e "s@<LoadGen.MessageFrequency>@$LOADGEN_MESSAGE_FREQUENCY@g" "$deployment_working_file"
                escapedSnitchAlertUrl="${SNITCH_ALERT_URL//&/\\&}"
                escapedSnitchBuildId="${SNITCH_BUILD_NUMBER//./}"
                sed -i -e "s@<Snitch.AlertUrl>@$escapedSnitchAlertUrl@g" "$deployment_working_file"
                sed -i -e "s@<Snitch.BuildNumber>@$SNITCH_BUILD_NUMBER@g" "$deployment_working_file"
                sed -i -e "s@<Snitch.BuildId>@$escapedSnitchBuildId@g" "$deployment_working_file"
                sed -i -e "s@<Snitch.ReportingIntervalInSecs>@$SNITCH_REPORTING_INTERVAL_IN_SECS@g" "$deployment_working_file"
                sed -i -e "s@<Snitch.StorageAccount>@$SNITCH_STORAGE_ACCOUNT@g" "$deployment_working_file"
                sed -i -e "s@<Snitch.StorageMasterKey>@$SNITCH_STORAGE_MASTER_KEY@g" "$deployment_working_file"
                sed -i -e "s@<Snitch.TestDurationInSecs>@$SNITCH_TEST_DURATION_IN_SECS@g" "$deployment_working_file";;
            'tempfilter')
                echo "Copy deployment file from $module_to_module_deployment_artifact_file"
                cp "$module_to_module_deployment_artifact_file" "$deployment_working_file";;
            'tempfilterfunctions')
                echo "Copy deployment file from $module_to_functions_deployment_artifact_file"
                cp "$module_to_functions_deployment_artifact_file" "$deployment_working_file";;
        esac

        sed -i -e "s@<Architecture>@$image_architecture_label@g" "$deployment_working_file"
        sed -i -e "s@<OptimizeForPerformance>@true@g" "$deployment_working_file"
        sed -i -e "s/<Build.BuildNumber>/$ARTIFACT_IMAGE_BUILD_NUMBER/g" "$deployment_working_file"
        sed -i -e "s@<CR.Username>@$CONTAINER_REGISTRY_USERNAME@g" "$deployment_working_file"
        sed -i -e "s@<CR.Password>@$CONTAINER_REGISTRY_PASSWORD@g" "$deployment_working_file"
    fi
}

function print_error() {
    local message=$1
    local red='\033[0;31m'
    local color_reset='\033[0m'
    echo -e "${red}$message${color_reset}"
}

function print_highlighted_message() {
    local message=$1
    local cyan='\033[0;36m'
    local color_reset='\033[0m'
    echo -e "${cyan}$message${color_reset}"
}

function print_logs() {
    local ret=$1
    local test_end_time=$2
    local elapsed_seconds=$3

    elapsed_time="$(TZ=UTC0 printf '%(%H:%M:%S)T\n' "$elapsed_seconds")"
    print_highlighted_message "Test completed at $test_end_time, took $elapsed_time."

    if (( ret < 1 )); then
        return;
    fi

    print_highlighted_message 'Print logs'
    print_highlighted_message 'LOGS FROM IOTEDGED'
    journalctl -u iotedge -u docker --since "$test_start_time" --no-pager || true

    print_highlighted_message 'EDGE AGENT LOGS'
    docker logs edgeAgent || true

    print_highlighted_message 'EDGE HUB LOGS'
    docker logs edgeHub || true

    if [[ "${TEST_NAME,,}" == 'tempsensor' ]]; then
        print_highlighted_message 'TEMP SENSOR LOGS'
        docker logs tempSensor || true
    fi

    if [[ "${TEST_NAME,,}" == 'tempfilter' ]]; then
        print_highlighted_message 'TEMP FILTER LOGS'
        docker logs tempFilter || true
    fi

    if [[ "${TEST_NAME,,}" == 'tempfilterfunctions' ]]; then
        print_highlighted_message 'TEMP FILTER FUNCTIONS LOGS'
        docker logs tempFilterFunctions || true
    fi

    if [[ "${TEST_NAME,,}" == directmethod* ]]; then
        print_highlighted_message 'DIRECT MTEHOD SENDER LOGS'
        docker logs DirectMethodSender || true

        print_highlighted_message 'DIRECT MTEHOD RECEIVER LOGS'
        docker logs DirectMethodReceiver || true
    fi
}

function process_args() {
    print_highlighted_message 'Process arguments'
    saveNextArg=0
    for arg in "$@"
    do
        if [ $saveNextArg -eq 1 ]; then
            E2E_TEST_DIR="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 2 ]; then
            RELEASE_LABEL="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 3 ]; then
            ARTIFACT_IMAGE_BUILD_NUMBER="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 4 ]; then
            TEST_NAME="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 5 ]; then
            CONTAINER_REGISTRY="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 6 ]; then
            CONTAINER_REGISTRY_USERNAME="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 7 ]; then
            CONTAINER_REGISTRY_PASSWORD="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 8 ]; then
            IOTHUB_CONNECTION_STRING="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 9 ]; then
            EVENTHUB_CONNECTION_STRING="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 10 ]; then
            LOADGEN_TRANSPORT_TYPE="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 11 ]; then
            LOADGEN_MESSAGE_FREQUENCY="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 12 ]; then
            SNITCH_ALERT_URL="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 13 ]; then
            SNITCH_BUILD_NUMBER="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 14 ]; then
            SNITCH_REPORTING_INTERVAL_IN_SECS="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 15 ]; then
            SNITCH_STORAGE_ACCOUNT="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 16 ]; then
            SNITCH_STORAGE_MASTER_KEY="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 17 ]; then
            SNITCH_TEST_DURATION_IN_SECS="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 18 ]; then
            LOADGEN1_TRANSPORT_TYPE="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 19 ]; then
            LOADGEN2_TRANSPORT_TYPE="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 20 ]; then
            LOADGEN3_TRANSPORT_TYPE="$arg"
            saveNextArg=0
        elif [ $saveNextArg -eq 21 ]; then
            LOADGEN4_TRANSPORT_TYPE="$arg"
            saveNextArg=0
        else
            case "$arg" in
                '-h' | '--help' ) usage;;
                '-testDir' ) saveNextArg=1;;
                '-releaseLabel' ) saveNextArg=2;;
                '-artifactImageBuildNumber' ) saveNextArg=3;;
                '-testName' ) saveNextArg=4;;
                '-containerRegistry' ) saveNextArg=5;;
                '-containerRegistryUsername' ) saveNextArg=6;;
                '-containerRegistryPassword' ) saveNextArg=7;;
                '-iotHubConnectionString' ) saveNextArg=8;;
                '-eventHubConnectionString' ) saveNextArg=9;;
                '-loadGenTransportType' ) saveNextArg=10;;
                '-loadGenMessageFrequency' ) saveNextArg=11;;
                '-snitchAlertUrl' ) saveNextArg=12;;
                '-snitchBuildNumber' ) saveNextArg=13;;
                '-snitchReportingIntervalInSecs' ) saveNextArg=14;;
                '-snitchStorageAccount' ) saveNextArg=15;;
                '-snitchStorageMasterKey' ) saveNextArg=16;;
                '-snitchTestDurationInSecs' ) saveNextArg=17;;
                '-loadGen1TransportType' ) saveNextArg=18;;
                '-loadGen2TransportType' ) saveNextArg=19;;
                '-loadGen3TransportType' ) saveNextArg=20;;
                '-loadGen4TransportType' ) saveNextArg=21;;
                * ) usage;;
            esac
        fi
    done

    # Required parameters
    [[ -z "$RELEASE_LABEL" ]] && { print_error 'Release label is required.'; exit 1; }
    [[ -z "$ARTIFACT_IMAGE_BUILD_NUMBER" ]] && { print_error 'Artifact image build number is required'; exit 1; }
    [[ -z "$TEST_NAME" ]] && { print_error 'Test name is required'; exit 1; }
    [[ -z "$CONTAINER_REGISTRY_PASSWORD" ]] && { print_error 'Container registry password is required'; exit 1; }
    [[ -z "$IOTHUB_CONNECTION_STRING" ]] && { print_error 'IoT hub connection string is required'; exit 1; }
    [[ -z "$EVENTHUB_CONNECTION_STRING" ]] && { print_error 'Event hub connection string is required'; exit 1; }

    echo 'Required parameters are provided'
}

function run_all_tests()
{
    local funcRet=0
    local testRet=0

    TEST_NAME='DirectMethodAmqp'
    run_directmethodamqp_test && funcRet=$? || funcRet=$?

    TEST_NAME='DirectMethodAmqpws'
    run_directmethodamqpws_test && testRet=$? || testRet=$?
    if (( funcRet = 0 )); then funcRet=$testRet; fi

    TEST_NAME='DirectMethodMqtt'
    run_directmethodmqtt_test && testRet=$? || testRet=$?
    if (( funcRet = 0 )); then funcRet=$testRet; fi

    TEST_NAME='DirectMethodMqttws'
    run_directmethodmqttws_test && testRet=$? || testRet=$?
    if (( funcRet = 0 )); then funcRet=$testRet; fi
    
    TEST_NAME='TempFilter'
    run_tempfilter_test && testRet=$? || testRet=$?
    if (( funcRet = 0 )); then funcRet=$testRet; fi
    
    TEST_NAME='TempFilterFunctions'
    run_tempfilterfunctions_test && testRet=$? || testRet=$?
    if (( funcRet = 0 )); then funcRet=$testRet; fi

    TEST_NAME='TempSensor'
    run_tempsensor_test && testRet=$? || testRet=$?
    if (( funcRet = 0 )); then funcRet=$testRet; fi

    return $funcRet
}

function run_directmethod_test()
{
    SECONDS=0
    local ret=0
    "$quickstart_working_folder/IotEdgeQuickstart" \
        -d "$device_id" \
        -a "$iotedge_package" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "$EVENTHUB_CONNECTION_STRING" \
        -r "$CONTAINER_REGISTRY" \
        -u "$CONTAINER_REGISTRY_USERNAME" \
        -p "$CONTAINER_REGISTRY_PASSWORD" \
        -t "$ARTIFACT_IMAGE_BUILD_NUMBER-linux-$image_architecture_label" \
        --verify-data-from-module "DirectMethodSender" \
        -l "$deployment_working_file" && ret=$? || ret=$?

    local elapsed_seconds=$SECONDS
    test_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_logs $ret "$test_end_time" $elapsed_seconds

    return $ret
}

function run_directmethodamqp_test() {
    print_highlighted_message "Run DirectMethod Amqp test on $image_architecture_label"
    test_setup

    device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-DMAmqp"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run DirectMethod Amqp test with -d '$device_id' started at $test_start_time"

    run_directmethod_test && ret=$? || ret=$?

    return $ret
}

function run_directmethodamqpws_test() {
    print_highlighted_message "Run DirectMethod Amqpws test on $image_architecture_label"
    test_setup

    device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-DMAmqpws"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run DirectMethod Amqpws test with -d '$device_id' started at $test_start_time"

    run_directmethod_test && ret=$? || ret=$?

    return $ret
}

function run_directmethodmqtt_test() {
    print_highlighted_message "Run DirectMethod Mqtt test on $image_architecture_label"
    test_setup

    device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-DMMqtt"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run DirectMethod Mqtt test with -d '$device_id' started at $test_start_time"

    run_directmethod_test && ret=$? || ret=$?

    return $ret
}

function run_directmethodmqttws_test() {
    print_highlighted_message "Run DirectMethod Mqttws test on $image_architecture_label"
    test_setup

    device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-DMMqttws"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run DirectMethod Mqttws test with -d '$device_id' started at $test_start_time"

    run_directmethod_test && ret=$? || ret=$?

    return $ret
}

function run_longhaul_test() {
    print_highlighted_message "Run Long Haul test on $image_architecture_label"
    test_setup

    local device_id="$RELEASE_LABEL-Linux-$image_architecture_label-longhaul"

    sed -i -e "s@<Analyzer.DeviceID>@$device_id@g" "$deployment_working_file"

    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run Long Haul test with -d '$device_id' started at $test_start_time"

    SECONDS=0
    local ret=0
    "$quickstart_working_folder/IotEdgeQuickstart" \
        -d "$device_id" \
        -a "$iotedge_package" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "$EVENTHUB_CONNECTION_STRING" \
        -r "$CONTAINER_REGISTRY" \
        -u "$CONTAINER_REGISTRY_USERNAME" \
        -p "$CONTAINER_REGISTRY_PASSWORD" \
        -t "$ARTIFACT_IMAGE_BUILD_NUMBER-linux-$image_architecture_label" \
        --leave-running=All \
        -l "$deployment_working_file" \
        --no-verify && ret=$? || ret=$?

    local elapsed_seconds=$SECONDS
    test_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_logs $ret "$test_end_time" $elapsed_seconds

    return $ret
}

function run_quickstartcerts_test() {
    print_highlighted_message "Run Quickstart Certs test on $image_architecture_label"
    test_setup

    local device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-QuickstartCert"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run Quickstart Certs test with -d '$device_id' started at $test_start_time"

    SECONDS=0
    local ret=0
    "$quickstart_working_folder/IotEdgeQuickstart" \
        -d "$device_id" \
        -a "$iotedge_package" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "doesNotNeed" \
        -n "$(hostname)" \
        -r "$CONTAINER_REGISTRY" \
        -u "$CONTAINER_REGISTRY_USERNAME" \
        -p "$CONTAINER_REGISTRY_PASSWORD" \
        -t "$ARTIFACT_IMAGE_BUILD_NUMBER-linux-$image_architecture_label" \
        --leave-running=Core \
        --optimize_for_performance=true \
        --no-verify && ret=$? || ret=$?

    declare -a certs=( /var/lib/iotedge/hsm/certs/edge_owner_ca*.pem )
    echo "cert: ${certs[0]}"
    # Workaround for multiple certificates in the x509store - remove this after quick start certs have Authority Key Identifier
    rm -rf ~/.dotnet/corefx/cryptography/x509stores/root/

    "$leafdevice_working_folder/LeafDevice" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "$EVENTHUB_CONNECTION_STRING" \
        -d "$device_id-leaf" \
        -ct "${certs[0]}" \
        -ed "$(hostname)" && ret=$? || ret=$? 

    local elapsed_seconds=$SECONDS
    test_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_logs $ret "$test_end_time" $elapsed_seconds

    return $ret
}

function run_stress_test() {
    print_highlighted_message "Run Stress test on $image_architecture_label"
    test_setup

    local device_id="$RELEASE_LABEL-Linux-$image_architecture_label-stress"

    sed -i -e "s@<Analyzer.DeviceID>@$device_id@g" "$deployment_working_file"

    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run Stress test with -d '$device_id' started at $test_start_time"

    SECONDS=0
    local ret=0
    "$quickstart_working_folder/IotEdgeQuickstart" \
        -d "$device_id" \
        -a "$iotedge_package" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "$EVENTHUB_CONNECTION_STRING" \
        -r "$CONTAINER_REGISTRY" \
        -u "$CONTAINER_REGISTRY_USERNAME" \
        -p "$CONTAINER_REGISTRY_PASSWORD" \
        -t "$ARTIFACT_IMAGE_BUILD_NUMBER-linux-$image_architecture_label" \
        --leave-running=All \
        -l "$deployment_working_file" \
        --no-verify && ret=$? || ret=$?

    local elapsed_seconds=$SECONDS
    test_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_logs $ret "$test_end_time" $elapsed_seconds

    return $ret
}

function run_tempfilter_test() {
    print_highlighted_message "Run TempFilter test on $image_architecture_label"
    test_setup

    local device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-tempFilter"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run TempFilter test with -d '$device_id' started at $test_start_time"

    SECONDS=0
    local ret=0
    "$quickstart_working_folder/IotEdgeQuickstart" \
        -d "$device_id" \
        -a "$iotedge_package" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "$EVENTHUB_CONNECTION_STRING" \
        -r "$CONTAINER_REGISTRY" \
        -u "$CONTAINER_REGISTRY_USERNAME" \
        -p "$CONTAINER_REGISTRY_PASSWORD" \
        --verify-data-from-module "tempFilter" \
        -t "$ARTIFACT_IMAGE_BUILD_NUMBER-linux-$image_architecture_label" \
        -l "$deployment_working_file" && ret=$? || ret=$?

    local elapsed_seconds=$SECONDS
    test_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_logs $ret "$test_end_time" $elapsed_seconds

    return $ret
}

function run_tempfilterfunctions_test() {
    print_highlighted_message "Run TempFilterFunctions test on $image_architecture_label"
    test_setup

    local device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-tempFilterFunc"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run TempFilterFunctions test with -d '$device_id' started at $test_start_time"

    SECONDS=0
    local ret=0
    "$quickstart_working_folder/IotEdgeQuickstart" \
        -d "$device_id" \
        -a "$iotedge_package" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "$EVENTHUB_CONNECTION_STRING" \
        -r "$CONTAINER_REGISTRY" \
        -u "$CONTAINER_REGISTRY_USERNAME" \
        -p "$CONTAINER_REGISTRY_PASSWORD" \
        --verify-data-from-module "tempFilterFunctions" \
        -t "$ARTIFACT_IMAGE_BUILD_NUMBER-linux-$image_architecture_label" \
        -l "$deployment_working_file" && ret=$? || ret=$?

    local elapsed_seconds=$SECONDS
    test_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_logs $ret "$test_end_time" $elapsed_seconds

    return $ret
}

function run_tempsensor_test() {
    print_highlighted_message "Run TempSensor test on $image_architecture_label"
    test_setup

    local device_id="e2e-$RELEASE_LABEL-Linux-$image_architecture_label-tempSensor"
    test_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_highlighted_message "Run TempSensor test with -d '$device_id' started at $test_start_time"

    SECONDS=0
    local ret=0
    "$quickstart_working_folder/IotEdgeQuickstart" \
        -d "$device_id" \
        -a "$iotedge_package" \
        -c "$IOTHUB_CONNECTION_STRING" \
        -e "$EVENTHUB_CONNECTION_STRING" \
        -r "$CONTAINER_REGISTRY" \
        -u "$CONTAINER_REGISTRY_USERNAME" \
        -p "$CONTAINER_REGISTRY_PASSWORD" \
        -tw "$E2E_TEST_DIR/artifacts/core-linux/e2e_test_files/twin_test_tempSensor.json" \
        --optimize_for_performance=true \
        -t "$ARTIFACT_IMAGE_BUILD_NUMBER-linux-$image_architecture_label" && ret=$? || ret=$?

    local elapsed_seconds=$SECONDS
    test_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    print_logs $ret "$test_end_time" $elapsed_seconds

    return $ret
}

function run_test()
{
    local ret=0
    case "${TEST_NAME,,}" in
        'all') run_all_tests && ret=$? || ret=$?;;
        'directmethodamqp') run_directmethodamqp_test && ret=$? || ret=$?;;
        'directmethodamqpws') run_directmethodamqpws_test && ret=$? || ret=$?;;
        'directmethodmqtt') run_directmethodmqtt_test && ret=$? || ret=$?;;
        'directmethodmqttws') run_directmethodmqttws_test && ret=$? || ret=$?;;
        'quickstartcerts') run_quickstartcerts_test && ret=$? || ret=$?;;
        'longhaul') run_longhaul_test && ret=$? || ret=$?;;
        'stress') run_stress_test && ret=$? || ret=$?;;
        'tempfilter') run_tempfilter_test && ret=$? || ret=$?;;
        'tempfilterfunctions') run_tempfilterfunctions_test && ret=$? || ret=$?;;
        'tempsensor') run_tempsensor_test && ret=$? || ret=$?;;
        *) print_highlighted_message "Can't find any test with name '$TEST_NAME'";;
    esac

    echo "Test exit with result code $ret"
    exit $ret
}

function test_setup() {
    validate_test_parameters
    clean_up
    prepare_test_from_artifacts
    create_iotedge_service_config
}

function validate_test_parameters() {
    print_highlighted_message "Validate test parameters for $TEST_NAME"

    local required_files=()
    local required_folders=()

    required_files+=("$iotedge_quickstart_artifact_file")
    required_folders+=("$iotedged_artifact_folder")

    case "${TEST_NAME,,}" in
        'tempsensor')
            required_files+=($twin_testfile_artifact_file);;
        'tempfilter')
            required_files+=($module_to_module_deployment_artifact_file);;
        'tempfilterfunctions')
            required_files+=($module_to_functions_deployment_artifact_file);;
        'longhaul')
            required_files+=($long_haul_deployment_artifact_file);;
        'quickstartcerts')
            required_files+=($leafdevice_artifact_file);;
        'stress')
            required_files+=($stress_deployment_artifact_file);;
    esac

    if [[ "${TEST_NAME,,}" == directmethod* ]]; then
        required_files+=($dm_module_to_module_deployment_artifact_file)
    fi

    local error=0
    for f in "${required_files[@]}"
    do
        if [ ! -f "$f" ]; then
            print_error "Required file, $f doesn't exist."
            ((error++))
        fi
    done

    for d in "${required_folders[@]}"
    do
        if [ ! -d "$d" ]; then
            print_error "Required directory, $d doesn't exist."
            ((error++))
        fi
    done

    if [[ "${TEST_NAME,,}" == "longhaul" ]] ||
       [[ "${TEST_NAME,,}" == "stress" ]];    then
        if [[ -z "$SNITCH_ALERT_URL" ]]; then
            print_error "Required snitch alert URL."
            ((error++))
        fi

        if [[ -z "$SNITCH_STORAGE_MASTER_KEY" ]]; then
            print_error "Required snitch storage master key."
            ((error++))
        fi 
    fi

    if (( error > 0 )); then
        exit 1
    fi
}

function usage() {
    echo "$SCRIPT_NAME [options]"
    echo ''
    echo 'options'
    echo ' -testDir                        Path of E2E test directory which contains artifacts and certs folders; defaul to current directory.'
    echo ' -releaseLabel                   Release label can be uniquely identify the build (e.g <ReleaseName>-<ReleaseAttempt>); which is used as part of Edge device name.'
    echo ' -testName                       Name of E2E test to be run.'
    echo "                                 Values are 'All', 'DirectMethodAmqp', 'DirectMethodAmqpWs', 'DirectMethodMqtt', 'DirectMethodMqttWs', 'LongHaul', 'QuickstartCerts', "
    echo "                                 'Stress', 'TempFilter', 'TempFilterFunctions', 'TempSensor'"
    echo "                                 Note: 'All' option doesn't include long hual and stress test."
    echo ' -artifactImageBuildNumber       Artifact image build number is used to construct path of docker images, pulling from docker registry. E.g. 20190101.1.'
    echo " -containerRegistry              Host address of container registry, default is 'edgebuilds.azurecr.io'"
    echo " -containerRegistryUsername      Username of container registry, default is 'EdgeBuilds'"
    echo ' -containerRegistryPassword      Password of given username for container registory'
    echo ' -iotHubConnectionString         IoT hub connection string for creating edge device'
    echo ' -eventHubConnectionString       Event hub connection string for receive D2C messages'
    echo ' -loadGenTransportType           Transport type for LoadGen for long haul test. Default is mqtt'
    echo ' -loadGenMessageFrequency        Frequency to send messages in LoadGen module for long haul and stress test. Default is 00.00.01'
    echo ' -snitchAlertUrl                 Alert Url pointing to Azure Logic App for email preparation and sending for long haul and stress test'
    echo ' -snitchBuildNumber              Build number for snitcher docker image for long haul and stress test. Default is 1.1'
    echo ' -snitchReportingIntervalInSecs  Reporting frequency in seconds to send status email for long hual and stress test. Default is 86400 (1 day)'
    echo ' -snitchStorageAccount           Azure blob Sstorage account for store logs used in status email for long haul and stress test. Default is snitchstore'
    echo ' -snitchStorageMasterKey         Master key of snitch storage account for long haul and stress test'
    echo ' -snitchTestDurationInSecs       Test duration in seconds for long haul and stress test'
    echo ' -loadGen1TransportType           Transport type for LoadGen1 for stress test. Default is amqp'
    echo ' -loadGen2TransportType           Transport type for LoadGen2 for stress test. Default is amqp'
    echo ' -loadGen3TransportType           Transport type for LoadGen3 for stress test. Default is mqtt'
    echo ' -loadGen4TransportType           Transport type for LoadGen4 for stress test. Default is mqtt'
    exit 1;
}

process_args "$@"

E2E_TEST_DIR="${E2E_TEST_DIR:-$(pwd)}"
CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-edgebuilds.azurecr.io}"
CONTAINER_REGISTRY_USERNAME="${CONTAINER_REGISTRY_USERNAME:-EdgeBuilds}"
LOADGEN_TRANSPORT_TYPE="${LOADGEN_TRANSPORT_TYPE:-mqtt}"
LOADGEN_MESSAGE_FREQUENCY="${LOADGEN_MESSAGE_FREQUENCY:-00:00:01}"
SNITCH_BUILD_NUMBER="${SNITCH_BUILD_NUMBER:-1.1}"
SNITCH_REPORTING_INTERVAL_IN_SECS="${SNITCH_REPORTING_INTERVAL_IN_SECS:-86400}"
SNITCH_STORAGE_ACCOUNT="${SNITCH_STORAGE_ACCOUNT:-snitchstore}"
SNITCH_TEST_DURATION_IN_SECS="${SNITCH_TEST_DURATION_IN_SECS:-604800}"
LOADGEN1_TRANSPORT_TYPE="${LOADGEN1_TRANSPORT_TYPE:-amqp}"
LOADGEN2_TRANSPORT_TYPE="${LOADGEN1_TRANSPORT_TYPE:-amqp}"
LOADGEN3_TRANSPORT_TYPE="${LOADGEN1_TRANSPORT_TYPE:-mqtt}"
LOADGEN4_TRANSPORT_TYPE="${LOADGEN1_TRANSPORT_TYPE:-mqtt}"


working_folder="$E2E_TEST_DIR/working"
image_architecture_label=$(get_image_architecture_label)
iotedged_artifact_folder="$(get_iotedged_artifact_folder)"
iotedge_quickstart_artifact_file="$(get_iotedge_quickstart_artifact_file)"
leafdevice_artifact_file="$(get_leafdevice_artifact_file)"
twin_testfile_artifact_file="$E2E_TEST_DIR/artifacts/core-linux/e2e_test_files/twin_test_tempSensor.json"
module_to_module_deployment_artifact_file="$E2E_TEST_DIR/artifacts/core-linux/e2e_deployment_files/module_to_module_deployment.template.json"
module_to_functions_deployment_artifact_file="$E2E_TEST_DIR/artifacts/core-linux/e2e_deployment_files/module_to_functions_deployment.template.json"
dm_module_to_module_deployment_artifact_file="$E2E_TEST_DIR/artifacts/core-linux/e2e_deployment_files/dm_module_to_module_deployment.json"
long_haul_deployment_artifact_file="$E2E_TEST_DIR/artifacts/core-linux/e2e_deployment_files/long_haul_deployment.template.json"
stress_deployment_artifact_file="$E2E_TEST_DIR/artifacts/core-linux/e2e_deployment_files/stress_deployment.template.json"
deployment_working_file="$working_folder/deployment.json"
quickstart_working_folder="$working_folder/quickstart"
leafdevice_working_folder="$working_folder/leafdevice"

run_test
