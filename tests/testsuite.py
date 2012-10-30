import unittest,subprocess,os,wsgikit,signal,time,json,urllib
from urllib.request import urlopen
from urllib.request import Request
import mimetypes

def encode_multipart_formdata( fields = None, files = None):
	"""
    fields is a sequence of (name, value) elements for regular form fields.
    files is a sequence of (name, filename, value) elements for data to be uploaded as files
    Return (content_type, body)
    """
	BOUNDARY = b'----------ThIs_Is_tHe_bouNdaRY_$'
	CRLF = b'\r\n'
	L = []
	
	if fields and len( fields) > 0:
		for (key, value) in fields:
			L.append( b'--' + BOUNDARY)
			L.append( b'Content-Disposition: form-data; name="' + key.encode('utf-8') + b'"')
			L.append( b'')
			L.append( value.encode('utf-8'))
	
	if files and len( files) > 0:
		for (key, filename, value) in files:
			L.append( b'--' + BOUNDARY)
			L.append( b'Content-Disposition: form-data; name="' + key.encode('utf-8') + b'"; filename="' + filename.encode('utf-8') + b'"')
			L.append( b'Content-Type: ' + get_content_type( filename).encode('utf-8'))
			L.append( b'')
			L.append( value)
	
	L.append( b'--' + BOUNDARY + b'--')
	L.append( b'')
	body = CRLF.join( L)
	content_type = 'multipart/form-data; boundary=%s' % BOUNDARY.decode('utf-8')
	
	return content_type, body

def get_content_type( filename):
	return mimetypes.guess_type( filename)[0] or 'application/octet-stream'

BASE_URL = 'http://localhost:10888/'
UPLOADS_PATH = './uploads'
DATA_PATH = './data'

def cleanup_uploads():
	for file in os.listdir( UPLOADS_PATH):
		file_path = os.path.join( UPLOADS_PATH, file)
		
		if os.path.isfile( file_path):
			os.unlink( file_path)

class Server(object):
	def start(self):
		print("Starting WSGI server...")
		self.pid = subprocess.Popen( ['/usr/bin/env', 'python', os.getcwd() + '/server.py', '&']).pid
		
		if not os.path.exists( UPLOADS_PATH):
			os.makedirs( UPLOADS_PATH)
		
		time.sleep(1)
		print('Done.')
	
	def stop(self):
		print("Shutdown server...")
		os.kill( self.pid, signal.SIGKILL)
		os.removedirs( UPLOADS_PATH)
		print("Done.")

class WsgiKitTest(unittest.TestCase):
	
	test_data = [{
		'raw'  : 'foo=1&bar=2',
		'dict' : {'foo':'1','bar':'2'}
	}, {
		'raw'  : 'foo[][]=1&foo[1][]=1&foo[1][]=1',
		'dict' : {'foo':{'0':{'0':'1'},'1':{'0':'1','1':'1'}}}
	}]
	
	test_files = [
		('upfiles[]', '01.txt', open( DATA_PATH + '/01.txt', 'rb').read()),
		('upfiles[]', '02.zip', open( DATA_PATH + '/02.zip', 'rb').read()),
		('upfiles[]', '03.zip', open( DATA_PATH + '/03.zip', 'rb').read()),
		('upfiles[]', 'large.zip', open( DATA_PATH + '/large.zip', 'rb').read()),
	]
	
	def test01_parse_query(self):
		self.assertEqual( wsgikit.HttpRequest.parse_query( self.test_data[0]['raw']), self.test_data[0]['dict'])
	
	def test02_remote_parse_query(self):
		for data in self.test_data:
			response = urlopen( BASE_URL + '?' + data['raw'])
			res = json.loads( response.read().decode( 'utf-8'))['QUERY']
			self.assertEqual( res, data['dict'])
	
	def test03_remote_parse_body(self):
		for data in self.test_data:
			request = Request( BASE_URL, data['raw'].encode( 'utf-8'))
			res = json.loads( urlopen( request).read().decode( 'utf-8'))['BODY']
			self.assertEqual( res, data['dict'])
	
	def test04_remote_parse_headers(self):
		request = Request( BASE_URL, headers = {
			'X-Test-Header' : 'tested'
		})
		res = json.loads( urlopen( request).read().decode( 'utf-8'))['HEADERS']
		self.assertTrue( 'X-Test-Header' in res and res['X-Test-Header'] == 'tested')
	
	def test05_remote_parse_cookie(self):
		request = Request( BASE_URL, headers = {
			'Cookie' : 'session=12345; sid=123456789',
		})
		res = json.loads( urlopen( request).read().decode( 'utf-8'))['COOKIE']
		self.assertEqual(res, { 'session' : '12345', 'sid' : '123456789' })
	
	def test06_remote_upload_files(self):
		ctype, body = encode_multipart_formdata(
			self.test_data[0]['dict'].items(),
			self.test_files[:2]
		)
		
		request = Request( BASE_URL, body, { 'Content-Type' : ctype })
		res = json.loads( urlopen( request).read().decode( 'utf-8'))['FILES']
		
		self.assertTrue('upfiles' in res)
		self.assertTrue('0' in res['upfiles'])
		self.assertTrue('1' in res['upfiles'])
		
		fnames = (self.test_files[0][1], self.test_files[1][1])
		
		self.assertTrue( res['upfiles']['0']['filename'] in fnames)
		self.assertTrue( res['upfiles']['1']['filename'] in fnames)
		
		dirfiles = os.listdir( UPLOADS_PATH)
		for file in fnames:
			self.assertTrue( file in dirfiles)
			self.assertEqual(
				open( UPLOADS_PATH + '/' + file, 'rb').read(),
				open( DATA_PATH + '/' + file, 'rb').read()
			)
		
		cleanup_uploads()
	
	def test07_remote_max_file_size_limit(self):
		ctype, body = encode_multipart_formdata(
			files = self.test_files[3:]
		)
		
		try :
			request = Request( BASE_URL, body, { 'Content-Type' : ctype })
			urlopen( request)
			self.assertEqual( True, False, "Max file size limit was not handled by the server")
		except Exception as e:
			self.assertIsInstance( e, urllib.error.HTTPError)
		
		cleanup_uploads()
	
	def test08_remote_max_files_limit(self):
		ctype, body = encode_multipart_formdata(
			self.test_data[0]['dict'].items(),
			self.test_files[:3]
		)
		
		try :
			request = Request( BASE_URL, body, { 'Content-Type' : ctype })
			urlopen( request)
			self.assertEqual( True, False, "Max uploaded files limit was not handled by the server")
		except Exception as e:
			self.assertIsInstance( e, urllib.error.HTTPError)
		
		cleanup_uploads()
	
	def test09_remote_max_body_size_limit(self):
		body = b'foo=' + b'0' * 512
		
		try :
			request = Request( BASE_URL, body)
			urlopen( request)
			self.assertEqual( True, False, "Max body size limit was not handled by the server")
		except Exception as e:
			self.assertIsInstance( e, urllib.error.HTTPError)
	
	@staticmethod
	def run_tests():
		srv = Server()
		srv.start()
		
		print("Running tests...")
		suite = unittest.TestLoader().loadTestsFromTestCase( WsgiKitTest)
		unittest.TextTestRunner( verbosity = 2).run( suite)

		srv.stop()

if __name__ == '__main__':
	WsgiKitTest.run_tests()
