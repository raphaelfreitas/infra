backend default {
  .host = "127.0.0.1";
  .port = "8080";
}

acl purge {
  "127.0.0.1";
  "localhost";
}

sub vcl_recv {
    if (req.request == "PURGE") {
      if (!client.ip ~ purge) {
        error 405 "Not allowed.";
      }
      ban("req.url ~ "+req.url+" && req.http.host == "+req.http.host);
      error 200 "OK";
    }

    # only using one backend
    set req.backend = default;

    # set standard proxied ip header for getting original remote address
    set req.http.X-Forwarded-For = client.ip;

    # logged in users must always pass
    if( req.url ~ "^/wp-(login|admin)|login-master|comprar|login" || req.http.Cookie ~ "wordpress_logged_in_" ){
        return (pass);
    }

    # don't cache search results
#    if( req.url ~ "\?s=" ){
#        return (pass);
#    }

    # always pass through posted requests and those with basic auth
    if ( req.request == "POST" || req.http.Authorization ) {
         return (pass);
    }

    # else ok to fetch a cached page
    unset req.http.Cookie;
    return (lookup);
}

sub vcl_fetch {

    # remove some headers we never want to see
    unset beresp.http.Server;
    unset beresp.http.X-Powered-By;

    # only allow cookies to be set if we're in admin area - i.e. commenters stay logged out
    if( beresp.http.Set-Cookie && req.url !~ "^/wp-(login|admin)|login-master|comprar|login" ){
        unset beresp.http.Set-Cookie;
    }

    # don't cache response to posted requests or those with basic auth
#    if ( req.request == "POST" || req.http.Authorization ) {
#         return (hit_for_pass);
#    }

    # only cache status ok
    if ( beresp.status != 200 ) {
        return (hit_for_pass);
    }

    # don't cache search results
#    if( req.url ~ "\?s=" ){
#        return (hit_for_pass);
#    }

    # else ok to cache the response
    set beresp.ttl = 24h;
    return (deliver);
}




sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    }
    else {
        set resp.http.X-Cache = "MISS";
    }
    unset resp.http.Via;
    unset resp.http.X-Varnish;
}

sub vcl_hit {
  if (req.request == "PURGE") {
    purge;
    error 200 "OK";
  }
}

sub vcl_miss {
  if (req.request == "PURGE") {
    purge;
    error 404 "Not cached";
  }
}


sub vcl_hash {
    hash_data( req.url );
    if ( req.http.host ) {
        hash_data( regsub( req.http.host, "^([^\.]+\.)+([a-z]+)$", "\1\2" ) );
    } else {
        hash_data( server.ip );
    }
    # ensure separate cache for mobile clients (WPTouch workaround)
    if( req.http.User-Agent ~ "(iPod|iPhone|incognito|webmate|dream|CUPCAKE|WebOS|blackberry9\d\d\d)" ){
        hash_data("touch");
    }
    return (hash);
}
