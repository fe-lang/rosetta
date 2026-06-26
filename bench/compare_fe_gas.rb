#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "time"

GasResult = Struct.new(:example, :suite, :test, :gas, keyword_init: true) do
  def key
    [example, suite, test]
  end
end

RunResult = Struct.new(:label, :fe_bin, :log_path, :exit_status, :gas, :failed_examples, keyword_init: true)

def usage
  <<~TEXT
    Usage:
      bench/compare_fe_gas.rb [options] BASE_FE_BIN CANDIDATE_FE_BIN [-- FORGE_ARGS...]

    Examples:
      bench/compare_fe_gas.rb \\
        ~/code/fe/master/target/release/fe \\
        ~/code/fe/debug/target/release/fe

      bench/compare_fe_gas.rb --label-base master --label-candidate debug \\
        ~/code/fe/master/target/release/fe \\
        ~/code/fe/debug/target/release/fe -- --match-test testGas
  TEXT
end

options = {
  out_dir: File.expand_path("out/gas-compare", Dir.pwd),
  label_base: "base",
  label_candidate: "candidate",
  keep_ansi: false,
  top: 20,
}

parser = OptionParser.new do |opts|
  opts.banner = usage

  opts.on("--out-dir DIR", "Directory for captured logs (default: out/gas-compare)") do |dir|
    options[:out_dir] = File.expand_path(dir)
  end

  opts.on("--label-base LABEL", "Label for the first Fe binary (default: base)") do |label|
    options[:label_base] = label
  end

  opts.on("--label-candidate LABEL", "Label for the second Fe binary (default: candidate)") do |label|
    options[:label_candidate] = label
  end

  opts.on("--top N", Integer, "Number of largest improvements/regressions to print (default: 20)") do |n|
    options[:top] = n
  end

  opts.on("--keep-ansi", "Keep ANSI color escapes in saved logs") do
    options[:keep_ansi] = true
  end

  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

argv = ARGV.dup
separator = argv.index("--")
forge_args = separator ? argv[(separator + 1)..] : []
argv = argv[0...separator] if separator
parser.parse!(argv)

if argv.length != 2
  warn parser.to_s
  exit 2
end

base_bin = File.expand_path(argv[0])
candidate_bin = File.expand_path(argv[1])

[base_bin, candidate_bin].each do |path|
  next if File.executable?(path)

  warn "Fe binary is not executable: #{path}"
  exit 2
end

def strip_ansi(line)
  line.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
end

def parse_log(path)
  gas = {}
  failed_examples = {}
  current_example = nil
  current_suite = nil

  File.foreach(path) do |raw_line|
    line = strip_ansi(raw_line)

    if line =~ /^\[(examples\/[^\] ]+)\]$/
      current_example = Regexp.last_match(1)
      current_suite = nil
      next
    end

    if line =~ /^Ran \d+ tests? for (.+)$/
      current_suite = Regexp.last_match(1).strip
      next
    end

    if line =~ /^\[(examples\/[^\]]+) failed with exit code (\d+)\]$/
      failed_examples[Regexp.last_match(1)] = Regexp.last_match(2).to_i
      next
    end

    next unless line =~ /^\[PASS\]\s+(.+?)\s+\(gas:\s*(\d+)\)/

    result = GasResult.new(
      example: current_example || "unknown",
      suite: current_suite || "unknown",
      test: Regexp.last_match(1),
      gas: Regexp.last_match(2).to_i,
    )
    gas[result.key] = result
  end

  [gas, failed_examples]
end

def run_rosetta(label:, fe_bin:, out_dir:, forge_args:, keep_ansi:)
  FileUtils.mkdir_p(out_dir)
  timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
  safe_label = label.gsub(/[^A-Za-z0-9_.-]+/, "_")
  log_path = File.join(out_dir, "rosetta-#{safe_label}-#{timestamp}.log")

  env = { "FE_BIN" => fe_bin }
  cmd = ["./test.sh", *forge_args]

  puts "Running #{label}: FE_BIN=#{fe_bin}"
  puts "Log: #{log_path}"

  status = nil
  File.open(log_path, "w") do |log|
    Open3.popen2e(env, *cmd) do |_stdin, output, wait_thread|
      output.each_line do |line|
        log.write(keep_ansi ? line : strip_ansi(line))
        print line
      end
      status = wait_thread.value
    end
  end

  gas, failed_examples = parse_log(log_path)
  RunResult.new(
    label: label,
    fe_bin: fe_bin,
    log_path: log_path,
    exit_status: status.exitstatus,
    gas: gas,
    failed_examples: failed_examples,
  )
end

def format_delta(delta, base)
  pct = base.zero? ? 0.0 : (delta * 100.0 / base)
  format("%+d (%+.2f%%)", delta, pct)
end

def print_rows(rows, limit:)
  rows.first(limit).each do |row|
    key, base_gas, candidate_gas, delta = row
    example, _suite, test = key
    printf(
      "%-12s %-55s %9d -> %9d  %s\n",
      example.delete_prefix("examples/"),
      test,
      base_gas,
      candidate_gas,
      format_delta(delta, base_gas),
    )
  end
end

def gas_pairs(results)
  by_subject = {}

  results.each_value do |result|
    next unless result.test =~ /^testGas_(sol|fe)_(.+)$/

    kind = Regexp.last_match(1).to_sym
    subject = Regexp.last_match(2)
    key = [result.example, result.suite, subject]
    by_subject[key] ||= {}
    by_subject[key][kind] = result
  end

  by_subject.select { |_key, pair| pair.key?(:sol) && pair.key?(:fe) }
