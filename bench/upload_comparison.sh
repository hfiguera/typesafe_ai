#!/bin/sh
# Run from bench/ with the separate fixture already listening on BENCH_PORT.
set -eu
: "${TYPESAFE_UPLOAD_BASELINE:?Set this to a checkout of commit 4982f5e}"
upload_prefix=${UPLOAD_OUTPUT_PREFIX:-results/upload}
upload_rate=${UPLOAD_RATE:-5000}
export ERL_FLAGS=${ERL_FLAGS:-'+S 4:4'}

select_version() {
  if [ "$1" = before ]; then
    TYPESAFE_BENCH_PATH=$TYPESAFE_UPLOAD_BASELINE
  else
    TYPESAFE_BENCH_PATH=..
  fi
  export TYPESAFE_BENCH_PATH
}

for upload_version in before after; do
  select_version "$upload_version"
  mix run run.exs --clients typesafe,finch --protocols http2 \
    --connections 1,4 --concurrency 128 \
    --payloads 256:1,256:32,16384:1,16384:32,16000:1,16400:1 --delays 0 \
    --requests 3000 --repetitions 3 --label "upload-$upload_version" \
    --output "$upload_prefix-$upload_version.json"
done

# Reverse version order for the mixed workload.
for upload_version in after before; do
  select_version "$upload_version"
  mix run run.exs --clients typesafe,finch --protocols http2 \
    --connections 1,4 --concurrency 128 --payloads 16384:32,524288:1 \
    --large-every 10 --delays 0 --requests 3000 --repetitions 3 \
    --label "upload-$upload_version-mixed" --output "$upload_prefix-$upload_version-mixed.json"
done

# Equal offered load, 90% small requests and 10% 512 KiB uploads.
for upload_repeat in 1 2 3 4 5; do
  for upload_connections in 1 4; do
    upload_order='before after'
    case "$upload_repeat" in 2|4) upload_order='after before';; esac
    for upload_version in $upload_order; do
      select_version "$upload_version"
      mix run load.exs --client typesafe --rate "$upload_rate" --requests 10000 \
        --connections "$upload_connections" --max-concurrency 128 --max-queue 1024 \
        --delay 0 --timeout 5000 --large-every 10 --bytes 524288 \
        --output "$upload_prefix-paired-$upload_version-${upload_connections}x-$upload_repeat.json"
    done
  done
done
