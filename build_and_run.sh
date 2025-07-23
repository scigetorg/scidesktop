#!/bin/bash
set -e

if docker ps --all | grep scidesktop; then
    if docker ps --all | grep scideskapp; then
        echo "detected a scideskapp container and ignoring it!"
    else
        bash stop_and_clean.sh
    fi
fi
# docker build -t scidesktop:latest .
# docker run --shm-size=1gb -it --privileged --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -p 8080:8080 scidesktop:latest
# -e CVMFS_DISABLE=true # will disable CVMFS for testing purposes

docker build . -t scidesktop:latest
# podman build . -t scidesktop:latest

# Test with internal CVMFS
# docker run --shm-size=1gb -it --cap-add SYS_ADMIN --security-opt apparmor:unconfined \
#     --device=/dev/fuse --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
#     -p 8888:8888 \
#     --user=root -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#     scidesktop:latest

# Test with persistent home directory
# docker volume create neurodesk-home
# docker run --shm-size=1gb -it --privileged --user=root \
#     --device=/dev/fuse --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
#     --mount source=neurodesk-home,target=/home/jovyan \
#     -p 8888:8888 \
#     -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#     scidesktop:latest

# Test Offline mode with CVMFS disabled
# docker volume create neurodesk-home
# docker run --shm-size=1gb -it --privileged --user=root \
#     --device=/dev/fuse --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
#     --mount source=neurodesk-home,target=/home/jovyan \
#     -e CVMFS_DISABLE=true \
#     -p 8888:8888 \
#     -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#     scidesktop:latest

# # Test Offline mode with CVMFS disabled without --device=/dev/fuse
# docker volume create neurodesk-home
# docker run --shm-size=1gb -it --privileged --user=root \
#     --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
#     --mount source=neurodesk-home,target=/home/jovyan \
#     -e CVMFS_DISABLE=true \
#     -p 8888:8888 \
#     -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#     scidesktop:latest





# Test Online mode with CVMFS enabled without --device=/dev/fuse
docker volume create neurodesk-home
docker run --shm-size=1gb -it --privileged --user=root \
    --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
    --mount source=neurodesk-home,target=/home/jovyan \
    -e CVMFS_DISABLE=false \
    -p 8888:8888 \
    -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
    scidesktop:latest


# podman volume create neurodesk-home &&
# sudo podman run \
#   --shm-size=1gb -it --privileged --user=root --name scidesktop \
#   -v ~/scidesktop-storage:/scidesktop-storage \
#   --mount type=volume,source=neurodesk-home,target=/home/jovyan \
#   -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#   -p 8888:8888 \
#   -e scidesktop_VERSION=development scidesktop:latest


# Test normal mode without --device=/dev/fuse
# docker volume create neurodesk-home
# docker run --shm-size=1gb -it --privileged --user=root \
#     --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
#     --mount source=neurodesk-home,target=/home/jovyan \
#     -p 8888:8888 \
#     -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#     scidesktop:latest

# Run with external CVMFS:
# docker run --shm-size=1gb -it --cap-add SYS_ADMIN --security-opt apparmor:unconfined \
#     --device=/dev/fuse --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
#     -v /cvmfs:/cvmfs -p 8888:8888 \
#     --user=root -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#     scidesktop:latest

# launch with custom token
# docker run --shm-size=1gb -it --cap-add SYS_ADMIN --security-opt apparmor:unconfined \
#     --device=/dev/fuse --name scidesktop -v ~/scidesktop-storage:/scidesktop-storage \
#     --mount source=neurodesk-home,target=/home/jovyan \
#     -p 8888:8888 \
#     --user=root -e NB_UID="$(id -u)" -e NB_GID="$(id -g)" \
#     scidesktop:latest start.sh jupyter lab --ServerApp.password="" --no-browser --expose-app-in-browser --ServerApp.token="jlab:srvr:123" --ServerApp.port=33163 --LabApp.quit_button=False
