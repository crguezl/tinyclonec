#!/usr/bin/env ruby
#
# A complete URL-shortening web application, written in Ruby/Sinatra. Run it 
# from the command line, and then visit http://localhost:4567/
#
# Or to run it under apache/passenger, you'll need a config.ru file with the
# following contents:
#
#   require 'tinyurl'
#   run Sinatra::Application
#
# 11 Apr 2009
# West Arete Computing
# http://westarete.com/

require 'rubygems'
require 'sinatra'
require 'active_record'

# ===== Controller =====

# Our home page lets people enter URLs to shorten.
get '/' do
  @link = Link.new
  haml :new
end

# Create a new short URL.
post '/' do
  # See if it already exists.
  @link = Link.find_by_url(params[:link][:url])
  if @link
    haml :show
  else
    # Create a new one.
    @link = Link.new(params[:link])
    if @link.save
      haml :show
    else
      haml :new
    end
  end
end

# Render the CSS stylesheet.
get '/stylesheet.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :stylesheet
end

# Redirect the visitor to the appropriate URL.
get '/:code' do
  @link = Link.find_by_code!(params[:code])
  @link.seen += 1
  @link.save!
  redirect @link.url
end

# https://groups.google.com/forum/#!msg/copenhagen-ruby-user-group/GEHgi_WudmM/gnCiwWqmVfMJ
# I have an issue with sinatra/activerecord, for some reason,
# activerecord does not check the connection back into the pool, when
# the request ends, so after [pool size] requests, the app starts
# throwing this at me:
# ActiveRecord::ConnectionTimeoutError - could not obtain a database connection within 5 seconds. The max pool size is currently 5; consider increasing it.
# I initially filed it in a support ticket at heroku, because I didn't discover before I deployed, but have since reproduced the problem locally.

after do
    ActiveRecord::Base.clear_active_connections!
end

# ===== Model =====

# See if we need to load the schema now, since the database will get created
# as soon as we connect.
dbfile = File.dirname(__FILE__) + '/database.sqlite3'
need_to_load_schema = ! File.exist?(dbfile)

# Connect to the database.
ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :database => dbfile)

# Create the database if it doesn't already exist.
if need_to_load_schema
  ActiveRecord::Schema.define do
    create_table "links", :force => true do |t|
      t.text     "url",   :null => false
      t.integer  "seen",  :null => false, :default => 0
      t.datetime "created_at"
    end
    add_index "links", ["url"], :name => "index_links_url", :unique => true
  end
end

# Due to the way that Sinatra reloads code, we need to wipe out our definition
# of the Link class after each request (in development mode).
Object.module_eval { remove_const(:Link) if const_defined?(:Link) } 
  
# This class is used to access the links that we create and follow.
class Link < ActiveRecord::Base  
  validates_presence_of   :url, :message => "You must specify a URL."
  validates_length_of     :url, :maximum => 4096, :allow_blank => true, :message => "That URL is too long."
  validates_format_of     :url, :with => %r{^(https?|ftp)://.+}i, :allow_blank => true, :message => "The URL must start with http://, https://, or ftp:// ."

  # :url is the only attribute that can be set via mass assignment, and only
  # via .new
  attr_accessible :url
  attr_readonly   :url
  
  # Retrieve the link with the given code. Raises Sinatra::NotFound if not
  # no such record.
  def self.find_by_code!(code)
    find_by_id(code.to_i(36)) or raise Sinatra::NotFound
  end

  # Return the code for this link. The code is the id in base 36 (all digits
  # plus all lowercase letters).
  def code
    id ? id.to_s(36) : nil
  end  
end

# ===== Helpers =====

# Helper methods that will be available in our route handlers and views.
helpers do

  # Escape HTML
  def h(text)
    Rack::Utils.escape_html(text)
  end
  
  # Escape URIs
  def u(text)
    URI.escape(text)
  end
  
  # The root URL for this site.
  def root_url
    server_name = headers['SERVER_NAME'] || 'localhost:4567'
    'http://' + server_name
  end
  
  # Return the proper pluralization for this number/word combination.
  def pluralize(number, word)
    "#{number} #{word}" + (number == 1 ? '' : 's') 
  end
    
  # Truncate the given text at the given length, adding ... to the end.
  def truncate(text, length)
    if text.length > length
      text[0...(length-3)] + '...'
    else
      text
    end
  end
  
  # Creates the browser link that people can use to post the current URL in
  # their browser to this application.
  def bookmarklet(text)
    # We need to POST the current URL to / from javascript. The only way
    # that I know to do this is to use javascript to create a form on the
    # current page, and then submit that form to /.
    js_code = <<-EOF
      var%20f = document.createElement('form'); 
      f.style.display = 'none'; 
      document.body.appendChild(f); 
      f.method = 'POST'; 
      f.action = '#{root_url}/'; 
      var%20m = document.createElement('input'); 
      m.setAttribute('type', 'hidden'); 
      m.setAttribute('name', 'link[url]'); 
      m.setAttribute('value', location.href); 
      f.appendChild(m); 
      f.submit();
      EOF
      
    # Remove all the whitespace from the javascript, so that it's a
    # bookmarkable URL.
    js_code.gsub!(/\s+/, '')
    
    # Return the link.
    %(<a href="javascript:#{js_code}">#{text}</a>)
  end
  
end

# ===== Views =====

#use_in_file_templates!
enable :inline_templates
__END__

@@ new
#new
  - unless @link.errors.empty?
    .error
      - for error in @link.errors.on(:url)
        %p= error

  %form{:action => '/', :method => 'post'}
    %label
      %input{:type => 'text', :size => '50', :name => 'link[url]', :value => @link.url}/
    %input{:type => 'submit', :value => 'Make Tiny'}/
    

@@ show
#show
  %dl
    %dt Tiny URL (copy this):
    %dd
      %a{:href => '/' + @link.code}= h(root_url + '/' + @link.code)
    %dt Points to: 
    %dd
      %a{:href => u(@link.url)}= h(truncate(@link.url, 60))
    %dt First created:
    %dd= @link.created_at.strftime('%A, %B %d, %Y at %I:%M:%S %p')
    %dt Used:
    %dd= pluralize(@link.seen, 'time')


@@ layout
!!! XML
!!! Strict
%html{:xmlns => "http://www.w3.org/1999/xhtml", "xml:lang" => "en"}
  %head
    %meta{"http-equiv" => "Content-type", "content" => "text/html; charset=utf-8"}/
    %link{:rel => 'stylesheet', :href => '/stylesheet.css', :type => 'text/css', :media => "screen, projection"}/
    %title Tiny URL

  %body
    %h1#title 
      %a{:href=>'/'} Tiny URL
    %p#tagline Shorten long, unruly URLs for pasting into tweets, chats, and emails.
  
    = yield
  
    #footer
      %p#bookmarklet
        Drag this link to your browser's bookmark bar to create a tiny URL 
        anywhere: 
        = bookmarklet("Link!")

      %p#copyright
        Copyright &copy;
        = Time.now.year
        %a{:href=>"http://westarete.com/"} West Arete Computing, Inc.

@@ stylesheet

.error
  :color red
  
#footer
  :margin-top 5em
  :font-size  small
