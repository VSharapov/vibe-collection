FROM ubuntu
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y android-tools-adb jq openssl moreutils less xvfb x11vnc novnc curl
RUN curl -sL https://github.com/Genymobile/scrcpy/releases/download/v3.3.4/scrcpy-linux-x86_64-v3.3.4.tar.gz | tar xz -C /opt
ENV PATH="/opt/scrcpy-linux-x86_64-v3.3.4:$PATH"
WORKDIR /root
