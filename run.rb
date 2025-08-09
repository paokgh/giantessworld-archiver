require "nokogiri"
require "debug"
require "net/http"

action =
  case ARGV[0]
  when "s"
    puts "PREPARING TO SCRAPE ALL STORIES"
    :stories
  when "o"
    puts "PREPARING TO SCRAPE ALL OLD STORIES"
    :old
  when "u"
    puts "PREPARING TO SCRAPE USERS FOUND IN SCRAPED STORIES"
    :users
  when "d"
    puts "scraping for discord links lmaooooo"
    :discord_links
  else
    puts "bro didn't call me with an argument 💀"
    puts "     ruby get_all.rb s  -  scrape all stories"
    puts "     ruby get_all.rb u  -  after scraping stories, scrape all author and reviewer users"
    puts "     ruby get_all.rb o  -  scrape the old story archive"
    puts "bro neads to READ the README"
    exit
  end

GWORLD = "https://giantessworld.net"

def get_table_of_contents_url(sid)
  "/viewstory.php?sid=#{sid}&index=1"
end

def get_user_url(uid)
  "/viewuser.php?uid=#{uid}"
end

def fetch(url)
  sleep 0.1
  response = Net::HTTP.get_response(URI(GWORLD + url))
  if (response.code != "200")
    raise "Error: response code #{response.code} for #{url}"
    exit
  end
  Nokogiri.HTML(response.body)
end

def is_error(table_of_contents)
  content = table_of_contents.css("#skinny")
  if content.text.strip ==
       "Access denied. This story has not been validated by the adminstrators of this site."
    return true
  end
  errortext = table_of_contents.css(".errortext")
  if errortext.text.strip ==
       "Access denied. This story has not been validated by the adminstrators of this site."
    return true
  end
  return false
end

def information_file_content(story_name, sid, author_name, uid)
  [
    "story_name: #{story_name}",
    "sid: #{sid}",
    "author_name: #{author_name}",
    "uid: #{uid}",
    "fetched_at: #{Time.now.utc.iso8601}"
  ].join("\n")
end

def force_insert_style(html)
  # force inserts a reference to the copied style sheet
  html.at_css("head").add_child <<-HTMLL
        <link rel="stylesheet" type="text/css" href="./style.css">
      HTMLL
end

def obliterate_frame(html)
  # removes the non-content html
  content = html.css("#skinny").first.parent.dup
  html.css("body").first["id"] = "middleindex" # this is a stupid hack to make the css work
  html.css("body").first.inner_html = content.inner_html
end

def prepare_html_for_saving(html)
  force_insert_style(html)
  obliterate_frame(html)
end

def fix_toc_chapter_links_for_the_hell_of_it(toc)
  linksdivs = toc.css("#output").children[4..]
  as = linksdivs.css("a").to_a.filter { |x| x["href"].include?("&chapter=") }
  as.each { |a| a["href"] = "./ch#{a["href"].split("=").last}.html" }
end

def fix_chapter_chapter_links_for_the_hell_of_it(chapter, one_base_index)
  n = chapter.css("a[class='next']").first
  if n
    n["href"] = "./ch#{one_base_index + 1}.html"
    #
  end
  p = chapter.css("a[class='prev']").first
  if p
    p["href"] = "./ch#{one_base_index - 1}.html"
    #
  end
end

if action == :discord_links
  # hahaha lol why the hell not
  d = []
  Dir
    .glob("scrape/stories/**/*.html")
    .each do |fn|
      txt = File.read(fn)
      txt.force_encoding("ISO-8859-1").encode("utf-8", replace: nil)
      d << txt.scan(%r{(discord\.gg/[a-zA-Z0-9]*)})
    end
  puts d.count
  Dir
    .glob("scrape/users/*.html")
    .each do |fn|
      txt = File.read(fn)
      txt.force_encoding("ISO-8859-1").encode("utf-8", replace: nil)
      d << txt.scan(%r{(discord\.gg/[a-zA-Z0-9]*)})
    end
  puts d.count

  d = d.flatten.map { |x| "https://" + x }.map(&:strip).uniq
  debugger
  puts d.sort.join("\n")

  # note that some of these are broken because they contain the next line's text. EG "fsdfsdaYu" Gi Oh
end

