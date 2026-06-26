#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "time"

GasResult = Struct.new(:example, :suite, :test, :gas, keyword_init: true)
RunResult = Struct.new(:label, :fe_bin, :log_path, :exit_status, :gas, :failed_examples, keyword_init: true)

def usage
  <<~TEXT
    Usage:
      bench/compare_sol_fe_gas.rb [options] [FE_BIN] [-- FORGE_ARGS...]

    Examples:
      bench/compare_sol_fe_gas.rb ~/code/fe/sona-bump/target/release/fe
      bench/compare_sol_fe_gas.rb --top 10 -- --match-test testGas
  TEXT
end

options = {
  out_dir: File.expand_path("out/gas-compare", Dir.pwd),
  label: "sol-vs-fe",
  keep_ansi: false,
  top: 20,
}

parser = OptionParser.new do |opts|
  opts.banner = usage

  opts.on("--out-dir DIR", "Directory for captured logs (default: out/gas-compare)") do |dir|
    options[:out_dir] = File.expand_path(dir)
  end

  opts.on("--label LABEL", "Label for the captured log (default: sol-vs-fe)") do |label|
    options[:label] = label
  end

  opts.on("--top N", Integer, "Number of largest Fe wins/losses to print (default: 20)") do |n|
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

if argv.length > 1
  warn parser.to_s
  exit 2
end

def executable_on_path?(command)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
    path = File.join(dir, command)
    File.file?(path) && File.executable?(path)
  end
end

def normalize_fe_bin(value)
  if value.include?(File::SEPARATOR)
    path = File.expand_path(value)
    return path if File.executable?(path)

    warn "Fe binary is not executable: #{path}"
    exit 2
  end

  return value if executable_on_path?(value)

  warn "Fe binary was not found on PATH: #{value}"
  exit 2
end

fe_bin = normalize_fe_bin(argv.first || ENV.fetch("FE_BIN", "fe"))

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
    gas[[result.example, result.suite, result.test]] = result
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

def format_delta(delta, base)
  pct = base.zero? ? 0.0 : (delta * 100.0 / base)
  format("%+d (%+.2f%%)", delta, pct)
end

def print_rows(rows, limit:)
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

run = run_rosetta(
  label: options[:label],
  fe_bin: fe_bin,
  out_dir: options[:out_dir],
  forge_args: forge_args,
  keep_ansi: options[:keep_ansi],
)

pairs = gas_pairs(run.gas)
rows = pairs.map do |key, pair|
  sol_gas = pair.fetch(:sol).gas
  fe_gas = pair.fetch(:fe).gas
  [key, sol_gas, fe_gas, fe_gas - sol_gas]
end.sort_by(&:first)

sol_total = rows.sum { |_key, gas, _fe_gas, _delta| gas }
fe_total = rows.sum { |_key, _sol_gas, gas, _delta| gas }
total_delta = fe_total - sol_total

puts
puts "Summary"
puts "======="
puts "exit: #{run.exit_status}, log: #{run.log_path}"
puts "Comparable Sol/Fe gas tests: #{rows.length}"
puts "Solidity total: #{sol_total}"
puts "Fe total: #{fe_total}"
puts "Delta: #{format_delta(total_delta, sol_total)}"

puts
puts "Largest Fe wins"
puts "==============="
wins = rows.select { |_key, _sol_gas, _fe_gas, delta| delta.negative? }
           .sort_by { |_key, _sol_gas, _fe_gas, delta| delta }
if wins.empty?
  puts "none"
else
  print_rows(wins, limit: options[:top])
end

puts
puts "Largest Fe losses"
puts "================="
losses = rows.select { |_key, _sol_gas, _fe_gas, delta| delta.positive? }
             .sort_by { |_key, _sol_gas, _fe_gas, delta| -delta }
if losses.empty?
  puts "none"
else
  print_rows(losses, limit: options[:top])
end

unpaired_sol = run.gas.values.select { |result| result.test =~ /^testGas_sol_/ && pairs.none? { |_key, pair| pair[:sol] == result } }
unpaired_fe = run.gas.values.select { |result| result.test =~ /^testGas_fe_/ && pairs.none? { |_key, pair| pair[:fe] == result } }

unless unpaired_sol.empty? && unpaired_fe.empty?
  puts
  puts "Unpaired gas tests"
  puts "=================="
  (unpaired_sol + unpaired_fe).sort_by { |result| [result.example, result.test] }.each do |result|
    puts "#{result.example.delete_prefix("examples/")} #{result.test}=#{result.gas}"
  end
end

unless run.failed_examples.empty?
  puts
  puts "Failed examples"
  puts "==============="
  run.failed_examples.sort.each do |example, code|
    puts "#{example} failed with exit code #{code}"
  end
end

exit(run.exit_status.zero? ? 0 : 1)
