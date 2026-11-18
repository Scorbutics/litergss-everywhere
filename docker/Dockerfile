FROM eclipse-temurin:17-jdk-noble

ENV ANDROID_NDK_HOME /opt/android-ndk
# r27 (LTS, clang 18): r28 (clang 19) libc++ has no std::char_traits<unsigned int>, which
# SFML 2.6 (sf::String, std::basic_string<Uint32>) needs
ENV ANDROID_NDK_VERSION r27d

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    build-essential \
    gcc-14 \
    g++-14 \
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
    libxinerama-dev \
    libgl1-mesa-dev \
    libudev-dev \
    libasound2-dev \
    libpulse-dev \
    pkg-config \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# GCC 14 as the default compiler: GCC 13 (24.04's) at -O3 builds raylib 6.0
# with broken render textures (incomplete framebuffers, viewports drawn black)
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 140 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-14 \
    && update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-14 140 \
    && update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-14 140

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
