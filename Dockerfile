FROM quay.io/jupyter/base-notebook:2025-06-30
# https://quay.io/repository/jupyter/base-notebook?tab=tags

LABEL maintainer="Neurodesk Project <scidesk.org>"

USER root

#========================================#
# Core services
#========================================#


# Install base image dependencies
RUN apt-get update --yes \
    && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends \
        software-properties-common \
        openjdk-21-jre \
        build-essential \
        libcairo2-dev \
        libjpeg-turbo8-dev \
        libpng-dev \
        libtool-bin \
        uuid-dev \
        freerdp2-dev \
        libvncserver-dev \
        libssl-dev \
        libwebp-dev \
        libssh2-1-dev \
        libpango1.0-dev \
        tigervnc-common \
        tigervnc-standalone-server \
        tigervnc-tools \
        xorgxrdp \
        xrdp \
        lxde \
        acl \
        wget \
        curl \
        dirmngr \
        gpg \
        gpg-agent \
        apt-transport-https \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# add a static strace executable to /opt which we can copy to containers for debugging:
RUN mkdir -p /opt/strace \
    && wget -qO- https://github.com/JuliaBinaryWrappers/strace_jll.jl/releases/download/strace-v6.7.0%2B1/strace.v6.7.0.x86_64-linux-gnu.tar.gz | tar xz -C /opt/strace --strip-components=1 \
    && chmod +x /opt/strace

ARG TOMCAT_REL="9"
ARG TOMCAT_VERSION="9.0.106"
ARG GUACAMOLE_VERSION="1.5.5"

ENV LANG=""
ENV LANGUAGE=""
ENV LC_ALL=""

# Install apptainer
RUN add-apt-repository -y ppa:apptainer/ppa \
    && apt-get update --yes \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes apptainer \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && rm -rf /root/.cache && rm -rf /home/${NB_USER}/.cache

