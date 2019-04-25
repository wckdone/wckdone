require 'sinatra'
require 'sinatra/cookies'
require "sinatra/content_for"
require 'kramdown'
require 'mini_magick'
require_relative './models/main'

use Rack::Logger

module Authentication
  def login! user
    session = Session.create user.id
    cookies[:token] = session.token
  end

  def current_user
    return nil unless cookies[:token]
    return @current_user unless @current_user.nil?
    session = Session.find(cookies[:token])
    return nil if session.nil? || session.user.nil?
    cookies[:token] = session.token
    session.user.log_visit(request.ip)
    @current_user = session.user
    @flash = Flash.new session.token
  end
end

module Images
  def create_image tempfile
    image = MiniMagick::Image::read(tempfile)
    return nil unless %w(JPEG GIF TIFF PNG).include?(image.type)
    name = SecureRandom.hex(64) + '.jpeg'
    path = '/photos/' + name
    image = MiniMagick::Image.open(tempfile.path)
    image.auto_orient
    image.strip
    image.format 'jpeg'
    image.resize '1200x1200>'
    image.write path
    return name
  rescue
    return nil
  end

  def stream_image name
    send_file "/photos/#{name}", type: 'image/jpeg'
  end
end

module Markdown
  def to_html(text)
    return nil if text.nil?
    text.gsub(/\n+/, '<br/>')
  end
end

