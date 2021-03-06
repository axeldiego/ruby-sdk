require 'cgi'
require 'digest/md5'
require 'rubygems'
require 'json'
require 'net/http'
require 'net/https'

module Facebook
# Copyright 2010 Facebook
# Adapted from the Python library by Alex Koppel, Context Optional
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
=begin
Ruby client library for the Facebook Platform.

This client library is designed to support the Graph API and the official
Facebook JavaScript SDK, which is the canonical way to implement
Facebook authentication. Read more about the Graph API at
http://developers.facebook.com/docs/api. You can download the Facebook
JavaScript SDK at http://github.com/facebook/connect-js/.
=end

  class GraphAPI
=begin  
    A client for the Facebook Graph API.

    See http://developers.facebook.com/docs/api for complete documentation
    for the API.

    The Graph API is made up of the objects in Facebook (e.g., people, pages,
    events, photos) and the connections between them (e.g., friends,
    photo tags, and event RSVPs). This client provides access to those
    primitive types in a generic way. For example, given an OAuth access
    token, this will fetch the profile of the active user and the list
    of the user's friends:

       graph = Facebook::GraphAPI(access_token)
       user = graph.get_object("me")
       friends = graph.get_connections(user["id"], "friends")

    You can see a list of all of the objects and connections supported
    by the API at http://developers.facebook.com/docs/reference/api/.

    You can obtain an access token via OAuth or by using the Facebook
    JavaScript SDK. See http://developers.facebook.com/docs/authentication/
    for details.

    If you are using the JavaScript SDK, you can use the
    Facebook::get_user_from_cookie() method below to get the OAuth access token
    for the active user from the cookie saved by the SDK.
=end

    attr_accessor :access_token
    
    def initialize(access_token = nil)
      self.access_token = access_token
      self
    end
    
    def get_object(id, args = {})
      #Fetchs the given object from the graph.
      self.request(id, args)
    end
    
    def get_objects(ids, args = {})
      # Fetchs all of the given object from the graph.
      # We return a map from ID to object. If any of the IDs are invalid,
      # we raise an exception.
      self.request(ids.join(","), args)
    end
    
    def get_connections(id, connection_name, args = {})
      #Fetchs the connections for given object.
      return self.request(id + "/" + connection_name, args)
    end
    
    def put_object(parent_object, connection_name, get_args = {}, post_args = nil)
=begin
        Writes the given object to the graph, connected to the given parent.

        For example,

            graph.put_object("me", "feed", :message => "Hello, world")

        writes "Hello, world" to the active user's wall. Likewise, this
        will comment on a the first post of the active user's feed:

            feed = graph.get_connections("me", "feed")
            post = feed["data"][0]
            graph.put_object(post["id"], "comments", :message => "First!")

        See http://developers.facebook.com/docs/api#publishing for all of
        the supported writeable objects.

        Most write operations require extended permissions. For example,
        publishing wall posts requires the "publish_stream" permission. See
        http://developers.facebook.com/docs/authentication/ for details about
        extended permissions.
        
=end
        raise "Write operations require an access token" unless self.access_token
        self.request(parent_object + "/" + connection_name, get_args, post_args)
    end
    
    def put_wall_post(message, attachment = {}, profile_id = "me")
=begin
        Writes a wall post to the given profile's wall.

        We default to writing to the authenticated user's wall if no
        profile_id is specified.

        attachment adds a structured attachment to the status message being
        posted to the Wall. It should be a dictionary of the form:

            {"name": "Link name"
             "link": "http://www.example.com/",
             "caption": "{*actor*} posted a new review",
             "description": "This is a longer description of the attachment",
             "picture": "http://www.example.com/thumbnail.jpg"}

=end
        self.put_object(profile_id, "feed", {:message => message}, attachment)
    end
    
    def put_comment(object_id, message)
      # Writes the given comment on the given post.
      self.put_object(object_id, "comments", {:message => message})
    end
    
    def put_like(object_id)
      #Likes the given post.
      self.put_object(object_id, "likes")
    end
    
    def delete_object(id)
      #Deletes the object with the given ID from the graph.
      self.request(id, nil, {"method" => "delete"})
    end
    
    def request(path, get_args = {}, post_args = nil)
=begin
      Fetches the given path in the Graph API.

      We translate args to a valid query string. If post_args is given,
      we send a POST request to the given path with the given arguments.
=end
      if self.access_token
        if post_args
          post_args["access_token"] = self.access_token
        else
          get_args["access_token"] = self.access_token
        end
      end
      
      http = Net::HTTP.new("graph.facebook.com", 443)
      http.use_ssl = true
      # TODO we could turn off certificate validation to avoid the "warning: peer certificate won't be verified in this SSL session" warning
      # not yet sure how best to handle that
      # see http://redcorundum.blogspot.com/2008/03/ssl-certificates-and-nethttps.html
      path += "?#{encode_params(get_args)}" if get_args
      
      result = http.start { |http|
        response, body = (post_args ? http.post(path, encode_params(post_args)) : http.get(path)) #Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path))
        body
      }

      # Facebook sometimes sends results like "true" and "false", which -- not being objects -- cause the parser to fail
      # so we account for that
      response = JSON.parse("[#{result}]")[0]
      raise GraphAPIError.new(response["error"]["code"], response["error"]["message"]) if response.is_a?(Hash) && response["error"]
      
      response
    end

    def encode_params(param_hash)
      # TODO investigating whether a built-in method handles this
      # if no hash (e.g. no auth token) return empty string
      ((param_hash || {}).collect do |key_and_value| 
        key_and_value[1] = key_and_value[1].to_json if key_and_value[1].class != String
        "#{key_and_value[0].to_s}=#{CGI.escape key_and_value[1]}"
      end).join("&")
    end
    protected :encode_params
  end

  
  class GraphAPIError < Exception
    attr_accessor :code
    def initialize(code, message)
      super(message)
      self.code = code  
    end
  end
  
  def get_user_from_cookie(cookies, app_id, app_secret)
=begin
    Parses the cookie set by the official Facebook JavaScript SDK.

    cookies should be a dictionary-like object mapping cookie names to
    cookie values.

    If the user is logged in via Facebook, we return a dictionary with the
    keys "uid" and "access_token". The former is the user's Facebook ID,
    and the latter can be used to make authenticated requests to the Graph API.
    If the user is not logged in, we return None.

    Download the official Facebook JavaScript SDK at
    http://github.com/facebook/connect-js/. Read more about Facebook
    authentication at http://developers.facebook.com/docs/authentication/.
=end

    if fb_cookie = cookies["fbs_" + app_id]
      # since we no longer get individual cookies, we have to separate out the components ourselves
      components = {}
      
      # split up the cookie, get the components for verification, and remove the sig before recombination 
      auth_string = fb_cookie.split("&").collect { |parameter| 
        # parameter is, e.g., expires=1260910800
        key_and_value = parameter.split("=")
        # save it to the hash
        components[key_and_value[0]] = key_and_value[1]
        
        # add it back to the string for sig verification, as long as it's not the expected sig value itself
        key_and_value[0] =~ /^sig=/ ? "" : parameter
      }.join("&") # preserving the order of the string

      sig = Digest::MD5.hexdigest(auth_string + app_secret)
      if sig == components["sig"] && Time.now.to_i < int(args["expires"])
        components
      else
        nil
      end
    end
  end
end