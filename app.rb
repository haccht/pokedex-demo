# Pokémon are registered trademarks of Nintendo and Game Freak.

require "json"
require "uri"
require "logger"
require 'digest'

require "httpclient"
require "redis"
require "sinatra/base"
require "sinatra/cookies"


CACHE_TTL = 30*24*60*60
REDIS_URL = "redis://127.0.0.1:6379/0"
POKEAPI_V2_URL = "https://pokeapi.co/api/v2/"

class PokeApp < Sinatra::Base
  helpers Sinatra::Cookies
  configure :development, :production do
    logger = Logger.new($stdout)
    set :logger, logger
  end

  set :http,  HTTPClient.new
  set :cache, Redis.new(url: REDIS_URL)

  helpers do
    def httpget(url)
      resp = settings.http.get(url)
      return resp.body if resp.ok?

      raise HTTPClient::BadResponseError.new(uri.to_s)
    end

    def httpget_cached(url)
      unless data = settings.cache.get(url)
        data = httpget(url)
        settings.cache.setex(url, CACHE_TTL, data)
      end

      data
    end

    def poke(*args)
      uri  = URI.join(POKEAPI_V2_URL, File.join(args.map(&:to_s)))
      data = httpget_cached(uri.to_s)

      JSON.parse(data, object_class: OpenStruct)
    end

    def sprite(url)
      uri  = URI(url)
      data = httpget_cached(uri.to_s)

      File.join('/img', uri.scheme, uri.host, uri.path)
    end

    def translate(items, *langs)
      translate_all(items, *langs).first
    end

    def translate_all(original_items, *langs)
      langs.each do |lang|
        items = original_items.select { |e| e.language.name == lang }
        return items unless items.empty?
      end
      return []
    end
  end

  get '/' do
    total    = poke('pokemon-species').count
    pokeid   = Random.rand(1..total)

    redirect to("https://#{request.host}/pokemon/#{pokeid}"), 302
  end

  get '/pokemon/:pokeid' do
    total    = poke('pokemon-species').count
    pokeid   = params[:pokeid].to_i

    @species = poke('pokemon-species', pokeid)
    @pokemon = poke('pokemon', pokeid)

    @previd = (pokeid > 1)?     pokeid-1 : total
    @nextid = (pokeid < total)? pokeid+1 : 1

    @types  = @pokemon.types.map { |item| poke('type', item.type.name) }
    @genera = translate(@species.genera, 'ja', 'ja-Hrkt', 'en')&.genus
    @flavor = translate_all(@species.flavor_text_entries, 'ja', 'ja-Hrkt').sample&.flavor_text

    slim :show
  end

  get '/quiz' do
    total    = poke('pokemon-species').count
    pokeid   = Random.rand(1..total)

    @species = poke('pokemon-species', pokeid)
    @pokemon = poke('pokemon', pokeid)

    @previd = (pokeid > 1)?     pokeid-1 : total
    @nextid = (pokeid < total)? pokeid+1 : 1

    @types  = @pokemon.types.map { |item| poke('type', item.type.name) }
    @genera = translate(@species.genera, 'ja', 'ja-Hrkt', 'en')&.genus
    @flavor = translate_all(@species.flavor_text_entries, 'ja', 'ja-Hrkt').sample&.flavor_text

    slim :quiz
  end

  post '/quiz' do
    total    = poke('pokemon-species').count
    pokeid   = params[:pokeid].to_i
    redirect to('/quiz') if pokeid == 0

    @pokemon = poke('pokemon', params[:pokeid])
    @species = poke('pokemon-species', params[:pokeid])

    @previd = (pokeid > 1)?     pokeid-1 : total
    @nextid = (pokeid < total)? pokeid+1 : 1

    @types  = @pokemon.types.map { |item| poke('type', item.type.name) }
    @genera = translate(@species.genera, 'ja', 'ja-Hrkt', 'en')&.genus
    @flavor = translate_all(@species.flavor_text_entries, 'ja', 'ja-Hrkt').sample&.flavor_text

    @answer = params[:answer]
    @ok = ['ja', 'ja-Hrkt', 'en'].any? { |lang| translate(@species.names, lang).name == @answer }

    slim :quiz
  end

  get '/img/:scheme/:host/*' do
    uri  = URI::Generic.build(scheme: params[:scheme], host: params[:host], path: "/#{params[:splat].first}")

    case File.extname(uri.path).downcase
    when '.jpg', '.jpeg'
      content_type 'image/jpeg'
    when '.png'
      content_type 'image/png'
    when '.gif'
      content_type 'image/gif'
    when '.webp'
      content_type 'image/webp'
    when '.avif'
      content_type 'image/avif'
    when '.svg'
      content_type 'image/svg+xml'
    else
      raise HTTPClient::BadResponseError.new(uri.to_s)
    end

    response.write(httpget_cached(uri.to_s))
  end

  get '/cdn/sureroute-test-object.html' do
    send_file File.join(settings.public_folder, 'cdn', 'sureroute-test-object.html')
  end

  get '/private/*' do
    send_file File.join(settings.public_folder, params[:splat][0])
  end
end
