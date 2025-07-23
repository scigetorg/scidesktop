set -e


docker build . -t scidesktop:latest
dive scidesktop --ci > wasted_space.txt
dive scidesktop 

rm wasted_space.txt