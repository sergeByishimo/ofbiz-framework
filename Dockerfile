# syntax=docker/dockerfile:1
FROM eclipse-temurin:17 as builder

# Git is used for various OFBiz build tasks.
RUN apt-get update \
    && apt-get install -y git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /builder

# Add and run the gradle wrapper to trigger a download if needed.
COPY gradle/init-gradle-wrapper.sh gradle/
COPY gradlew .
RUN ["sed", "-i", "s/shasum/sha1sum/g", "gradle/init-gradle-wrapper.sh"]
RUN ["gradle/init-gradle-wrapper.sh"]

# Run gradlew to trigger downloading of the gradle distribution (if needed)
RUN --mount=type=cache,id=gradle-cache,sharing=locked,target=/root/.gradle \
    ["./gradlew", "--console", "plain"]

# Copy all OFBiz sources.
COPY . .

# Build OFBiz while mounting a gradle cache
RUN --mount=type=cache,id=gradle-cache,sharing=locked,target=/root/.gradle \
    --mount=type=tmpfs,target=runtime/tmp \
    ["./gradlew", "--console", "plain", "distTar"]

###################################################################################

FROM eclipse-temurin:17 as runtimebase

RUN ["useradd", "ofbiz"]

# Configure volumes where hooks into the startup process can be placed.
RUN ["mkdir", "/docker-entrypoint-before-config-applied.d", "/docker-entrypoint-after-config-applied.d", \
    "/docker-entrypoint-before-data-load.d", "/docker-entrypoint-after-data-load.d", \
    "/docker-entrypoint-additional-data.d"]
RUN ["sh", "-c", "/usr/bin/chown -R ofbiz:ofbiz /docker-entrypoint-*.d" ]

USER ofbiz
WORKDIR /ofbiz

# Extract the OFBiz tar distribution created by the builder stage.
RUN --mount=type=bind,from=builder,source=/builder/build/distributions/ofbiz.tar,target=/mnt/ofbiz.tar \
    ["tar", "--extract", "--strip-components=1", "--file=/mnt/ofbiz.tar"]

RUN ["mkdir", "/ofbiz/runtime", "/ofbiz/config"]

COPY docker/docker-entrypoint.sh .
COPY docker/send_ofbiz_stop_signal.sh .

EXPOSE 8443
EXPOSE 8009
EXPOSE 5005

ENTRYPOINT ["/ofbiz/docker-entrypoint.sh"]
CMD ["bin/ofbiz"]

###################################################################################
# Load demo data before defining volumes. This results in a container image
# that is ready to go for demo purposes.
FROM runtimebase as demo

RUN /ofbiz/bin/ofbiz --load-data
RUN mkdir --parents /ofbiz/runtime/container_state
RUN touch /ofbiz/runtime/container_state/data_loaded
RUN touch /ofbiz/runtime/container_state/admin_loaded

VOLUME ["/docker-entrypoint-before-config-applied.d", "/docker-entrypoint-after-config-applied.d", \
    "/docker-entrypoint-before-data-load.d", "/docker-entrypoint-after-data-load.d", \
    "/docker-entrypoint-additional-data.d"]
VOLUME ["/ofbiz/config", "/ofbiz/runtime"]


###################################################################################
# Runtime image with no data loaded.
FROM runtimebase as runtime

VOLUME ["/docker-entrypoint-before-config-applied.d", "/docker-entrypoint-after-config-applied.d", \
    "/docker-entrypoint-before-data-load.d", "/docker-entrypoint-after-data-load.d", \
    "/docker-entrypoint-additional-data.d"]
VOLUME ["/ofbiz/config", "/ofbiz/runtime"]
