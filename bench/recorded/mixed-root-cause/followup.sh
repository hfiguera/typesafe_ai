set -eu
export PATH="$HOME/.local/share/mise/installs/elixir/1.20.4-otp-29/bin:$HOME/.local/share/mise/installs/erlang/29.0.6/bin:$PATH"
cd /tmp/typesafe-performance/project/bench
export ERL_FLAGS='+S 4:4'
export BENCH_PORT=8452
export BENCH_FIXTURE_DESCRIPTION='Mac fixture over SSH reverse forwarding; Linux client on separate physical host'
python3 mixed_comparison.py --baseline /tmp/typesafe-mixed-baseline --clients baseline,typesafe --connections 1 --workloads medium_mix --rates 2000 --seconds 15 --repetitions 3 --output results/root-medium-guard > results/root-medium-guard.log 2>&1
python3 mixed_comparison.py --baseline /tmp/typesafe-mixed-baseline --clients baseline,typesafe --connections 1 --workloads large_mix --rates 1000 --seconds 15 --repetitions 3 --output results/root-large-guard > results/root-large-guard.log 2>&1
export TYPESAFE_BENCH_PATH=/tmp/typesafe-mixed-baseline
for storage in list ets; do
  BENCH_DIAGNOSTICS="results/root-driver-$storage-diagnostics.json" mix run diagnose.exs --client typesafe --rate 3000 --requests 90000 --connections 4 --max-concurrency 128 --max-queue 1024 --large-every 10 --bytes 65536 --sample-storage "$storage" --output "results/root-driver-$storage.json" > "results/root-driver-$storage.log" 2>&1
done
for variant in baseline typesafe; do
  if [ "$variant" = baseline ]; then export TYPESAFE_BENCH_PATH=/tmp/typesafe-mixed-baseline; else export TYPESAFE_BENCH_PATH=/tmp/typesafe-performance/project; fi
  BENCH_PROFILE=call_count mix run profile.exs --clients typesafe --protocols http2 --connections 4 --concurrency 32 --payloads 65536:1 --large-every 10 --delays 5 --requests 5000 --warmup 16 --repetitions 1 --output "results/root-profile-$variant.json" > "results/root-profile-$variant.log" 2>&1
done
