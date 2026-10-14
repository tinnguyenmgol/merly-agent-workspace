FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 TMPDIR=/workspace/tmp
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server python3 python3-pytest python3-venv bash ca-certificates && rm -rf /var/lib/apt/lists/* \
 && groupadd -g 10001 merly-agent && useradd -u 10001 -g 10001 -d /workspace -M -s /bin/bash merly-agent \
 && usermod -p NP merly-agent && mkdir -p /etc/ssh/authorized_keys /etc/ssh/host_keys /monitor /run/sshd /workspace/tmp \
 && chown -R 10001:10001 /workspace && chmod 0700 /workspace/tmp \
 && touch /etc/ssh/authorized_keys/merly-agent && chmod 0644 /etc/ssh/authorized_keys/merly-agent \
 && rm -f /etc/ssh/ssh_host_*
COPY sshd_config /etc/ssh/sshd_config
WORKDIR /workspace
EXPOSE 2222
CMD ["/bin/sh","-ec","mkdir -p /run/sshd; /usr/sbin/sshd -t; exec /usr/sbin/sshd -D -e"]
