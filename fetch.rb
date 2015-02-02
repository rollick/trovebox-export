#!/usr/bin/env ruby

require "fileutils"
require "rubygems"

require "openphoto-ruby"
require "mini_exiftool"
require "typhoeus"
require "yaml"
require "awesome_print"


@debug = true

def log(object, options = {:multiline => false})
  ap object, options if @debug
end

def fetch(config="./default.yml")
  options = YAML.load_file(config)

  consumer_key = options["consumerKey"]
  consumer_secret = options["consumerSecret"]
  access_token = options["token"]
  access_token_secret = options["tokenSecret"]
  site = options["host"]

  client = Openphoto::Client.new(site, consumer_key, consumer_secret, access_token, access_token_secret)

  # get a list of albums
  albums = client.connect(:get, "/albums/list.json?auth=true&pageSize=9999")
  album_index = 1
  album_count = albums.result.length
  albums.result.each do |album|
    # create album directory if it doesn't exist
    album_name = album["name"].strip
    
    if Dir.exists?(album_name)
      log({"Skipping album (#{album_index}/#{album_count})" => album_name})
      album_index += 1
      next
    end

    log({"Processing album \"#{album_name}\"" => {
      "index" => "#{album_index}/#{album_count}",
      "photo_count" => album["count"]
    }}, {:multiline => true})

    # get a list of photos in this album
    remaining = 1
    page_size = 1000
    page = 1
    album_data = []
    while remaining > 0 do
      params = {
        "auth" => "true",
        "page" => page.to_s,
        "pageSize" => page_size.to_s,
        "album" => album["id"]
      }

      photos = client.connect(:get, "/photos/list.json?#{params.to_url_params}")

      if photos.result.length > 0
        # Download the photo and update IPTC info with keywords
        download photos.result, album_name, page_size
        
        # Merge fetched data set
        album_data.concat photos.result
      else
        remaining = 0
      end

      page += 1
    end

    json_filename = "#{album_name}/album.json"
    log({"Storing album data" => json_filename})

    album["photos"] = album_data
    File.open(json_filename, "w") do |file|
      file.puts JSON.pretty_generate(album)
    end

    album_index += 1
  end
end

def download(photos, dir, concurrency)
  hydra = Typhoeus::Hydra.new(max_concurrency: concurrency)
   
  photos.each do |photo|
    url = photo["pathOriginal"].gsub("http", "https")
    request = Typhoeus::Request.new url
    request.on_complete do |response|
      monthDouble = photo["dateTakenMonth"].to_i < 10 ? "0#{photo["dateTakenMonth"]}" : photo["dateTakenMonth"]
      filename = "./#{dir}/#{photo["dateTakenYear"]}/#{monthDouble}/#{File.basename(URI.parse(url.gsub(/<|>/, '')).path)}"

      process_photo photo, filename, response.body
    end
    hydra.queue request
  end
   
  hydra.run
end 

def process_photo(photo_data, filename, data)
  dirname = File.dirname(filename)
  unless File.directory?(dirname)
    FileUtils.mkdir_p(dirname)
  end

  File.open(filename, "w") do |file|
    file.puts data
  end

  # Update photo metadata with extra trovebox data
  photo = MiniExiftool.new(filename, iptc_encoding: "UTF8")
  photo.title = photo_data["title"]
  photo.comment = photo_data["description"]

  tags = photo_data["tags"].nil? ? [] : photo_data["tags"].map(&:to_s)
  photo["Keywords"] = tags
  photo.save()

  log({filename => {
    "title" => photo.title,
    "comment" => photo.comment,
    "keywords" => photo["Keywords"]
  }}, {:multiline => true})
end

class Hash
  def to_url_params
    elements = []
    keys.size.times do |i|
      elements << "#{CGI::escape(keys[i])}=#{CGI::escape(values[i])}"
    end
    elements.join("&")
  end

  def self.from_url_params(url_params)
    result = {}.with_indifferent_access
    url_params.split("&").each do |element|
      element = element.split("=")
      result[element[0]] = element[1]
    end
    result
  end
end

if __FILE__ == $0
  fetch
end
