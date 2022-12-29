#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'

def read_price_comment(doc)
  res = {}
  price_content = doc.at_xpath(
    "//ul[@class='comments']/li[./div/a/@href='/@ilCesare']" +
    "/div[@class='e-content']"
  )
  unless price_content
    warn("Could not find price content")
    return res
  end
  price_content.content.split("\n")[1..-1].each do |line|
    if line =~ /^(\d+) bottles for \$(\d+\.\d\d) /
      res[$1.to_i] = $2.to_f
    elsif line =~ /^Case of (\d+) for \$(\d+\.\d\d) /
      res[$1.to_i] = $2.to_f
    elsif line =~ /^\s*$/
    elsif line =~ /^\d\d\d\d/
      # Extra line about wine in a mixed case
    elsif res[:name]
      warn("Unparseable price line #{line}")
    else
      res[:name] = line.strip
    end
  end
  return res
end

#
# Given a comment element, extracts the username and text.
#
def parse_comment_li(elt)
  return {
    :user => elt.at_css('span.username').content,
    :text => elt.at_css('div.e-content').content.strip,
    :reply => elt['class'].include?('reply'),
  }
end

#
# Find all the comment threads that mention the given username, and return a
# list of those comments.
#
def find_self_comment(doc, user = 'cduan')
  comments = doc.xpath("//a[@href='/@cduan']/ancestor::li[contains(@class, 'comment')]")
  return [] if comments.empty?

  res = []
  comments.each do |comment|
    res.push(parse_comment_li(comment))
    comment.css('ul.replies li.reply').each do |reply|
      res.push(parse_comment_li(reply))
    end
  end
  return res
end


def report_on_url(url)

  begin
    doc = Nokogiri::HTML(URI.open(url))
    forum_url = URI.join(url, doc.at_css("#buttons a.button.secondary")['href'])
    doc = Nokogiri::HTML(URI.open(forum_url), nil, 'UTF-8')

    price = read_price_comment(doc)
    puts price[:name]
    price.each do |btl, prc|
      next if btl == :name
      puts "  #{btl} bottles -> $#{prc}"
    end
    price[:url] = forum_url

    find_self_comment(doc).each do |comment|
      if comment[:reply]
        puts "   |- #{comment[:user]}: #{comment[:text][0, 50]}"
      else
        puts "  #{comment[:user]}: #{comment[:text][0, 50]}"
      end
    end

    return price
  rescue
    warn("Failure: #$!")
    return nil
  end

end


#
# Requests a URL and number of bottles to split.
#
def survey
  loop do
    puts "\nWhat is the Casemates URL? (Type ^D to quit)"
    url = gets
    return nil unless url
    data = report_on_url(url.strip)
    if data
      survey_split(data)
      return data
    else
      puts "Oops, that didn't work"
    end
  end
end

#
# Runs a survey on how many bottles to split. Modifies data to indicate the
# split.
#
def survey_split(data)
  loop do
    puts "\nHow many bottles are you giving away in a split?"
    res = (gets || "").strip
    case res
    when ""
      puts "Ok, you're keeping it all"
      return
    when "half", "case"
      puts "Ok, you're splitting 6 out of 12 bottles"
      split, tot = 6, 12
    when /^(\d+)\/(\d+)$/
      split, tot = $1.to_i, $2.to_i
    when /^(\d+)$/
      puts "Assuming you're splitting a case"
      split, tot = $1.to_i, 12
    end
    unless data.include?(tot)
      puts("This didn't come in a #{tot}-pack")
      next
    end
    data[:split] = [ split, tot ]
    data[:split_price] = (data[tot] * 1.0 * split / tot).round(2)
    puts("You should be paid $#{data[:split_price]}")
    return
  end
end

res = []
loop do
  data = survey()
  break unless data
  res.push(data) if data[:split]
end

puts "Here's a summary of what you're splitting:"

res.each do |data|
  puts("%-50s %2d @ $%6.2f/%2d = $%6.2f" % [
    data[:name][0, 50],
    data[:split][0],
    data[data[:split][1]],
    data[:split][1],
    data[:split_price]
  ])
end
puts("%68s $%6.2f" % [ "TOTAL", res.map { |x| x[:split_price] }.sum ])


