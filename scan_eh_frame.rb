#!/usr/bin/env ruby
# Analyzes .eh_frame section size distribution across system binaries.
# Uses bloaty to measure VM size ratios of exception handling data in
# executables (/usr/bin) and shared libraries (/usr/lib/x86_64-linux-gnu).
# Outputs CSV data with summary statistics.

require 'open3'

# Configuration
BLOATY_PATH = File.expand_path("~/Dev/bloaty/out/release/bloaty")
EXECUTABLE_DIR = "/usr/bin"
SHARED_LIB_DIR = "/usr/lib/x86_64-linux-gnu"

def analyze_file(file_path)
  return nil unless File.readable?(file_path)

  begin
    stdout, stderr, status = Open3.capture3(BLOATY_PATH, file_path)
    return nil unless status.success? && !stdout.empty?

    # Parse total VM size
    total_line = stdout.lines.find { |line| line.include?("TOTAL") }
    return nil unless total_line

    total_parts = total_line.strip.split
    total_vm_str = total_parts[-2]  # Second to last column should be VM size
    total_vm_kb = parse_size_to_kb(total_vm_str)
    return nil unless total_vm_kb && total_vm_kb > 0

    # Parse .eh_frame VM size (avoid matching .eh_frame_hdr)
    eh_frame_line = stdout.lines.find { |line| line.match(/\s+\.eh_frame\s+/) }
    return nil unless eh_frame_line

    eh_frame_parts = eh_frame_line.strip.split
    eh_frame_vm_str = eh_frame_parts[-2]  # Second to last column should be VM size
    eh_frame_vm_kb = parse_size_to_kb(eh_frame_vm_str)
    return nil unless eh_frame_vm_kb

    ratio = (eh_frame_vm_kb / total_vm_kb * 100).round(4)

    {
      file: file_path,
      total_vm_kb: total_vm_kb,
      eh_frame_vm_kb: eh_frame_vm_kb,
      ratio: ratio
    }
  rescue => e
    nil
  end
end

def parse_size_to_kb(size_str)
  return nil if size_str.nil? || size_str.empty?

  case size_str
  when /^(\d+\.?\d*)Ki$/
    $1.to_f
  when /^(\d+\.?\d*)Mi$/
    $1.to_f * 1024
  when /^(\d+\.?\d*)Gi$/
    $1.to_f * 1024 * 1024
  when /^(\d+\.?\d*)$/
    $1.to_f / 1024  # Assume bytes, convert to KB
  else
    nil
  end
end

def scan_directory(dir, pattern = nil, max_files = 200)
  return [] unless Dir.exist?(dir)

  files = if pattern
    Dir.glob(File.join(dir, pattern)).select { |f| File.file?(f) }
  else
    Dir.entries(dir).reject { |f| f.start_with?('.') }.map { |f| File.join(dir, f) }.select { |f| File.file?(f) && File.executable?(f) }
  end

  files.first(max_files)
rescue => e
  STDERR.puts "Error scanning #{dir}: #{e.message}"
  []
end

def process_files(files, description)
  STDERR.puts "Scanning #{description}..."
  STDERR.puts "Found #{files.length} #{description}"
  results = []
  files.each do |file|
    result = analyze_file(file)
    if result
      results << result
      puts "#{result[:file]},#{result[:total_vm_kb]},#{result[:eh_frame_vm_kb]},#{result[:ratio]}"
    else
      STDERR.puts "  No .eh_frame found or error"
    end
  end
  results
end

# Main execution
puts "Scanning .eh_frame VM size distribution..."
puts "File,Total_VM_KB,EH_Frame_VM_KB,EH_Frame_Ratio"

results = []

# Scan executables in /usr/bin
executables = scan_directory(EXECUTABLE_DIR)
results.concat(process_files(executables, "executables in #{EXECUTABLE_DIR}"))

# Scan shared objects in /usr/lib/x86_64-linux-gnu
shared_objects = scan_directory(SHARED_LIB_DIR, "*.so*")
results.concat(process_files(shared_objects, "shared objects in #{SHARED_LIB_DIR}"))

# Print summary statistics
STDERR.puts "\n=== Summary Statistics ==="
STDERR.puts "Total files analyzed: #{results.length}"

if results.any?
  ratios = results.map { |r| r[:ratio] }
  STDERR.puts "EH_Frame ratio statistics:"
  STDERR.puts "  Min: #{ratios.min.round(4)}%"
  STDERR.puts "  Max: #{ratios.max.round(4)}%"
  STDERR.puts "  Mean: #{(ratios.sum / ratios.length).round(4)}%"
  STDERR.puts "  Median: #{ratios.sort[ratios.length/2].round(4)}%"

  # Distribution buckets - adjusted for 0.3% to 11.51% range
  STDERR.puts "\nDistribution:"
  buckets = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]
  buckets.each_with_index do |bucket, i|
    next_bucket = buckets[i + 1]
    break unless next_bucket

    count = ratios.count { |r| r >= bucket && r < next_bucket }
    STDERR.puts "  #{bucket}%-#{next_bucket}%: #{count} files"
  end
end
