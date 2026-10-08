require "test_helper"
require "minitest/mock"

class MapUrlResolverTest < ActiveSupport::TestCase
  def resolve(url) = MapUrlResolver.call(url)

  test "google maps: prefers the pin (!3d!4d) over the viewport (@)" do
    url = "https://www.google.com/maps/place/Foo/@9.9281,-84.0907,17z/data=!3m1!4b1!4m6!3m5!8m2!3d9.93!4d-84.09"
    assert_equal [9.93, -84.09], resolve(url)
  end

  test "google maps: @lat,lng and q=lat,lng" do
    assert_equal [9.9281, -84.0907], resolve("https://www.google.com/maps/@9.9281,-84.0907,15z")
    assert_equal [9.9281, -84.0907], resolve("https://maps.google.com/?q=9.9281,-84.0907")
  end

  test "apple maps: ll and coordinate params" do
    assert_equal [9.9281, -84.0907], resolve("https://maps.apple.com/?ll=9.9281,-84.0907&q=Foo")
    assert_equal [9.9281, -84.0907], resolve("https://maps.apple.com/place?coordinate=9.9281%2C-84.0907")
  end

  test "waze: ll param, directions to=ll.lat,lng and geohash links" do
    assert_equal [9.9281, -84.0907], resolve("https://waze.com/ul?ll=9.9281%2C-84.0907&navigate=yes")
    assert_equal [9.9281, -84.0907], resolve("https://www.waze.com/live-map/directions?to=ll.9.9281%2C-84.0907")
    lat, lng = resolve("https://waze.com/ul/hu4pruydqqvj")
    assert_in_delta 57.64911, lat, 0.0001
    assert_in_delta 10.40744, lng, 0.0001
  end

  test "short links follow redirects, only to allowed hosts" do
    resolver = MapUrlResolver.new
    hops = {"https://maps.app.goo.gl/abc" => "https://www.google.com/maps/@9.9281,-84.0907,15z"}
    resolver.stub(:redirect_of, ->(uri) { hops[uri.to_s] }) do
      assert_equal [9.9281, -84.0907], resolver.call("https://maps.app.goo.gl/abc")
    end
  end

  test "apple short links (maps.apple/p/...) follow the redirect to the coordinate" do
    resolver = MapUrlResolver.new
    hops = {"https://maps.apple/p/ZYmK~gANsKXo9~" => "https://maps.apple.com/place?coordinate=10.481639,-85.786175&name=Calle%20Potrero&map=h"}
    resolver.stub(:redirect_of, ->(uri) { hops[uri.to_s] }) do
      assert_equal [10.481639, -85.786175], resolver.call("https://maps.apple/p/ZYmK~gANsKXo9~")
    end
  end

  test "rejects other hosts, plain http, links without coordinates and garbage" do
    assert_nil resolve("https://evil.com/?q=9.9281,-84.0907")
    assert_nil resolve("https://google.com.evil.com/maps/@9.9281,-84.0907,15z")
    assert_nil resolve("http://www.google.com/maps/@9.9281,-84.0907,15z")
    assert_nil resolve("https://waze.com/ul?q=Pizza")
    assert_nil resolve("no es un enlace")
    assert_nil resolve("https://www.google.com/maps/@95.0,-84.0907,15z")
  end
end