if action == :stories
  (1..17_000).each_slice(10) do |sids|
    threads = []

    sids.each do |sid|
      threads << Thread.new do
        table_of_contents_url = get_table_of_contents_url(sid)
        table_of_contents = fetch(table_of_contents_url)

        if is_error(table_of_contents)
          path = "./scrape/stories/null - [#{sid}]"
          puts "#{sid} is empty"
          next
        else
          user_name = table_of_contents.css("#pagetitle").children.last.text
          uid =
            table_of_contents.css("#pagetitle").children.last.attributes["href"]
              .value
              .split("=")
              .last
          story_title =
            table_of_contents.css("#pagetitle").children.first.text.strip

          number_of_reviews =
            table_of_contents.css("#sort").children[3].text.to_i
          # there are 20 per page
          num_of_review_offsets = (number_of_reviews / 20.0).ceil

          chapter_links =
            table_of_contents
              .css("#output")
              .css("a")
              .map { |x| x["href"] }
              .filter { |x| x.include?("viewstory.php?sid=#{sid}&chapter=") }

          cleaned_story_title = story_title.gsub(%r{[\x00/\\:\*\?\"<>\|]}, "_")

          path =
            "./scrape/stories/#{cleaned_story_title} by #{user_name} - #{sid}/"
          FileUtils.mkdir_p(path)
          FileUtils.cp("./scrape/stylesheet/style.css", path + "style.css")

          # Info
          File.write(
            path + "info.txt",
            information_file_content(story_title, sid, user_name, uid)
          )

          # TOC
          prepare_html_for_saving(table_of_contents)
          fix_toc_chapter_links_for_the_hell_of_it(table_of_contents)
          File.write(path + "toc.html", table_of_contents)

          # REVIEWS

          if (number_of_reviews > 0)
            (0...num_of_review_offsets).each do |off|
              offset = off * 20
              reviews_link = "/reviews.php?type=ST&item=#{sid}&offset=#{offset}"
              reviews = fetch(reviews_link)
              prepare_html_for_saving(reviews)
              File.write(path + "rv#{off + 1}.html", reviews)
              puts "#{sid} - reviews #{off + 1}/#{num_of_review_offsets}"
            end
          end

          # CHAPTER LINKS

          chapter_links.each do |chl|
            index = chl.split("=").last
            chapter = fetch("/" + chl)
            prepare_html_for_saving(chapter)
            fix_chapter_chapter_links_for_the_hell_of_it(chapter, index.to_i)
            File.write(path + "ch#{index}.html", chapter)
            puts "#{sid} - chapter #{index}/#{chapter_links.size}"
          end
        end

        puts "#{sid}"
      rescue StandardError => e
        puts "#{sid} failure:"
        puts e
        raise e
      end
    end
    threads.each { |thr| thr.join }
  end
end

def fetch_old_story(url)
  sleep 0.2
  orig_url = url
  # many of the links are just incorrect
  url = url.gsub("http", "https") # great going guys
  url = url.gsub("ps0.net", "giantessworld.net") # what the fuck

  # sometimes it's Stories and sometimes its stories. GREAT!!!!!

  url1 = url.gsub("/Stories/", "/stories/")
  url2 = url.gsub("/stories/", "/Stories/")
  url3 = url.gsub("/stories/", "/Stories5/") # ??????
  url4 = url.gsub("/stories/", "/Stories6/") # ??????

  [url1, url2, url3, url4].each do |url|
    response = Net::HTTP.get_response(URI(url1))
    return Nokogiri.HTML(response.body) if (response.code == "200")
  end

  raise "Couldn't find #{url}, sorry!"
  exit
rescue StandardError => e
  puts "something went very wrong with #{orig_url}"
  raise e
end

if action == :old
  old_page = fetch("/storiesauthor.html")
  links = old_page.css("a").map { _1["href"] }.dup
  base_path = "./scrape/old_stories/"
  FileUtils.mkdir_p(base_path)

  # just update all the links in the index
  old_page
    .css("a")
    .each do |a|
      a["href"] = "./" + a["href"].split("/").last
      #
    end
  File.write(base_path + "toc.htm", old_page)

  links.each_with_index do |link, i|
    next if i < 460
    i_have_no_fucking_idea_where_this_story_is = [
      "http://giantessworld.net/Reviews/babysitters_pet.htm"
    ]
    next if i_have_no_fucking_idea_where_this_story_is.include?(link)
    next if link.include?("Reviews") # can't find the reviews either
    next if link.include?("mailto:")
    next if link.include?("www.geocities.com") # lmao

    url = link
    story = fetch_old_story(url)
    fn = url.split("/").last
    fn = fn.gsub("%20", " ")
    File.write(base_path + fn, story)
    puts "#{fn} #{i + 1}/#{links.count}"
  end
end

if action == :users
  base_path = "./scrape/users/"
  FileUtils.mkdir_p(base_path)
  FileUtils.cp("./scrape/stylesheet/style.css", base_path + "style.css")

  # get the list of users.
  user_ids = []

  # 1. iterate through all info.txts for uids
  Dir
    .glob("scrape/stories/**/info.txt")
    .each do |fn|
      # this is dumb
      user_ids << File
        .read(fn)
        .split("\n")
        .filter { |x| x.start_with?("uid:") }
        .first
        .split(":")
        .last
        .strip
        .to_i
    end

  user_ids = user_ids.uniq
  authors_count = user_ids.count
  puts "authors: #{authors_count}"

  # 2. iterate through all review htmls for user id links (I can actually use regex for this!)
  Dir
    .glob("scrape/stories/**/rv*.html")
    .each do |fn|
      File
        .read(fn)
        .scan(/href\=\"viewuser\.php\?uid=(\d+)\"/)
        .flatten
        .map { |x| x.strip.to_i }
        .uniq
        .each { |uid| user_ids << uid }
    end

  # 3. uniq

  user_ids = user_ids.uniq
  puts "Reviewers: #{user_ids.count - authors_count}"
  puts "Total users: #{user_ids.count}"

  user_ids.sort.each_with_index do |uid, i|
    user_page = fetch(get_user_url(uid))
    username =
      user_page.css("#biotitle").children.map(&:text)[1]
        .split(" ")
        &.first
        &.strip

    if !username
      puts "THIS USER DOESN'T HAVE ANY INFORMATION?????? #{uid}"
      File.write(
        base_path + "[DELETED] #{username} -  #{uid}.html",
        "No bio info..."
      )
      next
    end

    raise "couldnt get username for #{uid}" if username.empty?
    prepare_html_for_saving(user_page)
    # only save the bio
    bio = user_page.css("#bio")
    body = user_page.css("body").first
    body.children.map(&:remove)
    body.add_child(bio)

    File.write(base_path + "#{username} - #{uid}.html", user_page)
    puts "#{uid} - #{username} (#{i + 1}/#{user_ids.count})"
  rescue StandardError => e
    puts "issue with #{uid}"
    raise e
  end
end
