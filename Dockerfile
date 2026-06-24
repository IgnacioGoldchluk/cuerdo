FROM alpine:3.24.1

ARG TAG
ARG TARGETARCH

WORKDIR /app

ADD https://github.com/IgnacioGoldchluk/cuerdo/releases/download/${TAG}/cuerdo_linux_${TARGETARCH} /app/cuerdo

RUN chmod +x /app/cuerdo

ENTRYPOINT [ "/app/cuerdo" ]