# Install Apache Tomcat
RUN wget -q https://archive.apache.org/dist/tomcat/tomcat-${TOMCAT_REL}/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz -P /tmp \
    && tar -xf /tmp/apache-tomcat-${TOMCAT_VERSION}.tar.gz -C /tmp \
    && rm -rf /tmp/apache-tomcat-${TOMCAT_VERSION}.tar.gz \
    && mv /tmp/apache-tomcat-${TOMCAT_VERSION} /usr/local/tomcat \
    && mv /usr/local/tomcat/webapps /usr/local/tomcat/webapps.dist \
    && mkdir /usr/local/tomcat/webapps \
    && chmod +x /usr/local/tomcat/bin/*.sh

# Install Apache Guacamole
RUN wget -q "https://archive.apache.org/dist/guacamole/${GUACAMOLE_VERSION}/binary/guacamole-${GUACAMOLE_VERSION}.war" -O /usr/local/tomcat/webapps/ROOT.war \
    && wget -q "https://archive.apache.org/dist/guacamole/${GUACAMOLE_VERSION}/source/guacamole-server-${GUACAMOLE_VERSION}.tar.gz" -P /tmp \
    && tar xvf /tmp/guacamole-server-${GUACAMOLE_VERSION}.tar.gz -C /tmp \
    && rm /tmp/guacamole-server-${GUACAMOLE_VERSION}.tar.gz \
    && cd /tmp/guacamole-server-${GUACAMOLE_VERSION} \
    && ./configure --with-init-dir=/etc/init.d \
    && make \
    && make install \
    && ldconfig \
    && rm -r /tmp/guacamole-server-${GUACAMOLE_VERSION}

# # Set home directory default acls
# RUN chmod g+rwxs /home/${NB_USER}
# RUN setfacl -dRm u::rwX,g::rwX,o::0 /home/${NB_USER}

# #========================================#
# # Software (as root user)
# #========================================#

# Add Software sources
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg \
    && install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg \
    && sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' \
    && rm -f packages.microsoft.gpg \
    && add-apt-repository ppa:nextcloud-devs/client \
    && chmod -R 770 /home/${NB_USER}/.launchpadlib \
    && chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}/.launchpadlib \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Workaround for CVMFS to break systemctl by replacing it with a dummy script
RUN mv /usr/bin/systemctl /usr/bin/systemctl.orig \
    && echo '#!/bin/bash' > /usr/bin/systemctl \
    && echo 'echo "systemctl is disabled in this container"' >> /usr/bin/systemctl \
    && chmod +x /usr/bin/systemctl

# Install CVMFS
RUN wget -q https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest_all.deb -P /tmp \
    && dpkg -i /tmp/cvmfs-release-latest_all.deb \
    && rm /tmp/cvmfs-release-latest_all.deb

# Install CVMFS Packages
RUN apt-get update --yes \
    && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends cvmfs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Tools and Libs
RUN apt-get update --yes \
    && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends \
        aria2 \
        bc \
        code \
        davfs2 \
        debootstrap \
        dnsutils \
        emacs \
        gedit \
        git \
        git-annex \
        gnome-keyring \
        graphviz \
        htop \
        imagemagick \
        iputils-ping \
        less \
        libgfortran5 \
        libgpgme-dev \
        libossp-uuid-dev \
        libpci3 \
        libreoffice \
        lmod \
        lua-bit32 \
        lua-filesystem \
        lua-json \
        lua-lpeg \
        lua-posix \
        lua-term \
        lua5.2 \
        lxtask \
        man-db \
        nano \
        nextcloud-client \
        nodejs \
        openssh-client \
        openssh-server \
        owncloud-client \
        pciutils \
        python3-setuptools \
        qdirstat \
        rsync \
        s3fs \
        screen \
        sshfs \
        tcllib \
        tk \
        tmux \
        tree \
        uidmap \
        unzip \
        vim \
        xdg-utils \
        yarn \
        zip \
        tcsh \
        && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install firefox
RUN add-apt-repository ppa:mozillateam/ppa \
    && apt-get update --yes \
    && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends \
        --target-release 'o=LP-PPA-mozillateam' firefox \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY config/firefox/mozillateamppa /etc/apt/preferences.d/mozillateamppa
COPY config/firefox/syspref.js /etc/firefox/syspref.js

#========================================#
# Software (as notebook user)
#========================================#

USER ${NB_USER}

# Install conda packages
RUN conda install -c conda-forge nb_conda_kernels \
    && conda clean --all -f -y \
    && rm -rf /home/${NB_USER}/.cache
RUN conda config --system --prepend envs_dirs '~/conda-environments'

# Add datalad-container datalad-osf osfclient ipyniivue to the conda environment
RUN /opt/conda/bin/pip install datalad nipype matplotlib datalad-container datalad-osf osfclient  \
    && rm -rf /home/${NB_USER}/.cache
RUN git clone https://github.com/niivue/ipyniivue.git \
    && cd ipyniivue && git checkout main && git pull \
    && /opt/conda/bin/pip install .


# Install jupyter-server-proxy and disable announcements
RUN /opt/conda/bin/pip install jupyter-server-proxy \
    && /opt/conda/bin/jupyter labextension disable @jupyterlab/apputils-extension:announcements \
    && /opt/conda/bin/pip install jupyterlmod \
    && /opt/conda/bin/pip install jupyterlab-git \
    && /opt/conda/bin/pip install notebook_intelligence \
    && /opt/conda/bin/pip install jupyterlab_rise \
    && /opt/conda/bin/pip install ipycanvas \
    && /opt/conda/bin/pip install jupyter-resource-usage \
    && /opt/conda/bin/pip install jupyter_scheduler \
    && /opt/conda/bin/pip install httpx \
    && /opt/conda/bin/pip install ipywidgets ipyvolume jupyterlab_widgets \
    && /opt/conda/bin/pip install nbgitpuller \
    && rm -rf /home/${NB_USER}/.cache

#========================================#
# Configuration (as root user)
#========================================#

USER root

# # Customise logo, wallpaper, terminal
COPY config/jupyter/neurodesk_brain_logo.svg /opt/neurodesk_brain_logo.svg
COPY config/jupyter/neurodesk_brain_icon.svg /opt/neurodesk_brain_icon.svg

COPY config/lxde/background.png /usr/share/lxde/wallpapers/desktop_wallpaper.png
COPY config/lxde/pcmanfm.conf /etc/xdg/pcmanfm/LXDE/pcmanfm.conf
COPY config/lxde/lxterminal.conf /usr/share/lxterminal/lxterminal.conf
COPY config/lmod/module.sh /usr/share/

# Configure tiling of windows SHIFT-ALT-CTR-{Left,right,top,Bottom} and other openbox desktop mods
COPY ./config/lxde/rc.xml /etc/xdg/openbox

# Allow the root user to access the sshfs mount
# https://github.com/scigetorg/neurodesk/issues/47
RUN sed -i 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf

# Fetch singularity bind mount list and create placeholder mountpoints
# RUN mkdir -p `curl https://raw.githubusercontent.com/NeuroDesk/neurocontainers/master/recipes/globalMountPointList.txt`

# Fix "No session for pid prompt"
RUN rm /usr/bin/lxpolkit

# enable rootless mounts: 
RUN chmod +x /usr/bin/fusermount
    
# Add notebook startup scripts
# https://jupyter-docker-stacks.readthedocs.io/en/latest/using/common.html
RUN mkdir -p /usr/local/bin/start-notebook.d/ \
    && mkdir -p /usr/local/bin/before-notebook.d/
COPY config/jupyter/start_notebook.sh /usr/local/bin/start-notebook.d/
COPY config/jupyter/before_notebook.sh /usr/local/bin/before-notebook.d/

# Add jupyter notebook and startup scripts for system-wide configuration
COPY --chown=root:users config/jupyter/jupyter_notebook_config.py /etc/jupyter/jupyter_notebook_config.py
COPY --chown=root:users config/jupyter/jupyterlab_startup.sh /opt/scidesktop/jupyterlab_startup.sh
COPY --chown=root:users config/guacamole/guacamole.sh /opt/scidesktop/guacamole.sh
COPY --chown=root:users config/jupyter/environment_variables.sh /opt/scidesktop/environment_variables.sh
# COPY --chown=root:users config/guacamole/user-mapping.xml /etc/guacamole/user-mapping.xml

RUN chmod +x /etc/jupyter/jupyter_notebook_config.py \
    /opt/scidesktop/jupyterlab_startup.sh \
    /opt/scidesktop/guacamole.sh \
    /opt/scidesktop/environment_variables.sh

# Create Guacamole configurations (user-mapping.xml gets filled in the startup.sh script)
RUN mkdir -p /etc/guacamole \
    && echo -e "user-mapping: /etc/guacamole/user-mapping.xml\nguacd-hostname: 127.0.0.1" > /etc/guacamole/guacamole.properties \
    && echo -e "[server]\nbind_host = 127.0.0.1\nbind_port = 4822" > /etc/guacamole/guacd.conf
RUN chown -R ${NB_UID}:${NB_GID} /etc/guacamole
RUN chown -R ${NB_UID}:${NB_GID} /usr/local/tomcat
COPY --chown=${NB_UID}:${NB_GID} config/guacamole/user-mapping-vnc.xml /etc/guacamole/user-mapping-vnc.xml
COPY --chown=${NB_UID}:${NB_GID} config/guacamole/user-mapping-vnc-rdp.xml /etc/guacamole/user-mapping-vnc-rdp.xml

# Add NB_USER to sudoers
RUN echo "${NB_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/notebook \
# The following apply to Singleuser mode only. See config/jupyter/before_notebook.sh for Notebook mode
    && /usr/bin/printf '%s\n%s\n' 'password' 'password' | passwd ${NB_USER} \
    && usermod --shell /bin/bash ${NB_USER}

# Enable deletion of non-empty-directories in JupyterLab: https://github.com/jupyter/notebook/issues/4916
RUN sed -i 's/c.FileContentsManager.delete_to_trash = False/c.FileContentsManager.always_delete_dir = True/g' /etc/jupyter/jupyter_server_config.py

#========================================#
# Configuration (as notebook user)
#========================================#

# Switch to notebook user
USER ${NB_USER}

# Configure ITKsnap
RUN mkdir -p /home/${NB_USER}/.itksnap.org/ITK-SNAP \
    && chown ${NB_USER} /home/${NB_USER}/.itksnap.org -R
COPY --chown=${NB_UID}:${NB_GID} ./config/itksnap/UserPreferences.xml /home/${NB_USER}/.itksnap.org
COPY --chown=${NB_UID}:${NB_GID} ./config/lxde/mimeapps.list /home/${NB_USER}/.config/mimeapps.list

COPY --chown=${NB_UID}:${NB_GID} config/lxde/panel /home/${NB_USER}/.config/lxpanel/LXDE/panels/panel
COPY --chown=${NB_UID}:${NB_GID} config/lxde/.bashrc /home/${NB_USER}/tmp_bashrc
RUN cat /home/${NB_USER}/tmp_bashrc >> /home/${NB_USER}/.bashrc \
     && rm /home/${NB_USER}/tmp_bashrc

# Setup git
RUN git config --global user.email "user@neurodesk.org" \
    && git config --global user.name "Neurodesk User"

# Setup temp directory for matplotlib (required for fmriprep)
RUN mkdir -p /home/${NB_USER}/.config/matplotlib-mpldir \
    && chmod -R 700 /home/${NB_USER}/.config/matplotlib-mpldir \
    && chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}/.config/matplotlib-mpldir

COPY --chown=${NB_UID}:${NB_GID} config/vscode/settings.json /home/${NB_USER}/.config/Code/User/settings.json

# Add libfm script
RUN mkdir -p /home/${NB_USER}/.config/libfm
COPY --chown=${NB_UID}:${NB_GID} ./config/lxde/libfm.conf /home/${NB_USER}/.config/libfm

RUN touch /home/${NB_USER}/.sudo_as_admin_successful

ENV DONT_PROMPT_WSL_INSTALL=1
ENV LMOD_CMD=/usr/share/lmod/lmod/libexec/lmod

# Add startup and config files for scidesktop, jupyter, guacamole, vnc
RUN mkdir /home/${NB_USER}/.vnc \
    && chown ${NB_USER} /home/${NB_USER}/.vnc \
    && /usr/bin/printf '%s\n%s\n%s\n' 'password' 'password' 'n' | vncpasswd

COPY --chown=${NB_UID}:${NB_GID} config/lxde/xstartup /home/${NB_USER}/.vnc
COPY --chown=${NB_UID}:${NB_GID} config/conda/conda-readme.md /home/${NB_USER}/

RUN mkdir -p /home/${NB_USER}/.ssh \
    && chmod -R 700 /home/${NB_USER}/.ssh \
    && setfacl -dRm u::rwx,g::0,o::0 /home/${NB_USER}/.ssh
COPY --chown=${NB_UID}:${NB_GID} config/ssh/sshd_config /home/${NB_USER}/.ssh/sshd_config

RUN chmod +x /home/${NB_USER}/.vnc/xstartup

# Set up working directories and symlinks
RUN mkdir -p /home/${NB_USER}/Desktop/

#========================================#
# Finalise build
#========================================#

# Switch to root user
USER root

# Create cvmfs keys for neurodesk.ardc.edu.au
RUN mkdir -p /etc/cvmfs/keys/ardc.edu.au
COPY config/cvmfs/neurodesk.ardc.edu.au.pub /etc/cvmfs/keys/ardc.edu.au/neurodesk.ardc.edu.au.pub
COPY config/cvmfs/neurodesk.ardc.edu.au.conf* /etc/cvmfs/config.d/

# Create cvmfs keys for software.eessi.io
RUN mkdir -p /etc/cvmfs/keys/eessi.io
COPY config/cvmfs/software.eessi.io.pub /etc/cvmfs/keys/eessi.io/eessi.io.pub
COPY config/cvmfs/software.eessi.io.conf* /etc/cvmfs/config.d/

COPY config/cvmfs/default.local /etc/cvmfs/default.local

# Save a backup copy of startup home dir into /tmp
# Used to restore home dir in persistent sessions
RUN cp -rp /home/${NB_USER} /tmp/

# Set up data directory so it exists in the container for the SINGULARITY_BINDPATH
RUN mkdir -p /data /scidesktop-storage
RUN chown ${NB_UID}:${NB_GID} /scidesktop-storage \
    && chmod 770 /scidesktop-storage

# # Install neurocommand
# ADD "https://api.github.com/repos/neurodesk/neurocommand/git/refs/heads/main" /tmp/skipcache
# RUN rm /tmp/skipcache \
#     && git clone https://github.com/scigetorg/neurocommand.git /neurocommand \
#     && cd /neurocommand \
#     && bash build.sh --lxde --edit \
#     && bash install.sh \
#     && ln -s /home/${NB_USER}/scidesktop-storage/containers /neurocommand/local/containers

USER ${NB_UID}

WORKDIR "${HOME}"

# # Install example notebooks
# ADD "https://api.github.com/repos/neurodesk/example-notebooks/git/refs/heads/main" /home/${NB_USER}/skipcache
# RUN rm /home/${NB_USER}/skipcache \
#     && git clone --depth 1 https://github.com/scigetorg/example-notebooks