end

def sol_fe_rows(run)
  gas_pairs(run.gas).map do |key, pair|
    sol_gas = pair.fetch(:sol).gas
    fe_gas = pair.fetch(:fe).gas
    [key, sol_gas, fe_gas, fe_gas - sol_gas]
  end.sort_by(&:first)
end

def print_sol_fe_rows(rows, limit:)
  rows.first(limit).each do |row|
    (example, _suite, subject), sol_gas, fe_gas, delta = row
    printf(
      "%-12s %-40s %9d -> %9d  %s\n",
      example.delete_prefix("examples/"),
      subject,
      sol_gas,
      fe_gas,
      format_delta(delta, sol_gas),
    )
  end
end

def print_sol_fe_comparison(run, top:)
  rows = sol_fe_rows(run)
  sol_total = rows.sum { |_key, gas, _fe_gas, _delta| gas }
  fe_total = rows.sum { |_key, _sol_gas, gas, _delta| gas }
  total_delta = fe_total - sol_total

  puts
  puts "Solidity vs #{run.label}"
  puts "============#{'=' * run.label.length}"
  puts "Comparable Sol/Fe gas tests: #{rows.length}"
  puts "Solidity total: #{sol_total}"
  puts "#{run.label} Fe total: #{fe_total}"
  puts "Delta: #{format_delta(total_delta, sol_total)}"

  puts
  puts "Largest #{run.label} Fe wins"
  puts "========#{'=' * run.label.length}========"
  wins = rows.select { |_key, _sol_gas, _fe_gas, delta| delta.negative? }
             .sort_by { |_key, _sol_gas, _fe_gas, delta| delta }
  if wins.empty?
    puts "none"
  else
    print_sol_fe_rows(wins, limit: top)
  end

  puts
  puts "Largest #{run.label} Fe losses"
  puts "========#{'=' * run.label.length}=========="
  losses = rows.select { |_key, _sol_gas, _fe_gas, delta| delta.positive? }
               .sort_by { |_key, _sol_gas, _fe_gas, delta| -delta }
  if losses.empty?
    puts "none"
  else
    print_sol_fe_rows(losses, limit: top)
  end
end

base = run_rosetta(
  label: options[:label_base],
  fe_bin: base_bin,
  out_dir: options[:out_dir],
  forge_args: forge_args,
  keep_ansi: options[:keep_ansi],
)

candidate = run_rosetta(
  label: options[:label_candidate],
  fe_bin: candidate_bin,
  out_dir: options[:out_dir],
  forge_args: forge_args,
  keep_ansi: options[:keep_ansi],
)

base_keys = base.gas.keys
candidate_keys = candidate.gas.keys
common_keys = (base_keys & candidate_keys).sort

rows = common_keys.map do |key|
  base_gas = base.gas.fetch(key).gas
  candidate_gas = candidate.gas.fetch(key).gas
  [key, base_gas, candidate_gas, candidate_gas - base_gas]
end

base_total = rows.sum { |_key, gas, _candidate_gas, _delta| gas }
candidate_total = rows.sum { |_key, _base_gas, gas, _delta| gas }
total_delta = candidate_total - base_total

puts
puts "Summary"
puts "======="
puts "#{base.label} exit: #{base.exit_status}, log: #{base.log_path}"
puts "#{candidate.label} exit: #{candidate.exit_status}, log: #{candidate.log_path}"
puts "Comparable gas tests: #{rows.length}"
puts "#{base.label} total: #{base_total}"
puts "#{candidate.label} total: #{candidate_total}"
puts "Delta: #{format_delta(total_delta, base_total)}"

puts
puts "Largest improvements"
puts "===================="
improvements = rows.select { |_key, _base_gas, _candidate_gas, delta| delta.negative? }
                   .sort_by { |_key, _base_gas, _candidate_gas, delta| delta }
if improvements.empty?
  puts "none"
else
  print_rows(improvements, limit: options[:top])
end

puts
puts "Largest regressions"
puts "==================="
regressions = rows.select { |_key, _base_gas, _candidate_gas, delta| delta.positive? }
                  .sort_by { |_key, _base_gas, _candidate_gas, delta| -delta }
if regressions.empty?
  puts "none"
else
  print_rows(regressions, limit: options[:top])
end

print_sol_fe_comparison(base, top: options[:top])
print_sol_fe_comparison(candidate, top: options[:top])

base_only = base_keys - candidate_keys
candidate_only = candidate_keys - base_keys

unless base_only.empty?
  puts
  puts "Only in #{base.label}"
  puts "==============#{'=' * base.label.length}"
  base_only.sort.each do |example, _suite, test|
    puts "#{example.delete_prefix("examples/")} #{test}=#{base.gas.fetch([example, _suite, test]).gas}"
  end
end

unless candidate_only.empty?
  puts
  puts "Only in #{candidate.label}"
  puts "==============#{'=' * candidate.label.length}"
  candidate_only.sort.each do |example, _suite, test|
    puts "#{example.delete_prefix("examples/")} #{test}=#{candidate.gas.fetch([example, _suite, test]).gas}"
  end
end

unless base.failed_examples.empty? && candidate.failed_examples.empty?
  puts
  puts "Failed examples"
  puts "==============="
  { base => base.failed_examples, candidate => candidate.failed_examples }.each do |run, failures|
    next if failures.empty?

    failures.sort.each do |example, code|
      puts "#{run.label}: #{example} failed with exit code #{code}"
    end
  end
end

exit(base.exit_status.zero? && candidate.exit_status.zero? ? 0 : 1)
