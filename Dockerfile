FROM python
USER root
WORKDIR /app
COPY . .
RUN pip install scapy netifaces && chmod +x *
CMD [ "/app/main.py" ]