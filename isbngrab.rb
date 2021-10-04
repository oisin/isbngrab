#!/usr/bin/env ruby

def valid_isbn?(isbn) 
  case (isbn.length)
  when 10
    check = 0;
    for inx in 0..9 do
      check += ((isbn[inx].chr != 'X') ? isbn[inx].chr.to_i : 10) * (10-inx) 
    end 
		return (check % 11 == 0)
  when 13
    check = 0
		for inx in 0..12 do
      check += isbn[inx].chr.to_i * (inx % 2 == 0 ? 1 : 3) 
    end
		return (check % 10 == 0)
  end
  false
end

filename = ARGV.shift
abort("No file name") if filename.nil?
abort("File not found") unless File.exist?(filename)
abort("File is a directory") if File.directory?(filename)
abort("File not readable") unless File.readable?(filename)
abort("File is empty") if File.zero?(filename)

valid_isbns = []
File.foreach(filename).with_index do |line, line_no|
  # One ISBN per line, validate the syntax of each line
  
    # Remove non-digit, non-X characters and upcase x
  isbn = line.gsub(/[^0-9xX]/,'').tr('x','X').strip
  if (valid_isbn?(isbn))
    valid_isbns << isbn
  else
    puts("Line #{line_no}:  Invalid ISBN - #{line.strip}") unless valid_isbn?(isbn)
  end
end

abort("No valid ISBNs") if valid_isbns.empty?

# Google Books API call for an ISBN search.
# GET https://www.googleapis.com/books/v1/volumes?q=isbn:9780060891541
# 
# Fetch the volume details of each ISBN and store for selection/disambiguation

require 'net/http'
require 'json'
volumes_table = {}

valid_isbns.each do |candidate_isbn|
  uri = URI("https://www.googleapis.com/books/v1/volumes?q=isbn:#{candidate_isbn}")
  res = Net::HTTP.get_response(uri)
  abort("Stopping on server issue code") if (res.code.to_i >= 500)

  if (res.code.to_i != 200)
    puts("Failed to fetch volume details with error code #{res.code}") 
  else  
    # Only some of the items in the Volume record are useful for our purposes
    #   items[].volumeInfo.title
    #   items[].volumeInfo.subtitle
    #   items[].volumeInfo.authors[]
    #   items[].volumeInfo.publisher
    #   items[].volumeInfo.publishedDate
    #   items[].volumeInfo.categories[]
    #   items[].volumeInfo.description
    #   items[].volumeInfo.imageLinks.thumbnail
    # Extracting the volumeInfo part removes some unnecessary items, but leaves
    # others at the same level. 

    volumes_raw = JSON.parse(res.body)['items']
    volumes_table[candidate_isbn] = volumes_raw.map do |vol|
      vol['volumeInfo']
    end
  end
end

# Going to spec arrays as pipe separated lists when emitting CSV

require 'csv'

headers = %q{ISBN Title Subtitle Authors Publisher PublishedDate Categories Description Thumbnail}.split
CSV.open('output.csv', 'w') do |csv|
  csv << headers
  volumes_table.each do |key, value|
    row = Array.new
    row << key  
    # Shortcut. Take the details of the first book only (index == 0)
    row << value[0]['title']
    row << value[0]['subtitle']
    row << value[0]['authors'].join('|')
    row << value[0]['publisher']
    row << value[0]['publishedDate']
    if (value[0]['categories'].nil?)
      row << ''
    else
      row << value[0]['categories'].join('|')
    end
    row << value[0]['description']
    unless (value[0]['imageLinks'].nil?) 
      row << value[0]['imageLinks']['thumbnail']
    end
    csv << row
  end
end