Description
--------------------------------------------------------------------------------
Python tools for WSGI applications. Fast HTTP request parsing, files uploads, 
HTTP requests security, etc.

Written in Cython it is compiled into native C code and works dozens times
faster than standard cgi.FieldStorage. For example, on requsts containing
three files attached with overall size of 15 MB it works >25 times faster
that cgi module. Plus it reads data from wsgi.input by blocks, parses them
on-the-fly and stores found files into temporary location, contraversal to cgi,
which reads request data line-by-line and stores each part fully in memory.

Currently this module provides the following functionality:

 1. HTTP requests parsing from WSGI environment. It provides PHP-like style
 of data representation. Thus it defines the following storages for handled
 request data with HttpRequest object:
  - SERVER
  - HEADERS
  - BODY
  - QUERY
  - COOKIE
  - FILES

 2. Configurable limitations for HTTP request. Such limitations gives an 
 ability to prevent WSGI application from been flooded via network with the
 large requests.Currently it's possible to limit:
  - max allowed files to upload
  - max request body size
  - max file size in bytes per uploaded file
  - enable/disable file uploads

 3. Simple work with uploaded files through FileUploader

 4. PHP-style parameters parsing. For example such QUERY_STRING

    	foo[][bar]=1&foo[][baz]=2&foo[xyz]=777

 will be parsed to the following Python's dictionary object:

    	foo : {
        	0 : {
            	"bar" : 1
        	},
        	1 : {
            	"baz" : 2
        	},
        	"xyz" : 777
    	}

 The same rule works on BODY, QUERY, COOKIE and FILES storages of HttpRequest
 object.

Basic usage example:

```python
    import wsgikit
    
    def my_wsgi_app( environ, start_response):
        status = '200 OK'
        response_headers = [('Content-type','text/plain')]
        start_response( status, response_headers)
        request = wsgikit.HttpRequest( environ)
        return wsgikit.PrettyDict.format( request.to_dict())
```

Installation
--------------------------------------------------------------------------------
This module is availabe via Python Package Index (PyPI). Installation is
possible with pip or easy_install, like

    > pip install wsgikit
or

    > easy_install wsgikit

It's also available manual installation from git repository, like

    > git clone git://github.com/Mikhus/wsgikit.git
    > cd wsgikit
    > python setup.py install

Documentation
--------------------------------------------------------------------------------
On-line documentation coming soon. Module is self-documented, so it is available
to read docs by using

    > import wsgikit
    > help(wsgikit)

in python command line.

License
--------------------------------------------------------------------------------
This package is subject to MIT License. To get more info, please, see
LICENSE.txt file

Copyright (c) 2012
--------------------------------------------------------------------------------
Author: Mykhailo Stadnyk <mikhus@gmail.com>

Home page: https://github.com/Mikhus/wsgikit
