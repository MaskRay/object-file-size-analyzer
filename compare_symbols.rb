#!/usr/bin/env ruby
# This tool analyzes and compares function symbols in two executable files,
# showing size differences for functions above a specified threshold.
# Uses `nm` to extract symbol information and displays results sorted by
# size ratio to identify functions that grew or shrank significantly.

def get_symbols(executable, threshold)
  output = `nm -gU --size-sort #{executable}`
  exit 1 unless $?.success?

  symbols = {}
  output.each_line do |line|
    parts = line.strip.split(/\s+/, 3)
    next unless parts.length >= 3

    size, type, name = parts
    next unless type =~ /[tT]/ && size.to_i(16) > threshold

    symbols[name] = size.to_i(16)
  end
  symbols
end

def compare_executables(exe1, exe2, threshold)
  symbols1 = get_symbols(exe1, threshold)
  symbols2 = get_symbols(exe2, threshold)
  common = symbols1.keys & symbols2.keys

  puts "\nComparing #{common.length} common functions above threshold 0x#{threshold.to_s(16)}"
  puts "%-60s %12s %12s %8s" % ["Symbol", File.basename(exe1), File.basename(exe2), "Ratio"]
  puts "-" * 88

  results = common.map do |name|
    ratio = symbols2[name].to_f / symbols1[name]
    [ratio, name, symbols1[name], symbols2[name]]
  end.sort.reverse

  results.each do |ratio, name, size1, size2|
    puts "%-60s %12s %12s %8.3f" % [
      name.length > 60 ? name[0..56] + "..." : name,
      "0x#{size1.to_s(16)}",
      "0x#{size2.to_s(16)}",
      ratio
    ]
  end
end

if ARGV.length < 3
  puts "Usage: #{$0} <executable1> <executable2> <threshold>"
  exit 1
end
compare_executables(ARGV[0], ARGV[1], ARGV[2].to_i(0))
