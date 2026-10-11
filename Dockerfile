FROM ollama/ollama:latest

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_KEEP_ALIVE=30m

EXPOSE 11434

HEALTHCHECK --interval=15s --start-period=20s CMD ollama list || exit 1

ENTRYPOINT ["/entrypoint.sh"]