class App < Sinatra::Application
  helpers Sinatra::Cookies
  helpers Sinatra::ContentFor
  helpers Markdown
  include Authentication
  include Images
  set :cookie_options, secure: ENV['APP_ENV'] == 'production',
      domain: 'wckdone.com', same_site: :lax, expires: Time.now + 3600*24*365,
      http_only: true, max_age: 3600*24*365

  set(:authenticated) do |_|
    condition do
      redirect '/register' if current_user.nil?
    end
  end

  set(:approved) do |_|
    condition do
      redirect '/register' if current_user.nil?
      redirect '/verify' unless current_user.is_approved?
    end
  end

  set(:admin) do |_|
    condition do
      redirect '/register' if current_user.nil?
      redirect '/' unless current_user.is_admin
    end
  end
  
  get '/profile', authenticated: true do
    erb :profile
  end

  get '/redirect', authenticated: true do
    @flash.message = "good!"
    redirect '/profile'
  end

  get '/verify', authenticated: true do
    erb :verify
  end

  post '/verify', authenticated: true do
    redirect '/verify' if params[:photo].nil? || params[:photo][:tempfile].nil?
    image = create_image params[:photo][:tempfile]
    if image.nil?
      @error = 'Image format not recognized'
      erb :verify
    else
      current_user.set_verified_photo(image)
      @flash.message = 'Verified photo updated'
      redirect '/verify'
    end
  end

  get '/verify/delete', authenticated: true do
    current_user.delete_verified_photo
    @flash.message = 'Verified photo deleted'
    redirect '/verify'
  end

  get '/images/:name', authenticated: true do
    cache_control :public, :no_transform, :max_age => 60*60*24
    stream_image(params[:name])
  end

  get '/verifications', admin: true do
    @users = User.all_pending_review
    erb :verifications
  end

  get '/verifications/:id', admin: true do
    @user = User.find(id: params[:id])
    redirect '/verifications' unless @user&.is_pending?
    erb :verifications_show
  end

  post '/verifications/:id/approve', admin: true do
    user = User.find(id: params[:id])
    redirect '/verifications' unless user&.is_pending?
    user.set_review_status current_user.id, :approved
    @flash.message = "User's verified photo approved"
    redirect '/verifications'
  end

  post '/verifications/:id/reject', admin: true do
    user = User.find(id: params[:id])
    redirect '/verifications' unless user&.is_pending?
    user.set_review_status current_user.id, :rejected, params[:reason]
    @flash.message = "User's verified photo rejected"
    redirect '/verifications'
  end
  
  get '/register' do
    @user = current_user || User.new
    erb :register, layout: :guest_layout
  end

  post '/register' do
    birth_date = Date.civil params[:birth_year].to_i, params[:birth_month].to_i,
                            params[:birth_day].to_i
    @user = User.new username: params[:username], gender: params[:gender],
                     password: params[:password] || '',
                     birth_date: birth_date
    @into_genders = User.genders.each.map{|g| g if params["into-#{g}"] == 'on'}.
                      filter{|g| g != nil} || []
    if @user.valid? && @into_genders.length > 0
      @user.save
      @user.set_gender_interests @into_genders
      login! @user
      redirect '/'
    else
      @user.errors.add(:into, 'cannot be empty') if @into_genders.length < 1
      erb :register, layout: :guest_layout
    end
  end

  get '/login' do
    @user = User.new
    erb :login, layout: :guest_layout
  end

  post '/login' do
    @user = User.find(username: params[:username])
    if @user.nil?
      @user = User.new
      @user.username = params[:username]
      @user.errors.add(:username, 'does not exist')
      erb :login, layout: :guest_layout
    elsif !@user.check_password(params[:password])
      @user.errors.add(:password, 'is not correct')
      erb :login, layout: :guest_layout
    else
      login! @user
      redirect '/'
    end
  end

  get '/description', authenticated: true do
    erb :description
  end
  
  post '/description', authenticated: true do
    current_user.set_description(params[:description])
    @flash.message = 'Description updated'
    redirect '/profile'
  end

  get '/gender', authenticated: true do
    erb :gender
  end

  post '/gender', authenticated: true do
    @user = current_user
    @into_genders = User.genders.each.map{|g| g if params["into-#{g}"] == 'on'}.
                      filter{|g| g != nil} || []
    @user.gender = params['gender']
    if @user.valid? && @into_genders.length > 0
      @user.save_changes
      @user.set_gender_interests @into_genders
      @flash.message = 'Genders updated'
      redirect '/profile'
    else
      @user.errors.add(:into, 'cannot be empty') if @into_genders.length < 1
      erb :gender
    end
  end

  get '/photos', approved: true do
    erb :photos
  end

  post '/photos', approved: true do
    redirect "/photos" if params[:photo_file].nil? || params[:photo_file][:tempfile].nil?
    image = create_image params[:photo_file][:tempfile]
    if image.nil?
      @error = 'Image format not recognized'
      erb :photos
    else
      current_user.add_photo(filename: image)
      @flash.message = 'Photo added'
      redirect "/photos?photo=#{current_user.photos.count() - 1}"
    end
  end

  get '/photos/:id/delete', approved: true do
    photo_id = params[:id].to_i
    if photo_id >= 0 && photo_id < current_user.photos.count()
      current_user.photos[params[:id].to_i].delete
      @flash.message = 'Photo deleted'
    end
    redirect '/photos'
  end

  get '/candidates', approved: true do
    @candidates = current_user.get_candidates((params[:distance] || 100).to_i)
    erb :candidates
  end

  get '/user/:id', approved: true do
    @user = User.find(id: params[:id])
    redirect '/' if @user.nil? || @user.review_status != 'approved'
    @my_action = Action.find(source: current_user.id, destination: @user.id)
    their_action = Action.find(source: @user.id, destination: current_user.id)
    @match = @my_action&.action == 'like' && their_action&.action == 'like'
    erb :user_show
  end

  get '/user/:id/:action', approved: true do
    user = User.find(id: params[:id])
    redirect '/' if user.nil?
    redirect '/' unless ['pass', 'like'].include? params[:action]
    Action.create_or_update source: current_user.id, destination: user.id,
                            action: params[:action]
    act = {like: 'Liked', pass: 'Passed on'}
    @flash.message = "#{act[params[:action].to_sym]} #{user.username}"
    if params[:next]
      redirect params[:next]
    else
      redirect "/"
    end
  end

  get '/matches', approved: true do
    @matches = current_user.get_matches
    @conversations = Message.get_latest current_user, @matches
    @matches = @matches.sort do |a, b|
      # We sort in Descending order
      @conversations[b.id].sent_on <=> @conversations[a.id].sent_on
    end
    if @matches.count == 0
      erb :no_matches
    else
      erb :matches
    end
  end

  get '/matches/:id', approved: true do
    @match = current_user.get_match(params[:id])
    redirect '/' if @match.nil?
    @messages = Message.get_between(current_user, @match)
    Message.mark_read(@messages)
    erb :match_show
  end

  post '/matches/:id/message', approved: true do
    @match = current_user.get_match(params[:id])
    redirect '/' if @match.nil?
    @messsages = Message.get_between(current_user, @match)
    if params[:message].nil? && params[:photo]
      @errors = {message: ['cannot be empty']}
      erb :match_show
    else
      if params[:photo]
        image = create_image params[:photo][:tempfile]
        Message.send(current_user, @match, nil, image) unless image.nil?
      end
      if params[:message]
        Message.send(current_user, @match, params[:message])
      end
      @flash.message = 'Message sent'
      redirect "/matches/#{@match.id}#focus"
    end
  end
  
  get '/logout' do
    redirect '/login' if cookies[:token].nil?
    session = Session.find(cookies[:token])
    session.delete if session
    response.delete_cookie('token', domain: 'wckdone.com', path: '/')
    redirect '/login'
  end

  get '/', approved: true do
    @user = current_user.next_candidate
    if @user
      erb :user_show
    else
      erb :out_of_candidates
    end
  end

  get '/search', approved: true do
    erb :search
  end

  post '/search', approved: true do
    redirect '/search' unless params[:distance]
    redirect '/search' unless User.genders.include?(params[:gender])
    redirect '/search' unless User.genders.include?(params[:into])
    current_user.new_search params[:gender], params[:into],
                            params[:keywords], params[:distance].to_i
    redirect '/search/results'
  end

  get '/search/results', approved: true do
    r = current_user.search_results params[:start].to_i
    @next_id = r[0]
    @users = r[1]
    if @users.nil? || @users.length == 0
      erb :search_no_results
    else
      erb :search_results
    end
  end

  get '/email', authenticated: true do
    erb :email
  end

  post '/email', authenticated: true do
    redirect '/email' unless ['yes', 'no'].include? params[:email_notifications]
    current_user.email_update params[:email], params[:email_notifications] == 'yes'
    if current_user.errors
      erb :email
    else
      @flash.message = 'Email updated'
      redirect '/profile'
    end
  end

  get '/email/verify/:user_id/:token' do
    user = User.find(id: params[:user_id])
    redirect '/' unless user
    user.email_verify(params[:token])
    redirect '/'
  end

  get '/password', authenticated: true do
    @user = current_user
    erb :password
  end

  post '/password', authenticated: true do
    @user = current_user
    @user.password_change params
    if @user.errors.count > 0
      erb :password
    else
      @flash.message = 'Password changed'
      redirect '/profile'
    end
  end
end
