ARG RESTY_IMAGE_BASE="almalinux"
ARG RESTY_IMAGE_TAG="9-minimal"

FROM ${RESTY_IMAGE_BASE}:${RESTY_IMAGE_TAG}

LABEL maintainer="bryn.stephens <crusher.devourer@gmail.com>"

ARG RESTY_LUAROCKS_VERSION="3.12.0"
ARG RESTY_YUM_REPO="https://openresty.org/package/rhel/openresty2.repo"
ARG RESTY_RPM_FLAVOR=""
ARG RESTY_RPM_VERSION="1.27.1.2-1"
ARG RESTY_RPM_DIST="el9"
ARG RESTY_RPM_ARCH="x86_64"

LABEL resty_image_base="${RESTY_IMAGE_BASE}"
LABEL resty_image_tag="${RESTY_IMAGE_TAG}"
LABEL resty_luarocks_version="${RESTY_LUAROCKS_VERSION}"
LABEL resty_yum_repo="${RESTY_YUM_REPO}"
LABEL resty_rpm_flavor="${RESTY_RPM_FLAVOR}"
LABEL resty_rpm_version="${RESTY_RPM_VERSION}"
LABEL resty_rpm_dist="${RESTY_RPM_DIST}"
LABEL resty_rpm_arch="${RESTY_RPM_ARCH}"

USER root

RUN    microdnf install -y dnf-plugins-core
RUN    dnf-3 config-manager --add-repo ${RESTY_YUM_REPO}
RUN     microdnf install -y \
        epel-release
RUN     microdnf install -y \
        gettext \
        openresty${RESTY_RPM_FLAVOR}-${RESTY_RPM_VERSION}.${RESTY_RPM_DIST}.${RESTY_RPM_ARCH} \
        openresty-opm-${RESTY_RPM_VERSION}.${RESTY_RPM_DIST} \
        openresty-resty-${RESTY_RPM_VERSION}.${RESTY_RPM_DIST} \
        tar \
        unzip \
        luarocks \
        luajit \
        bind-utils \
        supervisor \
        awscli2 \
        busybox
RUN    microdnf clean all

RUN ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log \
    && ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log

# Unused, present for parity with other Dockerfiles
# This makes some tooling/testing easier, as specifying a build-arg
# and not consuming it fails the build.
ARG RESTY_J="1"

# Add additional binaries into PATH for convenience
ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

# Add LuaRocks paths
# If OpenResty changes, these may need updating:
#    /usr/local/openresty/bin/resty -e 'print(package.path)'
#    /usr/local/openresty/bin/resty -e 'print(package.cpath)'
ENV LUA_PATH="/usr/local/openresty/site/lualib/?.ljbc;/usr/local/openresty/site/lualib/?/init.ljbc;/usr/local/openresty/lualib/?.ljbc;/usr/local/openresty/lualib/?/init.ljbc;/usr/local/openresty/site/lualib/?.lua;/usr/local/openresty/site/lualib/?/init.lua;/usr/local/openresty/lualib/?.lua;/usr/local/openresty/lualib/?/init.lua;./?.lua;/usr/local/openresty/luajit/share/luajit-2.1/?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?/init.lua"
ENV LUA_CPATH="/usr/local/openresty/site/lualib/?.so;/usr/local/openresty/lualib/?.so;./?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so"

# Create directories and set permissions
RUN mkdir -p /{aws,supervisor,cron,scripts,cache} \
    mkdir -p /supervisor/{supervisord.d,run,logs} \
 && chgrp -R 0 /{aws,supervisor,cron,scripts,cache} /usr/local/openresty/ \
 && chmod -R g=u  /{aws,supervisor,cron,scripts,cache} /usr/local/openresty/ \
 && chmod -R g+w /{aws,supervisor,cron,scripts,cache} /usr/local/openresty/ 

 # Copy files
COPY files/startup.sh files/renew_token.sh files/setup-cron.sh   /scripts
RUN chmod a+x /scripts/startup.sh /scripts/renew_token.sh /scripts/setup-cron.sh
COPY files/ecr.ini /supervisor/supervisord.d/ecr.ini
COPY files/token /cron/token

# Move supervisord.conf to supervisor directory & set unix sock target
RUN cp /etc/supervisord.conf /supervisor/supervisord.conf \
&& sed -i '/^\[unix_http_server]/,/^\[/{s|^\s*file\s*=.*|file=/supervisor/run/supervisor.sock|}' /supervisor/supervisord.conf

# Copy nginx configuration files
COPY files/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY files/ssl.conf /usr/local/openresty/nginx/conf/ssl.conf

# Set environment variables for AWS CLI
ENV AWS_SHARED_CREDENTIALS_FILE /aws/credentials
ENV AWS_CONFIG_FILE /aws/config

# Change runtime user to non-root
USER nobody

# Add entrypoint and command
ENTRYPOINT ["/scripts/startup.sh"]
CMD ["/usr/bin/supervisord", "-c", "/supervisor/supervisord.conf"]

# Add stop signal for graceful shutdown
STOPSIGNAL SIGQUIT
