# Generated-By: GPT-4.1

# Use Red Hat UBI 10 minimal as base image
FROM registry.access.redhat.com/ubi10/ubi-minimal:latest

# Set labels for the image
LABEL maintainer="octosql-etcd"
LABEL description="RHEL UBI 10 with octosql and etcdsnapshot-plugin installed"

# Update system packages and install required dependencies
RUN microdnf update -y && \
    microdnf install -y \
    curl \
    tar \
    gzip \
    ca-certificates \
    jq \
    && microdnf clean all

# Install octosql
# Download and install the latest version of octosql
RUN OCTOSQL_VERSION=$(curl -s https://api.github.com/repos/cube2222/octosql/releases/latest | grep '"tag_name"' | cut -d'"' -f4) && \
    curl -L -o /tmp/octosql.tar.gz "https://github.com/cube2222/octosql/releases/download/${OCTOSQL_VERSION}/octosql_${OCTOSQL_VERSION#v}_linux_amd64.tar.gz" && \
    tar -xzf /tmp/octosql.tar.gz -C /tmp && \
    mv /tmp/octosql /usr/local/bin/ && \
    chmod +x /usr/local/bin/octosql && \
    rm -rf /tmp/octosql*

# Configure octosql file extension handlers for etcd snapshots
RUN mkdir -p /root/.octosql && \
    echo '{"snapshot": "etcdsnapshot"}' > /root/.octosql/file_extension_handlers.json

# Add the etcd snapshot plugin repository and install the plugin
RUN octosql plugin repository add https://raw.githubusercontent.com/tjungblu/octosql-plugin-etcdsnapshot/main/plugin_repository.json && \
    octosql plugin install etcdsnapshot/etcdsnapshot

# Verify installation
RUN octosql --version

# Disable octosql telemetry and give users a signal that they're in a container
ENV OCTOSQL_NO_TELEMETRY=1 AM_I_CONTAINER=yes

# Set the default command to shell
CMD ["/bin/bash"] 
