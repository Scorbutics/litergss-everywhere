FROM eclipse-temurin:17-jdk-jammy

ENV ANDROID_NDK_HOME /opt/android-ndk
ENV ANDROID_NDK_VERSION r25b

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    build-essential \
    cmake \
    ruby-dev \
    ninja-build \
    libtool \
    autoconf \
    automake \
    libncurses-dev \
    zip \
    unzip \
    wget \
    gettext \
    patch \
    libx11-dev \
    libxrandr-dev \
    libxcursor-dev \
    libxi-dev \
    libgl1-mesa-dev \
    libudev-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Get the Android NDK
RUN mkdir /tmp/android-ndk && \
    cd /tmp/android-ndk && \
    wget -q https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip && \
    unzip -q android-ndk-${ANDROID_NDK_VERSION}-linux.zip && \
    mv ./android-ndk-${ANDROID_NDK_VERSION} ${ANDROID_NDK_HOME} && \
    cd /tmp && rm -rf /tmp/android-ndk

# Add NDK to PATH
ENV PATH $PATH:$ANDROID_NDK_HOME
ENV ANDROID_NDK $ANDROID_NDK_HOME

WORKDIR /opt/current
