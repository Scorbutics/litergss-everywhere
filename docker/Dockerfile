FROM alpine:3.17

ENV ANDROID_NDK_HOME /opt/android-ndk
ENV ANDROID_NDK_VERSION r25b

# Get the Android NDK
RUN mkdir /tmp/android-ndk && \
    cd /tmp/android-ndk && \
    wget https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip && \
    unzip -q android-ndk-${ANDROID_NDK_VERSION}-linux.zip && \
    mv ./android-ndk-${ANDROID_NDK_VERSION} ${ANDROID_NDK_HOME} && \
    cd /tmp && rm -rf /tmp/android-ndk

RUN apk update && \
    apk upgrade && \
    apk add \
    git \
    make \
    'cmake>3.19.2' \
    'ruby-dev>3.1' \
    linux-headers \
    ninja \
    libtool \
# some executable in the ndk are prebuilt with glibc therefore require gcompat
    gcompat \
    bash \
    gcc \
    musl-dev \
    autoconf \
# ncurses on host is required for cross-compiling ncurses (tic executable must be on the host when cross-compiling)
    ncurses \
    zip \
    automake \
    g++ \
    gettext \
# some dependencies might need patches
    patch \
# X11 development libraries required for SFML on Linux desktop
    libx11-dev \
    libxrandr-dev \
    libxcursor-dev \
    libxi-dev \
    mesa-dev \
    eudev-dev

# Add NDK to PATH
ENV PATH $PATH:$ANDROID_NDK_HOME
ENV ANDROID_NDK $ANDROID_NDK_HOME

WORKDIR /opt/current
