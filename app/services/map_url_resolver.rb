require "net/http"

# Obtiene [lat, lng] de un enlace de Google Maps, Apple Maps o Waze. Si el enlace
# no trae coordenadas (enlaces cortos), sigue las redirecciones, solo hacia hosts
# de esos servicios (evita SSRF).
class MapUrlResolver
  DOMAINS = %w[google.com goo.gl apple.com maps.apple waze.com].freeze
  MAX_HOPS = 5
  COORD = /\A(?:ll\.)?(-?\d{1,3}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)\z/
  COORD_PARAMS = %w[q ll query destination daddr center sll coordinate to].freeze
  GEOHASH = "0123456789bcdefghjkmnpqrstuvwxyz"

  def self.call(url) = new.call(url)

  # @return [Array<Float>, nil] [lat, lng]
  def call(url, hops = 0)
    uri = parse(url) or return nil
    coords_in(uri) || (hops < MAX_HOPS && (next_url = redirect_of(uri)) && call(next_url, hops + 1)) || nil
  end

  private

  def parse(url)
    uri = URI.parse(url.to_s.strip)
    uri if uri.is_a?(URI::HTTPS) && allowed_host?(uri.host)
  rescue URI::InvalidURIError
    nil
  end

  def allowed_host?(host)
    host = host.to_s.downcase
    DOMAINS.any? { |d| host == d || host.end_with?(".#{d}") }
  end

  def coords_in(uri)
    text = CGI.unescape(uri.to_s)
    (m = text.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/)) && (return valid(m[1], m[2]))
    (m = text.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/)) && (return valid(m[1], m[2]))
    (m = uri.path.to_s.match(%r{/ul/h([0-9a-z]+)\z}i)) && (return geohash(m[1]))

    params = URI.decode_www_form(uri.query.to_s).to_h
    COORD_PARAMS.each do |key|
      (m = params[key].to_s.strip.match(COORD)) && (found = valid(m[1], m[2])) && (return found)
    end
    nil
  end

  def valid(lat, lng)
    lat, lng = Float(lat), Float(lng)
    [lat, lng] if lat.between?(-90, 90) && lng.between?(-180, 180)
  end

  # Waze comparte ubicaciones como waze.com/ul/h<geohash>
  def geohash(hash)
    lat, lng = [-90.0, 90.0], [-180.0, 180.0]
    even = true
    hash.downcase.each_char do |c|
      bits = GEOHASH.index(c) or return nil
      4.downto(0) do |i|
        range = even ? lng : lat
        mid = (range[0] + range[1]) / 2
        bits[i] == 1 ? range[0] = mid : range[1] = mid
        even = !even
      end
    end
    [(lat.sum / 2).round(6), (lng.sum / 2).round(6)]
  end

  def redirect_of(uri)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3) do |http|
      http.get(uri.request_uri, "User-Agent" => "Mozilla/5.0")
    end
    URI.join(uri, response["location"]).to_s if response.is_a?(Net::HTTPRedirection) && response["location"]
  rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, URI::InvalidURIError
    nil
  end
end
