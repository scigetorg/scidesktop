docker stop scidesktop
docker rm scidesktop
docker build -t scidesktop:latest .
docker run --shm-size=1gb -it --privileged --name scidesktop -v C:/scidesktop-storage:/scidesktop-storage -p 8888:8888 --user=root scidesktop:latest
@REM docker run --shm-size=1gb -it --privileged --name scidesktop -v C:/scidesktop-storage:/scidesktop-storage -e USER=user -e CVMFS_DISABLE=true -p 8080:8080 scidesktop:latest
