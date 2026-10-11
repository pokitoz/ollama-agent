#!/bin/bash
# start ollama, pull the models from .env, then keep running

ollama serve &
pid=$!
trap "kill $pid" TERM INT

# wait for the server to be up
until ollama list > /dev/null 2>&1; do
  sleep 1
done

for m in ${OLLAMA_MODELS_TO_PULL//,/ }; do
  if ollama show $m > /dev/null 2>&1; then
    echo "$m already there"
  else
    echo "pulling $m"
    ollama pull $m || echo "could not pull $m"
  fi
done

echo "ollama is ready"
wait $pid
