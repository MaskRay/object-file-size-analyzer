#!/usr/bin/env ruby
file = ARGV[0]

sections = `readelf -W -S "#{file}"`.lines
  .select { |l| l.match(/^\s*\[\d+\]/) }
  .map { |l|
    parts = l.split
    # Find the name (starts after the ]) and size (6th column after name)
    bracket_idx = parts.find_index { |p| p.match(/^\[\d+\]$/) }
    name = parts[bracket_idx + 1]
    size = parts[bracket_idx + 5].to_i(16)
    [name, size]
  }
  .to_h

sframe = sections['.sframe'] || 0
eh_frame = sections['.eh_frame'] || 0
eh_frame_hdr = sections['.eh_frame_hdr'] || 0
combined = eh_frame + eh_frame_hdr

sframe_ehframe_ratio = eh_frame > 0 ? (sframe.to_f / eh_frame).round(4) : 'N/A'
sframe_eh_ratio = combined > 0 ? (sframe.to_f / combined).round(4) : 'N/A'

puts "#{File.basename(file)}: sframe=#{sframe} eh_frame=#{eh_frame} eh_frame_hdr=#{eh_frame_hdr} eh=#{combined} sframe/eh_frame=#{sframe_ehframe_ratio} sframe/eh=#{sframe_eh_ratio}"
