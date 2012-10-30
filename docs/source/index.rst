Welcome to WSGIkit's documentation!
====================================

Introduction
------------

WSGIkit module gives an ability to process low-level HTTP request
parsing in WSGI applications and provide a comfortable way to work
with the request data, such as: QUERY_STRING parameters, request
body parameters, request headers, cookie variables, server environment
variables and uploaded files.

It's written in Cython and compiles to shared Python library from
native C code.

For those, whom like how HTTP request handling done in PHP, - yes,
this module parses the request data almost in the same way and provides
almost the same containers (QUERY = _GET, BODY = _POST, SERVER = _SERVER,
COOKIE = _COOKIE, FILES = _FILES, etc.)

Contents
--------

.. toctree::
   :maxdepth: 4

   httprequest.rst
   fileuploader.rst
   prettydict.rst
   errors.rst

Dependencies
------------
To get this module work it is required to have Python 2.x or
Python 3.x with Cython module and Python dev packages installed.

It was tested under Python 2.7.3 and Python 3.2.3, so if you find any
problems installing and using it on other versions, please, post an
issues at https://github.com/Mikhus/wsgikit/issues.

Installation
------------

Before installing wsgikit module, be ensure you have Python dev-packages
installed on your system and you have Cython module for Python installed.
Installation of Cython as easy as:
::
	> pip install cython

or:
::
	> easy_install cython

There is also possibility to install Cython manually. Just download the package
from http://cython.org/#download, unpack it and run:
::
	> cd cython
	> python setup.py install

Than wsgikit module is availabe to install via Python Package Index (PyPI).
Installation is also as easy as:
::
	> pip install wsgikit

or:
::
	> easy_install wsgikit

It's also available manual installation from git repository, like:
::
	> git clone git://github.com/Mikhus/wsgikit.git
	> cd wsgikit
	> python setup.py install

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
