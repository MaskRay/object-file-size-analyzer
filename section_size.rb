#!/usr/bin/env ruby
# Analyze executable file sections using readelf
#
# This tool parses readelf output to extract and analyze section sizes
# including .text, .eh_frame, .eh_frame_hdr, .sframe, and VM memory usage.
# Groups results by basename and displays a formatted table showing
# section sizes with percentages and VM memory increase comparisons.
def analyze_output(output)
  state = text = vm = eh_frame = eh_frame_hdr = sframe = 0

  output.each_line do |line|
    case line
    when /Section Headers:/; state = 1
    when /Program Headers:/; state = 2
    when /Section to Segment/; state = 3
    end

    parts = line.split
    if state == 1
      # Find the name (starts after the ]) and size (6th column after name)
      bracket_idx = parts.find_index { |p| p.match(/^\[\d+\]$/) }
      next unless bracket_idx
      name = parts[bracket_idx + 1]
      case name
      when /^\.text/; text += parts[bracket_idx + 5].to_i(16)
      when '.eh_frame'; eh_frame = parts[bracket_idx + 5].to_i(16)
      when '.eh_frame_hdr'; eh_frame_hdr = parts[bracket_idx + 5].to_i(16)
      when '.sframe'; sframe = parts[bracket_idx + 5].to_i(16)
      end
    end

    if state == 2 && parts[0] == 'LOAD'
      vm += parts[5].to_i(16)
    end
  end

  { text: text, eh: eh_frame + eh_frame_hdr, sframe: sframe, vm: vm }
end

if ARGV.empty?
  puts "Error: No files specified"
  exit 1
end

# Analyze readelf output and group results by basename
basename_groups = Hash.new {|h, k| h[k] = [] }
has_sframe = false

ARGV.each do |file|
  output = `readelf -WSl "#{file}"`
  if $?.exitstatus != 0
    puts "Error running readelf on #{file}: #{output}"
    exit 1
  end
  data = analyze_output(output)
  has_sframe ||= data[:sframe] > 0
  basename_groups[File.basename(file)] << [file, data]
end

# Build rows array with all content
header = ["Filename", ".text size", "EH size"]
header << ".sframe size" if has_sframe
header << "VM size" << "VM increase"
rows = [header]

basename_groups.each do |basename, files|
  base_vm = files.first[1][:vm]  # VM size of first file with this basename

  files.each do |filename, data|
    text_pct = ((data[:text].to_f / data[:vm]) * 100).round(1)
    eh_pct = ((data[:eh].to_f / data[:vm]) * 100).round(1)

    row = [filename, "#{data[:text]} (#{text_pct}%)", "#{data[:eh]} (#{eh_pct}%)"]
    if has_sframe
      sframe_pct = ((data[:sframe].to_f / data[:vm]) * 100).round(1)
      row << "#{data[:sframe]} (#{sframe_pct}%)"
    end
    row << data[:vm].to_s

    row << if data[:vm] == base_vm
      "-"
    else
      vm_increase_pct = ((data[:vm] - base_vm).to_f / base_vm * 100).round(1)
      "#{vm_increase_pct > 0 ? '+' : ''}#{vm_increase_pct}%"
    end

    rows << row
  end
end

# Calculate column widths and print table
col_widths = (0...rows[0].length).map { |col| rows.map { |row| row[col].length }.max }

# Print header
puts rows[0].zip(col_widths).map.with_index { |(content, width), idx|
  idx == 0 ? content.ljust(width) : content.rjust(width)
}.join(" | ")
puts col_widths.map { |width| "-" * width }.join("-+-")

# Print data rows
rows[1..-1].each do |row|
  puts row.zip(col_widths).map.with_index { |(content, width), idx|
    idx == 0 ? content.ljust(width) : content.rjust(width)
  }.join(" | ")
end
