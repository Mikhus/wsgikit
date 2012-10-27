"""Python tools for WSGI: HTTP request parsing, file upload handling, etc.
This code is subject to MIT license

Copyright (c) 2012 Mykhailo Stadnyk <mikhus@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""
import sys,os,hashlib,time,random,re

class HttpRequestError(Exception):
	"""Base error class for wsgikit.HttpRequest object
	"""
	pass

class MaxFilesError(HttpRequestError):
	"""Raised if the limit of max allowed files to upload reached
	"""
	def __init__(self, limit):
		self.limit = limit
	
	def __str__(self):
		return "Max uploaded files limit of %i files exceeded" \
			%(self.limit)

class MaxFileSizeError(HttpRequestError):
	"""Raised if one of the uploaded file exceeded max file size limit
	"""
	def __init__(self, filename, sizelimit):
		self.filename  = filename
		self.sizelimit = sizelimit
	
	def __str__(self):
		return 'Uploaded file "%s" exceeded size limit of %i bytes' \
			%(self.filename, self.sizelimit)

class MaxBodySizeError(HttpRequestError):
	"""Raised if data in request body (excluding files) exceeded 
	allowed limit of bytes
	"""
	def __init__(self, sizelimit):
		self.sizelimit  = sizelimit
	
	def __str__(self):
		return 'Max request body size limit of %i bytes exceeded' \
			%(self.sizelimit)

class FilesUploadError(HttpRequestError):
	"""Raised if files upload was disabled but the request
	contains the files in the body
	"""
	def __str__(self):
		return "Files upload was disabled, but files were found in request body"

class FileSaveError(HttpRequestError):
	"""Raised if an error occured during an attemt to save the
	uploaded file in a temporary location
	"""
	def __init__(self, filename, path, reason):
		self.filename = filename
		self.path     = path
		self.reason   = reason
	
	def __str__(self):
		return 'Error saving file "%s"\n Reason: %s' \
			%(self.filename, self.reason)

class HttpRequest(object):
	"""HttpRequest object handles an HTTP request, parses
	and provides a request data in a suitable format for
	further processing.
	
	Actually it is designed to handle a web environment
	in WSGI application.
	
	Benefit of using the wsgikit.HttpRequest:
	
	- significantly faster than standard cgi module
	  (savings grow exponentially to the amount
	  of data in request)
	- Protection to the WSGI application from 
	  flooding (provides configurable limitations
	  to the amount of allowed data in request body,
	  limits a number of attached files and file size
	  limit)
	- Comfortable PHP-like representation of the request
	  parameters:
	   
	::
		foo[][bar]=1&foo[][baz]=2&foo[xyz]=777
	
	will be parsed to the following dictionary:
	
	::
		{
			foo : {
				0 : {
					"bar" : 1
				},
				1 : {
					"baz" : 2
				},
				"xyz" : 777
			}
		}
	- Provides clean and tiny interface to work with request
	  parameters, web-server environment, uploaded files, cookies,
	  etc.
	
	Basic usage example:
	
	::
		import wsgikit
		
		def my_wsgi_app( environ, start_response):
			status = '200 OK'
			response_headers = [('Content-type','text/plain')]
			start_response( status, response_headers)
			
			request = wsgikit.HttpRequest( environ)
			
			return str( request)
	
	:Author: Mykhailo Stadnyk <mikhus@gmail.com>
	:Version: 1.0b
	"""
	_rx_keys_lookup = re.compile( "\[(.*?)\]")
	_rx_name_lookup = re.compile( "^(.*?)(?:\[.*$|$)")
	
	def __init__(self,
		environ              = None,          # wsgi environment
		encoding             = 'utf-8',       # request encoding
		files_upload_on      = True,          # do uploaded files should be loaded to the memory or saved temporary to disc?
		uploaded_files_dir   = '/tmp',        # where to store temporary uploaded files
		max_uploaded_files   = 20,            # max number for uploaded files
		max_filesize         = 2097152,       # 2MB max size per file
		max_content_length   = 8388608,       # 8MB max size per body content
		uploaded_file_prefix = 'http-upload-' # prefix to use for temporary uploaded file
	):
		if environ is None:
			environ = os.environ
		
		self._environ              = environ
		self._encoding             = encoding
		self._files_upload_on      = files_upload_on
		self._uploaded_files_dir   = uploaded_files_dir
		self._max_uploaded_files   = max_uploaded_files
		self._max_filesize         = max_filesize
		self._max_content_length   = max_content_length
		self._uploaded_file_prefix = uploaded_file_prefix
		
		self.QUERY    = {}
		self.BODY     = {}
		self.COOKIE   = {}
		self.HEADERS  = {}
		self.FILES    = {}
		self.SERVER   = {}
		
		self.FileUploader = None
		self.method       = None
		
		self._parse()
	
		
	def _normilize_key(self, key):
		key = key.lower().split( '-')
		
		for k,v in enumerate(key):
			try :
				key[k] = v[0].upper() + v[1:]
			except IndexError:
				continue
		
		return "-".join( key)
	
	def _cleanup_value(self, value):
		try :
			fch = value[0]
			lch = value[-1]
			
			if (fch == lch) and (fch == '"') or (fch == "'"):
				value = value[1 : len( value) - 1]
		
		except IndexError:
			pass
		
		return value
	
	def _parse_key_value(self, items, delimiter = '=', normalize = False, cleanup = False):
		kv_dict = {}
		for item in items:
			name = value = ''
			nstop = False
			
			for ch in item:
				if not nstop:
					if ch != delimiter:
						name += ch
					
					else :
						nstop = True
						continue
				
				else:
					value += ch
			
			if name:
				name = name.strip()
				value = value.strip()
				
				if normalize:
					name = self._normilize_key( name)
				
				if cleanup:
					value = self._cleanup_value( value)
				
				kv_dict[name] = value
		return kv_dict
	
	def _decode_value(self, value):
		if type( value) == bytes:
			value = value.decode( self._encoding)
		
		return value
	
	def _parse_cookie(self):
		cookie = self.header( 'Cookie')
		
		if cookie:
			cookie = self._parse_key_value( cookie.split( ';'))
			
			for name in cookie:
				self._parse_param(
					name.strip(),
					cookie[name],
					self.COOKIE
				)
	
	def _parse_headers(self):
		cdef int k
		for key, value in self._environ.items():
			try :
				if key[:5] == 'HTTP_':
					name = key[5:].split( '_')
					
					for k,v in enumerate( name):
						name[k] = v[0].upper() + v[1:].lower()
					
					name = "-".join(name)
					self.HEADERS[name] = self._decode_value( value)
			except :
				pass
		
		self.HEADERS['Content-Length'] = int( self._environ.get( 'CONTENT_LENGTH', '0'))
		
		ctype = self._environ.get('CONTENT_TYPE')

		if ctype :
			self.HEADERS['Content-Type'] = ctype 
	
	def _parse_server(self):
		for svar in self._environ:
			if svar != 'wsgi.input':
				self.SERVER[svar] = self._decode_value( self._environ[svar])
	
	def _parse_body(self):
		cdef unsigned long content_length
		content_length = self.header( 'Content-Length', 0)
		
		if ('wsgi.input' not in self._environ) or not content_length:
			return False
		
		instream = self._environ['wsgi.input']
		
		is_multipart = False
		boundary     = ''
		
		# check if body is multipart or not
		body_type = self.header( 'Content-Type')
		if body_type:
			body_type = body_type.split( ';')
			
			for piece in body_type:
				_piece = piece.strip().lower()
				
				# check if multipart
				if not is_multipart and (_piece in ['multipart/form-data', 'multipart/mixed']):
					is_multipart = True
				
				# lookup boundary
				try :
					if (boundary == '') and (_piece[:8] == 'boundary'):
						nstop = False
						
						for ch in piece:
							if not nstop:
								if ch == '=':
									nstop = True
									continue
							
							else:
								boundary += ch
				except :
					pass
				
				if is_multipart and (boundary != ''):
					break
			
			if is_multipart:
				self._parse_multipart( instream, bytes( boundary, self._encoding), content_length)
			
			else :
				self.BODY = self._parse_query_params( instream.read( content_length), self._encoding)
	
	def _parse_multipart(self, instream, boundary, content_length):
		cdef int buff_len = 8 * 1024
		cdef long remaining
		cdef int k
		cdef int size
		cdef long data_read
		
		# create temporary properties
		try :
			self._parts
		except AttributeError:
			self._parts = {}
		
		try :
			self._files_counter
		except AttributeError:
			self._files_counter = 0
		
		try :
			self._body_length
		except AttributeError:
			self._body_length = 0
		
		remaining = content_length
		next_data = b''
		endl      = b'\x0a'
		size      = buff_len
		data_read = 0
		
		while True:
			if remaining <= 0:
				break
			
			if buff_len > remaining:
				size = remaining
			
			data = instream.read( size)
			remaining -= size
			
			curr_data = b''
			
			# we want to ensure the block ends-up with the new line
			k = size
			while k > 0:
				k -= 1
				
				if data[k:k+1] == endl:
					k += 1
					break
			
			curr_data = next_data + data[:k]
			next_data = data[k:]
			
			# OK, data block read - proceed with its parsing
			self._parse_data_block( curr_data, boundary, k)
		
		self._parse_to_files()
		self._parse_to_body()
		
		# remove temporary properties - we don't need them anymore
		del self._parts
		del self._files_counter
		del self._body_length
	
	def _parse_data_block(self, data, boundary, data_length):
		cdef int curr_part_idx
		cdef unsigned long i
		
		prefix        = b'--'
		part_boundary = prefix + boundary
		last_boundary = part_boundary + prefix
		curr_part_idx = len( self._parts)
		is_new_part   = False
		i             = 0
		endl          = b'\x0d\x0a'
		
		disposition_key = 'Content-Disposition'
		name_key        = 'Name'
		filename_key    = 'Filename'
		ctype_key       = 'Content-Type'
		
		lines = data.split( endl)
		line = b''
		while True:
			try :
				line = lines[i]
			except IndexError:
				break
			
			if is_new_part: # new started
				while True:
					
					_line = line.decode( self._encoding).strip()
					
					if _line == '':
						break
					
					header = self._parse_key_value( [_line], ':', True)
					
					if curr_part_idx not in self._parts:
						self._parts[curr_part_idx] = {
							'headers'  : {},
							'length'   : 0,
							'name'     : None,
							'filename' : None,
							'mime'     : None
						}
					
					self._parts[curr_part_idx]['headers'].update( header)
					
					if ctype_key in header:
						self._parts[curr_part_idx]['mime'] = header[ctype_key]
					
					if disposition_key in header:
						
						disposition = self._parse_key_value(
							header[disposition_key].split( ';'),
							normalize = True,
							cleanup = True
						)
						
						if filename_key in disposition:
							self._parts[curr_part_idx]['filename'] = disposition[filename_key]
							self._files_counter += 1
							
							if self._files_counter > self._max_uploaded_files:
								raise MaxFilesError( self._max_uploaded_files)
						
						if name_key in disposition:
							self._parts[curr_part_idx]['name'] = disposition[name_key]
					
					i += 1
					try :
						line = lines[i]
					except IndexError:
						break
					
				is_new_part = False
			
			else:
				if line.startswith( prefix):
					if line.startswith( part_boundary):
						if line.startswith( last_boundary):
							break # last boundary reached, stop parsing
						
						curr_part_idx += 1
						is_new_part = True
				
				if not is_new_part :
					_endl = endl
					
					try :
						next_line = lines[i + 1]
						if next_line.startswith( prefix):
							if next_line.startswith( part_boundary):
								_endl = b''
					except IndexError:
						_endl = b''
					
					self._handle_part_line( line + _endl, curr_part_idx)
			
			i += 1			
	
	def _handle_part_line(self, line, unsigned int part_idx):
		part_info = self._parts[part_idx]
		
		if part_info['filename'] is not None:
			part_info['length'] += len( line)
		
			if part_info['length'] > self._max_filesize :
				raise MaxFileSizeError( part_info['filename'], self._max_filesize)
			
			if self._files_upload_on:
				tmp_name_key = 'tmp_name'
				
				try :
					if tmp_name_key not in part_info:
						m = hashlib.md5()
						m.update( bytes( str( time.time()), self._encoding))
						m.update( bytes( str( random.random()), self._encoding))
						m.update( bytes( str( part_info), self._encoding))
						
						part_info[tmp_name_key] = self._uploaded_file_prefix + m.hexdigest()
						part_info['handle'] = open( self._uploaded_files_dir + '/' + part_info[tmp_name_key], 'wb')
					
					part_info['handle'].write( line)
				except Exception as e:
					raise FileSaveError( part_info['filename'], e)
			else :
				raise FilesUploadError()
		else :
			data_key = 'data'
			
			if data_key not in part_info:
				part_info[data_key] = b''
			
			self._body_length += len( line)
			
			if self._body_length > self._max_content_length:
				raise MaxBodySizeError( self._max_content_length)
			
			part_info[data_key] += line

	@classmethod
	def _parse_query_params(this, params):
		if sys.version_info[0] == 2:
			import urllib
			urldecode = urllib.unquote_plus
		
		elif sys.version_info[0] >= 3:
			import urllib.parse
			urldecode = urllib.parse.unquote_plus
		
		if not params:
			return {}
		
		params     = params.split( '&')
		param_dict = {}
		
		for param in params:
			name, value = param.split( '=')
			
			name = urldecode( name)
			value = urldecode( value)
			
			this._parse_param( name, value, param_dict)
		
		return param_dict
	
	@classmethod
	def _parse_param(this, name, value, param_dict):
		cdef long j
		param_keys = this._rx_keys_lookup.findall( name)
		param_name = this._rx_name_lookup.sub( '\\1', name)
		
		if param_name not in param_dict:
			param_dict[param_name] = {}
		
		if len(param_keys) == 0:
			param_dict[param_name] = value
			return
		
		tmp_dict = param_dict[param_name]
		for j, key in enumerate( param_keys):
			try :
				key = int(key)
			except ValueError:
				pass
			
			if key == '':
				key = this._get_next_key( list( tmp_dict.keys()))
			
			try :
				param_keys[j + 1]
				
				if (key not in tmp_dict) or (type( tmp_dict[key]) is not dict):
					tmp_dict[key] = {}
			
			except IndexError:
				tmp_dict[key] = value
			
			tmp_dict = tmp_dict[key]
		
		return param_dict
	
	@classmethod
	def _get_next_key(this, lst):
		cdef long max = -1
		for val in lst:
			try :
				val = int(val)
			except ValueError:
				continue
			
			if max == -1:
				max = val
				continue
			
			if val > max:
				max = val
		
		if max is None:
			max = 0
		else :
			max += 1
		
		return max
	
	def _parse_to_files(self):
		for part in self._parts.values():
			if part['filename'] is not None:
				name = part['name']
				del part['name']
				self._parse_param( name, part, self.FILES)
	
	def _parse_to_body(self):
		for part in self._parts.values():
			if part['filename'] is None:
				self._parse_param(
					part['name'],
					self._decode_value( part['data']),
					self.BODY
				)
	
	def _parse_query(self):
		qs = 'QUERY_STRING'
		
		if qs not in self._environ:
			return False
		
		self.QUERY = self._parse_query_params( self._environ[qs])
	
	def _parse(self):
		self._parse_server()
		
		# shortcut to get the request method
		self.method = self.server( 'REQUEST_METHOD')
		
		self._parse_headers()
		self._parse_cookie()
		self._parse_body()
		self._parse_query()
		
		# provides functionality to work with uploaded files
		self.FileUploader = FileUploader(
			self.FILES,
			self._uploaded_files_dir
		)
	
	# PUBLIC INTERFACE:
	
	def __str__(self):
		return str( self.to_dict())
	
	def to_dict(self):
		"""Converts HttpRequest to dictionary presentation
		
		:rtype: dict - dictionary representation of HttpRequest object
		"""
		return {
			'SERVER'  : self.SERVER,
			'HEADERS' : self.HEADERS,
			'QUERY'   : self.QUERY,
			'BODY'    : self.BODY,
			'COOKIE'  : self.COOKIE,
			'FILES'   : self.FILES
		}
	
	def getenv(self, storage, key=None, default_value = None):
		"""Returns an entire storage or a value stored in
		this storage retrieved by a given key. Known storages are:
		
		- SERVER - server environment variables (everything which is
		  inside WSGI environ except 'wsgi.input')
		- HEADERS - all HTTP headers in current request
		- QUERY - dictionary of parsed QUERY_STRING parameters
		- BODY - dictionary of parsed parameters found in request's body
		- COOKIE - dictionary of parsed COOKIE parameters
		- FILES - dictionary of uploaded files
		
		:param storage: name of a storage
		:param key: [optional] key of the value to retrieve from tha given storage
		:param default_value: [optional] if no value is present in storage by a
		                      given key this will be returned (default is None)
		:rtype: mixed - storage dict or value or default_value
		"""
		env = getattr(self, storage)
		
		if key is None:
			return default_value
		
		if not env or (key not in env):
			return default_value
		
		if storage == 'HEADERS':
			key = self._normilize_key( key)
		
		res = default_value
		if key in env:
			res = env[key]
		
		return res
	
	@classmethod
	def parse_query( this, query_string):
		"""Static method providing an ability to parse
		QUERY_STRING-like parameters in the same way as this object does.
		
		Usage example:
		
		::
			import wsgikit
			
			my_params = 'f[]=2&f[]=3&f[][]=4&f[][]=5&f[][]=6'
			print( wsgikit.HttpRequest.parse_query( my_params))
		
		:param query_string: str - key=value params delimited with &
		:rtype: dict - dictionary of parsed parameters
		"""
		return this._parse_query_params( query_string)
	
	def header(self, name = None, default_value = None):
		"""Returns the content of HEADER storage if none name passed
		or returns a value for header with given name
		
		:param name: [optional] name of a header to get the value
		:param default_value: [optional] value to return if no header with given name found
		:rtype: dict or str - headers dict or string header value
		"""
		return self.getenv( 'HEADERS', name, default_value)
	
	def body(self, name = None, default_value = None):
		"""Returns the content of BODY storage if none name passed
		or returns a value for body parameter with given name
		
		:param name: [optional] name of a body parameter to get the value
		:param default_value: [optional] value to return if no body parameter with given name found
		:rtype: mixed - dict of body params or param value
		"""
		return self.getenv( 'BODY', name, default_value)
	
	def query(self, name = None, default_value = None):
		"""Returns the content of QUERY storage if none name passed
		or returns a value for QYERY_STRING parameter with given name
		
		:param name: [optional] name of a QUERY_STRING parameter to get the value
		:param default_value: [optional] value to return if no QUERY_STRING parameter with given name found
		:rtype: mixed - dict of QUERY_STRING params or param value
		"""
		return self.getenv( 'QUERY', name, default_value)
	
	def cookie(self, name = None, default_value = None):
		"""Returns the content of COOKIE storage if none name passed
		or returns a value for cookie parameter with given name
		
		:param name: [optional] name of a cookie parameter to get the value
		:param default_value: [optional] value to return if no cookie parameter with given name found
		:rtype: mixed - dict of cookie params or param value
		"""
		return self.getenv( 'COOKIE', name, default_value)
	
	def file(self, name = None, default_value = None):
		"""Returns the content of FILES storage if none name passed
		or returns a value for uploaded files with given name
		
		:param name: [optional] name of a uploaded files to get the value
		:param default_value: [optional] value to return if no uploaded files with given name found
		:rtype: mixed - dict of uploaded files or its part by a given name
		"""
		return self.getenv( 'FILES', name, default_value)
	
	def server(self, name = None, default_value = None):
		"""Returns the content of SERVER environment or the value
		of server environment variable.
		
		:param name: [optional] name of a server environment variable to get the value
		:param default_value: [optional] value to return if no server environment variable with given name found
		:rtype: mixed - dict of body params or param value
		"""
		return self.getenv( 'SERVER', name, default_value)
	
	def has_body(self):
		"""Returns True if HTTP request body contains any params, False otherwise
		
		:rtype: bool
		"""
		return self.BODY != {}
	
	def has_cookie(self):
		"""Returns True if HTTP request pass any cookie variables, False otherwise
		
		:rtype: bool
		"""
		return self.COOKIE != {}
	
	def has_files(self):
		"""Returns True if HTTP request contains any files attached and uploaded, False otherwise
		
		:rtype: bool
		"""
		return self.FILES != {}
	
	def has_query(self):
		"""Returns True if HTTP request contains any params passed with QUERY_STRING, False otherwise
		
		:rtype: bool
		"""
		return self.QUERY != {}

class FileUploaderError(Exception):
	"""Base error class for wsgikit.FileUploader object
	"""
	pass

class FileOverwriteError(FileUploaderError):
	"""Raised if during the file move there is already file existing
	with the same name and overwriting was disabled
	"""
	def __init__(self, filename):
		self.filename = filename
	
	def __str__(self):
		return 'Can not save file "%s". Such file already exists' \
			%(self.filename)

class UploadedFileSaveError(FileUploaderError):
	"""Raised id during the save uploaded file an error occured
	"""
	def __init__(self, filename, reason):
		self.filename = filename
		self.reason = reason
	
	def __str__(self):
		return 'Can not save file "%s". Reason: %s'\
			%(self.filename, self.reason)

class MoveError(FileUploaderError):
	"""Raised when uploaded file move() was called with invalid arguments
	"""
	def __str__(self):
		return 'Given file is invalid - expecting object from HttpRequest.FILES'

class MoveDestinationError(FileUploaderError):
	"""Raised when given destination to move uploaded files does not exist
	"""
	def __init__(self, destination):
		self.destination = destination
	
	def __str__(self):
		return 'Given destination "%s" is not a directory' \
			%(self.destination)

class FileUploader(object):
	"""FileUploader object provides basic functionality to
	work with files uploaded with wsgikit.HttpRequest object
	
	Naturally there is no need to instantiate it as far as it is
	instantiated automatically by HttpRequest during the HTTP
	request processing.
	
	It is enough to use it as:
	
	::
		import wsgikit
		
		def my_wsgi_app( environ, start_response):
			status = '200 OK'
			response_headers = [('Content-type','text/plain')]
			start_response( status, response_headers)
			
			request = wsgikit.HttpRequest( environ)
			
			if request.has_files():
				try :
					request.FileUploader.move_all(
						destination = '/my/cool/file/storage',
						overwrite = True
					)
					my_response = 'Thank you, we saved all you pass!'
				
				except FileUploaderError as e:
					my_response = "Oops, we can't save this! Reason: %s" %e
			
			else :
				my_response = 'There is nothing to do, sorry...'
			
			return my_response
	"""
	def __init__(self, files, tmp_dir):
		self.FILES      = files
		self.tmp_dir    = tmp_dir
	
	def move(self, file, destination, overwrite = False):
		"""Moves the fiven file from a temporary location to the
		given destination. If overwrite is turned on file will be
		overwritten during the move, otherwise error will be raised
		
		:param file: dict object of the file compatible by structure with the
                     FILES storage item in wsgikit.HttpRequest object
		:param destination: str - path where to move the file. If existing directory
                            provided will save the file in that directory with the
                            file name passed in HTTP request
        :param overwrite: bool - flag, to turn on/off files overwriting
        :rtype: returns new file destination on success
   		:raise: FileOverwriteError, UploadedFileSaveError or MoveError
		"""
		if type(file) is dict and 'tmp_name' in file:
			if os.path.isdir( destination):
				destination += '/' + file['filename']
			
			if file['handle']:
				file['handle'].close()
				del file['handle']
			
			if os.path.isfile( destination) and not overwrite:
				raise FileOverwriteError( destination)
			
			try :
				os.rename( self.tmp_dir + '/' + file['tmp_name'], destination)
				return destination
			except Exception as e:
				raise UploadedFileSaveError( destination, e)
		else:
			raise MoveError()
	
	def move_all(self, destination, overwrite = False, fdict = None):
		"""Moves all the files uploaded during HTTP request to the given destination
		
		:param destination: str - path where to store the files. Destination MUST be
                            a directory, otherwise an error will be raised
        :param overwrite: bool - flag, to turn on/off files overwriting
        :rtype: list - new files destinations
        :raise: FileOverwriteError, UploadedFileSaveError, MoveDestinationError or MoveError
		"""
		moved_files = []
		
		if not os.path.isdir( destination):
			raise MoveDestinationError( destination)
		
		if fdict is None:
			fdict = self.FILES
		
		for file in fdict.values():
			if type(file) is dict and 'tmp_name' not in file:
				moved_files += self.move_all( destination, overwrite, file)
			
			elif 'tmp_name' in file:
				moved_files += [self.move( file, destination, overwrite)]
			
			else:
				raise MoveError()
		
		return moved_files

class PrettyDict:
	"""Simple PrettyFormatter which provides an ability to
	represent Python's dictionary object as human-readable
	string
	
	Usage example:
	
	::
		import wsgikit
		
		def my_wsgi_app( environ, start_response):
			status = '200 OK'
			response_headers = [('Content-type','text/plain')]
			start_response( status, response_headers)
			
			request = wsgikit.HttpRequest( environ)
			
			return wsgikit.PrettyDict.format( request.to_dict())
	"""
	@classmethod
	def _format_value(this, v, indent, comma, tab):
		if type( v) == tuple:
			v = str(v)
		
		if type( v) == list:
			return ''.join( [this._format_value( item, indent, comma, tab) for item in v])
		
		elif type( v) == dict:
			res = ' : {\n'
			res += this.format( v, tab, indent)
			res += (" " * tab * (indent - 1)) + '}' + comma + '\n'
			return res
		
		else:
			return (' : "%s"' %(v)) + comma + "\n"
	
	@classmethod
	def format(this, d, tab = 4, indent = 0):
		"""Performs dict formatting to human-readable string
		
		:param d: dictionary to format
		:param tab: tab identation length
		:param indent: initial identation to use for formatting
		:rtype: str
		"""
		cdef int i = 0
		cdef int l = len(d)
		res = ''
		comma = ','
		
		for key in d:
			i += 1
			
			if i == l :
				comma = ''
			
			res += (" " * tab * indent) + ('"%s"' %key)
			res += this._format_value( d[key], indent + 1, comma, tab)
		
		return res
