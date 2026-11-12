FROM python:3.13-slim

ARG LOCAL_UID=1000
ARG LOCAL_GID=1000
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY local_auth/ /app/local_auth/
RUN mkdir -p /data && chown "${LOCAL_UID}:${LOCAL_GID}" /data && chmod 0700 /data
USER ${LOCAL_UID}:${LOCAL_GID}
EXPOSE 8000
ENTRYPOINT ["python"]
CMD ["-m", "local_auth"]
