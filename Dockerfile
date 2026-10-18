FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 TERM=xterm-256color

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git jq rsync sqlite3 openssh-server sudo \
    iproute2 iputils-ping net-tools dnsutils traceroute whois libcap2-bin \
    vim nano htop tmux screen less tree unzip zip p7zip-full \
    python3 python3-pip python3-venv python3-dev build-essential \
    nmap sqlmap hydra john hashcat wireshark-common tshark tcpdump \
    nikto gobuster dirb metasploit-framework wordlists exploitdb \
    libssl-dev zlib1g-dev libffi-dev libsqlite3-dev libreadline-dev \
    libncurses5-dev libxml2-dev libxslt1-dev libpq-dev libyaml-dev \
    libpng-dev libjpeg-dev linux-libc-dev locales procps file lsof \
    && locale-gen en_US.UTF-8 \
    && mkdir -p /run/sshd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && npm install -g --allow-scripts=9router 9router \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 \
    && chmod 0755 /usr/local/bin/ttyd \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

# Railway drops cap_net_raw / cap_net_admin from the container's capability bounding
# set. A binary that carries those file capabilities then fails to exec with EPERM
# (this is what breaks /usr/lib/nmap/nmap). Strip file capabilities at build time so
# such tools run at all. Consequence: raw-socket features stay unavailable
# (SYN/UDP scans, OS detection, packet capture) — use `nmap -sT` / `-sV`.
RUN find /usr/bin /usr/sbin /usr/lib -xdev -type f -exec getcap {} + 2>/dev/null \
      | awk '{print $1}' | sort -u | xargs -r -d '\n' setcap -r 2>/dev/null || true

COPY config.example.json /etc/kaliroute/config.json
COPY entrypoint.sh /usr/local/bin/kaliroute-entrypoint
COPY app-sync.sh /usr/local/bin/app-sync
COPY kali-sync.sh /usr/local/bin/kali-sync
RUN chmod 0755 /usr/local/bin/kaliroute-entrypoint /usr/local/bin/app-sync /usr/local/bin/kali-sync

EXPOSE 22 7681 20128
CMD ["/usr/local/bin/kaliroute-entrypoint"]
