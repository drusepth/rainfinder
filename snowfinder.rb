require 'rest-client'
require 'json'
require 'date'
require 'pry'

portland = {
  latitude:  45.5152,
  longitude: -122.6784
}

@cache_filename = "weather-#{Date.today.to_s}.cache"
@api_lookup_cache = {}

def point_data(latitude, longitude)
  url = "https://api.weather.gov/points/#{latitude},#{longitude}"
  return @api_lookup_cache[url] if @api_lookup_cache.key?(url)
  
  # puts "Making fresh API request for #{url}"
  response = JSON.parse(RestClient.get(url))
  
  @api_lookup_cache[url] = response
end

def city_near(latitude, longitude)
  data = point_data(latitude, longitude)['properties']['relativeLocation']['properties']
  
  "#{data['city']}, #{data['state']}"
end

def grid_coordinates(latitude, longitude)
  data = point_data(latitude, longitude)
  [data['properties']['gridX'], data['properties']['gridY']]
end

def nearby_stations(latitude, longitude)
  data = point_data(latitude, longitude)
  stations = JSON.parse(RestClient.get(data['properties']['observationStations']))
  
  stations['features']
end

def forecast_url(latitude, longitude)
  data = point_data(latitude, longitude)
  data['properties']['forecast']
end

def forecast_data(latitude, longitude)
  data = JSON.parse(RestClient.get(forecast_url(latitude, longitude)))
  
  data['properties']['periods'].map do |period|
    {
      time:  period['name'],
      short: period['shortForecast'],
      long:  period['detailedForecast'],
      temperature: "#{period['temperature']}#{period['temperatureUnit']}"
    }
  end
end

def rainy_forecasts(latitude, longitude)
  forecast = forecast_data(latitude, longitude)
  
  forecast.select do |period|
    period[:long].downcase =~ /snow/
  end
end

def save_cache
  puts "Writing cache to #{@cache_filename}..."
  File.open(@cache_filename, "w") do |f|
    f.write(@api_lookup_cache.to_json)
  end
end

def load_cache
  if File.exist?(@cache_filename)
    puts "Loading cache from #{@cache_filename}..."
    @api_lookup_cache = JSON.parse(File.read(@cache_filename))
  end
end

load_cache


min_latitude = 43
max_latitude = 49
latitude_step = 0.5
max_longitude = -110
min_longitude = -124
longitude_step = 0.5

rainy_cities = []
min_latitude.step(max_latitude, latitude_step) do |latitude|
  min_longitude.step(max_longitude, longitude_step) do |longitude|
    # puts "Checking forecast at: #{latitude}, #{longitude}"
    print '.'
    $stdout.flush

    rain = nil
    begin
      rain = rainy_forecasts(latitude, longitude)
      
    rescue RestClient::InternalServerError
      # puts "Hit what is probably a rate limit... retrying in 5!"
      sleep 5
      retry
      
    rescue RestClient::NotFound
      # puts "Probably hit one of those Canadian corner cases or lost our bad internet"
      # binding.pry
      
    rescue RestClient::ServiceUnavailable
      # puts "who knows anymore"
      # binding.pry

    else
      if rain.any?
        rainy_cities << {
          city:     city_near(latitude, longitude),
          forecast: rain
        }
      end
    end
    
    sleep 0.5
  end
end

puts
save_cache
puts "CITIES WITHIN 900 MI WITH SNOW THIS WEEK"
puts "------------------------------"
rainy_cities.each do |rain|
  puts "#{rain[:city]}"
  rain[:forecast].each do |forecast|
    puts "* #{forecast[:time]}: #{forecast[:short]}"
  end
  puts
end; 0

