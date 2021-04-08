FROM python
USER root
WORKDIR /app
COPY . .
LABEL org.opencontainers.image.source=https://github.com/ahmetozer/bypass-isp-udp-proxy
RUN pip install scapy netifaces && chmod +x *
CMD [ "/app/main.py" ]