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

# Install Android SDK command-line tools
ENV ANDROID_SDK_HOME /opt/android-sdk
ENV ANDROID_HOME ${ANDROID_SDK_HOME}
ENV ANDROID_SDK_ROOT ${ANDROID_SDK_HOME}

RUN mkdir -p ${ANDROID_SDK_HOME}/cmdline-tools && \
    cd ${ANDROID_SDK_HOME}/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
    unzip -q commandlinetools-linux-11076708_latest.zip && \
    mv cmdline-tools latest && \
    rm commandlinetools-linux-11076708_latest.zip

# Add Android SDK tools to PATH
ENV PATH ${PATH}:${ANDROID_SDK_HOME}/cmdline-tools/latest/bin:${ANDROID_SDK_HOME}/platform-tools

# Accept Android SDK licenses and install required components
RUN yes | sdkmanager --licenses && \
    sdkmanager "platforms;android-34" "build-tools;34.0.0" "platform-tools"

WORKDIR /opt/current
