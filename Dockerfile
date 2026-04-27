FROM --platform=linux/amd64 eclipse-temurin:21-jdk-jammy

ENV DEBIAN_FRONTEND noninteractive

#WORKDIR /
#=============================
# Install Dependenices
#=============================
SHELL ["/bin/bash", "-c"]

RUN apt update && apt install -y curl ca-certificates gnupg \
	sudo wget unzip bzip2 libdrm-dev \
	libxkbcommon-dev libgbm-dev libasound-dev libnss3 \
	libxcursor1 libpulse-dev libxshmfence-dev \
	xauth xvfb x11vnc fluxbox wmctrl libdbus-glib-1-2 socat \
	virt-manager git python3 make g++

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
	apt install -y nodejs && \
	node --version && \
	npm --version


# Docker labels.
LABEL maintainer "Halim Qarroum <hqm.post@gmail.com>"
LABEL description "A Docker image allowing to run an Android emulator"
LABEL version "1.0.0"


# Arguments that can be overriden at build-time.
ARG INSTALL_ANDROID_SDK=1
ARG API_LEVEL=33
ARG IMG_TYPE=google_apis
ARG ARCHITECTURE=x86_64
ARG CMD_LINE_VERSION=9477386_latest
ARG DEVICE_ID=pixel
ARG GPU_ACCELERATED=false
ARG WS_SCRCPY_REF=master

# Environment variables.
ENV ANDROID_SDK_ROOT=/opt/android \
	ANDROID_PLATFORM_VERSION="platforms;android-$API_LEVEL" \
	PACKAGE_PATH="system-images;android-${API_LEVEL};${IMG_TYPE};${ARCHITECTURE}" \
	API_LEVEL=$API_LEVEL \
	DEVICE_ID=$DEVICE_ID \
	ARCHITECTURE=$ARCHITECTURE \
	ABI=${IMG_TYPE}/${ARCHITECTURE} \
	GPU_ACCELERATED=$GPU_ACCELERATED \
	QTWEBENGINE_DISABLE_SANDBOX=1 \
	ANDROID_EMULATOR_WAIT_TIME_BEFORE_KILL=10 \
	ANDROID_AVD_HOME=/data \
	SCRCPY_WEB_ENABLED=false \
	SCRCPY_WEB_PORT=8000 \
	SCRCPY_WEB_PATH=/

# Exporting environment variables to keep in the path
# Android SDK binaries and shared libraries.
ENV PATH "${PATH}:${ANDROID_SDK_ROOT}/platform-tools"
ENV PATH "${PATH}:${ANDROID_SDK_ROOT}/emulator"
ENV PATH "${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/tools/bin"
ENV LD_LIBRARY_PATH "$ANDROID_SDK_ROOT/emulator/lib64:$ANDROID_SDK_ROOT/emulator/lib64/qt/lib"

# Set the working directory to /opt
WORKDIR /opt

# Exposing the Android emulator console port, the ADB port,
# and the optional ws-scrcpy web UI port.
EXPOSE 5554 5555 8000

# Initializing the required directories.
RUN mkdir /root/.android/ && \
	touch /root/.android/repositories.cfg && \
	mkdir /data

# Exporting ADB keys.
COPY keys/* /root/.android/

# The following layers will download the Android command-line tools
# to install the Android SDK, emulator and system images.
# It will then install the Android SDK and emulator.
COPY scripts/install-sdk.sh /opt/
RUN chmod +x /opt/install-sdk.sh
RUN /opt/install-sdk.sh

# Install ws-scrcpy for optional browser-based screen mirroring.
RUN git clone https://github.com/NetrisTV/ws-scrcpy.git /opt/ws-scrcpy && \
	cd /opt/ws-scrcpy && \
	git checkout "$WS_SCRCPY_REF" && \
	printf '%s\n' \
		'{' \
		'  "INCLUDE_APPL": false,' \
		'  "INCLUDE_GOOG": true,' \
		'  "INCLUDE_ADB_SHELL": true,' \
		'  "INCLUDE_DEV_TOOLS": false,' \
		'  "INCLUDE_FILE_LISTING": true,' \
		'  "USE_BROADWAY": false,' \
		'  "USE_H264_CONVERTER": true,' \
		'  "USE_TINY_H264": false,' \
		'  "USE_WEBCODECS": true,' \
		'  "USE_WDA_MJPEG_SERVER": false,' \
		'  "USE_QVH_SERVER": false,' \
		'  "SCRCPY_LISTENS_ON_ALL_INTERFACES": false' \
		'}' > build.config.override.json && \
	npm install && \
	npm run dist && \
	cd dist && \
	npm install --omit=dev && \
	cd /opt && \
	rm -rf /opt/ws-scrcpy/node_modules /root/.npm

# Copy the container scripts in the image.
COPY scripts/start-emulator.sh /opt/
COPY scripts/emulator-monitoring.sh /opt/
RUN chmod +x /opt/*.sh

# Set the entrypoint
ENTRYPOINT ["/opt/start-emulator.sh"]