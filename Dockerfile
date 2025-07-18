### -----------------------
# --- Stage: development
# --- Purpose: Local development environment
# --- https://hub.docker.com/_/golang
# --- https://github.com/microsoft/vscode-remote-try-go/blob/master/.devcontainer/Dockerfile
### -----------------------
    FROM debian:bookworm AS development

    # Avoid warnings by switching to noninteractive
    ENV DEBIAN_FRONTEND=noninteractive
    
    # Our Makefile / env fully supports parallel job execution
    ENV MAKEFLAGS "-j 8 --no-print-directory"

    
    # Install required system dependencies
    RUN apt-get update \
        && apt-get install -y \
        #
        # Mandadory minimal linux packages
        # Installed at development stage and app stage
        # Do not forget to add mandadory linux packages to the final app Dockerfile stage below!
        #
        # -- START MANDADORY --
        ca-certificates \
        wget \
        gnupg 
        # --- END MANDADORY ---

    # postgresql-support: Add the official postgres repo to install the matching postgresql-client tools of your stack
    # https://wiki.postgresql.org/wiki/Apt
    # run lsb_release -c inside the container to pick the proper repository flavor
    # e.g. stretch=>stretch-pgdg, buster=>buster-pgdg, bullseye=>bullseye-pgdg, bookworm=>bookworm-pgdg
    RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" \
        | tee /etc/apt/sources.list.d/pgdg.list \
        && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | apt-key add -

    RUN apt-get update \
        && apt-get install -y \   
        #
        # Development specific packages
        # Only installed at development stage and NOT available in the final Docker stage
        # based upon
        # https://github.com/microsoft/vscode-remote-try-go/blob/master/.devcontainer/Dockerfile
        # https://raw.githubusercontent.com/microsoft/vscode-dev-containers/master/script-library/common-debian.sh
        #
        # icu-devtools: https://stackoverflow.com/questions/58736399/how-to-get-vscode-liveshare-extension-working-when-running-inside-vscode-remote
        # graphviz: https://github.com/google/pprof#building-pprof
        # -- START DEVELOPMENT --
        make \
        gcc \
        apt-utils \
        dialog \
        openssh-client \
        less \
        iproute2 \
        procps \
        lsb-release \
        locales \
        sudo \
        bash-completion \
        bsdmainutils \
        graphviz \
        xz-utils \
        icu-devtools \
        postgresql-client-17 \
        # --- END DEVELOPMENT ---
        #
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*
    
    # env/vscode support: LANG must be supported, requires installing the locale package first
    # https://github.com/Microsoft/vscode/issues/58015
    # https://stackoverflow.com/questions/28405902/how-to-set-the-locale-inside-a-debian-ubuntu-docker-container
    RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
        dpkg-reconfigure --frontend=noninteractive locales && \
        update-locale LANG=en_US.UTF-8
    
    ENV LANG en_US.UTF-8

    # linux permissions / vscode support: Add user to avoid linux file permission issues
    # Detail: Inside the container, any mounted files/folders will have the exact same permissions
    # as outside the container - including the owner user ID (UID) and group ID (GID).
    # Because of this, your container user will either need to have the same UID or be in a group with the same GID.
    # The actual name of the user / group does not matter. The first user on a machine typically gets a UID of 1000,
    # so most containers use this as the ID of the user to try to avoid this problem.
    # 2020-04: docker-compose does not support passing id -u / id -g as part of its config, therefore we assume uid 1000
    # https://code.visualstudio.com/docs/remote/containers-advanced#_adding-a-nonroot-user-to-your-dev-container
    # https://code.visualstudio.com/docs/remote/containers-advanced#_creating-a-nonroot-user
    ARG USERNAME=development
    ARG USER_UID=1000
    ARG USER_GID=$USER_UID
    
    RUN groupadd --gid $USER_GID $USERNAME \
        && useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m $USERNAME \
        && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
        && chmod 0440 /etc/sudoers.d/$USERNAME
    
    # vscode support: cached extensions install directory
    # https://code.visualstudio.com/docs/remote/containers-advanced#_avoiding-extension-reinstalls-on-container-rebuild
    RUN mkdir -p /home/$USERNAME/.vscode-server/extensions \
        /home/$USERNAME/.vscode-server-insiders/extensions \
        && chown -R $USERNAME \
        /home/$USERNAME/.vscode-server \
        /home/$USERNAME/.vscode-server-insiders
    
    # https://code.visualstudio.com/remote/advancedcontainers/persist-bash-history
    RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/home/$USERNAME/commandhistory/.bash_history" \
        && mkdir /home/$USERNAME/commandhistory \
        && touch /home/$USERNAME/commandhistory/.bash_history \
        && chown -R $USERNAME /home/$USERNAME/commandhistory \
        && echo "$SNIPPET" >> "/home/$USERNAME/.bashrc"
    

    WORKDIR /app
    