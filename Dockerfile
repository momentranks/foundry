FROM debian:stable-slim as gobuilder
# defined from build kit
# DOCKER_BUILDKIT=1 docker build . -t ...
ARG TARGETARCH

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt update && \
  apt install -y -q --no-install-recommends \
    git curl gnupg2 build-essential coreutils \
    openssl libssl-dev pkg-config \
    ca-certificates apt-transport-https \
  python3 && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*

COPY . . 

## Go Lang
ARG GO_VERSION=1.19.3
ADD https://go.dev/dl/go${GO_VERSION}.linux-$TARGETARCH.tar.gz /go-ethereum/go${GO_VERSION}.linux-$TARGETARCH.tar.gz
# RUN cat /go-ethereum/go${GO_VERSION}.linux-$TARGETARCH.tar.gz | sha256sum -c go.${TARGETARCH}.sha256
RUN tar -C /usr/local -xzf /go-ethereum/go${GO_VERSION}.linux-$TARGETARCH.tar.gz
ENV PATH=$PATH:/usr/local/go/bin
RUN go version

## Go Ethereum
WORKDIR /go-ethereum
ARG ETH_VERSION=1.10.26
ADD https://github.com/ethereum/go-ethereum/archive/refs/tags/v${ETH_VERSION}.tar.gz /go-ethereum/go-ethereum-${ETH_VERSION}.tar.gz
RUN tar -zxf go-ethereum-${ETH_VERSION}.tar.gz  -C /go-ethereum
WORKDIR /go-ethereum/go-ethereum-${ETH_VERSION}
RUN go mod download 
RUN go run build/ci.go install

FROM ghcr.io/jac18281828/solc:latest as builder
# defined from build kit
# DOCKER_BUILDKIT=1 docker build . -t ...
ARG TARGETARCH

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt update && \
  apt install -y -q --no-install-recommends \
    git curl gnupg2 build-essential \
    g++-10 libc6-dev \ 
    openssl libssl-dev pkg-config \
    ca-certificates apt-transport-https \
  python3 && \
  apt clean && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home -s /bin/bash mr
RUN usermod -a -G sudo mr
RUN echo '%mr ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers


WORKDIR /rustup
## Rust
ADD https://sh.rustup.rs /rustup/rustup
RUN chmod 755 /rustup/rustup

ENV USER=mr
USER mr
RUN /rustup/rustup -y --default-toolchain stable --profile minimal

## Foundry
WORKDIR /foundry

# latest https://github.com/foundry-rs/foundry
ENV PATH=$PATH:~mr/.cargo/bin
RUN git clone https://github.com/foundry-rs/foundry

WORKDIR /foundry/foundry
RUN . ~mr/.cargo/env && \
    cargo install --path ./cli --profile local --bins --locked --force --jobs 1

FROM debian:stable-slim
ARG TARGETARCH

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt update && \
  apt install -y -q --no-install-recommends \
  git gnupg2 curl build-essential \
  sudo ripgrep npm procps \
  ca-certificates apt-transport-https \
  python3 python3-pip python3-dev && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*

RUN npm install yarn -g

RUN useradd --create-home -s /bin/bash mr
RUN usermod -a -G sudo mr
RUN echo '%mr ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# SOLC
COPY --from=builder /usr/local/bin/solc /usr/local/bin
COPY --from=builder /usr/local/bin/yul-phaser /usr/local/bin
COPY --from=builder /usr/local/bin/solidity-upgrade /usr/local/bin
RUN solc --version

## Rust 
COPY --chown=mr:mr --from=builder /home/mr/.cargo /home/mr/.cargo

# GO LANG
COPY --from=gobuilder /usr/local/go /usr/local/go

## GO Ethereum Binaries
ARG ETH_VERSION=1.10.26
COPY --from=gobuilder /go-ethereum/go-ethereum-${ETH_VERSION}/build/bin /usr/local/bin


